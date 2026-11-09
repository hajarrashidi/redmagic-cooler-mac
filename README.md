<div align="center">

# Smart Cooler Control for MacBook

**The intelligent, multi-brand active cooling controller for Apple Silicon MacBooks.**  
*Engineered exclusively for high-power external thermoelectric coolers (≥ 30W) to sustain peak performance and eliminate thermal throttling.*

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)](docs/GETTING_STARTED.md#requirements)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1%20%2F%20M2%20%2F%20M3%20%2F%20M4-black)](docs/GETTING_STARTED.md#requirements)
[![Swift](https://img.shields.io/badge/Swift-AppKit%20%2B%20CoreBluetooth-orange)](docs/DEVELOPMENT.md)
[![Cooler Standard](https://img.shields.io/badge/Benchmark-%E2%89%A5%2030W%20High--Power-red)](docs/COMPATIBILITY.md)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

</div>

---

## Why Smart Cooler Control?

MacBooks built with Apple Silicon (M1, M2, M3, M4 across Pro and Max tiers) deliver unprecedented computing density. However, under sustained workloads — such as 8K ProRes export, 3D rendering (Blender/Octane), deep learning / local LLM inference, and extended compiling — thermal mass builds up rapidly in the aluminum chassis, resulting in clock drops and thermal throttling.

Most generic phone coolers run at **10W to 15W**, which is physically insufficient to penetrate the thermal inertia of a solid aluminum unibody. 

**Smart Cooler Control enforces a strict minimum benchmark: ≥ 30W.** Only enthusiast-grade thermoelectric (Peltier) coolers with heavy-duty heat pumps, vapor chambers, and high-RPM blowers can make the list.

---

## Key Features

- **Dynamic Thermal Autopilot:** Continuously reads macOS internal die temperature sensors and adjusts cooling output in real-time.
- **Smart Max Profile:** Delivers instant 100% cooling power when heavy computation spikes the die, and safely ramps down to 60% and Off as the chassis cools.
- **Active Condensation & Ice Prevention:** Thermoelectric plates running at 36W–40W can freeze ambient moisture onto the chassis when the Mac is cool or idle. The autopilot automatically backs off power and cuts the cooler when the Mac is in repouso / sleep or turned off.
- **Native macOS Lifecycle Hooks:** Automatically turns off the cooler on `willSleepNotification`, `willPowerOffNotification`, and app termination, and resumes on `didWakeNotification`.
- **Auto-Reconnect on Launch:** Seamless background reconnection to your preferred device on startup.
- **Telemetry & Diagnostics:** Real-time temperature readout (die, cold plate, hot plate, ambient) and live fan RPM in the menu bar.

---

## Supported High-Power Coolers (≥ 30W Standard)

| Manufacturer | Model | Peak Power | Architecture | Status |
|---|---|---|---|---|
| **REDMAGIC** | **Cooler 6 Pro+** | **40W** | Liquid VC + TEC | **Supported (Native Driver)** |
| **REDMAGIC** | **Magnetic Cooler 5 Pro** | **36W** | Vapor Chamber + TEC | **Supported & Hardware-Verified** |
| **REDMAGIC** | **VC Cooler 6 Pro** | **36W** | Vapor Chamber + TEC | **Supported & Hardware-Verified** |
| **REDMAGIC** | **Cryo Cooler 8 Pro** | **36W** | 4th Gen Custom TEC | **Supported (Native Driver)** |
| **REDMAGIC** | **Magcooler 4 Pro** | **27W** | High-Power TEC | **Supported (Native Driver)** |
| **Black Shark** | **MagCooler 5 Pro** | **35W** | Custom 5-Step TEC (5100 RPM) | **Supported (Native Driver)** |
| **Black Shark** | **MagCooler 4 Pro** | **27W** | Dual-Channel Power + Fan | **Supported (Native Driver)** |
| **Flydigi** | **Flydigi B8X** | **30W** | Overclock Mode TEC | **Supported (Native Driver)** |
| **Flydigi** | **Flydigi B7X** | **27W** | High-Power Magnetic TEC | **Supported (Native Driver)** |
| **iQOO** | **Magnetic Cooler (iRA2571)** | **33W** | High-Power Dual-Clip | *In Protocol Extraction* |
| **OnePlus** | **45W Liquid Cooler** | **45W** | External Pump + TEC | *In Protocol Extraction* |

> *Strict Driver Isolation: Every supported device is uniquely identified via GATT services, manufacturer IDs and advertised packets. The app loads exclusively its compatible hardware driver, completely preventing cross-brand packet contamination.*

> *Note: Low-power coolers (< 30W) are excluded by design.*

---

## Quick Start

### Requirements
- macOS 13 (Ventura) or later
- Apple Silicon Mac (M1, M2, M3, M4, Pro, Max, Ultra)
- Bluetooth access granted

### Build and Run Locally
```bash
git clone https://github.com/Despensativo/redmagic-cooler-mac.git
cd redmagic-cooler-mac
./build.sh --run
```

---

## Architecture & Contributing

Smart Cooler Control is designed with an open, vendor-agnostic architecture:
- `DeviceProfile.swift`: Model-specific GATT mappings, raw hardware mode adapters, and telemetry frames.
- `AutopilotPolicy.swift`: Universal thermal decision matrix, dwell times, and hysteresis.
- `CoolerBLEManager.swift`: Resilient CoreBluetooth connection manager with automatic state recovery.

To contribute a new ≥ 30W cooler profile, see [Adding Devices](docs/ADDING_DEVICES.md).

---

## License

This project is open-source under the [MIT License](LICENSE).
