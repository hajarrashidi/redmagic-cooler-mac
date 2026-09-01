# Autopilot — how automatic cooling works

Auto mode runs the cooler **based on how hot your Mac actually is**. It turns
the cooler on when the Mac heats up, ramps its power as the temperature rises,
and turns it fully off once the Mac has cooled and no longer needs it — with no
input from you.

This doc covers the signal it watches, the levels it picks, the exact
temperatures it engages at, and how to tune it.

Implementation: [`src-swift/Core/AutopilotPolicy.swift`](../src-swift/Core/AutopilotPolicy.swift).
It is pure decision logic — no I/O, no hardware access — so it can be reasoned
about (and exercised) on its own.

---

## The temperature it watches

The autopilot is driven by your Mac's **SoC die temperature** (the CPU/GPU
silicon temperature, in °C), read natively from the Apple Silicon thermal
sensors via IOKit's HID system — **no `sudo`, no extra install**. This is the
*sensitive* signal: it moves within seconds of the Mac working hard.

> **Why not macOS's "thermal state"?**
> Apple's `ProcessInfo.thermalState` (`nominal` → `fair` → `serious` →
> `critical`) is the "official" signal, but it is heavily damped — it can stay
> `nominal` through *minutes* of full CPU load. Far too slow on its own, so the
> autopilot uses it only as a **safety floor** (see below).

Three temperatures are in play; don't confuse them:

| Temperature        | Where it comes from         | Used for                          |
|--------------------|-----------------------------|-----------------------------------|
| **Mac die °C**     | Mac's own SoC sensors (HID) | **Drives the autopilot decision** |
| Cooler cold/hot °C | The cooler's telemetry      | Display only                      |
| Ambient °C         | The cooler's telemetry      | Display only                      |

> **About "cold 0 °C / hot 0 °C":** the cooler only reports plate temperatures
> while it is actively cooling. When it's **off** those sensors read `0` — the
> device's behaviour, not a bug. Real numbers appear the instant cooling starts.

---

## The cooling levels

The cooler has two **independent** controls, and the autopilot sets both:

- **TEC mode** — the Peltier element that does the actual chilling.
- **Fan speed** — clears heat from the cooler's hot side, so the TEC can keep
  pumping without the cooler's own body overheating.

Five tiers:

| Tier        | TEC mode | Fan   | Meaning                         |
|-------------|----------|-------|---------------------------------|
| **off**     | off      | 0 %   | Mac is cool — nothing to do     |
| **low**     | low      | 60 %  | Mac is warming up               |
| **med-low** | med-low  | 80 %  | Mac is warm                     |
| **medium**  | medium   | 95 %  | Mac is hot                      |
| **max**     | max      | 100 % | Mac is very hot — cool flat out |

> Fan percentages are **not** linear in RPM. The firmware's response curve is
> U-shaped, so these values are calibrated against an RPM probe rather than
> chosen for roundness — see [`FINDINGS.md`](FINDINGS.md).

---

## At what temperature it engages — two profiles

| Mac die temp | Standard    | Custom (engage `E`) |
|--------------|-------------|---------------------|
| cool         | off         | off                 |
| **40 °C +**  | **low**     | off                 |
| **50 °C +**  | **med-low** | off                 |
| **62 °C +**  | **medium**  | off                 |
| **74 °C +**  | **max**     | off                 |
| **`E` +**    | —           | **low**             |
| **`E`+10 +** | —           | **med-low**         |
| **`E`+20 +** | —           | **medium**          |
| **`E`+30 +** | —           | **max** (capped at 95 °C) |

**Standard** is tuned for a cooler plate sat against a laptop chassis: it earns
its keep while the Mac is merely warm, not only under sustained load, so it
engages early and ramps quickly.

**Custom** lets you pick the engage point `E` (45–85 °C) with a slider in the
menu-bar app; the remaining tiers sit 10 °C apart above it, with the top tier
capped so a high engage point can't push it past 95 °C.

For reference, Apple Silicon typically idles around **40–45 °C** and climbs
toward **95–100 °C** (where it throttles) under sustained heavy load.

Choose **Standard** or **Custom** from the Auto Mode row in the menu-bar app.

---

## Fast to turn on, slow to turn off (anti-flap)

The autopilot reacts **immediately** to heat but is **deliberate** about backing
off — so it springs on the moment you need it, yet never flickers the Peltier on
and off while the Mac is still hot. Rapid cycling is bad for a TEC and achieves
nothing.

**Heating up:** the instant the die crosses a threshold, it steps up. No delay.

**Cooling down:** before dropping a tier, *both* must hold:

1. **Hysteresis band** — the die must fall a full **5 °C below** the tier's
   engage point, not merely dip under it. Standard's `medium` engages at 62 °C
   and doesn't release until **57 °C**, so a reading hovering on a threshold
   holds steady instead of bouncing.
