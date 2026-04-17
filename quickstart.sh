#!/usr/bin/env bash
# Interactive quickstart — walks through every setup step.
# Run from the repo root: ./quickstart.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Helpers ───────────────────────────────────────────────────────────────────

info()  { echo ""; echo "==> $*"; }
step()  { echo "    $*"; }
ask()   { read -r -p "    $* " _REPLY; echo "$_REPLY"; }
confirm() {
    local ans
    ans=$(ask "$1 [y/N]")
    [[ "$ans" =~ ^[Yy]$ ]]
}
pause() { read -r -p "    Press ENTER to continue… "; }

have() { command -v "$1" &>/dev/null; }

# Rustup installs cargo to ~/.cargo/bin, which may not be in PATH yet.
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

# ── Banner ────────────────────────────────────────────────────────────────────

cat <<'BANNER'

  Vial Layer Indicator — quickstart
  ─────────────────────────────────────
  This script will guide you through:
    1. Checking prerequisites
    2. Patching and flashing the firmware  (optional)
    3. Detecting your keyboard VID / PID
    4. Building the applet from source     (if binary not found)
    5. Installing the applet
    6. Installing the udev rule
    7. Creating an initial layer config
    8. Adding the applet to COSMIC panel

BANNER

pause

# ── 1. Prerequisites ──────────────────────────────────────────────────────────

info "Step 1: Checking prerequisites"

install_cargo() {
    echo "    Installing Rust via rustup …"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    # Source the env so cargo is available for the rest of this script.
    # shellcheck source=/dev/null
    source "$HOME/.cargo/env"
}

install_python3() {
    echo "    Attempting to install python3 via system package manager …"
    if have apt-get;  then sudo apt-get install -y python3
    elif have dnf;    then sudo dnf install -y python3
    elif have pacman; then sudo pacman -S --noconfirm python
    else
        echo "    Could not detect package manager. Install python3 manually."
        exit 1
    fi
}

VENV_DIR="$REPO_DIR/.venv"
VENV_PYTHON="$VENV_DIR/bin/python3"
VENV_QMK="$VENV_DIR/bin/qmk"

ensure_venv() {
    if [[ ! -x "$VENV_PYTHON" ]]; then
        echo "    Creating Python venv at $VENV_DIR …"
        python3 -m venv "$VENV_DIR"
    fi
}

install_hidapi_py() {
    ensure_venv
    echo "    Installing hidapi into venv …"
    "$VENV_PYTHON" -m pip install --quiet hidapi
}

install_qmk() {
    ensure_venv
    echo "    Installing qmk into venv …"
    "$VENV_PYTHON" -m pip install --quiet qmk
}

check_or_install() {
    local label="$1" check_fn="$2" install_fn="$3"
    if ! eval "$check_fn" &>/dev/null; then
        echo ""
        echo "    '$label' is not installed."
        if confirm "Install it now?"; then
            eval "$install_fn"
        else
            echo "    Skipped. Re-run this script after installing '$label'."
            exit 1
        fi
    fi
}

check_or_install "cargo"           "have cargo"                            "install_cargo"
check_or_install "python3"         "have python3"                          "install_python3"
check_or_install "hidapi (python)" "$VENV_PYTHON -c 'import hid'"         "install_hidapi_py"
check_or_install "qmk"             "[[ -x '$VENV_QMK' ]] || have qmk"    "install_qmk"

# Prefer the venv qmk over any system-installed one.
[[ -x "$VENV_QMK" ]] && export PATH="$VENV_DIR/bin:$PATH"

# System libraries required to build the applet (libcosmic / Wayland stack).
MISSING_LIBS=()
have pkg-config || MISSING_LIBS+=(pkg-config)
pkg-config --exists xkbcommon 2>/dev/null   || MISSING_LIBS+=(libxkbcommon-dev)
pkg-config --exists wayland-client 2>/dev/null || MISSING_LIBS+=(libwayland-dev)
pkg-config --exists libudev 2>/dev/null     || MISSING_LIBS+=(libudev-dev)

