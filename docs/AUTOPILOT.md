# Autopilot — how automatic cooling works

Auto mode follows the Mac's temperature. It turns the cooler on as the Mac
heats up, raises cooling power with temperature, and turns it off after the Mac
has cooled. Auto is the default mode after connection.

This guide explains the temperature signal, engage threshold, cooling ladder,
custom curve, anti-flap behaviour, safety floor, and LED heat gauge.

Implementation:
[`AutopilotPolicy.swift`](../src-swift/Core/AutopilotPolicy.swift).

## The temperature it watches

On Apple Silicon, the app reads the Mac's **SoC die temperature** from its
thermal sensors through IOKit's HID interface. It needs no `sudo` or additional
installation, and responds within seconds when the Mac starts working hard.

macOS also exposes `ProcessInfo.thermalState`, but that signal is heavily
damped. Autopilot uses it as a safety floor rather than its primary input.

| Temperature | Source | Use |
|-------------|--------|-----|
| **Mac °C** | Mac SoC sensors, or the sensor you choose | Drives Auto mode |
| Cooler cold/hot °C | Cooler telemetry | Display only |
| Ambient °C | Cooler telemetry | Display only |

The cooler reports plate temperatures only while actively cooling. Cold or hot
readings of `0 °C` while it is off are device behaviour.

### Choosing the sensor

By default Auto mode follows the **average of the SoC die sensors** (`PMU tdie*`).
**Settings → Temperature Source…** opens a live list of everything this Mac
reports, and the one you pick drives Auto mode, the status card and the LED's
Auto colour:

- **Groups:** SoC die average (the default) or hottest sensor, device sensors
  (`PMU tdev*`) average or hottest, battery, and SSD. A group appears only if
  this Mac has sensors for it.
- **Individual sensors,** by name (`PMU tdie3`, `gas gauge battery`, and so on).
  A sensor exposed more than once is shown as the mean of its readings.

The choice is saved by name. If the chosen sensor is missing at a later launch,
Auto mode uses the SoC die average instead of going blind. The sensors are
read-only and the list is what the HID interface exposes on your Mac, so names
and counts differ between models.

## Engage threshold and cooling levels

The **engage threshold** `E` is the die temperature at which cooling starts.
Use the threshold slider in Auto mode to set it from 45–85 °C. The default is
45 °C. There is one threshold control; the former Standard/Custom profile
choice is no longer needed.

The remaining tiers are derived from `E` in 10 °C steps. All tiers are capped
at 95 °C so a high engage point cannot create an out-of-order ladder.

| Die temperature | Tier | TEC mode | Fan |
|-----------------|------|----------|-----|
| Below `E` | off | off | 0% |
| `E` and above | low | low | 60% |
| `E`+10 and above | med-low | med-low | 80% |
| `E`+20 and above | medium | medium | 95% |
| `E`+30 and above | max | max | 100% |

For the default `E = 45 °C`, the tier boundaries are 45, 55, 65, and 75 °C.

## Custom curve

**Settings → Auto Curve…** replaces that derived ladder with a temperature of
your own for **every stage of your cooler**. The stages are the steps of the
cooler's own manual slider after Off, so Auto can use all of them: the Cryo
Cooler 8 Pro has nine (Level 1 to 8, then Diablo) and the VC Cooler 6 Pro has
nine (Low · to Max).

- Tick **Use a custom curve**, type a temperature for each stage, and Save. The
  fields are in your system temperature unit.
- Each stage must be at least 1 °C hotter than the one before, and all must fall
  between 30 and 100 °C. The window says what is wrong and keeps Save disabled
  until the curve is valid.
- **Reset** fills in an even spread from the threshold slider's temperature up to
  95 °C, last stage included. Unticking the box returns to the ladder and keeps
  your values for next time.
- While a custom curve is on, the threshold slider is greyed and the row reads
  **Custom curve** with the temperature where the first stage engages.

