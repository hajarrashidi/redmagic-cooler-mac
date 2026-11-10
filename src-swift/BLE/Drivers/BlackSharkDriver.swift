import Foundation
import CoreBluetooth

/// Dedicated driver for the Black Shark cooler family:
///  - Black Shark MagCooler 4 Pro (27W TEC)
///  - Black Shark MagCooler 5 Pro (35W TEC)
///
/// Implements the reverse-engineered protocol from BlackSharkLib / Moblin:
/// Service: `0000A0A0-3C17-D293-8E48-14FE2E4DA212`
/// Write:   `0000A001-3C17-D293-8E48-14FE2E4DA212` (.withoutResponse)
/// Read:    `0000A002-3C17-D293-8E48-14FE2E4DA212`
final class BlackSharkDriver: CoolerDriver {

    let profile: DeviceProfile

    let serviceUUID = CBUUID(string: "0000A0A0-3C17-D293-8E48-14FE2E4DA212")

    let writeCharacteristicUUID = CBUUID(string: "0000A001-3C17-D293-8E48-14FE2E4DA212")
    let readCharacteristicUUID  = CBUUID(string: "0000A002-3C17-D293-8E48-14FE2E4DA212")

    var notifyingUUIDs: Set<CBUUID> { [readCharacteristicUUID] }
    var writableUUIDs: Set<CBUUID> { [writeCharacteristicUUID] }

    private var characteristics: [CBUUID: CBCharacteristic] = [:]
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
        self.characteristics = characteristics
        self.peripheral = peripheral

