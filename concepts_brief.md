# Smart Cooler Control: Deterministic Step-Ladder Thermal Engine & Universal Safety Governor

* **Author:** Despensativo & EGM Swarm Synthesizer
* **Date:** 2026-11-10
* **Status:** Final Concept Brief (Post Multi-Lens Audit & Multi-Brand Hardware Study)

## 1. Executive Summary

A deterministic, multi-brand thermal architecture replacing ambiguous dual-slider tuning with an assertive 4-stage Step-Ladder engine, an asymmetric anti-chattering release buffer, and a hardware-enforced Universal Safety Governor:

1. **Deterministic 4-Stage Step-Ladder (Auto):** Silent standby during idle tasks ($< 50^\circ\text{C}$), followed by discrete power tiers at predictable milestones ($50^\circ\text{C} \rightarrow \text{Tier 1}$, $60^\circ\text{C} \rightarrow \text{Tier 2}$, $65^\circ\text{C} \rightarrow \text{Tier 3}$, $70^\circ\text{C} \rightarrow \text{Tier 4 Turbo}$).
2. **Asymmetric Anti-Chattering Buffer & Dynamic Dwell:** Wide asymmetric release thresholds (up to 8°C release buffer) paired with a 20–30s step-down dwell timer and thermal velocity ($dT/dt$) bypass to eliminate fan whines and motor cogging without condensation lag.
3. **Universal Condensation Safety Governor:** A top-level hardware safety barrier operating across **ALL** modes (Auto, Manual, Turbo) that instantly cuts TEC power whenever the Mac die falls below $36.0^\circ\text{C}$, re-arming only after rising to $\ge 38.0^\circ\text{C}$.
4. **Intermediate Manual Mode with Safety Preservation:** Direct user selection (40% to 100%) that retains user setpoints during safety cutoffs.
5. **Auto-Decaying Turbo Max:** Instant one-click maximum cooling with a 15-minute safety decay.
6. **Multi-Brand Hardware Capability Abstraction:** Driver isolation ensuring every cooler model (from 3-step clips to continuous PWM blowers) maps the abstract thermal tiers natively to its hardware capabilities.

---

## 2. Multi-Brand Hardware Capability Matrix & Mapping Study

The app supports 14 cooler models across 6 distinct hardware families with vastly different control mechanisms:

| Brand & Family | Control Mechanism | Step / Level Granularity | Tier 1 (Min, $\ge 50^\circ\text{C}$) | Tier 2 (Med, $\ge 60^\circ\text{C}$) | Tier 3 (High, $\ge 65^\circ\text{C}$) | Tier 4 (Turbo, $\ge 70^\circ\text{C}$) |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| **REDMAGIC** (5 Pro, 6 Pro, 6 Pro+, 8 Pro) | Mode + Continuous PWM (0–100%) | Continuous (1%) | Mode 0x01 / 40% Fan | Mode 0x02 / 60% Fan | Mode 0x02 / 80% Fan | Mode 0x08 / 100% Fan (36W–40W) |
| **Black Shark** (MagCooler 5 Pro 35W) | Discrete Stepped Intensity | 5 Discrete Steps (1–5) | Level 1 (Quiet) | Level 2 (Balanced) | Level 4 (High) | Level 5 (35W Turbo) |
| **Flydigi** (B7X 27W, B8X Overclock 30W) | Discrete Overclock Stepped Levels | 5 Discrete Steps (1–5) | Level 1 (Quiet) | Level 2 (Balanced) | Level 3/4 (Strong) | Level 5 (30W Overclock) |
| **iQOO** (Cooling Back Clip 2 Pro 27W) | Tri-Level Discrete Steps | 3 Discrete Steps (1–3) | Level 1 (Silent) | Level 2 (Balanced) | Level 2 (Balanced) | Level 3 (27W Overclock) |
| **OnePlus / OPPO** (27W Clip, 45W Liquid) | Multi-Level Liquid/TEC Protocol | 3 to 4 Discrete Steps | Level 1 (Silent) | Level 2 (Standard) | Level 3 (Max) | Level 4 (45W Ultra Liquid) |
| **MEMO** (CX07 30W, CX08 36W) | Tri-Level Discrete Steps | 3 Discrete Steps (1–3) | Level 1 (Low) | Level 2 (Medium) | Level 2 (Medium) | Level 3 (36W Overclock) |
| **Black Shark** (MagCooler 4 Pro 27W) | Independent Inverted Fan + TEC Steps | Inverted Fan + 3 TEC Levels | Fan 40% / TEC Low (0x4B) | Fan 60% / TEC Med (0x28) | Fan 80% / TEC Med (0x28) | Fan 100% / TEC Max (0x00) |

### Key Insight from Hardware Study:
* **The Abstract Tier Seam:** `AutopilotPolicy` **MUST NOT** know about raw bytes, PWM percentages, or vendor step numbers. It solely emits abstract `CoolingTier` states (`.standby`, `.tier1_low`, `.tier2_med`, `.tier3_high`, `.tier4_turbo`).
* **Driver Mapping:** Each dedicated brand driver (`RedMagicDriver`, `BlackSharkDriver`, `FlydigiDriver`, `IQOODriver`, `OnePlusDriver`, `MemoDriver`) translates the abstract tier to its native hardware commands.
  * If a cooler only has 3 levels (e.g. iQOO/MEMO), Tier 2 and Tier 3 both map gracefully to Level 2 (Balanced), avoiding invalid byte errors.
  * If a cooler has continuous PWM (REDMAGIC), it accesses the fine-tuned 40%/60%/80%/100% fan curves.