if [[ ${#MISSING_LIBS[@]} -gt 0 ]]; then
    echo ""
    echo "    Missing system build libraries: ${MISSING_LIBS[*]}"
    if confirm "Install them now? (requires sudo)"; then
        if have apt-get;  then sudo apt-get install -y "${MISSING_LIBS[@]}"
        elif have dnf;    then sudo dnf install -y "${MISSING_LIBS[@]}"
        elif have pacman; then
            # Arch package names differ — map them.
            sudo pacman -S --noconfirm libxkbcommon wayland pkgconf
        else
            echo "    Could not detect package manager. Install manually: ${MISSING_LIBS[*]}"
            exit 1
        fi
    else
        echo "    Skipped. The build will fail without these libraries."
        exit 1
    fi
fi

step "All required tools found."

# ── 2. Firmware ───────────────────────────────────────────────────────────────

info "Step 2: Firmware patch and flash"

echo ""
echo "    The firmware needs a small patch to report the active layer over HID."
echo "    Skip this step if you have already flashed the patched firmware."
echo ""

if confirm "Patch and flash the firmware now?"; then
    VIAL_QMK_DIR="${VIAL_QMK_DIR:-$HOME/vial-qmk}"
    KEYBOARD="${KEYBOARD:-beekeeb/piantor}"
    KEYMAP="${KEYMAP:-vial}"

    cat <<'WARN'

    ┌─ IMPORTANT: back up your Vial layout first ──────────────────────────┐
    │                                                                       │
    │  Flashing new firmware can reset EEPROM on first boot, which would   │
    │  wipe any keymap customisations you made in the Vial app.            │
    │                                                                       │
    │  Before continuing:                                                   │
    │    1. Open the Vial desktop app                                       │
    │    2. File → Save Current Layout  (saves a .vil file)                │
    │                                                                       │
    │  After flashing you can restore it with File → Load Saved Layout.    │
    └───────────────────────────────────────────────────────────────────────┘

WARN

    if ! confirm "Vial layout backed up — continue with flashing?"; then
        echo "    Aborted. Re-run once you have saved your layout."
        exit 0
    fi

    echo ""
    echo "    Using VIAL_QMK_DIR=$VIAL_QMK_DIR"
    echo "    Using KEYBOARD=$KEYBOARD  KEYMAP=$KEYMAP"
    echo "    (Set these env vars before running quickstart.sh to override.)"
    echo ""

    if [[ ! -d "$VIAL_QMK_DIR" ]]; then
        echo "    vial-qmk not found at $VIAL_QMK_DIR"
        if confirm "Clone and set up vial-qmk now? (downloads ~270 MB)"; then
            git clone https://github.com/vial-kb/vial-qmk "$VIAL_QMK_DIR"
            qmk setup -H "$VIAL_QMK_DIR" -y
        else
            echo "    Skipped. Re-run with VIAL_QMK_DIR set once you have it."
            if ! confirm "Continue anyway (skip flashing)?"; then
                exit 1
            fi
        fi
    fi

    if [[ -d "$VIAL_QMK_DIR" ]]; then
        info "  Applying firmware patch …"
        VIAL_QMK_DIR="$VIAL_QMK_DIR" KEYBOARD="$KEYBOARD" \
            "$REPO_DIR/firmware/apply.sh" "$KEYMAP"

        info "  Flashing firmware …"
        SIDE=$(ask "Which halves to flash? [left/right/both] (default: both):")
        SIDE="${SIDE:-both}"
        VIAL_QMK_DIR="$VIAL_QMK_DIR" KEYBOARD="$KEYBOARD" KEYMAP="$KEYMAP" \
            "$REPO_DIR/flash.sh" "$SIDE"

        echo ""
        echo "    Firmware flashed. Reconnect both halves normally before continuing."
        pause
    fi
else
    step "Skipping firmware step."
fi

# ── 3. Detect VID / PID ───────────────────────────────────────────────────────

info "Step 3: Detecting keyboard VID / PID"

echo ""
echo "    Make sure the keyboard is connected, then press ENTER."
pause

KBD_VID="" KBD_PID=""

json=$("$REPO_DIR/find_keyboard.sh" --json 2>/dev/null || true)
count=$(echo "$json" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)

if [[ "$count" -eq 1 ]]; then
    detected_vid=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin)[0]; print(f\"{d['vid']:#06x}\")")
    detected_pid=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin)[0]; print(f\"{d['pid']:#06x}\")")
    detected_name=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin)[0]; print(d['manufacturer'], d['product'])")
    echo ""
    echo "    Found: $detected_name"
    echo "      VID = $detected_vid"
    echo "      PID = $detected_pid"
    echo ""
    if confirm "Use this device?"; then
        KBD_VID="$detected_vid"
        KBD_PID="$detected_pid"
    fi
elif [[ "$count" -gt 1 ]]; then
    echo ""
    echo "    Multiple Vial devices found:"
    "$REPO_DIR/find_keyboard.sh"
fi

