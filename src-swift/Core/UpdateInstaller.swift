import AppKit

/// Downloads a release DMG, swaps the running bundle for the app inside it,
/// and relaunches — the half of updating that `UpdateChecker` deliberately
/// doesn't do (it only *notices* releases; this acts on them).
///
/// ### Why the swap is safe while the app is running
///
/// macOS keeps the running executable's inode open, so replacing the bundle on
/// disk doesn't disturb the current process. The relaunch then leans on
/// machinery that already exists: `open -n` starts the *new* binary, whose
/// `SingleInstance.terminateOthersAndWait` gracefully terminates this one —
/// which runs the normal quit path, including the clean Bluetooth teardown
/// that frees the cooler's single connection slot for the new instance.
///
/// ### Why this sidesteps the Gatekeeper problem
///
/// A DMG downloaded by a browser is quarantined, and quarantine is what makes
/// Gatekeeper refuse an un-notarized app. This app doesn't opt into
/// `LSFileQuarantineEnabled`, so a DMG it downloads itself carries no
/// quarantine flag and the app inside mounts and copies clean — updating
/// works even for ad-hoc-signed releases that a manual download would block.
///
/// Every failure lands in `.failed` rather than throwing UI: the banner offers
/// the release page as the fallback, which is exactly what the app did for
/// every release before it could install them.
final class UpdateInstaller {

    enum State: Equatable {
        case idle
        case downloading
        case installing
        /// The attempt failed; the banner falls back to the release page.
        /// A later check (tomorrow's, or next launch's) may retry.
        case failed
    }

    /// Read on the main thread; every transition is delivered there too.
    private(set) var state: State = .idle

    /// Called on the main queue whenever `state` changes.
    var onChange: (() -> Void)?

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        // The whole DMG, on a slow link. Generous — a stalled transfer is
        // cut by the request timeout above, not this.
        configuration.timeoutIntervalForResource = 15 * 60
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    // ── Entry point ──────────────────────────────────────────────────────────

    /// Downloads and installs `update`, relaunching on success.
    ///
    /// Callable from `.idle` and `.failed` — the latter so a later check can
    /// retry a transient failure — and a no-op mid-flight or without a DMG.
    func install(_ update: UpdateChecker.Available) {
        guard state == .idle || state == .failed else { return }
        guard let dmgURL = update.dmgURL else { return }

        setState(.downloading)
        EventLogger.record("update — downloading \(update.tag)")

        session.downloadTask(with: dmgURL) { [weak self] location, response, error in
            guard let self else { return }
            guard let location, error == nil,
                  (response as? HTTPURLResponse)?.statusCode == 200 else {
                EventLogger.record("update — download failed: "
                                 + (error?.localizedDescription ?? "bad response"))
                self.setState(.failed)
                return
            }

            // The system deletes `location` when this handler returns, so the
            // DMG must move somewhere stable before installing from it.
            let dmg = location.deletingLastPathComponent()
                .appendingPathComponent("redmagic-cooler-update.dmg")
            do {
                try? FileManager.default.removeItem(at: dmg)
                try FileManager.default.moveItem(at: location, to: dmg)
            } catch {
                EventLogger.record("update — could not keep download: "
                                 + error.localizedDescription)
                self.setState(.failed)
                return
            }

            self.setState(.installing)
            self.installAndRelaunch(dmg: dmg, tag: update.tag)
        }.resume()
    }