---

## 3. Thermal Step-Ladder Specification

| Thermal Tier | Abstract Cooling Tier | Trigger Threshold (Step-Up) | Release Threshold (Step-Down) | Target Behavior |
| :--- | :---: | :---: | :---: | :--- |
| **Standby** | `.standby` | Initial / $< 42^\circ\text{C}$ | N/A | Fan 0%, Peltier 0W. Silent passive operation. |
| **Tier 1 (Quiet Min)** | `.tier1_low` | $\ge 50^\circ\text{C}$ | $< 42^\circ\text{C}$ (8°C buffer) | Quiet floor. Dissipates moderate CPU work. |
| **Tier 2 (Medium)** | `.tier2_med` | $\ge 60^\circ\text{C}$ | $< 55^\circ\text{C}$ (5°C buffer) | Balanced active cooling for sustained light loads. |
| **Tier 3 (High Power)** | `.tier3_high` | $\ge 65^\circ\text{C}$ | $< 61^\circ\text{C}$ (4°C buffer) | High airflow for intense multi-core compilation. |
| **Tier 4 (Turbo Max)** | `.tier4_turbo` | $\ge 70^\circ\text{C}$ | $< 66^\circ\text{C}$ (4°C buffer) | Full hardware limit (30W–45W depending on model). |

### Dynamics & Timing
* **Step-Up:** Immediate ($\le 1$ second) upon crossing a tier boundary. Multi-tier temperature spikes jump directly to the target tier without intermediate steps.
* **Step-Down:** Dwell requirement of 20–30 seconds before stepping down.
* **Thermal Velocity Bypass ($dT/dt$):** If die temperature drops at a rate $\le -1.0^\circ\text{C}/\text{s}$ (workload termination), dwell is compressed to 3 seconds to prevent chassis overcooling.

---

## 4. Universal Condensation Safety Governor

* **Central Rule:** Regardless of whether the app is in `Auto`, `Manual`, or `Turbo Max`, if `dieTemperatureC < 36.0°C`, the hardware immediately commands `.standby` (TEC 0W, Fan 0%).
* **Universal Model Compatibility:** The `< 36.0°C` cutoff is universal and model-agnostic because every driver in the catalog implements a clean shutdown to Standby.
* **Asymmetric Re-Arm Threshold:** Once tripped, cooling remains disabled until `dieTemperatureC >= 38.0°C` (2°C deadband) to eliminate high-frequency relay hunting in air-conditioned environments.
* **Deferred Fan Work Item Invalidation:** Upon tripping, any pending fan speed writes in the BLE queue are immediately invalidated.
* **State Preservation:** In Manual mode, the user's requested setpoint is preserved and visually marked as `🛡️ Safety Intercepted (< 36°C)`. Cooling automatically resumes once the die reaches 38.0°C.

---

## 5. Architectural Boundaries

```
[ ThermalMonitor (IOKit) ] ➔ [ AppDelegate.tick() ]
                                      │
                 ┌────────────────────┴────────────────────┐
                 ▼                                         ▼
   [ HardwareSafetyGovernor ]                    [ Active Mode Selector ]
   (Enforces <36°C Cutoff &                     (Step-Ladder Auto /
    38°C Re-arm across ALL modes)                 Manual / Turbo Max)
                 │                                         │
                 └────────────────────┬────────────────────┘
                                      ▼
                         [ CoolerBLEManager.apply() ]
                                      │
                                      ▼
                      [ Brand Drivers (GATT Isolation) ]
    ┌──────────────┬──────────────┬──────────────┬──────────────┐
    ▼              ▼              ▼              ▼              ▼
 REDMAGIC     Black Shark     Flydigi        iQOO/MEMO       OnePlus
(Continuous)  (5 Steps)      (5 Steps)       (3 Steps)      (4 Steps)
```

---

## 6. Scope & Guardrails

### In-Scope
* Implementation of deterministic 4-stage Step-Ladder in `AutopilotPolicy.swift` emitting abstract `CoolingTier`.
* Top-level `HardwareSafetyGovernor` protecting Auto, Manual, and Turbo modes.
* Asymmetric release thresholds (8°C, 5°C, 4°C, 4°C) with anti-chattering dwell.
* Mapping of abstract tiers across all 6 brand drivers (`RedMagicDriver`, `BlackSharkDriver`, `FlydigiDriver`, `IQOODriver`, `OnePlusDriver`, `MemoDriver`).
* Replacement of dual sliders in `AutoOptionsView` with a discrete 4-stage visualizer.
* Thermal velocity ($dT/dt$) dwell bypass.

### Out-of-Scope
* Continuous analog temperature ramp curves.
* Fan operation below 40% (except 0% Standby).
* Disabling the 36°C condensation cutoff under any user toggle.
