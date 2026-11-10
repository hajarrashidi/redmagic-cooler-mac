import Foundation

enum AutoProfile: String, CaseIterable {
    case balanced = "Balanced"
    case smartMax = "Smart Max"

    var caption: String {
        switch self {
        case .balanced:
            return "Quiet min power below threshold. Smooth progressive ramp up to 100% when threshold is reached."
        case .smartMax:
            return "Quiet min power below threshold. Immediate 100% max boost when threshold is reached."
        }
    }
}

/// Thermal calibration thresholds for Mac families based on Apple Silicon thermal envelopes.
struct MacThermalThresholds {
    let greenMaxC: Double
    let redMinC: Double
}

enum MacThermalProfile {
    static func thresholds(for model: String) -> MacThermalThresholds {
        let lower = model.lowercased()
        if lower.contains("studio") || lower.contains("mini") || (lower.contains("pro") && !lower.contains("macbook")) {
            // Mac Studio / Mac mini / Mac Pro: massive active heatsinks, lower normal temp band
            return MacThermalThresholds(greenMaxC: 50.0, redMinC: 72.0)
        } else if lower.contains("air") {
            // MacBook Air: fanless passive chassis dissipation; 35-55°C is nominal idle/light work, >78°C is hot
            return MacThermalThresholds(greenMaxC: 55.0, redMinC: 80.0)
        } else if lower.contains("macbook") {
            // MacBook Pro: internal fans idle/off until ~75°C; 38-58°C nominal, >82°C hot
            return MacThermalThresholds(greenMaxC: 58.0, redMinC: 82.0)
        } else {
            return MacThermalThresholds(greenMaxC: 55.0, redMinC: 80.0)
        }
    }
}

/// Decides cooling intensity from Mac die temperature and macOS thermal pressure.
///
/// Supports two auto profiles:
///  * Balanced: Gentle acoustic ramp (min power to 100%) as temperature approaches engage threshold.
///  * Smart Max: Holds quiet min power across normal temperatures, delivering 100% full boost at engage.
///
/// Both profiles safely shut off completely (0% / Standby) when the Mac drops below the shutoff threshold.
final class AutopilotPolicy {

    struct Tier {
        let mode: CoolingMode
        let fanPercent: UInt8
        let label: String
    }

    static let tiers: [Tier] = [
        Tier(mode: .off,    fanPercent: 0,   label: "off"),
        Tier(mode: .low,    fanPercent: 40,  label: "low"),
        Tier(mode: .medium, fanPercent: 70,  label: "medium"),
        Tier(mode: .max,    fanPercent: 100, label: "max"),
    ]

    struct Decision {
        let tier: Tier
        let reason: String
    }

    // ── Configuration ────────────────────────────────────────────────────────

    private(set) var engageC: Double
    private(set) var shutoffC: Double
    private(set) var minFanPercent: UInt8
    private(set) var profile: AutoProfile = .balanced
    private(set) var hysteresisC: Double
    private(set) var isStandby: Bool = false

    /// The temperature the Mac must reach to exit Standby and resume active cooling.
    /// Clamped so it never exceeds the Engage threshold.
    var wakeThresholdC: Double {
        min(shutoffC + hysteresisC, engageC)
    }

    init(engageC: Double = Config.Autopilot.engageDefaultC,
         shutoffC: Double = Config.Autopilot.shutoffDefaultC,
         minFanPercent: UInt8 = Config.Autopilot.smartMaxMinFanDefault,
         dwell: TimeInterval = Config.Autopilot.cooldownDwell,
         hysteresisC: Double = Config.Autopilot.hysteresisC,
         shutoffFloorC: Double? = nil) {
        let safeEngage = engageC.clamped(to: Config.Autopilot.engageMinC...Config.Autopilot.engageMaxC)
        let maxAllowedShutoff = min(Config.Autopilot.shutoffMaxC, safeEngage - 2.0)
        let effectiveShutoff = shutoffFloorC ?? shutoffC
        self.shutoffC = effectiveShutoff.clamped(to: Config.Autopilot.shutoffMinC...maxAllowedShutoff)
        self.engageC = safeEngage
        self.minFanPercent = minFanPercent.clamped(to: 40...100)
        self.hysteresisC = max(0.0, hysteresisC)
    }

    func setProfile(_ profile: AutoProfile) {
        self.profile = profile
    }

    func setEngage(_ celsius: Double) {
        let minAllowed = max(Config.Autopilot.engageMinC, self.shutoffC + 2.0)
        self.engageC = celsius.clamped(to: minAllowed...Config.Autopilot.engageMaxC)
    }

