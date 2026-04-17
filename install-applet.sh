#!/usr/bin/env bash
# Builds and installs the COSMIC panel applet.
# Run find_keyboard.sh first to get your VID/PID, then:
#   KBD_VID=0xXXXX KBD_PID=0xXXXX ./install-applet.sh
set -euo pipefail

KBD_VID="${KBD_VID:?Set KBD_VID to your keyboard VID (e.g. 0x6c62). Run find_keyboard.sh.}"
KBD_PID="${KBD_PID:?Set KBD_PID to your keyboard PID. Run find_keyboard.sh.}"

cd "$(dirname "$0")/applet"

echo "==> Building applet …"
cargo build --release

BINARY="target/release/vial-layer"
DESKTOP="data/vial-layer.desktop"

echo "==> Installing binary to ~/.local/bin/ …"
install -Dm755 "$BINARY" "$HOME/.local/bin/vial-layer"

echo "==> Installing .desktop file (requires sudo) …"
sudo install -Dm644 "$DESKTOP" "/usr/share/applications/vial-layer.desktop"
# Remove stale copies if present.
rm -f "$HOME/.local/share/applications/vial-layer.desktop"
rm -f "$HOME/.local/share/applications/piantor-layer.desktop"
sudo rm -f "/usr/share/applications/piantor-layer.desktop"

# Persist VID/PID in the systemd user environment so the applet always finds the keyboard.
echo "==> Persisting VID/PID in systemd user environment …"
systemctl --user set-environment "KBD_VID=$KBD_VID" "KBD_PID=$KBD_PID"

# Also write to ~/.config/environment.d/ so it survives reboots.
ENVD="$HOME/.config/environment.d/vial-layer.conf"
mkdir -p "$(dirname "$ENVD")"
cat > "$ENVD" <<EOF
KBD_VID=$KBD_VID
KBD_PID=$KBD_PID
EOF
echo "    Written to $ENVD"

echo ""
echo "==> Done."
echo "    Install the udev rule (once) if you haven't:"
echo "      sudo cp ../udev/99-vial-hid.rules /etc/udev/rules.d/"
echo "      # edit the file to fill in VID/PID, then:"
echo "      sudo udevadm control --reload && sudo udevadm trigger"
echo ""
echo "    Then add 'Vial Layer Indicator' to your COSMIC panel via"
echo "    Settings → Desktop → Panel → Add Applet."
