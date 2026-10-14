import Foundation

/// Decides how hard to cool, from Mac die temperature and macOS thermal
/// pressure.
///
/// The policy is a five-step ladder (`Tier.off` … `Tier.max`), or, when the user
/// sets a custom curve, one stage per step of the connected cooler. Two
/// mechanisms keep it from oscillating around a threshold:
///
///  * **Hysteresis** — on the default ladder a tier only releases once the
///    temperature falls `Config.Autopilot.hysteresisC` *below* the point that
///    engaged it. A custom curve has none: below a stage's temperature the
///    stage is released.
///  * **Dwell** — the temperature must stay low for
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
        /// The step to hold: 0 is off, and 1… are the ladder's tiers (see
        /// `tiers`) or, with a custom curve, the stages of the cooler's steps.
        let index: Int
        /// Human-readable justification, written to the event log on a change.
        let reason: String
    }

    // ── Configuration ────────────────────────────────────────────────────────

    /// Temperature at which the first cooling step engages (°C). The whole
    /// ladder is derived from this one number — it is the single knob the
    /// menu's threshold slider drives.
    private(set) var engageC: Double

    private let dwell: TimeInterval
    private let ladderHysteresisC: Double

    /// A user-defined engage temperature for each stage of the cooler,
    /// replacing the ladder derived from `engageC`. `nil` means "use the
    /// ladder". Always valid when set — see `isValidCurve`.
    private(set) var customCurveC: [Double]?

    /// The release margin in force: none on a custom curve, so a stage lets go
    /// as soon as the Mac is below its temperature.
    private var hysteresisC: Double { customCurveC == nil ? ladderHysteresisC : 0 }

    /// The highest step, which the safety floor is measured against.
    private var floorTop: Int { engagePoints.count }

    /// Engage temperature for each tier index ≥ 1, ascending.
    private var engagePoints: [(temperatureC: Double, tierIndex: Int)] = []

    /// Where the first cooling tier engages: the threshold the menu reports
    /// while Auto is waiting for the Mac to warm up.
    var firstEngageC: Double { engagePoints.first?.temperatureC ?? engageC }

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
         dwell: TimeInterval = Config.Autopilot.cooldownDwell,
         hysteresisC: Double = Config.Autopilot.hysteresisC) {
        self.dwell = dwell
        self.ladderHysteresisC = hysteresisC
        self.engageC = engageC
        configure(engageC: engageC)
    }

    // ── Ladder configuration ─────────────────────────────────────────────────

    /// Moves the engage point and rebuilds the ladder around it.
    func setEngage(_ celsius: Double) {
        configure(engageC: celsius)
    }

    /// Replaces the ladder with explicit engage temperatures, one per stage of
    /// the cooler, or restores it with `nil`. An invalid curve is ignored, so a
    /// bad saved value can never leave the stages out of order.
    func setCustomCurve(_ temperaturesC: [Double]?) {
        if let temperaturesC, Self.isValidCurve(temperaturesC, stages: temperaturesC.count) {
            customCurveC = temperaturesC
        } else {
            customCurveC = nil
        }
        // The old stage no longer means what it did.
        tierIndex = 0
        configure(engageC: engageC)
    }

    /// Whether `temperaturesC` is a usable curve for a cooler with `stages`
    /// steps above Off: one point per stage, each inside the allowed range and
    /// each at least a degree above the one before it, so the stages engage in
    /// order.
    static func isValidCurve(_ temperaturesC: [Double], stages: Int) -> Bool {
        guard stages > 0, temperaturesC.count == stages else { return false }
        let bounds = Config.Autopilot.curveMinC...Config.Autopilot.curveMaxC
        guard temperaturesC.allSatisfy({ bounds.contains($0) }) else { return false }
        return zip(temperaturesC, temperaturesC.dropFirst()).allSatisfy { $1 - $0 >= 1 }
    }

    /// A starting curve for a cooler with `stages` steps above Off: every stage,
    /// the last included, spread evenly from `engageC` up to 95 °C. Stages are
    /// always at least a degree apart, so a high start with many stages runs
    /// past 95 °C rather than producing two equal temperatures.
    static func spreadCurve(engageC: Double, stages: Int) -> [Double] {
        let engage = clampEngage(engageC)
        guard stages > 1 else { return [engage] }
        var curve = [Double]()
        for index in 0..<stages {
            let even = engage + (Double(index) * (95 - engage) / Double(stages - 1)).rounded()
            curve.append(min(max(even, (curve.last ?? even - 1) + 1), Config.Autopilot.curveMaxC))
        }
        return curve
    }

    /// The ladder derived from a single engage point: steps 10 °C apart, with
    /// every tier capped so a high engage point can't push it past 95 °C. The
    /// intermediate steps need the cap too, not just the top one: an 80 °C
    /// engage point would otherwise put tier 3 at 100 °C — *above* tier 4's
    /// capped 95 — and the ladder would engage out of order.
    static func defaultCurve(engageC: Double) -> [Double] {
        let engage = clampEngage(engageC)
        let ceiling = min(engage + 30, 95)
        return [engage, min(engage + 10, ceiling), min(engage + 20, ceiling), ceiling]
    }

    private func configure(engageC: Double) {
        self.engageC = Self.clampEngage(engageC)

        let curve = customCurveC ?? Self.defaultCurve(engageC: self.engageC)
        engagePoints = curve.enumerated().map { (temperatureC: $0.element, tierIndex: $0.offset + 1) }
        ledGreenC = max(30, curve[0] - 10)
        ledRedC = curve[curve.count - 1]

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
        return Decision(index: tierIndex,
                        reason: "Mac \(temperature) (\(thermalState.rawValue))\(easing)")
    }

    /// The tier the current conditions call for, before dwell/hysteresis smoothing.
    private func targetTierIndex(thermalState: ThermalState, dieC: Double?) -> Int {
        max(thermalState.floor(top: floorTop), temperatureTierIndex(for: dieC))
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
