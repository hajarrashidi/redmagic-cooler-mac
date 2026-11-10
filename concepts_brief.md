# Smart Cooler Control: Deterministic Step-Ladder Thermal Engine & Universal Safety Governor

* **Author:** Despensativo & EGM Swarm Synthesizer
* **Date:** 2026-11-10
* **Status:** Final Concept Brief (Post Multi-Lens Audit)

## 1. Executive Summary

A deterministic, multi-brand thermal architecture replacing ambiguous dual-slider tuning with an assertive 4-stage Step-Ladder engine, an asymmetric anti-chattering release buffer, and a hardware-enforced Universal Safety Governor:

1. **Deterministic 4-Stage Step-Ladder (Auto):** Silent standby during idle tasks ($< 50^\circ\text{C}$), followed by discrete power tiers at predictable milestones ($50^\circ\text{C} \rightarrow 40\%$, $60^\circ\text{C} \rightarrow 60\%$, $65^\circ\text{C} \rightarrow 80\%$, $70^\circ\text{C} \rightarrow 100\%$ Turbo).
2. **Asymmetric Anti-Chattering Buffer & Dynamic Dwell:** Wide asymmetric release thresholds (up to 8°C release buffer) paired with a 20–30s step-down dwell timer and thermal velocity ($dT/dt$) bypass to eliminate fan whines and motor cogging without condensation lag.
3. **Universal Condensation Safety Governor:** A top-level hardware safety barrier operating across **ALL** modes (Auto, Manual, Turbo) that instantly cuts TEC power whenever the Mac die falls below $36.0^\circ\text{C}$, re-arming only after rising to $\ge 38.0^\circ\text{C}$.
4. **Intermediate Manual Mode with Safety Preservation:** Direct user selection (40% to 100%) that retains user setpoints during safety cutoffs.
5. **Auto-Decaying Turbo Max:** Instant one-click maximum cooling with a 15-minute safety decay.

---

## 2. Thermal Step-Ladder Specification

| Thermal Tier | Target Fan % | Abstract Cooling Tier | Hardware Mapping (REDMAGIC) | Hardware Mapping (Black Shark) | Engagement (Step-Up) | Release Threshold (Step-Down) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **Standby** | 0% | `.standby` | Mode 0x03 / 0% Fan | Off / 0% Fan | Initial / $< 42^\circ\text{C}$ | N/A (Quiet standby) |
| **Tier 1 (Quiet Min)** | 40% | `.tier1_low` | Mode 0x01 / 40% Fan | Step 1 / 40% Fan | $\ge 50^\circ\text{C}$ | $< 42^\circ\text{C}$ (8°C buffer) |
| **Tier 2 (Medium)** | 60% | `.tier2_med` | Mode 0x02 / 60% Fan | Step 2 / 60% Fan | $\ge 60^\circ\text{C}$ | $< 55^\circ\text{C}$ (5°C buffer) |
| **Tier 3 (High Power)** | 80% | `.tier3_high` | Mode 0x02 / 80% Fan | Step 4 / 80% Fan | $\ge 65^\circ\text{C}$ | $< 61^\circ\text{C}$ (4°C buffer) |
| **Tier 4 (Turbo Max)** | 100% | `.tier4_turbo` | Mode 0x08 / 100% Fan | Step 5 / 100% Fan | $\ge 70^\circ\text{C}$ | $< 66^\circ\text{C}$ (4°C buffer) |

### Dynamics & Timing
* **Step-Up:** Immediate ($\le 1$ second) upon crossing a tier boundary. Multi-tier temperature spikes jump directly to the target tier without intermediate steps.
* **Step-Down:** Dwell requirement of 20–30 seconds before stepping down.
* **Thermal Velocity Bypass ($dT/dt$):** If die temperature drops at a rate $\le -1.0^\circ\text{C}/\text{s}$ (workload termination), dwell is compressed to 3 seconds to prevent chassis overcooling.

---

## 3. Universal Condensation Safety Governor

* **Central Rule:** Regardless of whether the app is in `Auto`, `Manual`, or `Turbo Max`, if `dieTemperatureC < 36.0°C`, the hardware immediately commands `.standby` (TEC 0W, Fan 0%).
* **Asymmetric Re-Arm Threshold:** Once tripped, cooling remains disabled until `dieTemperatureC >= 38.0°C` (2°C deadband) to eliminate high-frequency relay hunting.
* **Deferred Fan Work Item Invalidation:** Upon tripping, any pending fan speed writes in the BLE queue are immediately invalidated.
* **State Preservation:** In Manual mode, the user's requested setpoint is preserved and visually marked as `🛡️ Safety Intercepted (< 36°C)`. Cooling automatically resumes once the die reaches 38.0°C.

---

## 4. Architectural Boundaries

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
                    (RedMagic / BlackShark / Memo / etc.)
```

---

## 5. Scope & Guardrails

### In-Scope
* Implementation of deterministic 4-stage Step-Ladder in `AutopilotPolicy.swift`.
* Top-level `HardwareSafetyGovernor` protecting Auto, Manual, and Turbo modes.
* Asymmetric release thresholds (8°C, 5°C, 4°C, 4°C) with anti-chattering dwell.
* Replacement of dual sliders in `AutoOptionsView` with a discrete 4-stage visualizer.
* Thermal velocity ($dT/dt$) dwell bypass.
* Brand driver isolation preserving multi-cooler compatibility.

### Out-of-Scope
* Continuous analog temperature ramp curves.
* Fan operation below 40% (except 0% Standby).
* Disabling the 36°C condensation cutoff under any user toggle.
