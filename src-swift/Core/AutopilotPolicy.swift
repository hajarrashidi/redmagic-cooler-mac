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

    init(engageC: Double = Config.Autopilot.engageDefaultC,
         shutoffC: Double = Config.Autopilot.shutoffDefaultC,
         minFanPercent: UInt8 = Config.Autopilot.smartMaxMinFanDefault,
         dwell: TimeInterval = Config.Autopilot.cooldownDwell,
         hysteresisC: Double = Config.Autopilot.hysteresisC,
         shutoffFloorC: Double? = nil) {
        let effectiveShutoff = shutoffFloorC ?? shutoffC
        self.shutoffC = effectiveShutoff.clamped(to: Config.Autopilot.shutoffMinC...Config.Autopilot.shutoffMaxC)
        self.minFanPercent = minFanPercent.clamped(to: 20...100)
        self.engageC = max(engageC, self.shutoffC + 2.0).clamped(to: Config.Autopilot.engageMinC...Config.Autopilot.engageMaxC)
    }

    func setProfile(_ profile: AutoProfile) {
        self.profile = profile
    }

    func setEngage(_ celsius: Double) {
        self.engageC = celsius.clamped(to: Config.Autopilot.engageMinC...Config.Autopilot.engageMaxC)
        // If engage is dragged down towards shutoff, push shutoff downward so they never collide or lock up
        if self.shutoffC > self.engageC - 2.0 {
            self.shutoffC = max(Config.Autopilot.shutoffMinC, self.engageC - 2.0)
        }
    }

    func setShutoff(_ celsius: Double) {
        self.shutoffC = celsius.clamped(to: Config.Autopilot.shutoffMinC...Config.Autopilot.shutoffMaxC)
        // If shutoff is dragged up towards engage, push engage upward so they never collide or lock up
        if self.engageC < self.shutoffC + 2.0 {
            self.engageC = min(Config.Autopilot.engageMaxC, self.shutoffC + 2.0)
        }
    }

    func setMinFanPercent(_ percent: UInt8) {
        self.minFanPercent = percent.clamped(to: 20...100)
    }

    // ── Evaluation ───────────────────────────────────────────────────────────

    func evaluate(thermalState: ThermalState,
                  dieC: Double?,
                  now: TimeInterval = 0) -> Decision {
        guard let dieC else {
            return Decision(tier: Tier(mode: .off, fanPercent: 0, label: "off"),
                            reason: "Mac temperature unavailable")
        }

        // Safety override for critical thermal pressure
        if thermalState == .critical {
            return Decision(tier: Tier(mode: .max, fanPercent: 100, label: "emergency max"),
                            reason: "Mac \(Int(round(dieC)))°C (critical)")
        }

        let targetMode: CoolingMode
        let targetFan: UInt8
        let label: String

        // 1. Cutoff: Below shutoff threshold, cooler turns completely off to prevent condensation
        if dieC < shutoffC {
            targetMode = .off
            targetFan = 0
            label = "Standby (< \(Int(round(shutoffC)))°C)"
        } else if dieC < engageC {
            // 2. Nominal Zone: shutoffC <= dieC < engageC
            // RIGIDLY HONORS USER'S MIN POWER!
            // When below engage threshold, the cooler stays quiet and steady at user-chosen minFanPercent.
            targetFan = minFanPercent
            label = "\(profile == .smartMax ? "Smart Max" : "Balanced") (\(targetFan)%)"
            targetMode = (targetFan >= 60) ? .medium : .low
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