if [[ -z "$KBD_VID" || -z "$KBD_PID" ]]; then
    if [[ "$count" -eq 0 ]]; then
        echo ""
        echo "    No Vial HID device found. Check:"
        echo "      • The keyboard is plugged in"
        echo "      • The patched firmware is flashed"
        echo "      • The udev rule is installed (we'll handle this in step 6)"
        echo ""
    fi
    KBD_VID=$(ask "Enter VID (e.g. 0x6c62):")
    KBD_PID=$(ask "Enter PID (e.g. 0x0001):")
fi

if [[ -z "$KBD_VID" || -z "$KBD_PID" ]]; then
    echo "    ERROR: VID and PID are required."
    exit 1
fi

export KBD_VID KBD_PID

# ── 4. Build ──────────────────────────────────────────────────────────────────

info "Step 4: Building the applet"

BINARY="$REPO_DIR/applet/target/release/vial-layer"

if [[ -f "$BINARY" ]]; then
    step "Binary already exists at $BINARY — skipping build."
    if confirm "Rebuild anyway?"; then
        (cd "$REPO_DIR/applet" && cargo build --release)
    fi
else
    step "Binary not found — building from source …"
    (cd "$REPO_DIR/applet" && cargo build --release)
    step "Build complete."
fi

# ── 5. Install applet ─────────────────────────────────────────────────────────

info "Step 5: Installing the applet"

install -Dm755 "$BINARY" "$HOME/.local/bin/vial-layer"
step "Binary installed to ~/.local/bin/vial-layer"

sudo install -Dm644 "$REPO_DIR/applet/data/vial-layer.desktop" \
    "/usr/share/applications/vial-layer.desktop"
rm -f "$HOME/.local/share/applications/vial-layer.desktop"
step ".desktop file installed to /usr/share/applications/"

systemctl --user set-environment "KBD_VID=$KBD_VID" "KBD_PID=$KBD_PID" 2>/dev/null || true

ENVD="$HOME/.config/environment.d/vial-layer.conf"
mkdir -p "$(dirname "$ENVD")"
cat > "$ENVD" <<EOF
KBD_VID=$KBD_VID
KBD_PID=$KBD_PID
EOF
step "VID/PID persisted in $ENVD"

# ── 6. udev rule ─────────────────────────────────────────────────────────────

info "Step 6: Installing udev rule"

RULES_DEST="/etc/udev/rules.d/99-vial-hid.rules"
RULES_TMP=$(mktemp)

# Substitute actual VID/PID into the rule (strip 0x prefix for udev)
VID_BARE="${KBD_VID#0x}"
PID_BARE="${KBD_PID#0x}"

sed "s/ATTRS{idVendor}==\"XXXX\"/ATTRS{idVendor}==\"$VID_BARE\"/" \
    "$REPO_DIR/udev/99-vial-hid.rules" \
  | sed "s/ATTRS{idProduct}==\"XXXX\"/ATTRS{idProduct}==\"$PID_BARE\"/" \
  > "$RULES_TMP"

if [[ -f "$RULES_DEST" ]]; then
    step "udev rule already installed at $RULES_DEST"
    if confirm "Overwrite with updated VID/PID?"; then
        sudo cp "$RULES_TMP" "$RULES_DEST"
        sudo udevadm control --reload-rules && sudo udevadm trigger
        step "udev rule updated and reloaded."
    fi
else
    echo ""
    echo "    This step requires sudo to write to /etc/udev/rules.d/."
    sudo cp "$RULES_TMP" "$RULES_DEST"
    sudo udevadm control --reload-rules && sudo udevadm trigger
    step "udev rule installed and reloaded."
fi

rm -f "$RULES_TMP"

# ── 7. Layer config ───────────────────────────────────────────────────────────

info "Step 7: Layer name config"

CONFIG_DIR="$HOME/.config/vial-layer"
CONFIG_FILE="$CONFIG_DIR/config.toml"

if [[ -f "$CONFIG_FILE" ]]; then
    step "Config already exists at $CONFIG_FILE — skipping."
else
    mkdir -p "$CONFIG_DIR"
    cp "$REPO_DIR/applet/data/config.toml.example" "$CONFIG_FILE"
    step "Example config written to $CONFIG_FILE"
    step "Edit it to match your layer names."
fi

# ── 8. Done ───────────────────────────────────────────────────────────────────

cat <<'DONE'

  ─────────────────────────────────────
  Setup complete!

  Last step — add the applet to COSMIC panel:
    1. Right-click the panel → "Edit Panel"  (or Settings → Desktop → Panel)
    2. Click "Add Applet"
    3. Select "Vial Layer Indicator"

  Tip: log out and back in (or reboot) if the applet doesn't appear — the
  environment variables need a fresh session to take effect.

DONE
