import Foundation
import CoreBluetooth

/// Dedicated driver for the REDMAGIC cooler family:
///  - REDMAGIC Magcooler 4 Pro (27W)
///  - REDMAGIC Magnetic Cooler 5 Pro (36W)
///  - REDMAGIC VC Cooler 6 Pro (36W)
///  - REDMAGIC VC Cooler 6 Pro+ (40W)
///  - REDMAGIC Cryo Cooler 8 Pro (36W)
final class RedMagicDriver: CoolerDriver {

    let profile: DeviceProfile

    let serviceUUID = CBUUID(string: "d52082ad-e805-9f97-9d4e-1c682d9c9ce6")

    // Full 128-bit CBUUIDs
    let coolingModeUUID = CBUUID(string: "00001011-0000-1000-8000-00805f9b34fb")
    let fanSpeedUUID    = CBUUID(string: "00001012-0000-1000-8000-00805f9b34fb")
    let lightModeUUID   = CBUUID(string: "00001013-0000-1000-8000-00805f9b34fb")
    let hallUUID        = CBUUID(string: "00001015-0000-1000-8000-00805f9b34fb")
    let telemetryUUID   = CBUUID(string: "00001016-0000-1000-8000-00805f9b34fb")

    // Both full and short 16-bit CBUUIDs so Set lookup always succeeds
    var notifyingUUIDs: Set<CBUUID> {
        [
            hallUUID, telemetryUUID,
            CBUUID(string: "1015"), CBUUID(string: "1016")
        ]
    }

    var writableUUIDs: Set<CBUUID> {
        [
            coolingModeUUID, fanSpeedUUID, lightModeUUID,
            CBUUID(string: "1011"), CBUUID(string: "1012"), CBUUID(string: "1013")
        ]
    }

    private var modeChar: CBCharacteristic?
    private var fanChar: CBCharacteristic?
    private var lightChar: CBCharacteristic?
    private var hallChar: CBCharacteristic?
    private var telemetryChar: CBCharacteristic?

    private var pendingFanWorkItem: DispatchWorkItem?
    private var telemetryPollTimer: Timer?
    private weak var peripheral: CBPeripheral?

    private var is5Pro: Bool {
        profile.id.contains("5pro") || profile.modelName.contains("5 Pro")
    }

    init(profile: DeviceProfile) {
        self.profile = profile
    }

    func didConnect(peripheral: CBPeripheral) {
        self.peripheral = peripheral
    }

    func didDiscoverCharacteristics(characteristics: [CBUUID: CBCharacteristic], peripheral: CBPeripheral) {
        self.peripheral = peripheral
        for (uuid, char) in characteristics {
            let str = uuid.uuidString.lowercased()
            if str.contains("1011") { modeChar = char }
            if str.contains("1012") { fanChar = char }
            if str.contains("1013") { lightChar = char }
            if str.contains("1015") { hallChar = char }
            if str.contains("1016") { telemetryChar = char }
        }

        // Seed initial values from hardware
        if let modeChar {
            peripheral.readValue(for: modeChar)
        }
        if let fanChar {
            peripheral.readValue(for: fanChar)
        }
        if let hallChar {
            peripheral.readValue(for: hallChar)
        }

        // Start periodic polling for telemetry & hall sensor (every 2s) to ensure
        // frames arrive even if firmware notification stream idles
        startPolling()
    }

