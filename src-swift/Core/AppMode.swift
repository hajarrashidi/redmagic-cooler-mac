import Foundation

/// Which control loop owns the cooler.
///
/// Persisted verbatim in `UserDefaults`, so changing the raw values requires a
/// migration for existing users.
enum AppMode: String {
    /// The autopilot follows Mac temperature and drives the cooler itself.
    case auto
    /// The user's slider position is held until they change it.
    case manual

    /// Decodes a persisted value, defaulting to `.auto`.
    /// Legacy builds also wrote "off" here; it maps to `.manual`, which is
    /// where an explicit off-state now lives (manual step 0).
    init(persisted raw: String?) {
        self = (raw == AppMode.manual.rawValue || raw == "off") ? .manual : .auto
    }
}

/// The autopilot's aggressiveness preset.
///
/// Raw values are persisted. Builds before the profile rework wrote
/// "aggressive"/"regular"; both migrate to `.standard`.
enum AutoProfile: String {
    /// A fixed, balanced tier ladder tuned for a cooler plate sitting on a Mac.
    case standard
    /// Tiers derived from a user-chosen engage temperature.
    case custom

    init(persisted raw: String?) {
        self = (raw == AutoProfile.custom.rawValue) ? .custom : .standard
    }

    var displayName: String { self == .custom ? "Custom" : "Standard" }
}

/// macOS's own thermal pressure level, from `ProcessInfo.thermalState`.
///
/// The autopilot uses this as a floor: regardless of the die temperature, a
/// `serious`/`critical` system gets cooling.
enum ThermalState: String {
    case nominal, fair, serious, critical

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal:  self = .nominal
        case .fair:     self = .fair
        case .serious:  self = .serious
        case .critical: self = .critical
        @unknown default: self = .nominal
        }
    }

    /// The lowest cooling tier the autopilot may settle at in this state.
    var tierFloor: Int {
        switch self {
        case .nominal, .fair: return 0
        case .serious:        return 3
        case .critical:       return 4
        }
    }
}
