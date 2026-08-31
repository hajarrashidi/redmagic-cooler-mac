import Foundation

/// Developer-only protocol probe hooks. The product UI remains the sole
/// supported control surface.
extension AppDelegate {

    func handlePendingProbeCommand() {
#if REDMAGIC_PROBES
        guard let command = ProbeBridge.takePendingCommand() else { return }

        if let wantsAuto = command.autoMode {
            appMode = wantsAuto ? .auto : .manual
            UserDefaults.standard.set(appMode.rawValue, forKey: Config.Key.appMode)
            EventLogger.record("probe — control mode \(appMode.rawValue)")
        }

        if let raw = command.coolingMode {
            appMode = .manual
            UserDefaults.standard.set(AppMode.manual.rawValue, forKey: Config.Key.appMode)
            let mode = CoolingMode(rawValue: UInt8(clamping: raw))
            ble.setMode(mode)
            EventLogger.record("probe — raw cooling mode \(raw)")
        }

        if let speed = command.fanSpeed {
            let percent = UInt8(clamping: speed)
            ble.setFanPercent(percent)
            EventLogger.record("probe — fan \(percent)%")
        }

        if let effect = command.lightMode {
            let values = command.lightRGB ?? []
            let color = RGB(
                r: values.indices.contains(0) ? UInt8(clamping: values[0]) : 0,
                g: values.indices.contains(1) ? UInt8(clamping: values[1]) : 0,
                b: values.indices.contains(2) ? UInt8(clamping: values[2]) : 0)
            ble.setLight(effect: UInt8(clamping: effect), color: color)
            EventLogger.record("probe — light byte \(effect)")
        }

        refresh()
#endif
    }

    func writeProbeSnapshot() {
#if REDMAGIC_PROBES
        ProbeBridge.write(.init(
            timestamp: Date().timeIntervalSince1970,
            connected: ble.isConnected,
            cpuC: thermal.dieTemperatureC,
            coldC: telemetry?.coldC,
            hotC: telemetry?.hotC,
            ambientC: telemetry?.ambientC,
            fanRPM: telemetry?.fanRPM))
#endif
    }

    func cleanUpProbeFiles() {
#if REDMAGIC_PROBES
        ProbeBridge.cleanUp()
#endif
    }
}
