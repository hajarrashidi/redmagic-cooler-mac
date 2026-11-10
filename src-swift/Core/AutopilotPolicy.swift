import Foundation

/// Discrete Cooling Tiers for the Deterministic Step-Ladder Engine.
enum CoolingTier: Int, Comparable, CaseIterable {
    case standby = 0
    case tier1_low = 1
    case tier2_med = 2
    case tier3_high = 3
    case tier4_turbo = 4

    static func < (lhs: CoolingTier, rhs: CoolingTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var fanPercent: UInt8 {
        switch self {
        case .standby:     return 0
        case .tier1_low:   return 40
        case .tier2_med:   return 60
        case .tier3_high:  return 80
        case .tier4_turbo: return 100
        }
    }

    var mode: CoolingMode {
        switch self {
        case .standby:     return .off
        case .tier1_low:   return .low
        case .tier2_med:   return .medium
        case .tier3_high:  return .medium
        case .tier4_turbo: return .max
        }
    }

    var label: String {
        switch self {
        case .standby:     return "Standby (Off)"
        case .tier1_low:   return "Tier 1 — Quiet (40%)"
        case .tier2_med:   return "Tier 2 — Balanced (60%)"
        case .tier3_high:  return "Tier 3 — High (80%)"
        case .tier4_turbo: return "Tier 4 — Turbo (100%)"
        }
    }
}

enum AutoProfile: String, CaseIterable {
    case stepLadder = "Step-Ladder"
    case balanced = "Balanced"
    case smartMax = "Smart Max"

