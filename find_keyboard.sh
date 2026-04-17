#!/usr/bin/env bash
# Prints VID/PID of HID devices with the Vial raw HID usage page (0xFF60).
# Requires: python3 + hidapi — installed automatically by quickstart.sh into .venv/
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_PYTHON="$REPO_DIR/.venv/bin/python3"
PYTHON="${VENV_PYTHON:-python3}"
[[ -x "$VENV_PYTHON" ]] && PYTHON="$VENV_PYTHON"

"$PYTHON" - "$@" <<'EOF'
import hid, sys, json

VIAL_USAGE_PAGE = 0xFF60
VIAL_USAGE      = 0x61

as_json = "--json" in sys.argv[1:]

devices = [
    d for d in hid.enumerate()
    if d['usage_page'] == VIAL_USAGE_PAGE and d['usage'] == VIAL_USAGE
]

if not devices:
    if as_json:
        print(json.dumps([]))
    else:
        print("No Vial raw HID device found.")
        print("Make sure the keyboard is plugged in and the firmware has RAW_ENABLE = yes.")
    sys.exit(1)

if as_json:
    print(json.dumps([
        {"vid": d['vendor_id'], "pid": d['product_id'],
         "manufacturer": d['manufacturer_string'], "product": d['product_string']}
        for d in devices
    ]))
else:
    for d in devices:
        vid, pid = d['vendor_id'], d['product_id']
        print(f"Found: {d['manufacturer_string']} {d['product_string']}")
        print(f"  VID = {vid:#06x}")
        print(f"  PID = {pid:#06x}")
        print(f"  Path: {d['path'].decode()}")
        print()
EOF
