import Foundation

enum AutoProfile: String, CaseIterable {
    case balanced = "Balanced"
    case smartMax = "Smart Max"

    var caption: String {
        switch self {
        case .balanced:
            return "Smooth ramp: starts at engage threshold, cools down to shutoff."
        case .smartMax:
            return "100% at ≥ engage point. Holds minimum power until < shutoff."
        }
    }
}

/// Decides how hard to cool, from Mac die temperature and macOS thermal
/// pressure.
///
/// The policy is a five-step ladder (`Tier.off` … `Tier.max`). Two mechanisms
/// keep it from oscillating around a threshold:
///
///  * **Hysteresis** — a tier only releases once the temperature falls
///    `Config.Autopilot.hysteresisC` *below* the point that engaged it.
///  * **Dwell** — after that, the temperature must stay low for
///    `Config.Autopilot.cooldownDwell` before stepping down, and steps down one
///    tier at a time rather than dropping straight to the target.
///
/// Ramping *up* is immediate: heat is the thing we're reacting to.
///
/// This type is pure decision logic — it performs no I/O and touches no
/// hardware, which is what makes it straightforward to reason about and test.
final class AutopilotPolicy {

    // ── Tier ladder ──────────────────────────────────────────────────────────

    /// One rung of the ladder. Fan values are RPM-probe calibrated rather than
    /// linear percentages — the firmware's response curve is U-shaped
    /// (0 → off, 60 → ~6 600, 80 → ~8 200, 95 → ~8 600 RPM).
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

    /// Result of one evaluation.
    struct Decision {
        let tier: Tier
        /// Human-readable justification, written to the event log on a change.
        let reason: String
    }

    // ── Configuration ────────────────────────────────────────────────────────

    /// Temperature at which the maximum or ramping cooling step engages (°C).
    private(set) var engageC: Double

    /// Temperature below which cooling turns off completely (0% fan / Standby).
    private(set) var shutoffC: Double

    /// Minimum fan speed in Smart Max when below engage threshold (default 30%).
    private(set) var minFanPercent: UInt8

    private(set) var profile: AutoProfile = .balanced

    private let dwell: TimeInterval
    private let hysteresisC: Double

    /// Engage temperature for each tier index ≥ 1, ascending.
    private var engagePoints: [(temperatureC: Double, tierIndex: Int)] = []

    /// Die temperatures mapped to the LED's green and red endpoints.
    private var ledGreenC: Double = 0
    private var ledRedC: Double = 0

    // ── Live state ───────────────────────────────────────────────────────────

    /// Index into `tiers` currently being held.
    private(set) var tierIndex = 0
    /// When the temperature first dropped below the current tier; `nil` while
    /// at or above it. Drives the dwell timer.
    private var coolingSince: TimeInterval?

    init(engageC: Double = Config.Autopilot.engageDefaultC,
         shutoffC: Double = Config.Autopilot.shutoffDefaultC,
         minFanPercent: UInt8 = Config.Autopilot.smartMaxMinFanDefault,
         dwell: TimeInterval = Config.Autopilot.cooldownDwell,
         hysteresisC: Double = Config.Autopilot.hysteresisC,
         shutoffFloorC: Double? = nil) {
        self.dwell = dwell
        self.hysteresisC = hysteresisC
        let effectiveShutoff = shutoffFloorC ?? shutoffC
        self.shutoffC = effectiveShutoff.clamped(to: Config.Autopilot.shutoffMinC...Config.Autopilot.shutoffMaxC)
        self.minFanPercent = minFanPercent.clamped(to: 10...100)
        self.engageC = engageC
        configure(engageC: engageC)
    }

    // ── Ladder configuration ─────────────────────────────────────────────────

    func setProfile(_ profile: AutoProfile) {
        self.profile = profile
        coolingSince = nil
    }

    /// Moves the engage point and rebuilds the ladder around it.
    func setEngage(_ celsius: Double) {
        configure(engageC: celsius)
    }

    /// Sets the shutoff cutoff temperature below which cooling is 0% / off.
    func setShutoff(_ celsius: Double) {
        self.shutoffC = celsius.clamped(to: Config.Autopilot.shutoffMinC...Config.Autopilot.shutoffMaxC)
        coolingSince = nil
    }

    /// Sets the minimum active fan speed in Smart Max (e.g. 30%).
    func setMinFanPercent(_ percent: UInt8) {
        self.minFanPercent = percent.clamped(to: 10...100)
    }

    private func configure(engageC: Double) {
        self.engageC = Self.clampEngage(engageC)

        // Steps sit 10 °C apart above the user's engage point, with every
        // tier capped so a high engage point can't push it past 95 °C. The
        // intermediate steps need the cap too, not just the top one: a
        // 80 °C engage point would otherwise put tier 3 at 100 °C — *above*
        // tier 4's capped 95 — and the ladder would engage out of order.
        let engage = self.engageC
        let ceiling = min(engage + 30, 95)
        engagePoints = [(engage, 1),
                        (min(engage + 10, ceiling), 2),
                        (min(engage + 20, ceiling), 3),
                        (ceiling, 4)]
        ledGreenC = max(30, engage - 10)
        ledRedC = ceiling

        // The ladder moved underneath us; abandon any dwell in progress.
        coolingSince = nil
    }

