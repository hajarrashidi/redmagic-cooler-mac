<div align="center">

# RedMagic Cooler for macOS

**A native menu-bar controller that cools your Mac automatically with a
Bluetooth REDMAGIC phone cooler.**

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)](docs/GETTING_STARTED.md#requirements)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-native-black)](docs/GETTING_STARTED.md#requirements)
[![Swift](https://img.shields.io/badge/Swift-AppKit%20%2B%20CoreBluetooth-orange)](docs/DEVELOPMENT.md)
[![Latest release](https://img.shields.io/badge/release-latest-blue)](https://github.com/hajarrashidi/redmagic-cooler-mac/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

https://github.com/user-attachments/assets/5cb1d11a-144d-45fd-8af2-f1497c26474c

</div>

## What it does

The app reads your Mac's temperature and controls a connected REDMAGIC cooler
over Bluetooth. Auto mode starts cooling as the Mac heats up, changes power
with temperature, and eases back down after it cools. You can also take manual
control, adjust the engage threshold, choose LED effects, and view cooler
telemetry.

The Bluetooth protocol was reverse-engineered from packet captures and the
vendor app. See the [protocol findings](docs/FINDINGS.md) for the full mapping.

## Device support

The **REDMAGIC VC Cooler 6 Pro** is currently the only supported and
hardware-verified model.

The **REDMAGIC Cryo Cooler 8 Pro** is REDMAGIC's latest app-connected cooler as
of September 2026. It has **not been tested or verified with this project** and
is not currently supported. Other Bluetooth/app-controlled models are also
unverified; button-only coolers are outside this project's scope.

Read [device compatibility](docs/COMPATIBILITY.md) for the researched model
list, evidence, and exact support status. If you own an untested Bluetooth
cooler, follow [Adding support for another cooler](docs/ADDING_DEVICES.md).

## Quick start

Requires macOS 13 or later, Apple Silicon for responsive die-temperature
control, and a supported cooler. macOS asks for Bluetooth permission on first
launch.

Download the DMG from the
[latest release](https://github.com/hajarrashidi/redmagic-cooler-mac/releases/latest),
or build locally with Xcode command-line tools:

```bash
git clone https://github.com/hajarrashidi/redmagic-cooler-mac.git
cd redmagic-cooler-mac
./build.sh --run
```

Open the menu-bar app, press **Allow Bluetooth Access**, then **Scan**, and
click your cooler. After that the menu leads with the cooler's own panel and its
**Connect** button.
The Auto/Manual controls appear after a connection is established, with Auto
as the default. See [Getting started](docs/GETTING_STARTED.md) for installation,
daily use, updates, and limitations.

## Documentation

| Topic | Guide |
|-------|-------|
| Install, connect, and use the app | [Getting started](docs/GETTING_STARTED.md) |
| Supported and untested coolers | [Device compatibility](docs/COMPATIBILITY.md) |
| Temperature thresholds and automatic cooling | [Autopilot](docs/AUTOPILOT.md) |
| Reverse-engineered BLE protocol | [Protocol findings](docs/FINDINGS.md) |
| Add a new Bluetooth cooler | [Adding devices](docs/ADDING_DEVICES.md) |
| LED effect bytes | [LED mapping](docs/led_mapping.md) |
| Build and understand the codebase | [Development](docs/DEVELOPMENT.md) |

Contributions and partial hardware findings are welcome. An advertised BLE
name or GATT dump can be enough to help the next person continue the work.

## Disclaimer and license

This project is not affiliated with or endorsed by Nubia/REDMAGIC. It is a
reverse-engineered third-party controller; use it at your own risk.

[MIT](LICENSE)
