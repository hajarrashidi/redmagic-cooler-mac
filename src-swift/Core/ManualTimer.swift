import Foundation

/// The auto-off clock for Manual cooling.
///
/// Manual is the one mode nothing ever switches off. Auto backs down on its
/// own as the Mac cools, and quitting turns the cooler off — but a Manual
/// session set and forgotten runs until someone remembers it. That matters more
/// for this hardware than for a fan: a thermoelectric plate held below room
/// temperature for hours condenses moisture out of the air onto itself, and it
/// does that whether or not anyone is watching.
///
/// So Manual gets a deadline by default, and removing it is a deliberate act
/// the menu asks about rather than a setting that starts switched off.
struct ManualTimer {

    /// How long a Manual session may run before it is switched off.
    ///
    /// Raw values are hours and are persisted directly, which makes `unlimited`
    /// zero — "no hours" reads naturally as "no limit", and it keeps a corrupt
    /// or missing default from silently meaning "run for ever" (the initialiser
    /// below falls back to `oneHour`, not to the zero case).
    enum Timeout: Int, CaseIterable {
        case oneHour = 1
        case twoHours = 2
        case threeHours = 3
        case unlimited = 0

        /// Menu labels, in `allCases` order.
        var label: String {
            switch self {
            case .oneHour:    return "1h"
            case .twoHours:   return "2h"
            case .threeHours: return "3h"
            case .unlimited:  return "∞"
            }
        }

        var seconds: TimeInterval? {
            self == .unlimited ? nil : TimeInterval(rawValue) * 3600
        }

        /// Anything unrecognised — a missing default, a value from a future
        /// build — lands on the shortest limit rather than on no limit.
        init(persisted raw: Int?) {
            guard let raw, let value = Timeout(rawValue: raw) else {
                self = .oneHour
                return
            }
            self = value
        }
    }

    private(set) var timeout: Timeout
    /// When the current session runs out. Nil whenever nothing is being timed:
    /// the cooler is off, the mode is Auto, or the timeout is unlimited.
    private(set) var deadline: TimeInterval?

    init(timeout: Timeout) {
        self.timeout = timeout
    }

    /// Starts the clock, or restarts it. Called whenever the user commands a
    /// Manual level — someone working the slider has plainly not forgotten the
    /// cooler, and it would be perverse to switch it off under them mid-session.
    mutating func start(now: TimeInterval = Date().timeIntervalSince1970) {
        deadline = timeout.seconds.map { now + $0 }
    }

    mutating func stop() {
        deadline = nil
    }

    mutating func setTimeout(_ timeout: Timeout,
                             running: Bool,
                             now: TimeInterval = Date().timeIntervalSince1970) {
        self.timeout = timeout
        // Re-based rather than adjusted: switching 1h → 2h mid-session means
        // "give me two hours", not "give me whatever is left plus one".
        if running {
            start(now: now)
        } else {
            stop()
        }
    }

    /// True once the deadline has passed. Reading it does not consume it —
    /// the caller decides what expiry means.
    func hasExpired(now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard let deadline else { return false }
        return now >= deadline
    }

    /// Time left, rendered for the menu: "1h 58m" down to "< 1m", or nil when
    /// nothing is being timed.
    func remainingText(now: TimeInterval = Date().timeIntervalSince1970) -> String? {
        guard let deadline else { return nil }
        let remaining = deadline - now
        guard remaining > 0 else { return "< 1m" }
        let minutes = Int(remaining / 60)
        guard minutes >= 60 else { return minutes < 1 ? "< 1m" : "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
