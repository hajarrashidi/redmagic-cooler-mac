# redmagic-cooler-mac

Drive a REDMAGIC VC Cooler 6 Pro from macOS over Bluetooth, and point it at your
Mac instead of a phone.

The Cooler 6 Pro is a magnetic phone cooler with a Peltier plate in it. It's
cheap, it gets genuinely cold, and it's a perfectly good laptop cooling pad if
you sit it under a MacBook. The problem is that it only ships with an Android
app, so there's no way to control it from a Mac and certainly no way to make it
react to how hot the Mac is.

So this is that: a menu-bar app that speaks the cooler's BLE protocol, plus an
autopilot that ramps cooling up and down based on your Mac's actual die
temperature.

The protocol isn't documented anywhere. I worked it out from BLE packet captures
and the vendor APK; the notes are in [docs/FINDINGS.md](docs/FINDINGS.md) if
you're doing something similar with another device.

## What it does

- Menu-bar app showing your Mac's die temperature, tinted by how hot it is
- Autopilot that drives the cooler from that temperature, with hysteresis so it
  doesn't flap on and off
- Manual mode with a ten-step power slider
- Full control of the cooler's ring LED, including a mode that uses it as a heat
  gauge (green when cool, red when hot)
- Live telemetry from the cooler: cold plate, hot side, ambient, fan RPM
- A shell CLI for scripting, with no dependencies

## Install

Grab the DMG from [Releases](https://github.com/hajarrashidi/redmagic-cooler-mac/releases),
open it, and drag the app to Applications.

The app isn't notarized by Apple, so the first launch takes an extra step:
macOS will refuse to open it and say it can't check for malicious software.
Go to **System Settings > Privacy & Security**, scroll to the bottom, and click
**Open Anyway** next to the message about RedMagic Cooler. You only do this
once.

(If you've seen the old right-click-and-pick-Open trick, that stopped working
in macOS 15. System Settings is the only route now.)

Or build it yourself, which sidesteps the whole thing:

```bash
git clone https://github.com/hajarrashidi/redmagic-cooler-mac.git
cd redmagic-cooler-mac
./build.sh --run
```

You need the Xcode command-line tools (`xcode-select --install`). Either way,
macOS asks for Bluetooth permission on first launch.

## Using it

Most of the time you'll just use the menu-bar app. There's also a CLI:

```bash
./cooler                        # open the app
./cooler on [low|medium|max]    # fixed cooling level
./cooler auto [standard|custom] # temperature-driven
./cooler off
./cooler fan 60                 # fan speed, 0-100
./cooler status
./cooler monitor                # live telemetry stream
./cooler log -f                 # follow the decision log
```

The CLI doesn't talk to the cooler itself. The device only accepts one
Bluetooth connection at a time, so the app owns it and the CLI leaves JSON
command files in `$HOME` for the app to pick up. That also means `status` and
`monitor` are free — they read a cache the app keeps current, rather than
fighting for the connection.

## The autopilot

Auto mode reads your Mac's SoC die temperature straight from the Apple Silicon
thermal sensors through IOKit's HID interface. No `sudo`, nothing to install.
It's a fast signal — it moves within a couple of seconds of the machine getting
busy.

macOS also exposes `ProcessInfo.thermalState`, but that thing is so heavily
damped it'll sit on `nominal` through minutes of full load. It's useless as a
primary signal, so it's only used as a floor: if the OS says `serious` or
`critical`, the cooler runs hard no matter what the sensors say.

There are five tiers, from off to max, and the default profile engages at 40°C:

| Die temp | Tier    | TEC     | Fan   |
|----------|---------|---------|-------|
| < 40°C   | off     | off     | 0%    |
| 40°C     | low     | low     | 60%   |
| 50°C     | med-low | med-low | 80%   |
| 62°C     | medium  | medium  | 95%   |
| 74°C     | max     | max     | 100%  |

That's deliberately eager. The plate is sitting against the chassis, so it
actually helps while the Mac is only warm, not just when it's melting. If you'd
rather it stayed quiet until things get serious, switch to the Custom profile
and set your own engage point — the remaining tiers space themselves 10°C apart
above it.

Going up is instant. Coming down is not: a tier only releases once the
temperature drops 5°C below the point that engaged it, and then only after
holding there for 15 seconds, and then only one tier at a time. Rapid-cycling a
Peltier is bad for it and pointless.

Fan percentages aren't linear in RPM, by the way. The firmware's response curve
is U-shaped, so those numbers come from an RPM probe rather than from anything
sensible.

More detail in [docs/AUTOPILOT.md](docs/AUTOPILOT.md).

## Notes on the Bluetooth side

Two things about this device shaped a lot of the code.

**It doesn't advertise its service UUID.** Filtering a scan by service will
never find it. You have to scan for everything and match on the device name
(`RM Magcooler 6pro`).

**It only accepts one connection, and it doesn't let go.** If a process dies
holding the link, the cooler keeps believing it's connected until its
supervision timeout, and nothing else can connect in the meantime. So launching
the app terminates any previous instance and waits for it to actually exit; a
stale system-level link gets explicitly cancelled before reconnecting;
`connect()` has an 8-second watchdog because CoreBluetooth's has none of its
own; and quitting holds termination open until the disconnect is confirmed.

If you're writing something for this device, those two are where you'll lose an
evening.

## Layout

```
cooler                bash CLI
build.sh              compiles src-swift into the app bundle
release.sh            builds a DMG, optionally signed and notarized
src-swift/
  App/                lifecycle, menu, actions, UI refresh, BLE callbacks
  Core/               domain logic: autopilot, thermal, LED, config, logging
  BLE/                CoreBluetooth: discovery, connection, GATT I/O
  IPC/                the file protocol shared with the CLI
  UI/                 AppKit views (custom-drawn menu rows)
docs/FINDINGS.md      protocol notes: GATT map, frame layout, mode bytes
docs/AUTOPILOT.md     how the autopilot and the LED heat gauge work
docs/led_mapping.md   probed LED effect bytes
probe_*.sh            scripts used to map the protocol
```

`Core/` has no AppKit in it, so the interesting logic — the autopilot especially
— can be read without wading through view code.

## Requirements

- macOS 13 or later
- Apple Silicon (the die-temperature read is Apple Silicon only; an Intel Mac
  will fall back to the OS thermal state and the autopilot will be much less
  useful)
- A REDMAGIC VC Cooler 6 Pro

## Caveats

The die-temperature read uses private IOKit symbols. They're undocumented and
Apple could rename them in any release; if that happens the app keeps working
but loses the fine-grained temperature and falls back to thermal state alone.

Persistent-off across a power cycle needs a BLE bond, which CoreBluetooth won't
do. The device will come back on after being unplugged and replugged.

This is not affiliated with or endorsed by Nubia/REDMAGIC. It's a
reverse-engineered third-party controller, so nothing here is guaranteed to
survive a firmware update.

## License

MIT — see [LICENSE](LICENSE).
