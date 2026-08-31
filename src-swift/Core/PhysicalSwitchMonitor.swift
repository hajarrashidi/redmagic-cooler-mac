import Foundation

/// Infers that the cooler's physical power switch is off while the app still
/// holds a Bluetooth link to it.
///
/// The device exposes no characteristic for the switch — `0x1017` and `0x1019`
/// read a constant `0x00` (see `docs/FINDINGS.md`) — so this is inferred from
/// the signals that do move. Two independent tells, because either can be the
/// only one available:
///
///  * **Fan reporting zero RPM** while the app has commanded cooling. The fan
///    is wired downstream of the switch, so it cannot spin with the switch off.
///    Useless on older firmware, whose shorter telemetry frames omit the field.
///  * **Telemetry going silent.** Frames stop arriving even though the link is
///    still up. This is the fallback for firmware with no RPM field.
///
/// Both are debounced: a fan takes a moment to spin up, and a single dropped
/// frame is normal. Being wrong here is cheap in one direction and annoying in
/// the other — a missed detection just leaves the old behaviour, while a false
/// positive tells the user their hardware is off when it is running — so the
/// thresholds are deliberately slack.
struct PhysicalSwitchMonitor {

    /// How long a tell must persist before it is believed. Comfortably longer
    /// than fan spin-up and any single missed frame.
    static let confirmAfter: TimeInterval = 6.0
    /// Silence longer than this counts as the device having stopped reporting.
    static let telemetrySilentAfter: TimeInterval = 10.0

    private var suspectSince: TimeInterval?

    /// True once a tell has persisted past `confirmAfter`.
    private(set) var looksPoweredOff = false

    /// - Parameters:
    ///   - isCommandedOn: the app has asked the cooler to run. Nothing is
    ///     inferred while it is meant to be off — a still fan proves nothing.
    ///   - fanRPM: latest reported RPM; `nil` when the firmware omits the field.
    ///   - secondsSinceLastFrame: age of the newest telemetry frame.
    mutating func update(isCommandedOn: Bool,
                         fanRPM: Int?,
                         secondsSinceLastFrame: TimeInterval,
                         now: TimeInterval) {
        guard isCommandedOn else { return reset() }

        let fanSaysOff = (fanRPM == 0)
        let silent = secondsSinceLastFrame >= Self.telemetrySilentAfter
        guard fanSaysOff || silent else { return reset() }

        let since = suspectSince ?? now
        suspectSince = since
        looksPoweredOff = (now - since) >= Self.confirmAfter
    }

    /// Clears the suspicion, so a device that starts responding is trusted
    /// again immediately rather than serving out the debounce.
    mutating func reset() {
        suspectSince = nil
        looksPoweredOff = false
    }
}