    func setShutoff(_ celsius: Double) {
        let maxAllowed = min(Config.Autopilot.shutoffMaxC, self.engageC - 2.0)
        self.shutoffC = celsius.clamped(to: Config.Autopilot.shutoffMinC...maxAllowed)
    }

    func setMinFanPercent(_ percent: UInt8) {
        self.minFanPercent = percent.clamped(to: 40...100)
    }

    func setHysteresis(_ celsius: Double) {
        self.hysteresisC = max(0.0, celsius)
    }

    func resetStandby(isStandby: Bool = false) {
        self.isStandby = isStandby
    }

    // ── Evaluation ───────────────────────────────────────────────────────────

    func evaluate(thermalState: ThermalState,
                  dieC: Double?,
                  now: TimeInterval = 0) -> Decision {
        guard let dieC else {
            isStandby = true
            return Decision(tier: Tier(mode: .off, fanPercent: 0, label: "off"),
                            reason: "Mac temperature unavailable")
        }

        // Safety override for critical thermal pressure
        if thermalState == .critical {
            isStandby = false
            return Decision(tier: Tier(mode: .max, fanPercent: 100, label: "emergency max"),
                            reason: "Mac \(Int(round(dieC)))°C (critical)")
        }

        // 1. Cutoff & 5°C Hysteresis State Machine:
        // When die drops below shutoff, cooler enters Standby immediately to prevent condensation.
        if dieC < shutoffC {
            isStandby = true
        } else if isStandby {
            // While in Standby, hold off cooling until die rises to wakeThresholdC (shutoff + 5°C)
            if dieC >= wakeThresholdC {
                isStandby = false
            }
        }

        if isStandby {
            let label = "Standby (< \(Int(round(wakeThresholdC)))°C)"
            return Decision(tier: Tier(mode: .off, fanPercent: 0, label: label),
                            reason: "Mac \(String(format: "%.0f°C", dieC)) (\(thermalState.rawValue))")
        }

        let targetMode: CoolingMode
        let targetFan: UInt8
        let label: String

        // 2. Active Nominal Zone: shutoffC <= dieC < engageC
        // RIGIDLY HONORS USER'S MIN POWER!
        // When below engage threshold, the cooler stays quiet and steady at user-chosen minFanPercent.
        if dieC < engageC {
            targetFan = minFanPercent
            label = "\(profile == .smartMax ? "Smart Max" : "Balanced") (\(targetFan)%)"
            if targetFan >= 85 {
                targetMode = .max
            } else if targetFan >= 60 {
                targetMode = .medium
            } else {
                targetMode = .low
            }
        } else {
            // 3. Active Engage Zone: dieC >= engageC
            if profile == .smartMax {
                // Smart Max: Immediate full 100% boost upon crossing engage threshold!
                targetFan = 100
                targetMode = .max
                label = "Smart Max (100%)"
            } else {
                // Balanced: Smooth progressive ramp above Engage from minFanPercent to 100%
                let span: Double = 15.0 // 15°C gentle ramp window above engage threshold
                let excess = dieC - engageC
                let progress = (excess / span).clamped(to: 0.0...1.0)
                let base = Double(minFanPercent)
                let rawFan = base + progress * (100.0 - base)
                targetFan = UInt8(min(100, max(base, round(rawFan / 5.0) * 5.0)))
                label = "Balanced (\(targetFan)%)"
                if targetFan >= 85 {
                    targetMode = .max
                } else if targetFan >= 60 {
                    targetMode = .medium
                } else {
                    targetMode = .low
                }
            }
        }

        let tempStr = String(format: "%.0f°C", dieC)
        return Decision(tier: Tier(mode: targetMode, fanPercent: targetFan, label: label),
                        reason: "Mac \(tempStr) (\(thermalState.rawValue))")
    }

    /// Calculates realistic thermal LED colour based on host Mac hardware family.
    /// Green: cool / nominal idle; Yellow: moderate active load; Red: high heat / throttling.
    func heatColor(for dieC: Double?, macModel: String = SystemInfo.macModel) -> RGB {
        guard let dieC else { return RGB(r: 0, g: 255, b: 0) }
        let t = MacThermalProfile.thresholds(for: macModel)
        if dieC <= t.greenMaxC {
            return RGB(r: 0, g: 255, b: 0)
        } else if dieC >= t.redMinC {
            return RGB(r: 255, g: 0, b: 0)
        } else {
            let fraction = (dieC - t.greenMaxC) / (t.redMinC - t.greenMaxC)
            let hue = (1.0 - fraction) * (120.0 / 360.0)
            return RGB(hue: hue)
        }
    }
}
