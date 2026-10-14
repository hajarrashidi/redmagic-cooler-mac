import AppKit

/// Device callbacks from the active cooler connection.
extension AppDelegate: CoolerBLEManagerDelegate {

    func bleManager(_ manager: CoolerBLEManager,
                    needsDeviceSelection devices: [CoolerBLEManager.DiscoveredDevice]) {
        isSelectingDevice = true
        devicePicker.updateDevices(devices)
        refresh()
    }

    func bleManager(_ manager: CoolerBLEManager, didChangePhase phase: ConnectionPhase) {
        refresh()
    }

    func bleManager(_ manager: CoolerBLEManager, didChangeConnected isConnected: Bool) {
        if isConnected {
            // Seed the telemetry clock at connect, so a device that never sends
            // a frame still registers as silent rather than as "no data yet".
            lastTelemetryAt = Date().timeIntervalSince1970
            // The curve has one point per stage of the cooler it was made for.
            syncCustomCurve()
            onConnected()
        } else {
            // Stale telemetry is worse than none — it would keep showing the
            // last reading as though the cooler were still reporting.
            telemetry = nil
            mountAttached = nil
            lastTelemetryAt = nil
            switchMonitor.reset()
        }
        refresh()
        writeProbeSnapshot()
    }

    /// Holds cooling back while the cold plate is under the user's limit, and lets
    /// it go again once the plate has recovered. See `PlateGuard`.
    ///
    /// Cooling counts as wanted whenever the app has asked for it and the cooler's
    /// own switch isn't off; that stays true while the guard itself has switched
    /// the cooler off, so the plate gets the time to warm up and the guard to
    /// release, rather than the cooler restarting at once.
    func updatePlateGuard() {
        let now = Date().timeIntervalSince1970
        let steps = activeProfile.manualSteps
        let fresh = ble.isConnected && lastTelemetryAt.map { now - $0 < 5 } == true
        // 0 is how some coolers say "not measured", and a reading outside the
        // plausible range (a 6 Pro plate below zero reads as a big unsigned byte)
        // is not believed either; the guard then keeps what it has.
        let plate = fresh ? telemetry.map { Double($0.coldC) } : nil
        let believed = plate.flatMap { $0 != 0 && Config.PlateLimit.plausibleC.contains($0) ? $0 : nil }

        let levels = plateGuard.update(
            plateC: believed,
            isCooling: ble.isConnected && ble.requested.mode.isOn && !switchMonitor.looksPoweredOff,
            floorC: plateLimitOn ? plateLimitC : nil,
            maxLevels: max(steps.count - 1, 0),
            now: now)
        guard levels != ble.heldBack else { return }

        if levels > ble.heldBack, let plate = believed {
            EventLogger.record("cold plate \(Int(plate))°C is under the \(Int(plateLimitC))°C limit → holding cooling back \(levels) level(s)")
        } else if levels < ble.heldBack {
            EventLogger.record("cold plate recovered → holding cooling back \(levels) level(s)")
        }
        ble.setHeldBack(levels)
        refresh()
    }

    /// Re-evaluates whether the cooler's physical switch looks off. Driven from
    /// the tick rather than from telemetry, because *silence* is one of the
    /// tells and silence produces no callback to hang this off.
    func updateSwitchMonitor() {
        guard ble.isConnected, let lastTelemetryAt else {
            switchMonitor.reset()
            return
        }
        let now = Date().timeIntervalSince1970
        switchMonitor.update(isCommandedOn: ble.mode.isOn,
                             fanRPM: telemetry?.fanRPM,
                             secondsSinceLastFrame: now - lastTelemetryAt,
                             now: now)
    }

    private func onConnected() {
        // When the user explicitly asked to connect, command the cooler off
        // once so it never resumes a stale running state on link-up.
        //
        // Only the hardware is touched here — not `appMode`, and not the saved
        // manual level — so switching to Manual still restores what the user
        // had chosen, and Auto still engages on its own once the Mac heats up.
        if turnOffOnConnect {
            turnOffOnConnect = false
            ble.apply(mode: .off, fanPercent: 0)
            EventLogger.record("forced cooler off on connect (preference preserved)")
        }

        // The cooler forgets its light state across a disconnect. Re-push it,
        // but only once the link has settled — writes sent immediately after
        // characteristic discovery are unreliable.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.led.reapply()
        }
    }

    func bleManager(_ manager: CoolerBLEManager, didReceive telemetry: CoolerTelemetry) {
        self.telemetry = telemetry
        lastTelemetryAt = Date().timeIntervalSince1970
        // Also here, not only on the 1 s tick: the tick does not run while a menu
        // is open, and a limit that protects the plate must not depend on whether
        // anyone is looking at the menu.
        updatePlateGuard()
        // At most once a second: the cooler can report several times a second,
        // and redrawing the menu that often fights whatever the user is doing in it.
        if lastTelemetryAt.map({ $0 - lastTelemetryRefresh >= 1 }) ?? true {
            lastTelemetryRefresh = lastTelemetryAt ?? 0
            refresh()
        }
        writeProbeSnapshot()
    }

    func bleManager(_ manager: CoolerBLEManager, didChangeMountAttached attached: Bool) {
        mountAttached = attached
        refresh()
        writeProbeSnapshot()
    }

    func bleManagerDidChangeSettings(_ manager: CoolerBLEManager) {
        refresh()
        writeProbeSnapshot()
    }
}
