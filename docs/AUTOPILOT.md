# Autopilot — Deterministic Step-Ladder Engine v3.1

Smart Cooler Control uses a deterministic 4-stage **Step-Ladder Engine** with asymmetric hysteresis, dynamic dwell time, thermal velocity bypass, and a hardware-grade **Universal Condensation Safety Governor**.

Implementation:
[`AutopilotPolicy.swift`](../src-swift/Core/AutopilotPolicy.swift).

---

## 1. Primary Temperature Signal (Apple Silicon)

On Apple Silicon (M1 through M4), the app reads the Mac's **SoC die temperature** directly from internal hardware sensors via IOKit's HID interface:
- **Zero Sudo / Privileges:** Operates completely in user space without kernel extensions or daemon privileges.
- **Immediate Response:** Real-time sampling with a 3-second evaluation loop that responds instantly when sustained CPU/GPU compute loads begin.

| Metric | Source | Role in Controller |
|---|---|---|
| **Mac Die / CPU °C** | IOKit Apple Silicon Sensors | **Drives Step-Ladder Autopilot & Thermal LED** |
| **Peltier Cold Plate °C** | Cooler BLE Telemetry Stream | Displayed in UI; monitored for frost prevention |
| **Hot Exhaust °C** | Cooler BLE Telemetry Stream | Telemetry monitor |
| **Fan RPM** | Cooler BLE Telemetry Stream | Real-time RPM readout |

---

## 2. Deterministic 4-Stage Step-Ladder

The Step-Ladder replaces unpredictable continuous PIDs or legacy single-slider thresholds with 4 deterministic operating tiers engineered specifically for Apple Silicon thermal dissipation:

| Stage | Trigger (Engage) | Power & Fan | Release (Disengage) | Primary Use Case |
|---|---|---|---|---|
| **Standby** | `< 50.0 °C` | 0% fan / 0W TEC | — | Idle, web browsing, word processing |
| **Tier 1 (Quiet)** | `≥ 50.0 °C` | 40% fan (`.low`) | `< 42.0 °C` | Light multitasking, video playback |
| **Tier 2 (Balanced)**| `≥ 60.0 °C` | 60% fan (`.medium`)| `< 55.0 °C` | Sustained compilation, Xcode builds |
| **Tier 3 (Boost)** | `≥ 65.0 °C` | 80% fan (`.medium`)| `< 61.0 °C` | Heavy 3D rendering, video export |
| **Tier 4 (Turbo)** | `≥ 70.0 °C` | 100% fan (`.max`) | `< 66.0 °C` | Peak compute stress, gaming, thermal throttling defense |

---

## 3. Asymmetric Hysteresis & Anti-Chattering

Peltier semiconductors degrade rapidly if cycled on/off repeatedly. Autopilot implements two layers of physical protection:

### Immediate Step-Up
When temperature spikes due to sudden compute demand (e.g. initiating a build or running local AI models), the engine steps up **immediately without delay**. Multi-tier jumps are permitted (e.g., from Standby straight to Tier 4 Turbo if die temp exceeds 70°C).

### Asymmetric Hold & Dwell Buffer
To drop a tier, two criteria must be satisfied:
1. **Asymmetric Release Point:** The temperature must drop completely below the tier's release threshold (e.g. Tier 1 requires `< 42°C`, providing an 8°C anti-hunting band).
2. **20-Second Cooldown Dwell:** The lower temperature must remain stable for at least 20 continuous seconds before lowering fan speed.

### Thermal Velocity Bypass
If a massive thermal plunge occurs ($dT/dt \le -3.0^\circ\text{C/s}$), the 20-second dwell buffer is bypassed and replaced with a **3-second fast dwell**. This prevents excessive cooling of the aluminum chassis after an intense workload suddenly stops.

---

## 4. Universal Condensation Safety Governor

Peltier cooling on high-powered magnetic coolers (30W–45W) can pull cold plate temperatures below zero degrees Celsius. If the chassis cools below the ambient dew point, moisture forms on internal laptop components.

Smart Cooler Control enforces a hardware-grade safety interlock across **ALL modes** (Auto, Manual, and Turbo):
- **Hard Cutoff:** If Mac die temperature drops below **`< 36.0 °C`**, the cooler immediately cuts power to 0% fan / 0W Standby (`.off`).
- **Anti-Hunting Re-Arm:** The cooler remains strictly in Standby until die temperature rises back to **`≥ 38.0 °C`**.
- In the UI, the safety status is signaled clearly by the shield indicator: `🛡️ Corte contra condensação < 36°C (retoma ≥ 38°C)`.

---

## 5. macOS Thermal Pressure Floor

macOS reports system-wide thermal pressure via `ProcessInfo.thermalState`. Autopilot treats this signal as a safety floor:

| macOS Thermal State | Enforced Minimum Tier |
|---|---|
| `nominal`, `fair` | None (normal Step-Ladder rules apply) |
| `serious` | Minimum **Tier 2 (Balanced, 60% fan)** |
| `critical` | Forced **Tier 4 (Turbo, 100% fan)** |

The OS signal can elevate cooling power to protect hardware, but can never reduce cooling power below what the die temperature warrants.

---

## 6. LED Thermal Scale (Mac Model-Aware)

When the cooler's lighting mode is set to **Auto**, the physical RGB ring functions as a real-time thermal gauge reflecting actual Mac thermal state. 

Apple Silicon chips safely operate between 40°C–60°C under normal usage. Warning indicators (Yellow/Orange) are strictly calibrated to start only at true thermal escalation points:

### Thermal Color Bands by Chassis

| Mac Chassis Family | Blue (Nominal / Minimum) | Yellow (Moderate) | Orange (Sustained) | Red (Critical / Throttle) |
|---|---|---|---|---|
| **MacBook Air** (fanless) | `< 65.0 °C` | `65.0 °C – 75.0 °C` | `75.0 °C – 85.0 °C` | `≥ 88.0 °C` |
| **MacBook Pro** (internal fans)| `< 68.0 °C` | `68.0 °C – 78.0 °C` | `78.0 °C – 88.0 °C` | `≥ 90.0 °C` |
| **Mac Studio / Mini** (desktop)| `< 58.0 °C` | `58.0 °C – 68.0 °C` | `68.0 °C – 78.0 °C` | `≥ 85.0 °C` |

### Standby LED Persistence
Unlike vendor defaults that revert to factory red flashing when fan stops, Smart Cooler Control maintains the thermal LED state during Auto Standby, keeping the ring in a serene, calm Blue so the user knows the system is healthy and active.
