# REDMAGIC VC Cooler 6 Pro — Reverse Engineering Findings

## Device

- **Model:** REDMAGIC VC Cooler 6 Pro Magnetic Edition
- **BLE name:** `RM Magcooler 6pro`
- **BLE identifier:** assigned per-host by CoreBluetooth, so yours will
  differ — the app saves it after the first connection
- **GATT service:** `d52082ad-e805-9f97-9d4e-1c682d9c9ce6`

---

## Hardware

The cooler contains two independent systems:

- **TEC (Thermoelectric/Peltier element):** actively pumps heat from your phone (cold side) to the cooler's body (hot side). Controlled by char `0x1011`.
- **Fan:** dissipates heat from the hot side of the TEC. Controlled independently by char `0x1012`. Fan speed has zero effect on TEC power and vice versa.
- **Hall effect sensor:** detects magnetic attachment of a phone via char `0x1015`.

---

## GATT Characteristic Map

| UUID suffix | Name           | Access    | Notes |
|-------------|----------------|-----------|-------|
| `0x1011`    | Cooling mode   | R/W       | TEC power level — see modes below |
| `0x1012`    | Fan speed      | R/W       | 0–100 (percent) |
| `0x1013`    | Light / colour | R/W       | 4 bytes `[mode, R, G, B]` — see below |
| `0x1014`    | Temp threshold | R/W       | °C, used by auto-temp feature |
| `0x1015`    | Hall sensor    | R/Notify  | `[4, x]` = phone attached, `[5, 0]` = detached |
| `0x1016`    | Telemetry      | R/Notify  | 16-byte frame, 1 Hz — see below |
| `0x1017`    | Unknown        | R         | Always `0x00` |
| `0x1018`    | Auto-temp      | R/W       | `0x00`=off, `0x01`=on |
| `0x1019`    | Unknown        | R         | Always `0x00` |

---

## Cooling Modes (char `0x1011`)

The device accepts values 0x01–0x08. The Goper app only exposes three of them.

| Value  | App name      | TEC power | Hot-side temp (observed) |
|--------|---------------|-----------|--------------------------|
| `0x03` | OFF           | off       | ~6°C (ambient drift)     |
| `0x01` | Low           | low       | ~10°C                    |
| `0x02` | Medium        | medium    | ~40°C                    |
| `0x04` | (unlisted)    | higher    | ~16°C                    |
| `0x05` | (unlisted)    | higher    | ~26°C                    |
| `0x06` | (unlisted)    | higher    | ~45°C                    |
| `0x07` | (unlisted)    | higher    | ~65°C                    |
| `0x08` | Super / Max   | max       | ~69°C                    |

Values 0x04–0x08 are not shown in the app UI but the firmware accepts and executes them without any authentication. Mode 0x08 is believed to be equivalent to Goper's "Super Mode" (overclocked Peltier).

**Fan speed is fully independent.** Writing a new cooling mode does not reset the fan speed.

---

## LED Light / Colour (char `0x1013`)

Takes a **4-byte** value `[mode, R, G, B]`. Byte 0 selects the effect; the
following three bytes are the RGB colour (R,G,B order, 0–255), honoured only by
the two single-colour effects.
**The LED only illuminates while the cooler (TEC) is actually running.**

Probed on-device with `tools/probe/probe_light.sh`; full sweep in
[`led_mapping.md`](led_mapping.md). This table is what
`LedEffect.DeviceEffect` implements.

| Byte 0 | Effect              | Colour bytes | Observed on-device                  |
|--------|---------------------|--------------|-------------------------------------|
| `0`    | Off                 | ignored      | LED off                             |
| `1`    | Rainbow             | ignored      | all colours at once                 |
| `2`    | Colourful breath    | ignored      | breathes through the whole wheel    |
| `3`    | Monochrome breath   | **used**     | breathes the given colour           |
| `4`    | **Static**          | **used**     | steady single colour from `[R,G,B]` |

Example: `04 ff 00 00` = static red, `04 00 ff 00` = static green,
`04 00 00 ff` = static blue. Verified on-device.

Bytes above 4 alias back onto these five rather than adding anything new. Read
the sweep with one caveat: rows recorded while the app's LED effect was on
**Auto** can read as "solid single colour" whatever byte was written, because
Auto repaints the LED with the static byte whenever the die temperature moves.
That is why the sweep's byte `0` row disagrees with this table.

Two earlier readings of this table were wrong and are worth naming, because both
are easy to arrive at again: the first guess (`1=Solid 2=Breath 3=Colorful
4=Flash`) had static on the wrong byte, and a later pass read byte `3` as a
rotating rainbow that ignored the colour bytes. It does not — it breathes the
colour you give it.

