#!/usr/bin/env bash
# Compiles the Vial/QMK firmware (with layer reporting) and flashes it via UF2.
# Usage: ./flash.sh [left|right|both]   (default: both)
#
# Prerequisites:
#   1. vial-qmk cloned and set up via: qmk setup -H ~/vial-qmk
#   2. firmware/apply.sh already run
#   3. qmk CLI available (system or .venv/ created by quickstart.sh)
set -euo pipefail

# Prefer the venv qmk installed by quickstart.sh over any system one.
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
[[ -x "$REPO_DIR/.venv/bin/qmk" ]] && export PATH="$REPO_DIR/.venv/bin:$PATH"

VIAL_QMK_DIR="${VIAL_QMK_DIR:-$HOME/vial-qmk}"
KEYBOARD="${KEYBOARD:-beekeeb/piantor}"
KEYMAP="${KEYMAP:-vial}"
SIDE="${1:-both}"

BUILD_DIR="$VIAL_QMK_DIR/.build"

# ── Vial layout backup reminder ──────────────────────────────────────────────

cat <<'WARN'

  IMPORTANT: back up your Vial layout before flashing.
  Flashing can reset EEPROM on first boot and wipe keymap customisations.

    1. Open the Vial app
    2. File → Save Current Layout  (saves a .vil file)

  After flashing: File → Load Saved Layout to restore.

WARN
read -r -p "  Layout backed up? Press ENTER to continue (Ctrl-C to abort) … "
echo ""

# ── Compile ──────────────────────────────────────────────────────────────────

echo "==> Compiling $KEYBOARD:$KEYMAP …"
cd "$VIAL_QMK_DIR"
qmk compile -kb "$KEYBOARD" -km "$KEYMAP"

# QMK names the output file as <keyboard_path>_<keymap>.uf2
# slashes in keyboard path become underscores
SAFE_KB="${KEYBOARD//\//_}"
UF2="$BUILD_DIR/${SAFE_KB}_${KEYMAP}.uf2"

if [[ ! -f "$UF2" ]]; then
    echo "ERROR: expected UF2 not found at $UF2"
    echo "Check the .build/ directory for the actual filename."
    ls "$BUILD_DIR"/*.uf2 2>/dev/null || true
    exit 1
fi

echo "==> Built: $UF2"

# ── Flash helper ─────────────────────────────────────────────────────────────

find_rpi_mount() {
    local mount device
    # Already mounted?
    mount=$(findmnt -rno TARGET -S LABEL=RPI-RP2 2>/dev/null || true)
    [[ -n "$mount" ]] && { echo "$mount"; return; }

    # Present but unmounted — mount it via udisksctl.
    device=$(lsblk -rno NAME,LABEL | awk '$2=="RPI-RP2"{print "/dev/"$1}' | head -1)
    if [[ -n "$device" ]]; then
        mount=$(udisksctl mount -b "$device" 2>/dev/null \
                | grep -oP 'at \K\S+' | tr -d '.')
        [[ -n "$mount" ]] && { echo "$mount"; return; }
    fi
}

flash_half() {
    local label="$1" mount
    echo ""
    echo "==> Flash $label half"
    echo "    1. Hold the BOOT button (or double-tap RESET) on the $label half."
    echo "    2. Plug it into USB — RPI-RP2 will appear."
    echo "    Waiting for RPI-RP2 …"

    until mount=$(find_rpi_mount) && [[ -n "$mount" ]]; do
        printf "."
        sleep 1
    done
    echo ""
    echo "    Detected: $mount"

    read -r -p "    Ready to flash $label half — press ENTER to copy UF2, Ctrl-C to abort. "

    echo "    Copying UF2 to $mount …"
    cp "$UF2" "$mount/"
    echo "    Done — waiting for the $label half to reboot and disconnect …"

    # Unmount explicitly in case the OS doesn't do it automatically,
    # then wait until the device disappears so the next poll starts clean.
    local device
    device=$(lsblk -rno NAME,LABEL | awk '$2=="RPI-RP2"{print "/dev/"$1}' | head -1)
    [[ -n "$device" ]] && udisksctl unmount -b "$device" &>/dev/null || true

    until ! lsblk -rno LABEL 2>/dev/null | grep -q "^RPI-RP2$"; do
        sleep 1
    done
    echo "    $label half disconnected."
}

case "$SIDE" in
    left)  flash_half "left" ;;
    right) flash_half "right" ;;
    both)
        flash_half "left"
        echo ""
        echo "    Unplug the left half, then repeat for the right."
        flash_half "right"
        ;;
    *)
        echo "Usage: $0 [left|right|both]"
        exit 1
        ;;
esac

echo ""
echo "==> Firmware flashed. Reconnect both halves normally."
