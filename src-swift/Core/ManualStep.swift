import Foundation

/// One position on the manual power slider.
///
/// A cooling mode paired with a fan speed, and, on models that have one, the
/// maximum-output "boost" mode on top. Each cooler model supplies its own list
/// (`DeviceProfile.manualSteps`), because what a position means is a property of
/// the hardware.
struct ManualStep {
    let mode: CoolingMode
    let fanPercent: UInt8
    let name: String
    /// The model's maximum-output mode (Diablo on the 8 Pro), switched on in
    /// addition to the mode and fan speed.
    var boost = false
}

/// A label drawn under the slider, centred on one of its tick marks.
struct SliderLabel {
    let text: String
    let tick: Int
    let isMajor: Bool
}

extension Array where Element == ManualStep {

    /// The index of the step best matching a device state, for syncing the
    /// slider to what the app last asked for.
    ///
    /// The mode is first folded into its zone, then the closest fan speed
    /// within that zone wins. A boosted state only matches boosted steps.
    func index(matching mode: CoolingMode, fanPercent: UInt8, boost: Bool) -> Int {
        guard mode.isOn else { return 0 }
        let target = mode.zoneRepresentative
        return enumerated()
            .filter { $0.element.mode == target && $0.element.boost == boost }
            .min { a, b in
                abs(Int(a.element.fanPercent) - Int(fanPercent))
                    < abs(Int(b.element.fanPercent) - Int(fanPercent))
            }?.offset ?? 0
    }

    /// What to actually send for a request, with cooling held back by `levels`:
    /// the request's own step moved down that many steps, to Off at the lowest.
    /// A request that is already off, or one that matches no step, is returned
    /// unchanged.
    func holdingBack(_ levels: Int, from request: (mode: CoolingMode, fanPercent: UInt8, boost: Bool))
        -> (mode: CoolingMode, fanPercent: UInt8, boost: Bool) {
        guard levels > 0, request.mode.isOn, !isEmpty else { return request }
        let index = self.index(matching: request.mode, fanPercent: request.fanPercent,
                               boost: request.boost)
        guard index > 0 else { return request }
        let step = self[Swift.max(index - levels, 0)]
        return (step.mode, step.fanPercent, step.boost)
    }
}
