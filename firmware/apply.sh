#!/usr/bin/env bash
# Patches a vial-qmk checkout to enable raw HID layer reporting.
# Usage: VIAL_QMK_DIR=~/vial-qmk ./apply.sh [keymap]
set -euo pipefail

VIAL_QMK_DIR="${VIAL_QMK_DIR:-$HOME/vial-qmk}"
KEYBOARD="${KEYBOARD:-beekeeb/piantor}"
KEYMAP="${1:-vial}"

KEYMAP_DIR="$VIAL_QMK_DIR/keyboards/$KEYBOARD/keymaps/$KEYMAP"
RULES_MK="$KEYMAP_DIR/rules.mk"
KEYMAP_C="$KEYMAP_DIR/keymap.c"
REPORT_C="$KEYMAP_DIR/layer_report.c"

if [[ ! -d "$KEYMAP_DIR" ]]; then
    echo "ERROR: keymap directory not found: $KEYMAP_DIR"
    echo "Set KEYBOARD= and/or KEYMAP= to match your layout, e.g.:"
    echo "  KEYBOARD=beekeeb/piantor_pro KEYMAP=default ./apply.sh"
    exit 1
fi

# --- rules.mk ---
if grep -q 'RAW_ENABLE' "$RULES_MK" 2>/dev/null; then
    echo "RAW_ENABLE already present in rules.mk — skipping."
else
    echo "RAW_ENABLE = yes" >> "$RULES_MK"
    echo "Added RAW_ENABLE = yes to $RULES_MK"
fi

# --- layer_report.c ---
if [[ -f "$REPORT_C" ]]; then
    echo "layer_report.c already exists in keymap dir — overwriting."
fi
cp "$(dirname "$0")/layer_report.c" "$REPORT_C"
echo "Copied layer_report.c to $REPORT_C"

# --- SRC += in rules.mk ---
# QMK does not auto-compile extra .c files in the keymap directory;
# they must be listed explicitly.
if grep -q 'SRC.*layer_report' "$RULES_MK" 2>/dev/null; then
    echo "SRC += layer_report.c already present in rules.mk — skipping."
else
    echo "SRC += layer_report.c" >> "$RULES_MK"
    echo "Added SRC += layer_report.c to $RULES_MK"
fi

echo ""
echo "Done. Now run flash.sh to compile and flash."
