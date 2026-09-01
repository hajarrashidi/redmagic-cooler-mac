# Getting started

This guide covers installing RedMagic Cooler for macOS, connecting a cooler,
and using the menu-bar controls. For supported hardware, see
[`COMPATIBILITY.md`](COMPATIBILITY.md).

## Requirements

- macOS 13 Ventura or later.
- Apple Silicon for direct SoC die-temperature readings. On an Intel Mac, the
  app falls back to macOS's coarser thermal state, so Auto mode is less
  responsive.
- A supported Bluetooth cooler.

The app asks for Bluetooth permission when you press **Allow Bluetooth
Access**, not at launch.

## Install a release

Download the DMG from the
[latest GitHub release](https://github.com/hajarrashidi/redmagic-cooler-mac/releases/latest),
open it, and drag **RedMagic Cooler** to Applications.

Releases are signed with a Developer ID certificate and notarized by Apple.
The app checks GitHub for updates at launch and once per day while running. If
one is available a banner offers it — **nothing installs until you press it**.
Doing so turns the cooler off and disables the rest of the menu while the swap
runs, because the app replaces itself and relaunches. You can skip a version,
and if the install cannot finish the banner opens the release page instead.

## Build from source

Install Apple's Xcode command-line tools with `xcode-select --install`, then:

```bash
git clone https://github.com/hajarrashidi/redmagic-cooler-mac.git
cd redmagic-cooler-mac
./build.sh --run
```

A local build does not need to pass through Gatekeeper.

## Connect a cooler

1. Power the cooler and open RedMagic Cooler from the menu bar.
2. On a first run the **Available devices** picker is already there, because
   the app has no cooler to connect to yet. Press **Allow Bluetooth Access** —
   the app does not touch Bluetooth, and so does not trigger the macOS
   permission prompt, until you ask it to.
3. Press **Scan**, then click a cooler under *Supported*.
4. Once a cooler has been chosen, the menu leads with its panel instead, and
   **Connect** on that panel reconnects to it. The line under the model name
   reads **Connected over Bluetooth** once the link is live, and reports the
   connection's progress before that.

If access was refused at some point, the button becomes **Open Bluetooth
Settings** — macOS only asks once, so System Settings → Privacy & Security →
Bluetooth is the only way back.

The control rows stay hidden until a connection succeeds. After connecting,
the app defaults to **Auto** and shows the Auto/Manual switch, engage-threshold
slider, cooler status, and light controls in the cooler section.

To use a different cooler, choose **Change Device**, which brings the picker
back. Every named device in range is listed. Coolers the app has no profile for
appear greyed out and cannot be selected — the picker names the models it does
support and links to the porting guide.

## Use the controls

- **Auto** follows the Mac's temperature. The engage-threshold slider chooses
  when cooling begins; higher power tiers are derived from that value. The
  detailed ladder and cooldown behaviour are in [`AUTOPILOT.md`](AUTOPILOT.md).
- **Manual** holds the level selected with the power slider until you change it.
  Because nothing else will end that session, Manual carries an **auto-off**
  limit — 1, 2 or 3 hours, with the time left shown beside it. When it runs out
  the cooler switches off and stays off; it does not hand back to Auto, which
  would simply start it again. Choosing **∞** removes the limit and asks you to
  confirm: a thermoelectric plate held cold for hours condenses moisture onto
  itself whether or not anyone is at the Mac.
- **Cooler effect** changes the cooler's LED mode and colour. The Auto effect
  uses colour as a heat gauge.
- **Turn Off** stops cooling while keeping the connection available.
- **Turn Off & Quit** stops the cooler, releases its Bluetooth link, and closes
  the app. It is the way out — a cooler must never be left running with nothing
  controlling it, so quitting always turns it off first.

The menu-bar readout shows the Mac's current die temperature beside a plain
white mark. Connected cooler telemetry includes cold-plate, hot-side, ambient,
and fan-speed readings, with the cooler's own line reporting anything that needs
saying — a switch that is off, a change in flight, or Auto waiting for the Mac
to warm up.

The cooler reports plate temperatures only while actively cooling. A cold or
hot reading of `0 °C` while off is device behaviour, not a sensor fault.

## Known limitations

- Direct die-temperature readings use private IOKit symbols. If Apple changes
  them, the app continues with the less responsive macOS thermal state.
- The cooler accepts one Bluetooth connection. After an interrupted process,
  its firmware may hold that connection until the supervision timeout expires.
- Keeping the VC Cooler 6 Pro off across a power cycle requires a BLE bond that
  CoreBluetooth cannot establish here. The cooler may turn on after power is
  removed and restored; the app reconnects and resumes the selected control
  mode.

For the underlying connection workarounds and protocol details, see
[`FINDINGS.md`](FINDINGS.md#controller-architecture).
