import Foundation
import CoreBluetooth

/// Dedicated driver for the iQOO cooler family:
///  - iQOO Cooling Back Clip 2 Pro (27W TEC, peak 30W)
///
/// Service: `0000FFF0-0000-1000-8000-00805F9B34FB`
/// Write:   `0000FFF1-0000-1000-8000-00805F9B34FB` (.withoutResponse)
/// Notify:  `0000FFF2-0000-1000-8000-00805F9B34FB`
final class IQOODriver: CoolerDriver {

    let profile: DeviceProfile

    let serviceUUID = CBUUID(string: "0000FFF0-0000-1000-8000-00805F9B34FB")

    let writeCharacteristicUUID  = CBUUID(string: "0000FFF1-0000-1000-8000-00805F9B34FB")
    let notifyCharacteristicUUID = CBUUID(string: "0000FFF2-0000-1000-8000-00805F9B34FB")

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
        // iQOO status query frame: [0xAA, 0x03, 0x00, 0x55]
        peripheral.writeValue(Data([0xAA, 0x03, 0x00, 0x55]), for: writeChar, type: .withoutResponse)
    }

    func apply(mode: CoolingMode, fanPercent: UInt8, peripheral: CBPeripheral) {
        guard let writeChar = characteristics[writeCharacteristicUUID] else { return }
        let targetSpeed: UInt8 = mode.isOn ? min(fanPercent, 100) : 0
        guard mode != lastAppliedMode || targetSpeed != lastAppliedFan else { return }
        lastAppliedMode = mode
        lastAppliedFan = targetSpeed

        if mode == .off {
            // Power off: [0xAA, 0x01, 0x00, 0x00, 0x55]
            let offCmd = Data([0xAA, 0x01, 0x00, 0x00, 0x55])
            peripheral.writeValue(offCmd, for: writeChar, type: .withoutResponse)
        } else {
            let level: UInt8
            switch mode.zone {
            case .off:
                level = 0
            case .low:
                level = 1 // Silent (quiet cooling)
            case .medium:
                level = 2 // Balanced
            case .max:
                level = 3 // Max 27W Overclock power
            }

            // Power on at level: [0xAA, 0x01, 0x01, level, 0x55]
            let cmd = Data([0xAA, 0x01, 0x01, level, 0x55])
            peripheral.writeValue(cmd, for: writeChar, type: .withoutResponse)
        }
    }

    func setLight(effect: UInt8, color: RGB, peripheral: CBPeripheral) {
        guard let writeChar = characteristics[writeCharacteristicUUID] else { return }
        // Light frame: [0xAA, 0x02, (effect == 0 ? 0x00 : 0x01), effect, 0x55]
        let lightState: UInt8 = (effect == 0) ? 0x00 : 0x01
        let cmd = Data([0xAA, 0x02, lightState, effect, 0x55])
        peripheral.writeValue(cmd, for: writeChar, type: .withoutResponse)
    }

    func handleCharacteristicUpdate(characteristic: CBCharacteristic, peripheral: CBPeripheral) -> DriverUpdate {
        guard characteristic.uuid == notifyCharacteristicUUID,
              let data = characteristic.value,
              data.count >= 4 else { return .none }

        let bytes = [UInt8](data)
        // Frame format: [0xAA, type, ...]
        guard bytes[0] == 0xAA else { return .none }

        if bytes[1] == 0x03 && bytes.count >= 6 {
            // Telemetry: byte 2 = cold plate temp, byte 3..4 = RPM
            let coldTemp = Int(Int8(bitPattern: bytes[2]))
            let rpm = (Int(bytes[3]) << 8) | Int(bytes[4])
            let telemetry = CoolerTelemetry(
                coldC: coldTemp > -30 && coldTemp < 60 ? coldTemp : 0,
                hotC: 0,
                ambientC: 0,
                fanRPM: rpm > 0 && rpm < 15000 ? rpm : nil
            )
            return .telemetry(telemetry)
        }

        return .none
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