---

## Telemetry Frame (char `0x1016`)

16-byte little-endian frame, pushed at ~1 Hz via BLE notify.

```
Byte  Content
  0   0xAA (frame start marker)
  2   Cold-side temperature (°C)
  3   Hot-side temperature (°C)
  5   Cold-side temperature (duplicate)
  6   Hot-side temperature (duplicate)
  7   Ambient temperature (°C)
 13   Fan RPM low byte  ╮ uint16 little-endian
 14   Fan RPM high byte ╯
 15   0xDD (frame end marker)
```

Example decode (Python):
```python
cold_c   = data[2]
hot_c    = data[3]
ambient  = data[7]
fan_rpm  = int.from_bytes(data[13:15], "little")
```

---

## Flash Persistence

The device has a cmd characteristic that can write settings to internal flash (survives power cycles).

| Command bytes  | Effect                          |
|----------------|---------------------------------|
| `aa631102dd`   | Persist ON (medium) to flash    |
| `aa631103dd`   | Crashes the BLE stack — avoid   |

Persistent OFF could not be found without a bonded BLE connection. The Goper app uses an existing bond to authenticate flash writes. CoreBluetooth on macOS blocks app-layer bonding, so this path is not accessible from Mac.

**Workaround:** use the Goper app once to set flash state to OFF, then use the
menu-bar app for daily control. The app reconnects automatically after a power
cycle and resumes temperature-driven cooling when needed.

---

## BLE Auth / Pairing

The device uses a User Description descriptor (`0x2901`) as a custom auth channel. The Goper app sends a bonded write sequence before issuing flash commands.

macOS CoreBluetooth returns `"Pairing is not available in Core Bluetooth"` when bonding is attempted — this is a platform restriction with no known workaround.

---

## Controller architecture

The controller is a native Swift menu-bar app (`RedMagic Cooler.app`). All
day-to-day control, device selection, and telemetry live in its status menu.
See the [README](../README.md) for usage and the source layout.

- **The app is the only process that talks to the cooler.** The device accepts a
  single BLE connection, so everything funnels through one owner.
- **Selection is explicit.** On first launch and after **Change Device**,
  discovered devices appear inside the status menu and require a click before
  connecting, even when only one supported cooler is found.
- **The app keeps ownership orderly.** A new app launch asks an existing copy to
  quit cleanly before taking the cooler's single connection slot.
- **Protocol probes are isolated.** The scripts in `tools/probe/` use a narrow
  developer-only JSON bridge for raw experiments; it is not an app control
  surface.

### Key implementation notes

- **Fan writes must trail mode writes.** A fan value arriving in the same
  connection interval as a mode change is silently dropped by the firmware, so
  `CoolerBLEManager.apply(mode:fanPercent:)` defers the fan write by 200 ms.
  Every caller changing both goes through it.
- **Heartbeat.** Mode and fan are re-asserted every 30 s, so a dropped write
  can't leave the UI and the hardware disagreeing indefinitely.
- **Auto-reconnect** after a 5 s delay when the link drops (e.g. the cooler is
  power-cycled).
- **The single connection slot** is not released promptly on a half-open link —
  the device holds it until its supervision timeout. So: launch terminates any
  prior app instance and waits for it to exit; a stale system-level link is
  explicitly cancelled before reconnecting; `connect()` carries an 8 s watchdog
  because CoreBluetooth's has none; and quit holds termination open until the
  disconnect is confirmed.

### LED effect bytes

All five are exposed in the menu, mapped in `LedEffect.DeviceEffect` — see
[LED Light / Colour](#led-light--colour-char-0x1013) above for the byte table.
The app's own `Auto` effect is not a device effect: it writes the static
colour (byte `4`) on a timer, graded by die temperature.

---

## What Works

| Feature | Status |
|---------|--------|
| Turn ON / OFF | Working |
| Set TEC power level (all 8 modes) | Working |
| Set fan speed 0–100% | Working |
| Read live temps (cold / hot / ambient) | Working |
| Read fan RPM | Working |
| Read light mode | Working |
| Detect phone attachment (hall sensor) | Working |
| Auto-reconnect after power cycle | Working |
| Persistent ON across power cycles | Working (`aa631102dd`) |
| Persistent OFF across power cycles | Not accessible from Mac (requires BLE bond) |
| BLE pairing / bonding | Blocked by CoreBluetooth |

---

## Tools Used

- [`bleak`](https://github.com/hbldh/bleak) — Python BLE library (CoreBluetooth backend on macOS)
- Android ADB over WiFi + `btsnoop_hci.log` — captured BLE traffic from the Goper app
- APK decompilation — confirmed characteristic UUIDs and command format
