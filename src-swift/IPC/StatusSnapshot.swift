import Foundation

/// The JSON written to `~/.cooler_status.json` for the `cooler` CLI to read.
///
/// ### Compatibility
/// The property names are the CLI's wire format — `cooler status` and
/// `cooler monitor` parse them with `jq`. Renaming a field, or changing its
/// type, breaks those commands. `snake_case` here is deliberate for the same
/// reason; the `CodingKeys` below keep Swift naming idiomatic on this side
/// without touching the wire format.
struct StatusSnapshot: Codable {
    /// Unix timestamp. The CLI treats a snapshot older than ~15 s as stale,
    /// which is how it detects that the app has died without cleaning up.
    let timestamp: Double
    /// "on" while connected, "connecting" otherwise.
    let state: String
    /// "auto" in auto mode, else the current mode's slug.
    let level: String
    let isAuto: Bool
    let fanPercent: Int
    let modeName: String
    let thermalState: String
    let cpuC: Double?
    let profile: String

    /// Last LED colour written, as `[R, G, B]`; absent when the LED is
    /// device-driven (rainbow/breath) rather than a colour we chose.
    let led: [Int]?
    let lightMode: Int?
    let tempThreshold: Int?
    let deviceAutoTemp: Bool?

    /// Magnetic mount seated.
    let mountAttached: Bool?
    let coldC: Int?
    let hotC: Int?
    let ambientC: Int?
    let fanRPM: Int?

    enum CodingKeys: String, CodingKey {
        case timestamp = "ts"
        case state
        case level
        case isAuto = "auto"
        case fanPercent = "fan_pct"
        case modeName = "mode_name"
        case thermalState = "thermal"
        case cpuC = "cpu_c"
        case profile
        case led
        case lightMode = "light_mode"
        case tempThreshold = "temp_thresh"
        case deviceAutoTemp = "auto_temp"
        case mountAttached = "hall"
        case coldC = "cold_c"
        case hotC = "hot_c"
        case ambientC = "ambient_c"
        case fanRPM = "fan_rpm"
    }
}

/// A command dropped at `~/.cooler_cmd.json` by the CLI, consumed by the app on
/// its next tick.
///
/// Every field is optional: a drop carries only the settings it wants to change.
/// Field names are part of the CLI contract — see `StatusSnapshot`.
struct ControlCommand: Codable {
    /// Switch between autopilot and manual.
    let autoMode: Bool?
    /// `AutoProfile.rawValue`.
    let autoProfile: String?
    /// A raw `CoolingMode` byte. Implies manual mode.
    let coolingMode: Int?
    let fanSpeed: Int?
    /// Raw light-effect byte, for probing effects beyond those the UI exposes.
    let lightMode: Int?
    /// Optional `[R, G, B]` accompanying `lightMode`.
    let lightRGB: [Int]?
    let tempThreshold: Int?
    let deviceAutoTemp: Bool?

    enum CodingKeys: String, CodingKey {
        case autoMode = "auto_mode"
        case autoProfile = "auto_profile"
        case coolingMode = "cooling_mode"
        case fanSpeed = "fan_speed"
        case lightMode = "light_mode"
        case lightRGB = "light_rgb"
        case tempThreshold = "temp_thresh"
        case deviceAutoTemp = "auto_temp"
    }
}
