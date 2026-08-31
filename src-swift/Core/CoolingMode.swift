import Foundation

/// A TEC (thermo-electric cooler) power setting, as carried in byte 0 of the
/// cooling-mode characteristic.
///
/// This is a `RawRepresentable` struct rather than an `enum` on purpose: the
/// firmware reports intermediate bytes we never write ourselves (0x04, 0x06,
/// 0x07), and an unknown byte read back from the device must round-trip rather
/// than fail to decode. Named constants cover everything we write; `zone`
/// folds any byte — known or not — into the coarse band the UI displays.
///
/// Hot-side temperatures below are from the bench measurements in
/// `docs/FINDINGS.md`; they are not linear in the byte value.
struct CoolingMode: RawRepresentable, Equatable, Hashable {
    let rawValue: UInt8

    init(rawValue: UInt8) { self.rawValue = rawValue }

    static let off     = CoolingMode(rawValue: 0x03)   // TEC disabled
    static let low     = CoolingMode(rawValue: 0x01)   // ~10 °C hot side
    static let lowPlus = CoolingMode(rawValue: 0x04)   // firmware-reported only
    static let medLow  = CoolingMode(rawValue: 0x05)   // ~26 °C
    static let medium  = CoolingMode(rawValue: 0x02)   // ~40 °C
    static let medHigh = CoolingMode(rawValue: 0x06)   // firmware-reported only
    static let high    = CoolingMode(rawValue: 0x07)   // firmware-reported only
    static let max     = CoolingMode(rawValue: 0x08)   // ~69 °C

    /// True whenever the TEC is drawing power. The single most-asked question
    /// about a mode byte, and the reason `!= .off` never appears inline.
    var isOn: Bool { self != .off }

    /// The coarse band a mode falls into, used for the slider zones, the fan
    /// animation speed, and the status badge. Unknown bytes are treated as
    /// `.medium` — a safe middle for display purposes.
    enum Zone: Int, Comparable {
        case off = 0, low = 1, medium = 2, max = 3
        static func < (a: Zone, b: Zone) -> Bool { a.rawValue < b.rawValue }
    }

    var zone: Zone {
        switch self {
        case .off:                      return .off
        case .low, .lowPlus, .medLow:   return .low
        case .medium, .medHigh:         return .medium
        case .high, .max:               return .max
        default:                        return .medium
        }
    }

    /// The mode this zone is driven with when the user picks it directly.
    var zoneRepresentative: CoolingMode {
        switch zone {
        case .off:    return .off
        case .low:    return .low
        case .medium: return .medium
        case .max:    return .max
        }
    }

    /// Short badge text for the status card.
    var displayName: String {
        switch self {
        case .off:     return "Off"
        case .low:     return "Low"
        case .lowPlus: return "Low+"
        case .medLow:  return "Med-Low"
        case .medium:  return "Medium"
        case .medHigh: return "Med-High"
        case .high:    return "High"
        case .max:     return "Max"
        default:       return "On"
        }
    }

    /// Stable lowercase identifier used in the IPC status file and the log.
    var slug: String {
        switch zone {
        case .off:    return "off"
        case .low:    return "low"
        case .medium: return "medium"
        case .max:    return "max"
        }
    }
}
