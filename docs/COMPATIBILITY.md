# Device Compatibility Matrix (≥ 27W/30W Standard)

Smart Cooler Control enforces a strict **≥ 27W/30W cooling benchmark**. Low-power coolers (10W-15W USB 5V clips) are intentionally excluded because passive fanless Apple Silicon MacBooks require high-output TEC peltier refrigeration under sustained workloads.

Every supported cooler is recognized through dedicated `DeviceProfile` definitions and isolated `CoolerDriver` protocol drivers.

## Full Multi-Brand Compatibility Matrix

| Brand | Model | Rated Power | Primary GATT Service | Driver Class | Status |
|---|---|---|---|---|---|
| **REDMAGIC** | VC Cooler 6 Pro+ | **40W** | `d52082ad-e805-9f97-9d4e-1c682d9c9ce6` | `RedMagicDriver` | Supported |
| **REDMAGIC** | Cryo Cooler 8 Pro | **36W** | `d52082ad-e805-9f97-9d4e-1c682d9c9ce6` | `RedMagicDriver` | Supported |
| **REDMAGIC** | VC Cooler 6 Pro | **36W** | `d52082ad-e805-9f97-9d4e-1c682d9c9ce6` | `RedMagicDriver` | Supported |
| **REDMAGIC** | Magnetic Cooler 5 Pro | **36W** | `d52082ad-e805-9f97-9d4e-1c682d9c9ce6` | `RedMagicDriver` | Supported (Hardware Verified) |
| **REDMAGIC** | Magcooler 4 Pro | **27W** | `d52082ad-e805-9f97-9d4e-1c682d9c9ce6` | `RedMagicDriver` | Supported |
| **OnePlus** | 45W Liquid Cooler | **45W** | `0000FEE7-0000-1000-8000-00805F9B34FB` | `OnePlusDriver` | Supported |
| **OnePlus** | 27W Freezing Point Clip | **27W** | `0000FEE7-0000-1000-8000-00805F9B34FB` | `OnePlusDriver` | Supported |
| **Black Shark** | MagCooler 5 Pro (BR42) | **35W** | `0000A0A0-3C17-D293-8E48-14FE2E4DA212` | `BlackSharkDriver` | Supported |
| **Black Shark** | MagCooler 4 Pro | **27W** | `0000A0A0-3C17-D293-8E48-14FE2E4DA212` | `BlackSharkDriver` | Supported |
| **MEMO** | CX08 Magnetic Cooler | **36W** | `0000FFE0-0000-1000-8000-00805F9B34FB` | `MemoDriver` | Supported |
| **MEMO** | CX07 Magnetic Cooler | **30W** | `0000FFE0-0000-1000-8000-00805F9B34FB` | `MemoDriver` | Supported |
| **Flydigi** | B8X Overclock | **30W** | `0000FFE0-0000-1000-8000-00805F9B34FB` | `FlydigiDriver` | Supported |
| **Flydigi** | B7X | **27W** | `0000FFE0-0000-1000-8000-00805F9B34FB` | `FlydigiDriver` | Supported |
| **iQOO** | Cooling Back Clip 2 Pro | **27W** | `0000FFF0-0000-1000-8000-00805F9B34FB` | `IQOODriver` | Supported |

## 38°C Shutoff Floor Standard

To deliver optimal sustained thermals while preventing moisture condensation:
1. **Engage Threshold Slider**: Range is **38°C to 85°C**.
2. **Cooling Behavior**: When Mac die heats up to the configured threshold, the cooler engages immediately.
3. **Continuous Cooling Down to 38°C**: The cooler remains actively cooling (stepping down to low/quiet power) until the die drops below **38°C**.
4. **100% Shutoff (< 38°C)**: When the die drops below 38°C, the cooler cuts power completely (Standby / 0% fan) to prevent cold plate condensation when the Mac is cool.
