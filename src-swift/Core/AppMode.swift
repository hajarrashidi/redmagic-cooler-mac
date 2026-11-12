import Foundation

/// Which control loop owns the cooler.
///
/// Persisted verbatim in `UserDefaults`, so changing the raw values requires a
/// migration for existing users.
enum AppMode: String, CaseIterable {
    /// The deterministic 4-stage step-ladder autopilot drives the cooler.
    case auto
    /// The user's manual cooling setting is held until changed.
    case manual
    /// Immediate continuous 100% boost (protected by the < 36°C Safety Governor).
    case turbo

    /// Decodes a persisted value, defaulting to `.auto`.
    /// Legacy builds also wrote "off" here; it maps to `.manual`, which is
    /// where an explicit off-state now lives (manual step 0).
    init(persisted raw: String?) {
        switch raw {
        case AppMode.manual.rawValue, "off":
            self = .manual
        case AppMode.turbo.rawValue:
            self = .turbo
        default:
            self = .auto
        }
    }
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
    var tierFloor: CoolingTier {
        switch self {
        case .nominal, .fair: return .standby
        case .serious:        return .tier2_med
        case .critical:       return .tier4_turbo
        }
    }
}
