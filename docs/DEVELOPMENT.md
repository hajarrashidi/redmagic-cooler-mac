# Development

RedMagic Cooler is a native Swift/AppKit menu-bar app. CoreBluetooth owns the
cooler's single connection, while temperature and autopilot logic stay
separate from the UI and hardware transport.

## Build and run

Install Apple's Xcode command-line tools, then run:

```bash
./build.sh --run
```

`build.sh` compiles the Swift sources and assembles the app bundle. `release.sh`
builds a DMG and can sign and notarize it for distribution.

## Project layout

```text
build.sh                build the app bundle
release.sh              build a distributable DMG
Resources/              app icon and bundled resources
src-swift/
  App/                  lifecycle, menu, actions, refresh, BLE callbacks
  Core/                 autopilot, thermal, LED, config, and logging
  BLE/                  CoreBluetooth I/O and device profiles
  Probe/                developer-only bridge for protocol experiments
  UI/                   custom AppKit menu views
docs/                   user, protocol, and contributor guides
tools/probe/            protocol experiment scripts
```

`Core/` has no AppKit dependency, so the decision logic can be understood and
tested without the menu code. Everything under `tools/` is for protocol work,
not normal app control.

## Where to go next

- [`AUTOPILOT.md`](AUTOPILOT.md) explains the temperature ladder, hysteresis,
  dwell, safety floor, and tuning points.
- [`FINDINGS.md`](FINDINGS.md) documents the mapped VC Cooler 6 Pro GATT
  service, payloads, telemetry, and connection behaviour.
- [`ADDING_DEVICES.md`](ADDING_DEVICES.md) walks through adding a profile for
  another Bluetooth cooler.
- [`../tools/probe/README.md`](../tools/probe/README.md) explains the probe
  scripts and developer-only JSON bridge.

## Device profiles

All model-specific discovery and protocol information lives in
[`DeviceProfile.swift`](../src-swift/BLE/DeviceProfile.swift). A profile
contains the advertised-name hints, GATT service and characteristic UUIDs, and
telemetry decoder. The rest of the app follows whichever profile matched.

Do not assume another REDMAGIC cooler shares the VC Cooler 6 Pro protocol.
Capture and verify its GATT table and payloads on physical hardware before
marking it supported.
