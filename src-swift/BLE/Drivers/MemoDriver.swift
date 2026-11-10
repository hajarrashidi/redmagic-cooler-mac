import Foundation
import CoreBluetooth

/// Dedicated driver for the MEMO cooler family:
///  - MEMO CX07 Magnetic Cooler (30W TEC)
///  - MEMO CX08 Magnetic Cooler (36W TEC)
///
/// Service: `0000FFE0-0000-1000-8000-00805F9B34FB`
/// Write:   `0000FFE1-0000-1000-8000-00805F9B34FB` (.withoutResponse)
/// Notify:  `0000FFE2-0000-1000-8000-00805F9B34FB`
final class MemoDriver: CoolerDriver {

    let profile: DeviceProfile

    let serviceUUID = CBUUID(string: "0000FFE0-0000-1000-8000-00805F9B34FB")

    let writeCharacteristicUUID  = CBUUID(string: "0000FFE1-0000-1000-8000-00805F9B34FB")
    let notifyCharacteristicUUID = CBUUID(string: "0000FFE2-0000-1000-8000-00805F9B34FB")

    var notifyingUUIDs: Set<CBUUID> { [notifyCharacteristicUUID] }
    var writableUUIDs: Set<CBUUID> { [writeCharacteristicUUID] }

    private var characteristics: [CBUUID: CBCharacteristic] = [:]
    private var telemetryPollTimer: Timer?
    private weak var peripheral: CBPeripheral?

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
        // MEMO query state: [0xFE, 0x03, 0x00, 0xEF]
        peripheral.writeValue(Data([0xFE, 0x03, 0x00, 0xEF]), for: writeChar, type: .withoutResponse)
    }

    func apply(mode: CoolingMode, fanPercent: UInt8, peripheral: CBPeripheral) {
        guard let writeChar = characteristics[writeCharacteristicUUID] else { return }

        if mode == .off {
            // Power off: [0xFE, 0x01, 0x00, 0x00, 0xEF]
            let offCmd = Data([0xFE, 0x01, 0x00, 0x00, 0xEF])
            peripheral.writeValue(offCmd, for: writeChar, type: .withoutResponse)
        } else {
            let level: UInt8
            switch mode.zone {
            case .off:
                level = 0
            case .low:
                level = 1
            case .medium:
                level = 2
            case .max:
                level = 3 // 30W / 36W Overclock
            }

            // Power on: [0xFE, 0x01, 0x01, level, 0xEF]
            let cmd = Data([0xFE, 0x01, 0x01, level, 0xEF])
            peripheral.writeValue(cmd, for: writeChar, type: .withoutResponse)
        }
    }

    func setLight(effect: UInt8, color: RGB, peripheral: CBPeripheral) {
        guard let writeChar = characteristics[writeCharacteristicUUID] else { return }
        // Light command: [0xFE, 0x02, (effect == 0 ? 0x00 : 0x01), 0xEF]
        let lightVal: UInt8 = (effect == 0) ? 0x00 : 0x01
        let cmd = Data([0xFE, 0x02, lightVal, 0xEF])
        peripheral.writeValue(cmd, for: writeChar, type: .withoutResponse)
    }

    func handleCharacteristicUpdate(characteristic: CBCharacteristic, peripheral: CBPeripheral) -> DriverUpdate {
        guard characteristic.uuid == notifyCharacteristicUUID,
              let data = characteristic.value,
              data.count >= 4 else { return .none }

        let bytes = [UInt8](data)
        guard bytes[0] == 0xFE else { return .none }

        if bytes[1] == 0x03 && bytes.count >= 5 {
            let coldTemp = Int(Int8(bitPattern: bytes[2]))
            let telemetry = CoolerTelemetry(
                coldC: coldTemp > -30 && coldTemp < 60 ? coldTemp : 0,
                hotC: 0,
                ambientC: 0,
                fanRPM: nil
            )
            return .telemetry(telemetry)
        }

        return .none
    }

    func disconnect() {
        telemetryPollTimer?.invalidate()
        telemetryPollTimer = nil
        characteristics.removeAll()
        peripheral = nil
    }
}
