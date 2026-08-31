<div align="center">

# RedMagic Cooler for macOS

**Automatically cool your Mac from the menu bar: the app turns the cooler on
as your Mac heats up, ramps its power with the temperature, and turns it off
again once cooling is no longer needed.**

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)](#requirements)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-native-black)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-AppKit%20%2B%20CoreBluetooth-orange)](#project-layout)
[![Latest release](https://img.shields.io/badge/release-latest-blue)](https://github.com/hajarrashidi/redmagic-cooler-mac/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

<img src="docs/screenshot.png" width="324" alt="The menu, showing Mac temperature, cooler telemetry and the autopilot controls">

</div>

## About

The REDMAGIC VC Cooler 6 Pro is a magnetic phone cooler with a Peltier plate
in it. It is inexpensive, it gets genuinely cold, and it works well as a
laptop cooling pad if you sit it under a MacBook — but its companion app is
only available for Android and iOS, so there is no way to control it from a
Mac, let alone make it react to how hot the Mac is.

This project fills that gap: a native menu-bar app that speaks the cooler's
Bluetooth LE protocol and runs it fully automatically — switching the cooler
on when the Mac gets warm, ramping the cooling level up and down to match the
die temperature, and switching it back off when the Mac has cooled down.

The protocol is not documented anywhere. It was reverse-engineered from BLE
packet captures and the vendor APK; the complete notes are in
[docs/FINDINGS.md](docs/FINDINGS.md) if you are doing something similar with
another device.

## Features

- **Menu-bar temperature readout** — your Mac's die temperature, colour-graded
  by how hot it is
- **Autopilot** — switches the cooler on and off and adjusts its power
  automatically from that temperature, with hysteresis and a cooldown dwell so
  it never rapid-cycles the Peltier
- **Manual mode** — a ten-step power slider
- **Full LED control** — every ring effect, including a heat-gauge mode
  (green when cool, red when hot)
- **Live telemetry** — cold plate, hot side, ambient and fan RPM, streamed
  from the cooler

## Supported devices

| Model | Year | Control | Works with this app? |
|-------|------|---------|----------------------|
| [VC Cooler 6 Pro](https://redmagic.tech/products/redmagic-vc-cooler-6-pro) | 2025 | Bluetooth LE (Goper app) | ✅ **Supported** — the device the protocol was mapped on |
| VC Cooler 6 / 6 Air | 2025 | Bluetooth LE (Goper app) | ⚠️ Untested — same generation, protocol likely close |
| [VC Cooler 5 Pro](https://redmagic.tech/blogs/product-information/learn-more-about-the-technology-that-brings-you-the-redmagic-vc-cooler-5-pro) | 2024 | Bluetooth LE (Goper app) | ⚠️ Untested — BLE-controlled, worth trying |
| Dual-Core Ice Dock | 2022 | Bluetooth LE (Equipment app) | ❌ Older app family, protocol unknown |
| Turbo Cooler / Gen 4 | 2023 | Mechanical button | ❌ No radio to talk to |
| Ice Dock | 2020 | None | ❌ No radio |

If you own one of the untested BLE models, the app may already discover it —
scan matching is by name substring (`magcooler`, `rm cooler`) — and if the
firmware shares the 6 Pro's GATT layout it may simply work. If not, adding a
model is a documented, deliberately small job: see
[Adding support for another cooler](#adding-support-for-another-cooler).

## Installation

### Requirements

- macOS 13 (Ventura) or later
- Apple Silicon — the die-temperature read is Apple Silicon only. On an Intel
  Mac the app falls back to the OS thermal state and the autopilot is much
  less responsive.
- A supported cooler (see [above](#supported-devices))

macOS will ask for Bluetooth permission on first launch.

### Option 1 — Download the release

Download the DMG from the
[latest release](https://github.com/hajarrashidi/redmagic-cooler-mac/releases/latest),
open it, and drag **RedMagic Cooler** to Applications.

Releases are signed with a Developer ID certificate and notarized by Apple, so
the app opens without any Gatekeeper warnings.

The app checks for a newer release on GitHub each time it starts, and shows a
banner at the top of the menu when one is out. It never downloads or installs
anything itself — the banner opens the release page, and updating stays a
deliberate drag to Applications.

### Option 2 — Build from source

Building locally sidesteps Gatekeeper entirely. You need Apple's Xcode
developer tools (`xcode-select --install`):

```bash
git clone https://github.com/hajarrashidi/redmagic-cooler-mac.git
cd redmagic-cooler-mac
./build.sh --run
```

## Usage

On first launch — and after choosing **Change Device** — available supported
coolers appear directly inside the same menu. Click the device you want before
the app connects; selection is explicit even when the list contains only one
option.

After connecting, everything day-to-day stays in that menu: switch between
**Auto** and **Manual**, set the manual power level, pick LED effects and
colours, and watch live telemetry. The menu-bar icon shows the Mac's current
die temperature, tinted by heat.

## How the autopilot works

Auto mode reads the Mac's SoC die temperature directly from the Apple Silicon
thermal sensors through IOKit's HID interface — no `sudo`, nothing to install.
It is a fast signal that moves within a couple of seconds of the machine
getting busy.

macOS also exposes `ProcessInfo.thermalState`, but it is so heavily damped
that it sits on `nominal` through minutes of full load. It is therefore only
used as a floor: if the OS reports `serious` or `critical`, the cooler runs
hard no matter what the sensors say.

There are five tiers, from off to max. The default profile engages at 40 °C:

| Die temp | Tier    | TEC     | Fan   |
|----------|---------|---------|-------|
| < 40 °C  | off     | off     | 0 %   |
| 40 °C    | low     | low     | 60 %  |
| 50 °C    | med-low | med-low | 80 %  |
| 62 °C    | medium  | medium  | 95 %  |
| 74 °C    | max     | max     | 100 % |

That is deliberately eager: the plate sits against the chassis, so it helps
while the Mac is merely warm, not only when it is overheating. If you would
rather it stayed quiet until things get serious, switch to the **Custom**
profile and set your own engage point — the remaining tiers space themselves
10 °C apart above it.

Stepping up is instant. Stepping down is not: a tier only releases once the
temperature drops 5 °C below the point that engaged it, holds there for
15 seconds, and then steps down one tier at a time. Rapid-cycling a Peltier
element is bad for it and pointless.

Fan percentages are not linear in RPM — the firmware's response curve is
U-shaped, so the values above come from an RPM probe rather than from
anything obvious. Full detail in [docs/AUTOPILOT.md](docs/AUTOPILOT.md).

## Bluetooth implementation notes

Two facts about this device shaped a lot of the code:

- **It does not advertise its service UUID.** Filtering a scan by service will
  never find it; the app scans broadly and matches on the device name
  (`RM Magcooler 6pro`).
- **It accepts one connection and does not let go.** If a process dies holding
  the link, the cooler believes it is still connected until its supervision
  timeout, and nothing else can connect in the meantime. So launching the app
  terminates any previous instance and waits for it to exit; a stale
  system-level link is explicitly cancelled before reconnecting; `connect()`
  gets an 8-second watchdog because CoreBluetooth's has none of its own; and
  quitting holds termination open until the disconnect is confirmed.

If you are writing software for this device, those two are where you will
lose an evening.

## Development

### Project layout

```
build.sh                compiles src-swift into the app bundle
release.sh              builds a DMG, optionally signed and notarized
Resources/              AppIcon.icns, copied into the bundle at build time
src-swift/
  App/                  lifecycle, menu, actions, UI refresh, BLE callbacks
  Core/                 domain logic: autopilot, thermal, LED, config, logging
  BLE/                  CoreBluetooth I/O, plus DeviceProfile — the one file
                        that knows which cooler models exist
  Probe/                narrow developer-only bridge for protocol experiments
  UI/                   AppKit views (custom-drawn menu rows)
docs/FINDINGS.md        protocol notes: GATT map, frame layout, mode bytes
docs/ADDING_DEVICES.md  how to add support for another cooler model
docs/AUTOPILOT.md       how the autopilot and the LED heat gauge work
docs/led_mapping.md     probed LED effect bytes
tools/probe/            developer-only protocol experiments; not app controls
```

`Core/` contains no AppKit, so the interesting logic — the autopilot
especially — can be read without wading through view code. Everything under
`tools/` is for people hacking on the project, not for running it.

### Adding support for another cooler

Everything model-specific — the scan name to match, the GATT service and
characteristic UUIDs, how to decode a telemetry frame — lives in a single
file, [`src-swift/BLE/DeviceProfile.swift`](src-swift/BLE/DeviceProfile.swift).
The rest of the app is model-agnostic and follows the profile for whichever
discovered cooler the user selects, so supporting a new cooler means
reverse-engineering its protocol and writing one new profile.

[docs/ADDING_DEVICES.md](docs/ADDING_DEVICES.md) is the full walkthrough: how
to find the device's advertised name, map its GATT table, capture what the
vendor app sends, and verify the result with the probe scripts in
[`tools/probe/`](tools/probe/). [docs/FINDINGS.md](docs/FINDINGS.md) is the
finished worked example for the 6 Pro.

## Known limitations

- The die-temperature read uses private IOKit symbols. They are undocumented
  and Apple could rename them in any release; if that happens the app keeps
  working but falls back to the (much coarser) OS thermal state.
- Keeping the cooler off across a power cycle needs a BLE bond, which
  CoreBluetooth will not establish here. The device turns back on after being
  unplugged and replugged.

## Disclaimer

This project is not affiliated with or endorsed by Nubia/REDMAGIC. It is a
reverse-engineered third-party controller; nothing here is guaranteed to
survive a firmware update. Use at your own risk.

## License

[MIT](LICENSE)
