import AppKit

/// Ensures only one copy of the app owns the Bluetooth link.
///
/// The cooler accepts a single connection, and a second menu-bar instance —
/// easy to end up with when rebuilding and relaunching — holds that slot so the
/// new one can never acquire it. Launch therefore terminates any prior instance
/// *and waits for it to actually exit*, because the slot isn't freed until the
/// old process runs its own clean disconnect on the way out.
enum SingleInstance {

    /// Terminates other instances and blocks until they exit (or the timeout
    /// elapses). Call before starting a scan.
    static func terminateOthersAndWait() {
        let myPID = ProcessInfo.processInfo.processIdentifier

        // Matches .app launches.
        let running: [NSRunningApplication] = Bundle.main.bundleIdentifier.map {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0)
                .filter { $0.processIdentifier != myPID }
        } ?? []

        guard !running.isEmpty else { return }

        for app in running {
            EventLogger.record("terminating prior instance (pid \(app.processIdentifier))")
            // Graceful: runs its applicationShouldTerminate, which disconnects.
            app.terminate()
        }
        waitForExit(running: running)
    }

    /// Spins the run loop until the old instances are gone. Capped so a process
    /// that refuses to die delays launch rather than hanging it.
    ///
    /// The run loop must keep turning here: `NSRunningApplication.isTerminated`
    /// is updated by a notification that a plain `sleep` would never let arrive.
    private static func waitForExit(running: [NSRunningApplication]) {
        let deadline = Date(timeIntervalSinceNow: Config.Timing.instanceHandoffTimeout)
        while Date() < deadline {
            if !running.contains(where: { !$0.isTerminated }) { return }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        EventLogger.record("prior instance did not exit within timeout — continuing anyway")
    }
}
