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
            onConnected()
        } else {
            // Stale telemetry is worse than none — it would keep showing the
            // last reading as though the cooler were still reporting.
            telemetry = nil
            mountAttached = nil
        }
        refresh()
        writeProbeSnapshot()
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
