# REDMAGIC Cryo Cooler 8 Pro — Reverse Engineering Findings

How this model differs from the [VC Cooler 6 Pro](FINDINGS.md), and how the
app drives it. Everything below was observed on physical hardware with a raw
GATT explorer (connect, dump the table, write one byte, watch the notifications)
and with the app itself. Items that were **not** exercised are listed at the end.

## Device

- **Model:** REDMAGIC Cryo Cooler 8 Pro (magnetic)
- **BLE name:** `RM Magcooler 8pro`
- **GATT service:** `d52082ad-e805-9f97-9d4e-1c682d9c9ce6` (same as the 6 Pro)
- **Device Information service (`0x180A`):** manufacturer `Nubia Technology`,
  firmware revision `FV1B.3.6.8`, software revision `V8.4.7`
- **Second service** `00010203-0405-0607-0809-0A0B0C0D1912`: one `writeNR`
  characteristic and one read-only characteristic whose value contains the
  ASCII string `SRQ_8PRO_BLE_F80`
- The vendor Android app identifies it as device code `rm_charge_clip8_pro`
  (package `cn.nubia.externdevice`)

The name contains `magcooler`, like the 6 Pro. The 6 Pro profile matches on
that substring, so the 8 Pro profile uses the more specific `magcooler 8pro`
and is registered **before** the 6 Pro in `DeviceProfile.all` (first match
wins). Before this profile existed, an 8 Pro was listed as a 6 Pro and driven
with 6 Pro bytes.

---

## GATT Characteristic Map

| UUID suffix | Access | Meaning on the 8 Pro |
|-------------|--------|----------------------|
| `0x1011` | R/W | **On/off switch** for cooling: `02` on, `03` off |
| `0x1012` | R/W | **Cooling level**, `0x2e`–`0x50` (see below). Sets fan and TEC together |
| `0x1013` | R/W | Light, 4 bytes `[effect, R, G, B]` (see below) |
| `0x1014` | R | Live plate temperature, raw (same scale as the `04` status frame) |
| `0x1015` | R/Notify | **Status stream**: four-byte frames, one field each |
| `0x1016` | R/Notify | 16 bytes, always zero; **never notified** in any state tried |
| `0x1017` | R/W | "Diablo" mode: `01` on, `00` off. Maximum output |
| `0x1018` | R/W | Auto-temperature flag (reads `00`). Not exercised |
| `0x101C` | R | Live fan RPM, big-endian 16-bit (`0f1e` = 3870) |
| `0x101D` | R | Live power draw in watts, 1 byte |
| `0x101F` | R | Reads `0700ffff`. Unknown |

`0x1013` and `0x1014` advertise the notify property but have no client
configuration descriptor; enabling notifications fails with "attribute could
not be found". `0x101C` and `0x101D` are plain reads and are handy while probing
because the `0x1015` stream only reports changes.

On connect the device reports `0x1011 = 02` and `0x1012 = 00` while idle, so a
read-back at connect does not describe a running cooler. The profile sets
`readBackReflectsState = false`: the app keeps its own record of what it last
asked for instead of adopting these values, because adopting them would have the
30-second re-assert start the cooler.

---

## Cooling control (`0x1011`, `0x1012`)

This is the main difference from the 6 Pro, where `0x1011` selects TEC power and
`0x1012` is an independent fan percentage.

- `0x1011 = 03` stops everything: fan RPM goes to 0 and power to about 1 W,
  whatever `0x1012` holds. Writes to `0x1012` have no visible effect while it is
  off.
- `0x1011 = 02` starts cooling at the level held in `0x1012`.
- `0x1012` is a single **level** byte. The vendor app offers eight levels, the
  bytes below. The cooler spools slowly, so values settle over tens of seconds;
  the figures are readings of `0x101C` / `0x101D` after holding each level for
  50 s, stepping up from level 1 (they did not change in the following 6 s).
  Quicker steps read a level behind, so give any new measurement time.

| Level | Byte | Power | Fan RPM |
|-------|------|-------|---------|
| 1 | `2e` | 9 W | ~3,550 |
| 2 | `34` | 16 W | ~4,050 |
| 3 | `3a` | 23 W | ~4,200 |
| 4 | `40` | 26 W | ~4,550 |
| 5 | `44` | 26 W | ~4,950 |
| 6 | `48` | 29 W | ~4,980 |
| 7 | `4c` | 31 W | ~5,180 |
| 8 | `50` | 31 W | ~5,460 |

In free air with nothing against it, the plate reached about −20 °C (raw `0xf2`)
at the top levels within a minute. That is the reason for the app's plate limit
(Settings → Plate Limit…), which holds cooling back while the plate is under a
limit: the 8 Pro reports no ambient or humidity reading, so a dew point cannot be
worked out, and the plate temperature is the signal available.

- **Values below `0x2e` are not "lower".** `0x00`, `0x01`, `0x10` and `0x20` all
  ended at about 32 W and 5,300–5,500 RPM, as hard as level 8 or a little harder. An "off" that
  writes fan `0` therefore ramps the cooler up the next time it is switched on.
  The app never writes below `0x2e`.
- Values above `0x50` were tried (`0x58`, `0x64`) but the results were
  inconclusive because of the slow ramp; the app does not use them.
- **Diablo mode (`0x1017 = 01`)** reached 37 W and about 6,550 RPM within 12 s,
  the advertised ~36 W maximum. Writing `00` ends it, and moving to a lower level
  or Off over Bluetooth did the same.

### How the app maps its controls

