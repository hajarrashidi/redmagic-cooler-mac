import AppKit

/// Device callbacks and the CLI command channel.
extension AppDelegate: CoolerBLEManagerDelegate {

    func bleManager(_ manager: CoolerBLEManager,
                    needsDeviceSelection devices: [CoolerBLEManager.DiscoveredDevice]) {
        if devicePicker == nil { showDevicePicker() }
        devicePicker?.updateDevices(devices)
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
        writeStatusSnapshot()
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
        writeStatusSnapshot()
    }

    func bleManager(_ manager: CoolerBLEManager, didChangeMountAttached attached: Bool) {
        mountAttached = attached
        refresh()
        writeStatusSnapshot()
    }

    func bleManagerDidChangeSettings(_ manager: CoolerBLEManager) {
        refresh()
        writeStatusSnapshot()
    }

    // ── CLI commands ─────────────────────────────────────────────────────────

    /// Applies a command dropped by the `cooler` CLI, if one is waiting.
    ///
    /// Fields are independent and applied in order, so a single drop can, say,
    /// switch to manual and set a fan speed at once.
    func handlePendingCommand() {
        guard let command = IPCBridge.takePendingCommand() else { return }

        if let wantsAuto = command.autoMode {
            let mode: AppMode = wantsAuto ? .auto : .manual
            appMode = mode
            UserDefaults.standard.set(mode.rawValue, forKey: Config.Key.appMode)
            EventLogger.record("\(mode.rawValue) (via CLI)")
        }

        if let raw = command.autoProfile {
            let profile = AutoProfile(persisted: raw)
            autopilot.setProfile(profile)
            UserDefaults.standard.set(profile.rawValue, forKey: Config.Key.autoProfile)
            EventLogger.record("auto profile → \(profile.rawValue) (via CLI)")
        }

        if let raw = command.coolingMode {
            // An explicit mode implies manual: the autopilot would otherwise
            // overwrite it on its next evaluation.
            appMode = .manual
            UserDefaults.standard.set(AppMode.manual.rawValue, forKey: Config.Key.appMode)
            let mode = CoolingMode(rawValue: UInt8(clamping: raw))
            ble.setMode(mode)
            EventLogger.record("manual mode \(mode.displayName) (via CLI)")
        }

        if let speed = command.fanSpeed {
            let percent = UInt8(clamping: speed)
            ble.setFanPercent(percent)
            UserDefaults.standard.set(Int(percent), forKey: Config.Key.manualFanSpeed)
            EventLogger.record("manual fan \(percent)% (via CLI)")
        }

        // Raw light writes, used by the probe scripts to map undocumented
        // effects — deliberately not routed through LedController, which only
        // models the effects the UI exposes.
        if let effect = command.lightMode {
            let rgb = command.lightRGB ?? []
            let color = RGB(r: rgb.count > 0 ? UInt8(clamping: rgb[0]) : 0,
                            g: rgb.count > 1 ? UInt8(clamping: rgb[1]) : 0,
                            b: rgb.count > 2 ? UInt8(clamping: rgb[2]) : 0)
            ble.setLight(effect: UInt8(clamping: effect), color: color)
            EventLogger.record("light probe → [\(effect), \(color.r), \(color.g), \(color.b)] (via CLI)")
        }

        if let threshold = command.tempThreshold {
            ble.setTempThreshold(UInt8(clamping: threshold))
        }
        if let enabled = command.deviceAutoTemp {
            ble.setDeviceAutoTemp(enabled)
        }

        refresh()
        writeStatusSnapshot()
    }
}
