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

    /// Re-evaluates whether the cooler's physical switch looks off. Driven from
    /// the tick rather than from telemetry, because *silence* is one of the
    /// tells and silence produces no callback to hang this off.
    func updateSwitchMonitor() {
        guard let profile = ble.profile, profile.hasPhysicalPowerSwitch, ble.isConnected, let lastTelemetryAt else {
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
        thermal = ThermalMonitor.read()
        if turnOffOnConnect {
            turnOffOnConnect = false
            autopilot.resetStandby(isStandby: true)
        }
        EventLogger.record("connected — syncing \(appMode.rawValue) mode to hardware")
        syncHardwareToActiveMode(force: true)

        // The cooler forgets its light state across a disconnect. Re-push it
        // again once the link has fully settled — writes sent immediately after
        // characteristic discovery can occasionally be dropped by the MCU.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, self.ble.isConnected else { return }
            self.led.reapply(dieC: self.thermal.dieTemperatureC, autopilot: self.autopilot)
        }
    }

    func bleManager(_ manager: CoolerBLEManager, didReceive telemetry: CoolerTelemetry) {
        self.telemetry = telemetry
        lastTelemetryAt = Date().timeIntervalSince1970
        refresh()
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