The app's controls produce a cooling *mode* and a fan *percentage*. This device
has one axis, so the profile folds both into a level byte: each mode zone gets a
band, and the fan percentage moves within it over the range the app uses for
that zone (anything outside is clamped). Every Auto tier lands on a different,
rising level, and the profile sends Auto's four tiers as **levels 1, 2, 4 and 8**
(about 9, 16, 26 and 31 W) through `autoFanPercents`, so the gentlest tier is the
cooler's gentlest level.

| Zone | Level bytes | Fan speeds mapped | About |
|------|-------------|-------------------|-------|
| Low | `2e`–`3a` | 40–80 % | 9–23 W |
| Medium | `40`–`48` | 60–95 % | 26–29 W |
| Max | `4c`–`50` | 70–80 % | 31 W |
| Off | `0x1011 = 03`, level `2e` | | idle |

The **manual slider** does not fold anything. It offers the cooler's own steps:
Off, Level 1 to 8 (exactly the bytes above) and **Diablo**, which is level 8 with
`0x1017 = 01`. Every command that doesn't ask for it (Off, Turn Off & Quit, and
any Auto decision that isn't the Diablo stage) writes `0x1017 = 00` along with the
level, and the 30-second re-assert keeps whichever state was asked for. The default
Auto ladder never reaches it; a custom Auto curve has Diablo as its last stage and
uses it if the Mac gets that hot. The manual auto-off timer applies to it like any
other level. It is not something to leave running unattended: the plate goes well
below zero.

---

## LED Light / Colour (`0x1013`)

Four bytes `[effect, R, G, B]`, as on the 6 Pro, but with a different off byte.
Checked one byte at a time by eye:

| Byte 0 | Effect | Uses colour |
|--------|--------|-------------|
| `06` | **Off** | no |
| `01` | Rainbow, colours flowing | no |
| `02` | Colourful breath | no |
| `03` | Monochrome breath | yes |
| `04` | Steady colour | yes |
| `05` | Monochrome breath (same as `03`) | yes |
| `00` | Steady colour (**not** off) | yes |
| `07` | Steady colour | yes |

On the 6 Pro, `00` is off. The profile carries the off byte (`lightOffEffect`).

---

## Status stream (`0x1015`)

Four-byte frames `[type, a, b, 0]`, several per second while connected.
Each frame carries one field; the rest are the values from earlier frames.

| Type | Decode |
|------|--------|
| `04 xx` | Plate temperature: `xx` as a **signed** byte, minus 6, in °C. The plate goes below zero (a run at Medium produced raw `0xf5`, which is −17 °C, and shows as 239 if read unsigned). The offset comes from earlier comparison against the vendor app's displayed value; it is not an independent calibration |
| `08 hi lo` | Fan RPM, big-endian `(hi << 8) \| lo` |
| `09 xx` | Power draw in watts |
| `07 08` | Constant `08` in every capture; probably the top level. Unused |
| `05 00 …` | Normal |
| `05 7f 00 00` | **Cooling is not running**: sent after the physical button stops it, and after `0x1011 = 03` over Bluetooth. Gone as soon as cooling runs again |

Frames `05` and `07` carry the low byte of the most recent RPM in byte 2. That
looks like a stale buffer and is ignored.

The status frames only fire when a value changes (`04`, `08`, `09`), so a steady
state is silent apart from the constant `05` / `07` frames.

### Physical button

The cooler has one button. Pressing it stops the fan, the light and cooling
while the Bluetooth link stays up. Observed:

- The status stream switches to `05 7f 00 00`, and no further RPM frames are
  sent. `0x101C` reads `0000`, `0x101D` reads about 1 W.
- `0x1011`, `0x1012` and `0x1013` keep their old values; the device does not
  report the stop through them.
- Pressing again resumes at the previous level and light colour (the fan briefly
  overshoots while spinning back up). `05 00` frames return.

The profile's decoder turns `05 7f` into 0 RPM, which is what the app's
`PhysicalSwitchMonitor` looks for. The frame does not say *who* stopped the
cooler, but if the app has asked for cooling and sees it, the button did.

Because the cooler accepts Bluetooth writes while stopped by the button, the app
can start it again: its 30-second re-assert of the current mode does so, so a
button stop lasts at most until then while the app wants cooling on.

### Mount sensor

There is none. Pulling the cooler off the magnet surface produced no new frame,
and no frame type other than the five above was ever seen. The profile gives the
mount characteristic a UUID the device does not expose, so the mount state stays
unknown.

### Telemetry the 6 Pro has and this model lacks

Only the plate temperature is reported. There is no hot-side or ambient
reading, so the panel shows Cold, RPM and Power for this model.

---

## Power cycle

Unplugging the cooler and plugging it back in makes it **start running by
itself**, with no app connected (fan and light come on). The 6 Pro does the
same. With the app running and set to Off, it reconnects and switches the cooler
off again at its next 30-second re-assert, so the cooler can run for up to about
that long after a power cycle. The exact delay was observed by eye, not timed.

---

## What was verified

On hardware, with the app: device discovery as a supported model; connect and
reconnect to the saved device; Manual Low, Medium, Max and Off (fan, RPM and cold
readings follow); every light effect from the menu, including Auto; Auto mode
engaging at the low tier; Turn Off & Quit leaving the cooler off; the physical
button stop and resume; three minutes at a fixed level with the menu closed (no
false "power switch off", and a below-zero plate reading shown correctly); and
the app regaining control after a power cycle.

## Not verified

- Whether any setting persists in the cooler's flash across a power cycle
- `0x1018` (auto-temperature) and `0x101F`
- Levels above `0x50`, and long unattended runs
- An independent calibration of the `− 6` temperature offset