A custom curve is literal. Below the first temperature the cooler is **off**, and
each stage engages when the Mac reaches its temperature and is released once the
Mac is below it. There is no 5 °C hold zone, which belongs to the default ladder.
The 15-second cool-down delay still applies, and it still steps down one stage at
a time, so a reading hovering on a threshold does not switch the cooler on and
off every few seconds.

Other things that stay the same: the safety floor applies (under `serious`
thermal pressure Auto goes at least three quarters of the way up your stages, and
under `critical` to the last one), and the LED heat gauge runs from 10 °C below the
first stage to red at the last.

The last stage is whatever your cooler's top step is. On the 8 Pro that is
**Diablo** (about 37 W), so a curve that reaches it will use it. Reset puts it at
95 °C; lower it only if you want that.

A curve has one point per stage, so it belongs to a cooler with that many. If you
connect a cooler with a different number of stages, the ladder from the threshold
slider is used until you set a curve for it.

## Fast to turn on, slow to turn off

Autopilot reacts immediately to rising heat but backs off deliberately so the
Peltier does not rapid-cycle.

**Heating up:** it steps up as soon as the die crosses a tier boundary.

**Cooling down:** both conditions must hold before it drops one tier:

1. The die is at least **5 °C below** that tier's engage point.
2. It remains there for **15 seconds**.

The app then steps down one tier at a time. A drop from max to off therefore
follows `max → medium → med-low → low → off`, with each change gated by those
rules. Autopilot evaluates every three seconds.

## LED heat gauge

Set the cooler effect to **Auto** to make its colour follow the Mac die
temperature: green while cool, through yellow and orange, to red while hot.

For an engage threshold `E`, the colour sweep starts at `E−10 °C` (with a
30 °C minimum) and reaches red at `E+30 °C` (with a 95 °C maximum). At the
default 45 °C threshold, that is green at 35 °C and red at 75 °C.

The sweep uses HSV hue from 120° to 0° and writes the cooler's static-colour
effect only when the colour changes. The LED is lit only while the cooler is
running; select another effect to opt out of the heat gauge.

## Safety floor

macOS's own thermal state can force a minimum cooling tier regardless of the
die reading:

| macOS thermal state | Minimum tier |
|---------------------|--------------|
| `nominal`, `fair` | none |
| `serious` | medium |
| `critical` | max |

The final decision is the higher of the die-temperature tier and this safety
floor. The OS signal can raise cooling power but cannot lower it.

## Worked example

With the default 45 °C engage threshold:

```text
die 40 °C  → off
die 48 °C  → low,     fan 60%
die 58 °C  → med-low, fan 80%
die 68 °C  → medium,  fan 95%
die 78 °C  → max,     fan 100%
...the workload finishes...
die 69 °C  → max      (not yet below the 70 °C release point long enough)
die 67 °C  → medium   (below 70 °C for 15 seconds)
die 57 °C  → med-low  (below 60 °C for 15 seconds)
die 47 °C  → low      (below 50 °C for 15 seconds)
die 37 °C  → off      (below 40 °C for 15 seconds)
```

Transitions are written to `~/.cooler.log`.

## Tuning the implementation

The threshold range, default, hysteresis, and dwell are in
[`Config.swift`](../src-swift/Core/Config.swift). The tier ladder and LED band
are built by `configure(engageC:)` in
[`AutopilotPolicy.swift`](../src-swift/Core/AutopilotPolicy.swift), from either
`defaultCurve(engageC:)` or a validated custom curve (`isValidCurve`).

```swift
enum Autopilot {
    static let hysteresisC: Double = 5.0
    static let cooldownDwell: TimeInterval = 15
    static let engageDefaultC: Double = 45
    static let engageMinC: Double = 45
    static let engageMaxC: Double = 85
}
```

Lowering the engage threshold makes cooling start earlier. Increasing the
threshold, dwell, or hysteresis makes the controller less eager. The tier fan
values are RPM-calibrated; read [`FINDINGS.md`](FINDINGS.md) before changing
them.
