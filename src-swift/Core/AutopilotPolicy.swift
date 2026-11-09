import Foundation

enum AutoProfile: String, CaseIterable {
    case balanced = "Balanced"
    case smartMax = "Smart Max"

    var caption: String {
        switch self {
        case .balanced:
            return "Smooth acoustic curve: scales gently from 35% to 100%. Shuts off below threshold."
        case .smartMax:
            return "Aggressive cooling ramp: fast-attack boost from base power to 100%. Shuts off below threshold."
        }
    }
}

/// Decides cooling intensity from Mac die temperature and macOS thermal pressure.
///
/// Supports two auto profiles:
///  * Balanced: Gentle linear acoustic ramp (35% to 100%) between shutoff and engage.
///  * Smart Max: Fast-attack aggressive curve (base power to 100%) between shutoff and engage.
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

    /// Physical PWM floor of high-power Peltier coolers (where fan starts distinct acoustic modulation)
    static let hardwareFloorPercent: Double = 35.0

    init(engageC: Double = Config.Autopilot.engageDefaultC,
         shutoffC: Double = Config.Autopilot.shutoffDefaultC,
         minFanPercent: UInt8 = Config.Autopilot.smartMaxMinFanDefault,
         dwell: TimeInterval = Config.Autopilot.cooldownDwell,
         hysteresisC: Double = Config.Autopilot.hysteresisC,
         shutoffFloorC: Double? = nil) {
        let effectiveShutoff = shutoffFloorC ?? shutoffC
        self.shutoffC = effectiveShutoff.clamped(to: Config.Autopilot.shutoffMinC...Config.Autopilot.shutoffMaxC)
        self.minFanPercent = max(35, minFanPercent).clamped(to: 35...100)
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
        self.minFanPercent = max(35, percent).clamped(to: 35...100)
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
        } else if dieC >= engageC {
            // 2. Engage threshold reached or exceeded: Full boost 100%
            targetMode = .max
            targetFan = 100
            label = "\(profile == .smartMax ? "Smart Max" : "Balanced") (100%)"
        } else {
            // 3. Active thermal control zone: shutoffC <= dieC < engageC
            let span = max(1.0, engageC - shutoffC)
            let progress = ((dieC - shutoffC) / span).clamped(to: 0.0...1.0)

            if profile == .smartMax {
                // Smart Max: Fast-attack aggressive curve from base power to 100%
                // Uses sqrt(progress) convex attack so it delivers aggressive cooling immediately
                let base = Double(max(Int(Self.hardwareFloorPercent), Int(minFanPercent)))
                let aggressiveProgress = sqrt(progress)
                let rawFan = base + aggressiveProgress * (100.0 - base)
                targetFan = UInt8(min(100, max(base, round(rawFan / 5.0) * 5.0)))
                label = "Smart Max (\(targetFan)%)"
            } else {
                // Balanced: Gentle linear acoustic ramp from hardware floor (35%) to 100%
                let floor = Self.hardwareFloorPercent
                let rawFan = floor + progress * (100.0 - floor)
                targetFan = UInt8(min(100, max(floor, round(rawFan / 5.0) * 5.0)))
                label = "Balanced (\(targetFan)%)"
            }

            if targetFan >= 85 {
                targetMode = .max
            } else if targetFan >= 60 {
                targetMode = .medium
            } else {
                targetMode = .low
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
