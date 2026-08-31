import Foundation

/// Narrow file transport for the reverse-engineering scripts in this folder.
/// This source is compiled into local development builds only when
/// `build.sh --with-probes` is used; release builds do not contain it.
enum ProbeBridge {
    private static let home = FileManager.default.homeDirectoryForCurrentUser
    private static let statusURL = home.appendingPathComponent(".redmagic_probe_status.json")
    private static let commandURL = home.appendingPathComponent(".redmagic_probe_command.json")

    struct Snapshot: Encodable {
        let timestamp: Double
        let connected: Bool
        let cpuC: Double?
        let coldC: Int?
        let hotC: Int?
        let ambientC: Int?
        let fanRPM: Int?

        enum CodingKeys: String, CodingKey {
            case timestamp = "ts"
            case connected
            case cpuC = "cpu_c"
            case coldC = "cold_c"
            case hotC = "hot_c"
            case ambientC = "ambient_c"
            case fanRPM = "fan_rpm"
        }
    }

    struct Command: Decodable {
        let autoMode: Bool?
        let coolingMode: Int?
        let fanSpeed: Int?
        let lightMode: Int?
        let lightRGB: [Int]?

        enum CodingKeys: String, CodingKey {
            case autoMode = "auto_mode"
            case coolingMode = "cooling_mode"
            case fanSpeed = "fan_speed"
            case lightMode = "light_mode"
            case lightRGB = "light_rgb"
        }
    }

    static func write(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: statusURL, options: .atomic)
    }

    static func takePendingCommand() -> Command? {
        guard FileManager.default.fileExists(atPath: commandURL.path) else { return nil }

        defer { try? FileManager.default.removeItem(at: commandURL) }
        guard let data = try? Data(contentsOf: commandURL) else { return nil }
        do {
            return try JSONDecoder().decode(Command.self, from: data)
        } catch {
            EventLogger.record("probe — discarding malformed command: \(error)")
            return nil
        }
    }

    static func cleanUp() {
        try? FileManager.default.removeItem(at: statusURL)
        try? FileManager.default.removeItem(at: commandURL)
    }
}
