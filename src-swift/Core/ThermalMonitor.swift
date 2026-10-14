import Foundation
import IOKit

/// Reads Apple-silicon temperatures and macOS thermal pressure.
///
/// There is no public API for die temperature, so this binds the private
/// `IOHIDEventSystemClient` symbols out of IOKit at runtime and reads the
/// sensors it lists, by default averaging the `PMU tdie*` ones. The binding is resolved once and cached — the previous
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

    /// Which temperature the app treats as "the Mac's temperature": it drives
    /// Auto mode, the status card and the LED's Auto colour.
    enum Source: Equatable {
        /// Mean of the SoC die sensors. The default, and the only choice
        /// before the picker existed.
        case dieAverage
        case dieHottest
        case deviceAverage
        case deviceHottest
        case battery
        case storage
        /// One sensor by its `Product` name, e.g. `PMU tdie3`.
        case sensor(String)

        /// The fixed choices, in the order the picker lists them.
        static let groups: [Source] = [
            .dieAverage, .dieHottest, .deviceAverage, .deviceHottest, .battery, .storage,
        ]

        var title: String {
            switch self {
            case .dieAverage:    return "SoC die, average"
            case .dieHottest:    return "SoC die, hottest sensor"
            case .deviceAverage: return "Device sensors, average"
            case .deviceHottest: return "Device sensors, hottest"
            case .battery:       return "Battery"
            case .storage:       return "SSD"
            case .sensor(let name): return name
            }
        }

        /// The form written to `UserDefaults`.
        var stored: String {
            switch self {
            case .dieAverage:    return "die-average"
            case .dieHottest:    return "die-hottest"
            case .deviceAverage: return "device-average"
            case .deviceHottest: return "device-hottest"
            case .battery:       return "battery"
            case .storage:       return "storage"
            case .sensor(let name): return "sensor:" + name
            }
        }

        init(stored: String?) {
            guard let stored else { self = .dieAverage; return }
            if stored.hasPrefix("sensor:") {
                self = .sensor(String(stored.dropFirst("sensor:".count)))
            } else {
                self = Self.groups.first { $0.stored == stored } ?? .dieAverage
            }
        }
    }

    /// One temperature sensor, as the HID system reports it.
    struct Sensor {
        let name: String
        let celsius: Double
    }

    struct Reading {
        /// macOS's own thermal pressure level — always available.
        let thermalState: ThermalState
        /// Temperature in °C from the selected `Source` (the mean die
        /// temperature by default), or `nil` if no sensor could be read.
        let dieTemperatureC: Double?
    }

    /// Samples both signals. Cheap enough to call at the 1 Hz poll rate.
    static func read(source: Source = .dieAverage) -> Reading {
        Reading(thermalState: ThermalState(ProcessInfo.processInfo.thermalState),
                dieTemperatureC: temperature(for: source, in: sensors()))
    }

    /// The reading for `source`. A source with no sensors (one that has gone
    /// missing, say) falls back to the die average rather than leaving Auto
    /// mode blind.
    static func temperature(for source: Source, in sensors: [Sensor]) -> Double? {
        reading(for: source, in: sensors)
            ?? reading(for: .dieAverage, in: sensors)
    }

    /// The reading for `source` alone, `nil` when this Mac has no such sensor.
    /// The picker uses it to list only the choices that exist.
    static func reading(for source: Source, in sensors: [Sensor]) -> Double? {
        func values(where match: (String) -> Bool) -> [Double] {
            sensors.filter { match($0.name) }.map(\.celsius)
        }
        func mean(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        let isDie: (String) -> Bool = { $0.hasPrefix("PMU tdie") }
        let isDevice: (String) -> Bool = { $0.hasPrefix("PMU tdev") }

        switch source {
        case .dieAverage:    return mean(values(where: isDie))
        case .dieHottest:    return values(where: isDie).max()
        case .deviceAverage: return mean(values(where: isDevice))
        case .deviceHottest: return values(where: isDevice).max()
        case .battery:       return mean(values(where: { $0 == "gas gauge battery" }))
        case .storage:       return mean(values(where: { $0.hasPrefix("NAND") }))
        case .sensor(let name): return mean(values(where: { $0 == name }))
        }
    }

    /// Every plausible temperature reading, one per HID service. Names repeat
    /// (a sensor can be exposed by more than one service), so callers that list
    /// sensors group by name.
    static func sensors() -> [Sensor] {
        guard let hid = symbols,
              let clientRef = hid.create(kCFAllocatorDefault, 0) else { return [] }

        let client = clientRef.takeRetainedValue()
        hid.setMatching(client, sensorMatch)

        guard let servicesRef = hid.copyServices(client) else { return [] }
        let services = servicesRef.takeRetainedValue() as [AnyObject]

        var found = [Sensor]()
        for service in services {
            guard let nameRef = hid.copyProperty(service, "Product" as CFString),
                  let name = nameRef.takeRetainedValue() as? String else { continue }
            guard let eventRef = hid.copyEvent(service, temperatureEventType, 0, 0) else { continue }

            let celsius = hid.floatValue(eventRef.takeRetainedValue(),
                                         temperatureEventType << 16)
            guard plausibleRange.contains(celsius) else { continue }
            found.append(Sensor(name: name, celsius: celsius))
        }
        return found
    }

    /// The individual sensors for the picker: one entry per name, with the mean
    /// of its readings, in natural order (`tdie2` before `tdie10`).
    static func namedSensors(from sensors: [Sensor]) -> [Sensor] {
        Dictionary(grouping: sensors, by: \.name)
            .map { name, group in
                Sensor(name: name, celsius: group.map(\.celsius).reduce(0, +) / Double(group.count))
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
