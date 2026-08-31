import Foundation

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

    private(set) var profile: AutoProfile
    /// Temperature at which the first cooling step engages, for `.custom` (°C).
    private(set) var customEngageC: Double

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

    init(profile: AutoProfile = .standard,
         customEngageC: Double = Config.Autopilot.customEngageDefaultC,
         dwell: TimeInterval = Config.Autopilot.cooldownDwell,
         hysteresisC: Double = Config.Autopilot.hysteresisC) {
        self.dwell = dwell
        self.hysteresisC = hysteresisC
        self.profile = profile
        self.customEngageC = customEngageC
        configure(profile: profile, customEngageC: customEngageC)
    }

    // ── Profile configuration ────────────────────────────────────────────────

    func setProfile(_ profile: AutoProfile) {
        configure(profile: profile, customEngageC: customEngageC)
    }

    /// Sets the custom engage point. Recomputes the ladder only when `.custom`
    /// is the active profile; otherwise the value is just remembered.
    func setCustomEngage(_ celsius: Double) {
        let clamped = Self.clampEngage(celsius)
        guard profile == .custom else { customEngageC = clamped; return }
        configure(profile: .custom, customEngageC: clamped)
    }

    private func configure(profile: AutoProfile, customEngageC: Double) {
        self.profile = profile
        self.customEngageC = Self.clampEngage(customEngageC)

        switch profile {
        case .custom:
            // Steps sit 10 °C apart above the user's engage point, with the top
            // tier capped so a high engage point can't push it past 95 °C.
            let engage = self.customEngageC
            let ceiling = min(engage + 30, 95)
            engagePoints = [(engage, 1), (engage + 10, 2), (engage + 20, 3), (ceiling, 4)]
            ledGreenC = max(30, engage - 10)
            ledRedC = ceiling

        case .standard:
            // The cooler plate sits on the Mac's chassis, so it earns its keep
            // while the machine is merely warm — not only under sustained load.
            // Engage early and ramp quickly.
            engagePoints = [(Config.Autopilot.standardEngageC, 1), (50, 2), (62, 3), (74, 4)]
            ledGreenC = Config.Autopilot.standardEngageC
            ledRedC = 78
        }

        // The ladder moved underneath us; abandon any dwell in progress.
        coolingSince = nil
    }

    private static func clampEngage(_ celsius: Double) -> Double {
        let bounds = Config.Autopilot.customEngageMinC...Config.Autopilot.customEngageMaxC
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
            // Cooling off — hold, then release one tier at a time.
            if let since = coolingSince {
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

        let temperature = dieC.map { String(format: "%.0f°C", $0) } ?? "temp ?"
        let easing = (target < tierIndex && coolingSince != nil) ? " — easing down soon" : ""
        return Decision(tier: Self.tiers[tierIndex],
                        reason: "Mac \(temperature) (\(thermalState.rawValue))\(easing)")
    }

    /// The tier the current conditions call for, before dwell/hysteresis smoothing.
    private func targetTierIndex(thermalState: ThermalState, dieC: Double?) -> Int {
        max(thermalState.tierFloor, temperatureTierIndex(for: dieC))
    }

    /// Highest tier whose engage point the temperature has reached, with
    /// hysteresis applied so the current tier is held slightly past its own
    /// engage point on the way down.
    private func temperatureTierIndex(for dieC: Double?) -> Int {
        guard let dieC else { return 0 }

        let rising = engagePoints.last { dieC >= $0.temperatureC }?.tierIndex ?? 0
        guard rising < tierIndex else { return rising }

        guard let currentEngage = engagePoints.first(where: { $0.tierIndex == tierIndex })?.temperatureC
        else { return 0 }
        return dieC >= (currentEngage - hysteresisC) ? tierIndex : rising
    }

    // ── LED heat colour ──────────────────────────────────────────────────────

    /// Green→red gradient for the current die temperature, used by the LED's
    /// "Auto" effect. The endpoints track the active profile so the colour
    /// stays meaningful when the user moves their engage point.
    func heatColor(for dieC: Double?) -> RGB {
        let temperature = dieC ?? ledGreenC
        let span = max(1, ledRedC - ledGreenC)
        let fraction = ((temperature - ledGreenC) / span).clamped(to: 0...1)
        // Hue 120° (green) → 0° (red).
        return RGB(hue: (1 - fraction) * (120.0 / 360.0))
    }
}