    /// Runs on the URLSession callback queue — a background thread, which is
    /// what the blocking `hdiutil`/`ditto` calls below want anyway.
    private func installAndRelaunch(dmg: URL, tag: String) {
        defer { try? FileManager.default.removeItem(at: dmg) }
        do {
            let mountPoint = try Self.attach(dmg)
            defer { Self.detach(mountPoint) }

            let newApp = try Self.appBundle(in: mountPoint)
            try Self.validate(newApp)

            let destination = Bundle.main.bundleURL
            try Self.swap(newApp, into: destination)

            EventLogger.record("update — installed \(tag), relaunching")
            DispatchQueue.main.async { [weak self] in
                Self.relaunch(destination)
                // The new instance takes over by terminating this one. If it
                // never does — launch failed, or the new build crashed on
                // start — don't spin the banner forever over an install that
                // already landed; a manual restart picks it up.
                DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                    guard let self, self.state == .installing else { return }
                    EventLogger.record("update — relaunch did not take over")
                    self.setState(.failed)
                }
            }
        } catch {
            EventLogger.record("update — install failed: \(error.localizedDescription)")
            setState(.failed)
        }
    }

    private func setState(_ newState: State) {
        DispatchQueue.main.async {
            guard self.state != newState else { return }
            self.state = newState
            self.onChange?()
        }
    }

    // ── Install steps ────────────────────────────────────────────────────────
    // Static and stateless so each is testable on its own; only the state
    // machine above needs the instance.

    struct InstallError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    /// Mounts the DMG and returns its mount point.
    static func attach(_ dmg: URL) throws -> URL {
        let output = try run("/usr/bin/hdiutil",
                             ["attach", dmg.path, "-nobrowse", "-readonly", "-plist"])
        guard let plist = try? PropertyListSerialization
                .propertyList(from: output, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mountPoint = entities.compactMap({ $0["mount-point"] as? String }).first
        else { throw InstallError("could not find the DMG's mount point") }
        return URL(fileURLWithPath: mountPoint)
    }

    static func detach(_ mountPoint: URL) {
        // Best effort; a busy volume gets one forced retry. A mount left
        // behind is untidy but harmless — the install itself already copied
        // everything it needs.
        if (try? run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"])) == nil {
            _ = try? run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force", "-quiet"])
        }
    }

    /// The single `.app` at the top of the mounted volume.
    static func appBundle(in mountPoint: URL) throws -> URL {
        let contents = try FileManager.default.contentsOfDirectory(
            at: mountPoint, includingPropertiesForKeys: nil)
        guard let app = contents.first(where: { $0.pathExtension == "app" })
        else { throw InstallError("no app bundle in the DMG") }
        return app
    }

    /// Refuses to install a bundle that isn't this app. Guards against a
    /// mislabelled asset — the DMG downloaded over TLS from the release the
    /// checker matched, but carrying the wrong contents.
    static func validate(_ app: URL) throws {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist),
              let identifier = info["CFBundleIdentifier"] as? String
        else { throw InstallError("downloaded app has no readable Info.plist") }
        guard identifier == Bundle.main.bundleIdentifier else {
            throw InstallError("downloaded app is \(identifier), not this app")
        }
    }

    /// Replaces `destination` with `newApp`.
    ///
    /// Staged as copy → aside → move so the destination always holds a
    /// complete bundle: `ditto` into a hidden sibling first (same volume, so
    /// the final step is a rename, not a copy), then the old bundle steps
    /// aside, and only then does the new one take its place. If that last
    /// rename fails the old bundle is put back.
    static func swap(_ newApp: URL, into destination: URL) throws {
        let fm = FileManager.default
        let parent = destination.deletingLastPathComponent()
        let staging = parent.appendingPathComponent("." + destination.lastPathComponent + ".update")
        let aside = parent.appendingPathComponent("." + destination.lastPathComponent + ".old")

        try? fm.removeItem(at: staging)
        try? fm.removeItem(at: aside)

        // ditto preserves what a plain copy loses — permissions, symlinks,
        // and the code signature's extended attributes.
        try run("/usr/bin/ditto", [newApp.path, staging.path])

        try fm.moveItem(at: destination, to: aside)
        do {
            try fm.moveItem(at: staging, to: destination)
        } catch {
            try? fm.moveItem(at: aside, to: destination)   // roll back
            throw error
        }
        try? fm.removeItem(at: aside)
    }

    /// Starts the freshly installed bundle. `-n` forces a new instance —
    /// without it, launch services would just activate this process — and the
    /// new instance's `SingleInstance` handoff terminates this one cleanly.
    static func relaunch(_ app: URL) {
        _ = try? run("/usr/bin/open", ["-n", app.path])
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) throws -> Data {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = arguments
        let stdout = Pipe()
        task.standardOutput = stdout
        task.standardError = FileHandle.nullDevice
        try task.run()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            let name = (tool as NSString).lastPathComponent
            throw InstallError("\(name) exited with status \(task.terminationStatus)")
        }
        return output
    }
}