        // Start active telemetry polling timer (every 2.0s)
        startTelemetryPolling()
    }

    private func startTelemetryPolling() {
        telemetryPollTimer?.invalidate()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pollTelemetry()
        }
        RunLoop.main.add(timer, forMode: .common)
        telemetryPollTimer = timer
        // Immediate first poll
        pollTelemetry()
    }

    private func pollTelemetry() {
        guard let peripheral, let writeChar = characteristics[writeCharacteristicUUID] else { return }
        let pollPayload: [UInt8]
        if is5Pro {
            // MagCooler 5 Pro query: [0x05, 0x06, 0x20, 0x00, 0x00]
            pollPayload = [0x05, 0x06, 0x20, 0x00, 0x00]
        } else {
            // MagCooler 4 Pro query: [0x05, 0x06, 0x00, 0x00, 0x00]
            pollPayload = [0x05, 0x06, 0x00, 0x00, 0x00]
        }
        peripheral.writeValue(Data(pollPayload), for: writeChar, type: .withoutResponse)
    }

    func apply(mode: CoolingMode, fanPercent: UInt8, peripheral: CBPeripheral) {
        guard let writeChar = characteristics[writeCharacteristicUUID] else { return }

        if is5Pro {
            // Black Shark MagCooler 5 Pro (35W):
            // Has 5 custom intensity steps:
            // 1: 19W (3360 RPM), 2: 22W (4000 RPM), 3: 26W (4770 RPM), 4: 30W (4950 RPM), 5: 35W (5100 RPM)
            // Desk mode: [0x05, 0x07, 0x00, 0x00, 0x01] = cooling off, fan idle
            if mode == .off {
                let deskModeOff = Data([0x05, 0x07, 0x00, 0x00, 0x01])
                peripheral.writeValue(deskModeOff, for: writeChar, type: .withoutResponse)
            } else {
                // Ensure cooling enabled (desk mode off)
                let deskModeOn = Data([0x05, 0x07, 0x00, 0x00, 0x00])
                peripheral.writeValue(deskModeOn, for: writeChar, type: .withoutResponse)

                // Map mode/fan to intensity 1..5
                let intensity: UInt8
                switch mode.zone {
                case .off:
                    intensity = 1
                case .low:
                    intensity = (fanPercent > 50) ? 2 : 1
                case .medium:
                    intensity = (fanPercent > 60) ? 4 : 3
                case .max:
                    intensity = 5 // Maximum 35W cooling power!
                }

                let customModeCommand = Data([0x06, 0x05, 0x00, 0x00, 0x04, intensity])
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    peripheral.writeValue(customModeCommand, for: writeChar, type: .withoutResponse)
                }
            }
        } else {
            // Black Shark MagCooler 4 Pro (27W):
            // Independent Peltier power and fan speed (0-100 inverted, 0 = 0xFB)
            let fanVal: UInt8 = (fanPercent == 0 || !mode.isOn) ? 0xFB : UInt8(100 - min(fanPercent, 100))
            let coolVal: UInt8
            if mode == .off {
                coolVal = 0xFB
            } else {
                switch mode.zone {
                case .off:    coolVal = 0xFB
                case .low:    coolVal = 0x4B // ~25%
                case .medium: coolVal = 0x28 // ~60%
                case .max:    coolVal = 0x00 // 100% full Peltier
                }
            }

            let fanCmd = Data([0x05, 0x02, 0x00, 0x00, fanVal])
            let coolCmd = Data([0x05, 0x05, 0x00, 0x00, coolVal])

            peripheral.writeValue(coolCmd, for: writeChar, type: .withoutResponse)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                peripheral.writeValue(fanCmd, for: writeChar, type: .withoutResponse)
            }
        }
    }

    func setLight(effect: UInt8, color: RGB, peripheral: CBPeripheral) {
        guard let writeChar = characteristics[writeCharacteristicUUID] else { return }

        let r = (effect == 0) ? 0 : color.r
        let g = (effect == 0) ? 0 : color.g
        let b = (effect == 0) ? 0 : color.b

        if is5Pro {
            // 16-byte frame for 5 Pro
            let payload = Data([
                0x10, 0x01, 0x10, 0x00,
                0x00, 0x09, 0xff, 0x00,
                0x64, // Brightness constant (100)
                0x01,
                r, g, b,
                0x00, 0x00, 0x00
            ])
            peripheral.writeValue(payload, for: writeChar, type: .withoutResponse)
        } else {
            // 47-byte frame for 4 Pro
            var bytes = [UInt8](repeating: 0, count: 47)
            bytes[0] = 0x2f
            bytes[1] = 0x01
            bytes[2] = 0x20
            bytes[4] = (effect == 0) ? 0x01 : 0x06 // Mode: 0x01 off, 0x06 steady color
            bytes[6] = 0xff
            bytes[7] = 0xff
            bytes[8] = 0xff
            bytes[10] = 0x01
            bytes[11] = r
            bytes[12] = g
            bytes[13] = b
            peripheral.writeValue(Data(bytes), for: writeChar, type: .withoutResponse)
        }
    }

    func handleCharacteristicUpdate(characteristic: CBCharacteristic, peripheral: CBPeripheral) -> DriverUpdate {
        guard characteristic.uuid == readCharacteristicUUID,
              let data = characteristic.value,
              data.count > 2 else { return .none }

        let bytes = [UInt8](data)

        // 1. MagCooler 5 Pro Telemetry frame (89 06)
        // 89 06 20 00 <cold> <hot> <rpm-lo> <rpm-hi> <power>
        if is5Pro && bytes[0] == 0x89 && bytes[1] == 0x06 {
            guard bytes.count > 8 else { return .none }
            let coldC = Int(Int8(bitPattern: bytes[4]))
            let hotC = Int(Int8(bitPattern: bytes[5]))
            let fanRPM = Int(bytes[6]) | (Int(bytes[7]) << 8)

            let telemetry = CoolerTelemetry(
                coldC: coldC,
                hotC: hotC,
                ambientC: 0,
                fanRPM: fanRPM
            )
            return .telemetry(telemetry)
        }

        // 2. MagCooler 4 Pro Telemetry frame (06 00)
        if !is5Pro && bytes[1] == 0x06 && bytes[2] == 0x00 {
            guard bytes.count > 7 else { return .none }
            let coldC = Int(Int8(bitPattern: bytes[5]))
            let hotC = Int(Int8(bitPattern: bytes[7]))

            let telemetry = CoolerTelemetry(
                coldC: coldC,
                hotC: hotC,
                ambientC: 0,
                fanRPM: nil
            )
            return .telemetry(telemetry)
        }

        // 3. Fan status report (02 10)
        if bytes[1] == 0x02 && bytes[2] == 0x10, bytes.count > 4 {
            let speed = max(0, min(100, 100 - Int(bytes[4])))
            return .fan(UInt8(speed))
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