2. **Cool-down dwell** — that calmer reading must **hold for 15 s** before it
   eases down one tier. A brief dip won't switch cooling off.

It steps down **one tier at a time**, so `max` back to `off` is a gentle
`max → medium → med-low → low → off`, each step gated by the rules above.

The autopilot re-evaluates every **3 seconds**.

---

## The LED as a heat gauge

With the LED effect set to **Auto**, the cooler's colour tracks the die
temperature — green when cooling starts, through yellow and orange, to **red**
when hot. The sweep spans the active profile's working band:

| Profile              | 🟢 green at | 🔴 red at        |
|----------------------|------------|------------------|
| Standard             | 40 °C      | 78 °C            |
| Custom (engage `E`)  | `E`−10 °C  | `E`+30 (max 95)  |

The sweep is a natural HSV spectrum (hue 120° → 0°), not a muddy blend. It uses
the device's **static-colour** effect (light char `0x1013`, byte 0 = `4`,
followed by `R,G,B`), and writes only when the colour actually changes.

> **The LED only lights while the cooler is running.** When the Mac is cool and
> the cooler is off, the LED is off too — so the light doubles as an "actively
> cooling" indicator. Pick any other LED effect to opt out of the heat gauge.

---

## The safety floor (belt and suspenders)

If macOS's own `thermalState` reports trouble, the autopilot cools hard
regardless of what the die sensor says:

| macOS thermalState | Minimum tier forced |
|--------------------|---------------------|
| `nominal`, `fair`  | — (no floor)        |
| `serious`          | medium              |
| `critical`         | max                 |

The decision is always **the higher** of (die-temperature tier, safety floor).
The OS signal can only *raise* the cooling level, never lower it.

---

## A worked example

Standard profile. Starting from a cool, idle Mac, you launch a heavy build:

```
die 38 °C  → off              (cool, nothing to do)
die 43 °C  → low,     fan 60% (crossed 40 °C — engages instantly)
die 55 °C  → med-low, fan 80% (crossed 50 °C)
die 66 °C  → medium,  fan 95% (crossed 62 °C)
die 79 °C  → max,     fan 100% (crossed 74 °C — flat out)
...build finishes, Mac starts cooling...
die 71 °C  → max,     fan 100% (below 74−5=69? no — holds)
die 66 °C  → medium,  fan 95% (below 69, held 15 s → eases down one tier)
die 54 °C  → med-low, fan 80% (below 57, held 15 s → eases down again)
die 43 °C  → low,     fan 60% (below 45, held 15 s)
die 33 °C  → off              (below 35, held 15 s → fully off)
```

Every transition is written to `~/.cooler.log`:

```
Mac 66°C (nominal)  → cooler medium, fan 95%
Mac 63°C (nominal) — easing down soon  → cooler medium, fan 95%
Mac 33°C (nominal)  → cooler off, fan 0%
```

---

## Using it

Choose **Auto** in the menu for temperature-driven cooling, then select the
**Standard** profile or set a **Custom** engage temperature. Choose **Manual**
for a fixed level regardless of temperature, or use **Turn Off** to stop.

---

## Tuning it

The tier ladder and LED band live in `configure(profile:customEngageC:)` in
[`AutopilotPolicy.swift`](../src-swift/Core/AutopilotPolicy.swift); the timing
constants live in `Config.Autopilot` and `Config.Timing`
([`Config.swift`](../src-swift/Core/Config.swift)). Edit, then `./build.sh`.

```swift
// Config.swift
enum Autopilot {
    static let hysteresisC: Double = 5.0        // °C below engage before a tier releases
    static let cooldownDwell: TimeInterval = 15 // s a calmer reading must hold
    static let standardEngageC: Double = 40     // where Standard's first step engages
    static let customEngageDefaultC: Double = 65
    static let customEngageMinC: Double = 45
    static let customEngageMaxC: Double = 85
}
enum Timing {
    static let autopilotEveryTicks = 3          // evaluate every 3 s (poll is 1 s)
}
```

```swift
// AutopilotPolicy.configure(profile:customEngageC:) — the Standard ladder.
// The first engage point is Config.Autopilot.standardEngageC (40 °C), shared
// with the menu so the row can label the threshold it will actually use.
engagePoints = [(Config.Autopilot.standardEngageC, 1), (50, 2), (62, 3), (74, 4)]
ledGreenC = Config.Autopilot.standardEngageC
ledRedC = 78
```

- **Want it more eager?** Lower the first engage point.
- **Want it calmer / less twitchy?** Raise the engage points, or increase
  `cooldownDwell` and `hysteresisC`.

The tier table itself — which TEC mode and fan speed each tier uses — is
`AutopilotPolicy.tiers`. Those fan values are RPM-calibrated; read
[`FINDINGS.md`](FINDINGS.md) before changing them.
