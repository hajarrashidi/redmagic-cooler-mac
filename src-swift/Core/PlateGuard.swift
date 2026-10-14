import Foundation

/// Holds cooling back while the cold plate is colder than a limit, so a cooler
/// left running does not take the plate far below the room's dew point and
/// freeze it or soak what is around it.
///
/// There is no humidity or ambient reading to work out a dew point from, so the
/// limit is a plate temperature the user can set. The guard steps cooling down a
/// level at a time while the plate is under it, and gives the levels back only
/// after the plate has stayed clear of it for a while, so it cannot hunt around
/// the limit. Pure logic: no I/O and no hardware, which is what makes it testable.
struct PlateGuard {

    /// How often another level is held back while the plate stays under the limit.
    /// Long enough for the plate to respond to the last one.
    static let stepDownEvery: TimeInterval = 20
    /// The same, once the plate is `farBelowC` under the limit: waiting a full
    /// interval at each step would let it keep falling.
    static let farStepDownEvery: TimeInterval = 10
    static let farBelowC: Double = 5
    /// How long the plate must stay `releaseMarginC` above the limit before a
    /// level is given back.
    static let recoverAfter: TimeInterval = 30
    static let releaseMarginC: Double = 3

    /// How many levels cooling is currently held back by.
    private(set) var levels = 0

    private var lastStepDown: TimeInterval?
    private var recoveredSince: TimeInterval?

    /// Advances the guard and returns how many levels to hold back.
    ///
    /// - Parameters:
    ///   - plateC: the cold plate temperature, or `nil` when there is no fresh
    ///     reading. Without one the guard keeps what it has rather than guess.
    ///   - isCooling: cooling is wanted and the cooler can act on it. When it is
    ///     not (the user turned it off, or its own switch is off) there is
    ///     nothing to hold back, so the guard resets.
    ///   - floorC: the limit, or `nil` when the guard is switched off.
    ///   - maxLevels: the most that can be held back (every step above Off).
    mutating func update(plateC: Double?, isCooling: Bool, floorC: Double?,
                         maxLevels: Int, now: TimeInterval) -> Int {
        guard isCooling, let floorC else {
            reset()
            return 0
        }
        guard let plateC else { return levels }

        if plateC < floorC {
            recoveredSince = nil
            let interval = plateC < floorC - Self.farBelowC ? Self.farStepDownEvery : Self.stepDownEvery
            if lastStepDown.map({ now - $0 >= interval }) ?? true {
                levels = min(levels + 1, maxLevels)
                lastStepDown = now
            }
        } else if plateC >= floorC + Self.releaseMarginC {
            if levels == 0 {
                recoveredSince = nil
            } else {
                let since = recoveredSince ?? now
                recoveredSince = since
                if now - since >= Self.recoverAfter {
                    levels -= 1
                    recoveredSince = now
                }
            }
        } else {
            // Between the limit and the margin: hold what we have.
            recoveredSince = nil
        }
        return levels
    }

    mutating func reset() {
        levels = 0
        lastStepDown = nil
        recoveredSince = nil
    }
}
