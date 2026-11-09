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

    let coolingModeUUID = CBUUID(string: "00001011-0000-1000-8000-00805f9b34fb")
    let fanSpeedUUID    = CBUUID(string: "00001012-0000-1000-8000-00805f9b34fb")
    let lightModeUUID   = CBUUID(string: "00001013-0000-1000-8000-00805f9b34fb")
    let hallUUID        = CBUUID(string: "00001015-0000-1000-8000-00805f9b34fb")
    let telemetryUUID   = CBUUID(string: "00001016-0000-1000-8000-00805f9b34fb")

    var notifyingUUIDs: Set<CBUUID> { [hallUUID, telemetryUUID] }
    var writableUUIDs: Set<CBUUID> { [coolingModeUUID, fanSpeedUUID, lightModeUUID] }

    private var characteristics: [CBUUID: CBCharacteristic] = [:]
    private var pendingFanWorkItem: DispatchWorkItem?

    private var is5Pro: Bool {
        profile.id.contains("5pro") || profile.modelName.contains("5 Pro")
    }

    init(profile: DeviceProfile) {
        self.profile = profile
    }

    func didConnect(peripheral: CBPeripheral) {
        // REDMAGIC peripherals stream telemetry autonomously once subscribed; no polling required.
    }

    func didDiscoverCharacteristics(characteristics: [CBUUID: CBCharacteristic], peripheral: CBPeripheral) {
        self.characteristics = characteristics

        // Seed caches from hardware
        if let modeChar = characteristics[coolingModeUUID] {
            peripheral.readValue(for: modeChar)
        }
        if let fanChar = characteristics[fanSpeedUUID] {
            peripheral.readValue(for: fanChar)
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

        if let modeChar = characteristics[coolingModeUUID] {
            peripheral.writeValue(Data([rawByte]), for: modeChar, type: .withResponse)
        }

        // 2. Deferred fan speed write
        let targetSpeed = mode.isOn ? min(fanPercent, 100) : 0
        let work = DispatchWorkItem { [weak self, weak peripheral] in
            guard let self, let peripheral, let fanChar = self.characteristics[self.fanSpeedUUID] else { return }
            peripheral.writeValue(Data([targetSpeed]), for: fanChar, type: .withResponse)
        }
        pendingFanWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Config.BLE.fanWriteDelay, execute: work)
    }

    func setLight(effect: UInt8, color: RGB, peripheral: CBPeripheral) {
        guard let lightChar = characteristics[lightModeUUID] else { return }
        let payload = [effect] + color.bytes
        peripheral.writeValue(Data(payload), for: lightChar, type: .withResponse)
    }

    func handleCharacteristicUpdate(characteristic: CBCharacteristic, peripheral: CBPeripheral) -> DriverUpdate {
        guard let data = characteristic.value, !data.isEmpty else { return .none }

        switch characteristic.uuid {
        case coolingModeUUID:
            let raw = data[0]
            if raw == 0x03 {
                return .mode(.off)
            } else if raw == 0x02 && is5Pro {
                return .mode(.medium)
            } else {
                return .mode(CoolingMode(rawValue: raw))
            }

        case fanSpeedUUID:
            return .fan(data[0])

        case hallUUID:
            let attached = !data.isEmpty && data[0] == 4
            return .mountAttached(attached)

        case telemetryUUID:
            guard data.count >= 8, data[0] == 0xAA else { return .none }
            let rpm = data.count >= 15 ? Int(data[13]) | (Int(data[14]) << 8) : nil
            let telemetry = CoolerTelemetry(
                coldC: Int(data[2]),
                hotC: Int(data[3]),
                ambientC: Int(data[7]),
                fanRPM: rpm
            )
            return .telemetry(telemetry)

        default:
            return .none
        }
    }

    func disconnect() {
        pendingFanWorkItem?.cancel()
        pendingFanWorkItem = nil
        characteristics.removeAll()
    }
}
