import Foundation

/// Append-only timeline of heat and cooler events, tailed by `cooler log`.
///
/// Writes are appends, not rewrites: the previous implementation read the whole
/// file, re-joined it and wrote it back on *every* line, which is O(file) per
/// event on the main thread. The file is trimmed back to `maxLines` only when
/// it grows past `trimThreshold`, so the expensive path runs roughly once per
/// thousand events instead of every one.
enum EventLogger {

    static let maxLines = 2_000
    /// Trim once the file exceeds this; the slack avoids trimming every append.
    private static let trimThreshold = 3_000

    private static let queue = DispatchQueue(label: "com.redmagic.cooler.eventlog")

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Appends one line. Safe to call from any thread; ordering is preserved.
    ///
    /// Serialised on a private queue but dispatched synchronously so a line
    /// logged immediately before `exit()` still reaches disk.
    static func record(_ message: String) {
        let line = "\(timestampFormatter.string(from: Date()))  \(message)\n"
        queue.sync { append(line) }
    }

    private static func append(_ line: String) {
        let url = Config.Paths.log
        guard let data = line.data(using: .utf8) else { return }

        guard let handle = try? FileHandle(forWritingTo: url) else {
            // File doesn't exist yet (or isn't writable) — create it.
            try? data.write(to: url, options: .atomic)
            return
        }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return }
        try? handle.write(contentsOf: data)

        // Cheap pre-filter on file size — assuming a conservative ~64 bytes per
        // line — so the line-counting pass in trim() runs only when the file is
        // plausibly over the limit, not on every append.
        if end > UInt64(trimThreshold * 64) { trim(url) }
    }

    /// Rewrites the file keeping only the most recent `maxLines` entries.
    private static func trim(_ url: URL) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        var lines = content.components(separatedBy: "\n")
        if lines.last?.isEmpty == true { lines.removeLast() }
        guard lines.count > trimThreshold else { return }

        let kept = lines.suffix(maxLines).joined(separator: "\n") + "\n"
        try? kept.data(using: .utf8)?.write(to: url, options: .atomic)
    }
}