    private static func clampEngage(_ celsius: Double) -> Double {
        let bounds = Config.Autopilot.engageMinC...Config.Autopilot.engageMaxC
        return celsius.clamped(to: bounds)
    }

    // ── Evaluation ───────────────────────────────────────────────────────────

    /// Advances the policy one step and returns the tier to apply.
    ///
    /// - Parameters:
    ///   - thermalState: macOS thermal pressure, used as a tier floor.
    ///   - dieC: mean die temperature, or `nil` when unavailable (treated as cool).
    ///   - now: current time; injected so the dwell logic is testable.
    func evaluate(thermalState: ThermalState,
                  dieC: Double?,
                  now: TimeInterval) -> Decision {
        let target = targetTierIndex(thermalState: thermalState, dieC: dieC)

        if target > tierIndex {
            // Heat rises — follow it immediately.
            tierIndex = target
            coolingSince = nil
        } else if target < tierIndex {
            // If target is off (below shutoff threshold), cut cooling immediately
            // so cooler doesn't run needlessly while the Mac is already cold.
            let cutoff = min(engageC, shutoffC)
            if target == 0 && (dieC == nil || dieC! < cutoff) {
                tierIndex = 0
                coolingSince = nil
            } else if profile == .smartMax && target == 1 {
                // Smart Max eases down directly to min tier without dwell delay
                tierIndex = 1
                coolingSince = nil
            } else if let since = coolingSince {
                // Stepped cool-down for hot Mac transitioning between active tiers
                if now - since >= dwell {
                    tierIndex -= 1
                    coolingSince = (tierIndex > target) ? now : nil
                }
            } else {
                coolingSince = now
            }
        } else {
            coolingSince = nil
        }

        let appliedTier: Tier
        if profile == .smartMax && tierIndex == 1 {
            // In Smart Max, below engage threshold runs at user-configured minimum fan speed
            appliedTier = Tier(mode: .low, fanPercent: minFanPercent, label: "min (\(minFanPercent)%)")
        } else {
            appliedTier = Self.tiers[tierIndex]
        }

        let temperature = dieC.map { String(format: "%.0f°C", $0) } ?? "temp ?"
        let easing = (target < tierIndex && coolingSince != nil) ? " — easing down soon" : ""
        return Decision(tier: appliedTier,
                        reason: "Mac \(temperature) (\(thermalState.rawValue))\(easing)")
    }

    /// The tier the current conditions call for, before dwell/hysteresis smoothing.
    private func targetTierIndex(thermalState: ThermalState, dieC: Double?) -> Int {
        if profile == .smartMax, let dieC {
            if dieC >= engageC {
                return 4 // Max Tier (100% fan)
            } else if dieC >= shutoffC {
                // In Smart Max: between shutoff and engage, stay active at minimum power!
                return 1 // Min Tier (runs at minFanPercent)
            } else {
                return 0 // Off (below shutoff threshold)
            }
        }

        return max(thermalState.tierFloor, temperatureTierIndex(for: dieC))
    }

    /// Highest tier whose engage point the temperature has reached, with
    /// hysteresis applied so the current tier is held slightly past its own
    /// engage point on the way down.
    private func temperatureTierIndex(for dieC: Double?) -> Int {
        guard let dieC else { return 0 }

        let rising = engagePoints.last { dieC >= $0.temperatureC }?.tierIndex ?? 0
        guard rising < tierIndex else { return rising }

        // When stepping down from an active tier:
        // Tier 1 stays held until dieC drops below shutoffC!
        if tierIndex == 1 {
            let cutoff = min(engageC, shutoffC)
            return dieC >= cutoff ? 1 : 0
        }

        guard let currentEngage = engagePoints.first(where: { $0.tierIndex == tierIndex })?.temperatureC
        else { return 0 }
        return dieC >= (currentEngage - hysteresisC) ? tierIndex : rising
    }

    // ── LED heat colour ──────────────────────────────────────────────────────

    /// Green→red gradient for the current die temperature, used by the LED's
    /// "Auto" effect. The endpoints track the ladder so the colour stays
    /// meaningful when the user moves their engage point.
    func heatColor(for dieC: Double?) -> RGB {
        let temperature = dieC ?? ledGreenC
        let span = max(1, ledRedC - ledGreenC)
        let fraction = ((temperature - ledGreenC) / span).clamped(to: 0...1)
        // Hue 120° (green) → 0° (red).
        return RGB(hue: (1 - fraction) * (120.0 / 360.0))
    }
}
