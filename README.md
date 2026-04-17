# Vial Layer Indicator

A COSMIC desktop panel applet that displays the active layer of any Vial-based QMK keyboard in real time, using raw HID communication.

## Overview

This project has two components:

- **Firmware patch** — adds raw HID layer reporting to your vial-qmk keymap
- **Panel applet** — reads the active layer every 100 ms and shows it in the COSMIC panel

## Quickstart

Run the interactive setup script from the repo root:

```bash
./quickstart.sh
```

It walks through every step below, offering to install missing prerequisites along the way.

## Manual setup

### 1. Patch and flash the firmware

```bash
# Patch your vial-qmk checkout (set KEYBOARD/KEYMAP to match your board)
KEYBOARD=beekeeb/piantor KEYMAP=vial firmware/apply.sh

# Compile and flash (left, right, or both halves)
./flash.sh both
```

`apply.sh` enables `RAW_ENABLE` and installs the layer reporting callback (`layer_report.c`).
It is idempotent — safe to run again after updates.

> **Back up your Vial layout first** (File → Save Current Layout in the Vial app).
> Flashing can reset EEPROM on first boot, wiping keymap customisations.

### 2. Find your keyboard's VID and PID

```bash
./find_keyboard.sh
```

Prints the vendor ID, product ID, and device path of connected Vial HID devices.
Requires Python 3 and the `hidapi` package (`pip install hidapi`), or use `quickstart.sh` to install them automatically into a local venv.

### 3. Install the applet

```bash
KBD_VID=0x3A3B KBD_PID=0x0001 ./install-applet.sh
```

The script:
- Builds the Rust binary and installs it to `~/.local/bin/vial-layer`
- Installs the `.desktop` file to `/usr/share/applications/` (requires sudo)
- Persists `KBD_VID` / `KBD_PID` in `~/.config/environment.d/vial-layer.conf`

### 4. Install the udev rule

```bash
# Edit the file first to fill in your VID and PID (without 0x prefix)
sudo cp udev/99-vial-hid.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger
```

This allows the applet to open the HID device without root.
`quickstart.sh` fills in the VID/PID automatically.

### 5. Add to COSMIC panel

Right-click the panel → Edit Panel → Add Applet → **Vial Layer Indicator**.

Log out and back in first if the applet doesn't appear (the environment variables need a fresh session).

## Configuration

Create `~/.config/vial-layer/config.toml` to name your layers:

```toml
layers = [
    "Base",   # 0
    "Nav",    # 1
    "Sym",    # 2
    "Fn",     # 3
]
```

Layers without a name fall back to `Layer N`. See [applet/data/config.toml.example](applet/data/config.toml.example) for a full example.

### Environment variables

| Variable | Default | Description |
|---|---|---|
| `KBD_VID` | — | USB vendor ID (required) |
| `KBD_PID` | — | USB product ID (required) |
| `VIAL_LAYER_CONFIG` | `~/.config/vial-layer/config.toml` | Path to config file |

## Applet behaviour

- **Right-click menu** — pause/resume polling and reload the config file without restarting
- **Vial compatibility** — polling is automatically suspended while the Vial app is open, preventing HID command conflicts
- **Display states** — `disconnected` (keyboard not found), `no firmware support` (layer query unhandled by firmware), `paused` (polling paused by user)

## How it works

`apply.sh` adds `RAW_ENABLE = yes` and `layer_report.c` to the vial-qmk keymap.
The firmware implements `raw_hid_receive_kb()`: when the applet sends command byte `0x42`, the keyboard responds with the current layer index from `get_highest_layer(layer_state)`.
The applet polls every 100 ms via the Vial raw HID interface (usage page `0xFF60`, usage `0x61`).

## Project structure

```
├── applet/           # COSMIC panel applet (Rust + libcosmic + hidapi)
│   ├── src/main.rs
│   ├── Cargo.toml
│   └── data/
│       ├── vial-layer.desktop
│       └── config.toml.example
├── firmware/
│   ├── layer_report.c  # QMK raw HID callback
│   └── apply.sh        # Patches vial-qmk to enable layer reporting
├── udev/
│   └── 99-vial-hid.rules
├── find_keyboard.sh    # Discover keyboard VID/PID
├── flash.sh            # Compile and flash firmware
├── install-applet.sh   # Build and install the applet
└── quickstart.sh       # Interactive end-to-end setup
```