    var caption: String {
        switch self {
        case .stepLadder:
            return "Deterministic 4-stage ladder (50°/60°/65°/70°C) with anti-chattering dwell and safety."
        case .balanced:
            return "Quiet min power below threshold. Progressive ramp up to 100% when threshold is reached."
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
/// Implements the deterministic 4-stage Step-Ladder thermal engine with wide asymmetric
/// anti-chattering release buffers (up to 8°C release buffer) and dynamic dwell timing
/// with thermal velocity (dT/dt) fast bypass.
final class AutopilotPolicy {

    struct Tier: Equatable {
        let mode: CoolingMode
        let fanPercent: UInt8
        let label: String
        let coolingTier: CoolingTier?

        init(mode: CoolingMode, fanPercent: UInt8, label: String, coolingTier: CoolingTier? = nil) {
            self.mode = mode
            self.fanPercent = fanPercent
            self.label = label
            self.coolingTier = coolingTier
        }
    }

    static let tiers: [Tier] = [
        Tier(mode: .off,    fanPercent: 0,   label: "off",     coolingTier: .standby),
        Tier(mode: .low,    fanPercent: 40,  label: "low",     coolingTier: .tier1_low),
        Tier(mode: .medium, fanPercent: 60,  label: "medium",  coolingTier: .tier2_med),
        Tier(mode: .medium, fanPercent: 80,  label: "high",    coolingTier: .tier3_high),
        Tier(mode: .max,    fanPercent: 100, label: "turbo",   coolingTier: .tier4_turbo),
    ]

    struct Decision {
        let tier: Tier
        let reason: String
    }

    // ── State ────────────────────────────────────────────────────────────────

    private(set) var currentTier: CoolingTier = .standby
    private(set) var isStandby: Bool = true
    private(set) var profile: AutoProfile = .stepLadder

    // Timing and Dwell state
    private var pendingTier: CoolingTier? = nil
    private var pendingTierStartTime: TimeInterval = 0
    private var pendingIsFastDwell: Bool = false
    private var lastTierChangeTime: TimeInterval = 0
    private var lastEvaluatedTempC: Double? = nil
    private var lastEvaluatedTime: TimeInterval = 0

    // Configuration / Compatibility
    private(set) var engageC: Double = Config.Autopilot.tier1TriggerC
    private(set) var shutoffC: Double = Config.Autopilot.tier1ReleaseC
    private(set) var minFanPercent: UInt8 = 40
    private(set) var hysteresisC: Double = Config.Autopilot.hysteresisC

    /// The temperature the Mac must reach to exit Standby and resume active cooling.
    var wakeThresholdC: Double {
        return Config.Autopilot.tier1TriggerC
    }

    init(engageC: Double = Config.Autopilot.tier1TriggerC,
         shutoffC: Double = Config.Autopilot.tier1ReleaseC,
         minFanPercent: UInt8 = 40,
         dwell: TimeInterval = Config.Autopilot.stepDownDwellSeconds,
         hysteresisC: Double = Config.Autopilot.hysteresisC,
         shutoffFloorC: Double? = nil) {
        self.engageC = engageC
        self.shutoffC = shutoffC
        self.minFanPercent = minFanPercent.clamped(to: 40...100)
        self.hysteresisC = hysteresisC
    }

    func setProfile(_ profile: AutoProfile) {
        self.profile = profile
    }

    func setEngage(_ celsius: Double) {
        self.engageC = celsius
    }

    func setShutoff(_ celsius: Double) {
        self.shutoffC = celsius
    }

    func setMinFanPercent(_ percent: UInt8) {
        self.minFanPercent = percent.clamped(to: 40...100)
    }

    func setHysteresis(_ celsius: Double) {
        self.hysteresisC = max(0.0, celsius)
    }

    func resetStandby(isStandby: Bool = false) {
        self.isStandby = isStandby
        self.currentTier = isStandby ? .standby : .tier1_low
        self.pendingTier = nil
        self.pendingTierStartTime = 0
    }

    func setTier(_ tier: CoolingTier) {
        self.currentTier = tier
        self.isStandby = (tier == .standby)
        self.pendingTier = nil
        self.pendingTierStartTime = 0
    }

    // ── Candidate Tier Calculation ───────────────────────────────────────────

    /// Calculates which tier the temperature qualifies for, respecting asymmetric hysteresis.
    func candidateTier(for dieC: Double, current: CoolingTier) -> CoolingTier {
        // Step-Up Triggers: Any temperature crossing an upper threshold qualifies immediately
        if dieC >= Config.Autopilot.tier4TriggerC {
            return .tier4_turbo
        }
        if dieC >= Config.Autopilot.tier3TriggerC && current < .tier4_turbo {
            return .tier3_high
        }
        if dieC >= Config.Autopilot.tier2TriggerC && current < .tier3_high {
            return .tier2_med
        }
        if dieC >= Config.Autopilot.tier1TriggerC && current < .tier2_med {
            return .tier1_low
        }

        // Asymmetric Step-Down Release Thresholds:
        if current == .tier4_turbo {
            if dieC >= Config.Autopilot.tier4ReleaseC { return .tier4_turbo }
            if dieC >= Config.Autopilot.tier3ReleaseC { return .tier3_high }
            if dieC >= Config.Autopilot.tier2ReleaseC { return .tier2_med }
            if dieC >= Config.Autopilot.tier1ReleaseC { return .tier1_low }
            return .standby
        }

        if current == .tier3_high {
            if dieC >= Config.Autopilot.tier3ReleaseC { return .tier3_high }
            if dieC >= Config.Autopilot.tier2ReleaseC { return .tier2_med }
            if dieC >= Config.Autopilot.tier1ReleaseC { return .tier1_low }
            return .standby
        }

        if current == .tier2_med {
            if dieC >= Config.Autopilot.tier2ReleaseC { return .tier2_med }
            if dieC >= Config.Autopilot.tier1ReleaseC { return .tier1_low }
            return .standby
        }

        if current == .tier1_low {
            if dieC >= Config.Autopilot.tier1ReleaseC { return .tier1_low }
            return .standby
        }

        // Current is Standby: holds Standby until dieC >= tier1TriggerC (50°C)
        return .standby
    }

    // ── Evaluation ───────────────────────────────────────────────────────────

    func evaluate(thermalState: ThermalState,
                  dieC: Double?,
                  now: TimeInterval = 0) -> Decision {
        let currentTime = (now > 0) ? now : Date().timeIntervalSince1970

        guard let dieC else {
            isStandby = true
            currentTier = .standby
            pendingTier = nil
            return Decision(tier: Tier(mode: .off, fanPercent: 0, label: "off", coolingTier: .standby),
                            reason: "Mac temperature unavailable")
        }

        // Safety override for critical thermal pressure
        if thermalState == .critical {
            isStandby = false
            currentTier = .tier4_turbo
            pendingTier = nil
            lastTierChangeTime = currentTime
            return Decision(tier: Tier(mode: .max, fanPercent: 100, label: "emergency max", coolingTier: .tier4_turbo),
                            reason: "Mac \(Int(round(dieC)))°C (critical)")
        }

        // Universal Condensation Cutoff: Die below 36.0°C forces Standby
        if dieC < Config.Safety.condensationCutoffC {
            isStandby = true
            currentTier = .standby
            pendingTier = nil
            return Decision(tier: Tier(mode: .off, fanPercent: 0, label: "Standby (< 36°C Safety)", coolingTier: .standby),
                            reason: "Mac \(String(format: "%.0f°C", dieC)) (Safety Intercept)")
        }

        // Thermal Velocity (dT/dt) Calculation:
        var isRapidlyCooling = false
        if let lastT = lastEvaluatedTempC, lastEvaluatedTime > 0, currentTime > lastEvaluatedTime {
            let dt = currentTime - lastEvaluatedTime
            if dt > 0.05 {
                let dT = dieC - lastT
                let rate = dT / dt // °C / second
                if rate <= Config.Autopilot.velocityBypassRateCPerSec {
                    isRapidlyCooling = true
                }
            }
        }
        lastEvaluatedTempC = dieC
        lastEvaluatedTime = currentTime

        // Determine Candidate Tier
        let candidate = candidateTier(for: dieC, current: currentTier)

        if candidate > currentTier {
            // STEP-UP: Immediate execution (no dwell)
            currentTier = candidate
            pendingTier = nil
            pendingTierStartTime = 0
            pendingIsFastDwell = false
            lastTierChangeTime = currentTime
            isStandby = (currentTier == .standby)
        } else if candidate < currentTier {
            // STEP-DOWN: Enforce dwell unless rapid cooling bypasses it
            if isRapidlyCooling {
                pendingIsFastDwell = true
            }

            if pendingTier != candidate {
                pendingTier = candidate
                pendingTierStartTime = currentTime
                if isRapidlyCooling {
                    pendingIsFastDwell = true
                }
            }

            let requiredDwell = pendingIsFastDwell ? Config.Autopilot.fastDwellSeconds : Config.Autopilot.stepDownDwellSeconds
            let elapsed = currentTime - pendingTierStartTime
            if elapsed >= requiredDwell {
                currentTier = candidate
                pendingTier = nil
                pendingTierStartTime = 0
                pendingIsFastDwell = false
                lastTierChangeTime = currentTime
                isStandby = (currentTier == .standby)
            }
            // While dwelling, currentTier is held!
        } else {
            // Equal: No change, clear any stale pending step-down
            pendingTier = nil
            pendingTierStartTime = 0
            pendingIsFastDwell = false
            isStandby = (currentTier == .standby)
        }

        let tempStr = String(format: "%.0f°C", dieC)
        let tierObj = Tier(mode: currentTier.mode,
                           fanPercent: currentTier.fanPercent,
                           label: currentTier.label,
                           coolingTier: currentTier)

        return Decision(tier: tierObj,
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
