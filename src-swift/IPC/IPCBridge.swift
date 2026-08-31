import Foundation

/// The file-based bridge to the `cooler` shell CLI.
///
/// The menu-bar app is the only process that talks to the cooler, so the CLI
/// cannot drive the hardware directly — it leaves a command file for the app to
/// pick up and reads a status file the app keeps current. Files in `$HOME` were
/// chosen over a socket or XPC service because they let the CLI stay a plain
/// shell script with no helper binary.
///
///  * `~/.cooler_status.json` — written every tick (`StatusSnapshot`).
///  * `~/.cooler_cmd.json`    — polled every tick, then deleted (`ControlCommand`).
///  * `~/.cooler.pid`         — this process's PID, so the CLI can tell whether
///                              the app is running and the next launch can hand
///                              the Bluetooth link over cleanly.
enum IPCBridge {

    // ── PID file ─────────────────────────────────────────────────────────────

    static func writePIDFile() {
        let pid = String(ProcessInfo.processInfo.processIdentifier)
        try? pid.write(to: Config.Paths.pid, atomically: true, encoding: .utf8)
    }

    /// Removes the runtime files at quit, so the CLI reports "not running"
    /// rather than reading a stale snapshot.
    static func cleanUpRuntimeFiles() {
        try? FileManager.default.removeItem(at: Config.Paths.pid)
        try? FileManager.default.removeItem(at: Config.Paths.status)
    }

    /// The PID recorded by a previous instance, if that process is still alive.
    static func liveRecordedPID() -> Int32? {
        guard let raw = try? String(contentsOf: Config.Paths.pid, encoding: .utf8),
              let pid = Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid != ProcessInfo.processInfo.processIdentifier,
              kill(pid, 0) == 0
        else { return nil }
        return pid
    }

    // ── Status ───────────────────────────────────────────────────────────────

    /// Writes the snapshot atomically, so a CLI reading concurrently never sees
    /// a half-written file. Failures are ignored: a missed snapshot is
    /// self-correcting on the next tick, and there is no user-facing recovery.
    static func write(_ snapshot: StatusSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: Config.Paths.status, options: .atomic)
    }

    // ── Commands ─────────────────────────────────────────────────────────────

    /// Reads and consumes a pending command, if one is waiting.
    ///
    /// The file is deleted before decoding, and also when decoding fails, so a
    /// malformed drop can't wedge the poll loop by being retried forever.
    static func takePendingCommand() -> ControlCommand? {
        let url = Config.Paths.command
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        defer { try? FileManager.default.removeItem(at: url) }
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(ControlCommand.self, from: data)
        } catch {
            EventLogger.record("IPC — discarding malformed command file: \(error)")
            return nil
        }
    }
}
