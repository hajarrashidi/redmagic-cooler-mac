import Foundation
import CoreBluetooth

/// Events signaled back by a cooler driver to the BLE manager.
enum DriverUpdate {
    case none
    case mode(CoolingMode)
    case fan(UInt8)
    case mountAttached(Bool)
    case telemetry(CoolerTelemetry)
}

/// Common protocol implemented by all brand-specific cooler drivers.
///
/// Each supported hardware family (REDMAGIC, Black Shark, Flydigi, etc.) has its
/// own driver isolating its unique GATT service UUIDs, characteristic layouts,
/// packet byte encoding, timing constraints, and telemetry polling routines.
///
/// This design guarantees that once a cooler is discovered and matched to its profile,
/// only its dedicated driver is instantiated and executed — preventing any cross-brand
/// command contamination or invalid byte writes.
protocol CoolerDriver: AnyObject {

    /// The profile associated with this driver.
    var profile: DeviceProfile { get }

    /// The primary service UUID that carries this cooler's characteristics.
    var serviceUUID: CBUUID { get }

    /// Set of characteristic UUIDs to subscribe to for notifications.
    var notifyingUUIDs: Set<CBUUID> { get }

    /// Set of characteristic UUIDs the driver writes to or reads from.
    var writableUUIDs: Set<CBUUID> { get }

    /// Called when the peripheral is connected and service discovery is initiated.
    func didConnect(peripheral: CBPeripheral)

    /// Called after GATT characteristics have been discovered.
    func didDiscoverCharacteristics(characteristics: [CBUUID: CBCharacteristic], peripheral: CBPeripheral)

    /// Applies the requested cooling mode and fan speed using the device's native command format.
    func apply(mode: CoolingMode, fanPercent: UInt8, peripheral: CBPeripheral)

    /// Sets the LED effect and color using the device's native lighting command format.
    func setLight(effect: UInt8, color: RGB, peripheral: CBPeripheral)

    /// Handles an incoming notification or read-back from a characteristic.
    func handleCharacteristicUpdate(characteristic: CBCharacteristic, peripheral: CBPeripheral) -> DriverUpdate

    /// Cleans up timers, cancels pending dispatches, and releases references upon disconnect.
    func disconnect()
}