    private func startPolling() {
        telemetryPollTimer?.invalidate()
        telemetryPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self, let peripheral = self.peripheral else { return }
            // Only poll telemetry if the profile officially provides a telemetry stream
            if self.profile.hasTelemetryStream, let telemetryChar = self.telemetryChar {
                peripheral.readValue(for: telemetryChar)
            }
            if let hallChar = self.hallChar {
                peripheral.readValue(for: hallChar)
            }
        }
    }

    func apply(mode: CoolingMode, fanPercent: UInt8, peripheral: CBPeripheral) {
        pendingFanWorkItem?.cancel()

        // 1. Hardware mode write
        let rawByte: UInt8
        if is5Pro {
            rawByte = (mode == .off) ? 0x03 : 0x02
        } else {
            rawByte = mode.rawValue
        }

        if let modeChar {
            EventLogger.record("REDMAGIC — writing mode 0x\(String(format: "%02X", rawByte)) to 1011")
            peripheral.writeValue(Data([rawByte]), for: modeChar, type: .withResponse)
        } else {
            EventLogger.record("REDMAGIC — apply error: modeChar is nil")
        }

        // 2. Deferred fan speed write (cooler firmware requires ~200ms spacing)
        let targetSpeed = mode.isOn ? min(fanPercent, 100) : 0
        let work = DispatchWorkItem { [weak self, weak peripheral] in
            guard let self, let peripheral, let fanChar = self.fanChar else {
                EventLogger.record("REDMAGIC — apply error: fanChar is nil")
                return
            }
            EventLogger.record("REDMAGIC — writing fan \(targetSpeed)% to 1012")
            peripheral.writeValue(Data([targetSpeed]), for: fanChar, type: .withResponse)
        }
        pendingFanWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Config.BLE.fanWriteDelay, execute: work)
    }

    func setLight(effect: UInt8, color: RGB, peripheral: CBPeripheral) {
        guard let lightChar else { return }
        let payload = [effect] + color.bytes
        peripheral.writeValue(Data(payload), for: lightChar, type: .withResponse)
    }

    func handleCharacteristicUpdate(characteristic: CBCharacteristic, peripheral: CBPeripheral) -> DriverUpdate {
        guard let data = characteristic.value, !data.isEmpty else { return .none }

        let uuidStr = characteristic.uuid.uuidString.lowercased()

        // 1. Telemetry notification (0x1016)
        if uuidStr.contains("1016") {
            // Ignore unpopulated / all-zero dummy BLE frames
            guard data.count >= 8, !data.allSatisfy({ $0 == 0 }) else {
                return .none
            }

            // Valid telemetry frames must begin with 0xAA
            guard data[0] == 0xAA else {
                return .none
            }

            let hexStr = data.map { String(format: "%02X", $0) }.joined(separator: " ")
            EventLogger.record("REDMAGIC — telemetry raw [\(data.count)B]: \(hexStr)")

            let coldC = Int(data[2])
            let hotC = Int(data[3])
            let ambientC = Int(data[7])
            let rpm = data.count >= 15 ? Int(data[13]) | (Int(data[14]) << 8) : nil

            let telemetry = CoolerTelemetry(
                coldC: coldC,
                hotC: hotC,
                ambientC: ambientC,
                fanRPM: rpm
            )
            return .telemetry(telemetry)
        }

        // 2. Cooling Mode readback (0x1011)
        if uuidStr.contains("1011") {
            let raw = data[0]
            if raw == 0x03 {
                return .mode(.off)
            } else if raw == 0x02 && is5Pro {
                return .mode(.medium)
            } else {
                return .mode(CoolingMode(rawValue: raw))
            }
        }

        // 3. Fan speed readback (0x1012)
        if uuidStr.contains("1012") {
            return .fan(data[0])
        }

        // 4. Hall sensor notification (0x1015)
        if uuidStr.contains("1015") {
            let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
            EventLogger.record("REDMAGIC — hall sensor raw: \(hex)")
            // On Cooler 5 Pro, 0x05 indicates normal active operation; bringing a magnet triggers 0x04 / cutoff
            let attached = is5Pro ? (data[0] == 0x05) : (data[0] == 0x04)
            return .mountAttached(attached)
        }

        return .none
    }

    func disconnect() {
        telemetryPollTimer?.invalidate()
        telemetryPollTimer = nil
        pendingFanWorkItem?.cancel()
        pendingFanWorkItem = nil
        modeChar = nil
        fanChar = nil
        lightChar = nil
        hallChar = nil
        telemetryChar = nil
        peripheral = nil
    }
}
