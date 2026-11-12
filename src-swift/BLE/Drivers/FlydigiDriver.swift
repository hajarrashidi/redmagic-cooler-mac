import Foundation
import CoreBluetooth

/// Dedicated driver for the Flydigi cooler family:
///  - Flydigi B8X (30W Overclock TEC)
///  - Flydigi B7X (27W TEC)
///
/// Implements the reverse-engineered protocol from ha-flydigi-b8x:
/// Service: `0000FFE0-0000-1000-8000-00805F9B34FB`
/// Write:   `0000FFE1-0000-1000-8000-00805F9B34FB` (.withoutResponse)
/// Notify:  `0000FFE4-0000-1000-8000-00805F9B34FB`
final class FlydigiDriver: CoolerDriver {

    let profile: DeviceProfile

    let serviceUUID = CBUUID(string: "0000FFE0-0000-1000-8000-00805F9B34FB")

    let writeCharacteristicUUID  = CBUUID(string: "0000FFE1-0000-1000-8000-00805F9B34FB")
    let notifyCharacteristicUUID = CBUUID(string: "0000FFE4-0000-1000-8000-00805F9B34FB")

    var notifyingUUIDs: Set<CBUUID> { [notifyCharacteristicUUID] }
    var writableUUIDs: Set<CBUUID> { [writeCharacteristicUUID] }

    private var characteristics: [CBUUID: CBCharacteristic] = [:]
    private var telemetryPollTimer: Timer?
    private weak var peripheral: CBPeripheral?
    private var lastAppliedMode: CoolingMode?
    private var lastAppliedFan: UInt8?

    init(profile: DeviceProfile) {
        self.profile = profile
    }

    func didConnect(peripheral: CBPeripheral) {
        self.peripheral = peripheral
    }

    func didDiscoverCharacteristics(characteristics: [CBUUID: CBCharacteristic], peripheral: CBPeripheral) {
        self.characteristics = characteristics
        self.peripheral = peripheral

        startTelemetryPolling()
    }

    private func startTelemetryPolling() {
        telemetryPollTimer?.invalidate()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pollTelemetry()
        }
        RunLoop.main.add(timer, forMode: .common)
        telemetryPollTimer = timer
        pollTelemetry()
    }

    private func pollTelemetry() {
        guard let peripheral, let writeChar = characteristics[writeCharacteristicUUID] else { return }
        // Flydigi status query byte is 0x13
        peripheral.writeValue(Data([0x13]), for: writeChar, type: .withoutResponse)
    }

    func apply(mode: CoolingMode, fanPercent: UInt8, peripheral: CBPeripheral) {
        guard let writeChar = characteristics[writeCharacteristicUUID] else { return }
        let targetSpeed: UInt8 = mode.isOn ? min(fanPercent, 100) : 0
        guard mode != lastAppliedMode || targetSpeed != lastAppliedFan else { return }
        lastAppliedMode = mode
        lastAppliedFan = targetSpeed

        if mode == .off {
            let offCmd = Data([0x20, 0x00, 0x00, 0x00, 0x00])
            peripheral.writeValue(offCmd, for: writeChar, type: .withoutResponse)
        } else {
            let level: UInt8
            switch mode.zone {
            case .off:
                level = 0
            case .low:
                level = (fanPercent > 50) ? 2 : 1
            case .medium:
                level = (fanPercent > 60) ? 4 : 3
            case .max:
                level = 5 // Maximum 30W Overclock mode!
            }

            // Command 0x20: [0x20, mode (0x01 = manual), level (1-5), wind_hi, wind_lo]
            let cmd = Data([0x20, 0x01, level, 0x00, 0x00])
            peripheral.writeValue(cmd, for: writeChar, type: .withoutResponse)
        }
    }

    func setLight(effect: UInt8, color: RGB, peripheral: CBPeripheral) {
        guard let writeChar = characteristics[writeCharacteristicUUID] else { return }
        // Light command: [0x10, 0xFF for on, 0x00 for off]
        let lightByte: UInt8 = (effect == 0) ? 0x00 : 0xFF
        peripheral.writeValue(Data([0x10, lightByte]), for: writeChar, type: .withoutResponse)
    }

    func handleCharacteristicUpdate(characteristic: CBCharacteristic, peripheral: CBPeripheral) -> DriverUpdate {
        guard characteristic.uuid == notifyCharacteristicUUID,
              let data = characteristic.value,
              data.count >= 14 else { return .none }

        let bytes = [UInt8](data)

        // Telemetry frame (20 bytes):
        // byte 7 (signed Int8) + signed fractional byte 8/10.0: cold side temperature
        // byte 9 (signed Int8): hot side temperature
        // bytes 12..13: fan RPM (b[12]*100 + b[13])
        let coldWhole = Int(Int8(bitPattern: bytes[7]))
        let fracMag = Double(min(bytes[8], 9)) / 10.0
        let coldDouble = coldWhole < 0 ? (Double(coldWhole) - fracMag) : (Double(coldWhole) + fracMag)
        let coldC = Int(round(coldDouble))
        let hotC = Int(Int8(bitPattern: bytes[9]))
        let fanRPM = Int(bytes[12]) * 100 + Int(bytes[13])

        let telemetry = CoolerTelemetry(
            coldC: coldC,
            hotC: hotC,
            ambientC: 0,
            fanRPM: fanRPM
        )
        return .telemetry(telemetry)
    }

    func disconnect() {
        telemetryPollTimer?.invalidate()
        telemetryPollTimer = nil
        lastAppliedMode = nil
        lastAppliedFan = nil
        characteristics.removeAll()
        peripheral = nil
    }
}
