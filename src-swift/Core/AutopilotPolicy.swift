import Foundation

enum AutoProfile: String, CaseIterable {
    case balanced = "Balanced"
    case smartMax = "Smart Max"

    var caption: String {
        switch self {
        case .balanced:
            return "Dynamic curve: smooth 25%–100% cooling. Safely shuts off below threshold."
        case .smartMax:
            return "Full 100% power at ≥ engage. Minimum quiet power until < shutoff."
        }
    }
}

/// Decides how hard to cool from Mac die temperature and macOS thermal pressure.
///
/// Supports two auto profiles:
///  * Balanced: Dynamic proportional fan curve (25% to 100%) between shutoff and engage thresholds.
///  * Smart Max: Full 100% power at/above engage threshold, quiet minimum power between shutoff and engage.
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
        Tier(mode: .low,    fanPercent: 60,  label: "low"),
        Tier(mode: .medLow, fanPercent: 80,  label: "med-low"),
        Tier(mode: .medium, fanPercent: 95,  label: "medium"),
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
        self.minFanPercent = minFanPercent.clamped(to: 10...100)
        self.engageC = max(engageC, self.shutoffC + 2.0).clamped(to: Config.Autopilot.engageMinC...Config.Autopilot.engageMaxC)
    }

    func setProfile(_ profile: AutoProfile) {
        self.profile = profile
    }

    func setEngage(_ celsius: Double) {
        self.engageC = max(celsius, shutoffC + 2.0).clamped(to: Config.Autopilot.engageMinC...Config.Autopilot.engageMaxC)
    }

    func setShutoff(_ celsius: Double) {
        self.shutoffC = min(celsius, engageC - 2.0).clamped(to: Config.Autopilot.shutoffMinC...Config.Autopilot.shutoffMaxC)
    }

    func setMinFanPercent(_ percent: UInt8) {
        self.minFanPercent = percent.clamped(to: 10...100)
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

        // 1. Shutoff condition applies to BOTH Balanced and Smart Max!
        if dieC < shutoffC {
            targetMode = .off
            targetFan = 0
            label = "off (< \(Int(round(shutoffC)))°C)"
        } else if profile == .smartMax {
            // Smart Max profile
            if dieC >= engageC {
                targetMode = .max
                targetFan = 100
                label = "max (100%)"
            } else {
                targetMode = .low
                targetFan = minFanPercent
                label = "min (\(minFanPercent)%)"
            }
        } else {
            // Balanced profile: Dynamic proportional curve
            if dieC >= engageC {
                targetMode = .max
                targetFan = 100
                label = "max (100%)"
            } else {
                let span = max(1.0, engageC - shutoffC)
                let t = ((dieC - shutoffC) / span).clamped(to: 0.0...1.0)
                // Linear interpolation from 25% to 100%, rounded to nearest 5%
                let rawFan = 25.0 + t * 75.0
                let quantizedFan = UInt8(min(100, max(20, round(rawFan / 5.0) * 5.0)))
                targetFan = quantizedFan
                if targetFan >= 85 {
                    targetMode = .max
                } else if targetFan >= 65 {
                    targetMode = .medium
                } else {
                    targetMode = .low
                }
                label = "curve (\(targetFan)%)"
            }
        }

        let tempStr = String(format: "%.0f°C", dieC)
        return Decision(tier: Tier(mode: targetMode, fanPercent: targetFan, label: label),
                        reason: "Mac \(tempStr) (\(thermalState.rawValue))")
    }

    func heatColor(for dieC: Double?) -> RGB {
        let temp = dieC ?? shutoffC
        let span = max(1.0, engageC - shutoffC)
        let fraction = ((temp - shutoffC) / span).clamped(to: 0.0...1.0)
        return RGB(hue: (1.0 - fraction) * (120.0 / 360.0))
    }
}
