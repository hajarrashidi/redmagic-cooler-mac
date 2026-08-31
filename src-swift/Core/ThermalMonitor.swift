import Foundation
import IOKit

/// Reads Apple-silicon die temperature and macOS thermal pressure.
///
/// There is no public API for die temperature, so this binds the private
/// `IOHIDEventSystemClient` symbols out of IOKit at runtime and averages the
/// `PMU tdie*` sensors. The binding is resolved once and cached — the previous
/// implementation ran `dlopen`, six `dlsym` lookups and `dlclose` on every
/// sample, which for a 1 Hz poll is pure overhead. If the symbols ever go away
/// (a future macOS could rename them), `read()` degrades to reporting thermal
/// pressure with a `nil` temperature rather than failing.
enum ThermalMonitor {

    /// `kIOHIDEventTypeTemperature`.
    private static let temperatureEventType: Int64 = 15

    /// HID usage page/usage that selects the SoC's thermal sensors.
    private static let sensorMatch =
        ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary

    /// Plausibility window for a die reading, in °C. Sensors occasionally
    /// return 0 or a garbage spike; those samples are dropped.
    private static let plausibleRange: ClosedRange<Double> = 1...130

    // ── Private IOKit binding ────────────────────────────────────────────────

    private typealias CreateFn = @convention(c) (CFAllocator?, UInt32) -> Unmanaged<AnyObject>?
    private typealias MatchFn  = @convention(c) (AnyObject, CFDictionary) -> Void
    private typealias ServicesFn = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyEventFn = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias FloatValueFn = @convention(c) (AnyObject, Int64) -> Double
    private typealias CopyPropertyFn = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?

    private struct HIDSymbols {
        let create: CreateFn
        let setMatching: MatchFn
        let copyServices: ServicesFn
        let copyEvent: CopyEventFn
        let floatValue: FloatValueFn
        let copyProperty: CopyPropertyFn
    }

    /// Resolved once on first use. `nil` when the private symbols are missing,
    /// which permanently disables die-temperature reporting for this run.
    ///
    /// The handle is deliberately never `dlclose`d: the function pointers below
    /// stay live for the process lifetime.
    private static let symbols: HIDSymbols? = {
        guard let lib = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) else {
            return nil
        }
        func sym(_ name: String) -> UnsafeMutableRawPointer? { dlsym(lib, name) }

        guard let create = sym("IOHIDEventSystemClientCreate"),
              let match = sym("IOHIDEventSystemClientSetMatching"),
              let services = sym("IOHIDEventSystemClientCopyServices"),
              let event = sym("IOHIDServiceClientCopyEvent"),
              let fval = sym("IOHIDEventGetFloatValue"),
              let prop = sym("IOHIDServiceClientCopyProperty") else {
            EventLogger.record("thermal — private IOKit symbols unavailable; die temperature disabled")
            return nil
        }
        return HIDSymbols(
            create: unsafeBitCast(create, to: CreateFn.self),
            setMatching: unsafeBitCast(match, to: MatchFn.self),
            copyServices: unsafeBitCast(services, to: ServicesFn.self),
            copyEvent: unsafeBitCast(event, to: CopyEventFn.self),
            floatValue: unsafeBitCast(fval, to: FloatValueFn.self),
            copyProperty: unsafeBitCast(prop, to: CopyPropertyFn.self)
        )
    }()

    // ── Public API ───────────────────────────────────────────────────────────

    struct Reading {
        /// macOS's own thermal pressure level — always available.
        let thermalState: ThermalState
        /// Mean die temperature in °C, or `nil` if no sensor could be read.
        let dieTemperatureC: Double?
    }

    /// Samples both signals. Cheap enough to call at the 1 Hz poll rate.
    static func read() -> Reading {
        Reading(thermalState: ThermalState(ProcessInfo.processInfo.thermalState),
                dieTemperatureC: dieTemperature())
    }

    /// Mean of the `PMU tdie*` sensors, or `nil` when none report plausibly.
    private static func dieTemperature() -> Double? {
        guard let hid = symbols,
              let clientRef = hid.create(kCFAllocatorDefault, 0) else { return nil }

        let client = clientRef.takeRetainedValue()
        hid.setMatching(client, sensorMatch)

        guard let servicesRef = hid.copyServices(client) else { return nil }
        let services = servicesRef.takeRetainedValue() as [AnyObject]

        var sum = 0.0
        var count = 0
        for service in services {
            guard let nameRef = hid.copyProperty(service, "Product" as CFString),
                  let name = nameRef.takeRetainedValue() as? String,
                  name.hasPrefix("PMU tdie") else { continue }
            guard let eventRef = hid.copyEvent(service, temperatureEventType, 0, 0) else { continue }

            let celsius = hid.floatValue(eventRef.takeRetainedValue(),
                                         temperatureEventType << 16)
            guard plausibleRange.contains(celsius) else { continue }
            sum += celsius
            count += 1
        }
        return count > 0 ? sum / Double(count) : nil
    }
}
