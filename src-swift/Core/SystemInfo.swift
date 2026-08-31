import Foundation

/// Host-machine facts the UI displays: the Mac's marketing name and the user's
/// preferred temperature unit.
enum SystemInfo {

    // ── Temperature unit ─────────────────────────────────────────────────────

    enum TempUnit {
        case celsius, fahrenheit
        var suffix: String { self == .celsius ? "°C" : "°F" }
    }

    /// The system-wide preference (System Settings → General → Language &
    /// Region → Temperature), falling back to the locale's measurement system.
    static func temperatureUnit() -> TempUnit {
        // `AppleTemperatureUnit` lives in NSGlobalDomain, which `.standard`
        // searches. Its value is "Celsius" or "Fahrenheit".
        if let raw = UserDefaults.standard.string(forKey: "AppleTemperatureUnit") {
            return raw.lowercased().hasPrefix("f") ? .fahrenheit : .celsius
        }
        return Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
    }

    /// Formats a Celsius value in the user's unit, e.g. `54°C` / `129°F`.
    /// - Parameter degreeOnly: drop the C/F letter, for tight telemetry cells.
    static func formatTemp(_ celsius: Double?,
                           degreeOnly: Bool = false,
                           unit: TempUnit? = nil) -> String {
        guard let celsius else { return "—" }
        let unit = unit ?? temperatureUnit()
        let value = (unit == .fahrenheit) ? celsius * 9 / 5 + 32 : celsius
        let rounded = Int(value.rounded())
        return degreeOnly ? "\(rounded)°" : "\(rounded)\(unit.suffix)"
    }

    static func formatTemp(_ celsius: Int?,
                           degreeOnly: Bool = false,
                           unit: TempUnit? = nil) -> String {
        formatTemp(celsius.map(Double.init), degreeOnly: degreeOnly, unit: unit)
    }

    // ── Mac model name ───────────────────────────────────────────────────────

    /// Guards `cachedModel`, which is written from the background resolver and
    /// read from the main thread on every menu draw.
    private static let cacheLock = NSLock()
    private static var cachedModel: String?

    /// Best known friendly model name, e.g. "MacBook Pro".
    ///
    /// Returns immediately. On a cold cache this is a coarse family derived
    /// from `hw.model`; call `resolveModelName` once at launch to refine it.
    static var macModel: String {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cachedModel { return cachedModel }
        let value = UserDefaults.standard.string(forKey: Config.Key.cachedMacModel)
            ?? coarseModelFamily()
        cachedModel = value
        return value
    }

    /// Refines `macModel` via `system_profiler` — which takes hundreds of
    /// milliseconds, hence the background queue — and caches the result across
    /// launches. `completion` runs on the main queue, and only if the name
    /// actually changed, so the caller can refresh the UI without a needless
    /// redraw at every launch.
    static func resolveModelName(_ completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let resolved = marketingName() ?? coarseModelFamily()

            cacheLock.lock()
            let changed = (resolved != cachedModel)
            cachedModel = resolved
            cacheLock.unlock()

            UserDefaults.standard.set(resolved, forKey: Config.Key.cachedMacModel)
            guard changed else { return }
            DispatchQueue.main.async { completion(resolved) }
        }
    }

    /// Reads "Model Name" out of `system_profiler SPHardwareDataType`.
    private static func marketingName() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        task.arguments = ["SPHardwareDataType"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8) else { return nil }

            for line in output.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("Model Name:") else { continue }
                let name = trimmed.dropFirst("Model Name:".count)
                    .trimmingCharacters(in: .whitespaces)
                return name.isEmpty ? nil : name
            }
        } catch {
            return nil
        }
        return nil
    }

    /// A fast, coarse family name from the `hw.model` identifier, so there is
    /// always something to show before `system_profiler` returns.
    ///
    /// Apple-silicon machines report an opaque `MacN,N` that carries no family,
    /// so those fall through to the generic "Mac" until the resolver runs.
    private static func coarseModelFamily() -> String {
        let identifier = hardwareIdentifier().lowercased()
        let families = [
            ("macbookpro", "MacBook Pro"),
            ("macbookair", "MacBook Air"),
            ("macbook",    "MacBook"),
            ("macmini",    "Mac mini"),
            ("macstudio",  "Mac Studio"),
            ("macpro",     "Mac Pro"),
            ("imac",       "iMac"),
        ]
        return families.first { identifier.hasPrefix($0.0) }?.1 ?? "Mac"
    }

    private static func hardwareIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }
}
