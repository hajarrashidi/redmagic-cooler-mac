import Foundation
import CoreBluetooth

/// Everything the app knows about one cooler model, gathered in one place:
/// how to recognise it in a scan, its brand and rated wattage, its primary GATT service,
/// and the factory function to instantiate its dedicated hardware driver.
///
/// This is the single seam for supporting another device. To add a model,
/// define a new profile below and append it to `all` — the rest of the app is
/// model-agnostic and follows whichever driver matches during discovery.
struct DeviceProfile: Equatable {

    /// Unique identifier for settings persistence (e.g. "rm-magcooler-5pro", "bs-magcooler-5pro").
    let id: String

    /// Brand / Manufacturer name (e.g. "REDMAGIC", "Black Shark", "Flydigi").
    let brand: String

    /// Human-readable model name, for logs, UI badges and the device picker.
    let modelName: String

    /// Maximum rated cooling power in Watts (e.g. 36W, 35W, 30W, 40W, 27W).
    let ratedWatts: Int

    /// Whether the hardware model contains a physical mechanical switch that cuts cooling while BLE remains alive.
    let hasPhysicalPowerSwitch: Bool

    /// Whether the hardware model broadcasts continuous live telemetry frames (temperatures/fan RPM).
    let hasTelemetryStream: Bool

    /// Lowercased substrings that identify this model in a scan result.
    let nameHints: [String]

    /// The vendor GATT service that carries all the control characteristics.
    let serviceUUID: CBUUID

    /// Instantiates the dedicated hardware driver for this profile.
    let driverFactory: (DeviceProfile) -> CoolerDriver

    func makeDriver() -> CoolerDriver {
        driverFactory(self)
    }

    // Equatable conformance based on unique ID
    static func == (lhs: DeviceProfile, rhs: DeviceProfile) -> Bool {
        lhs.id == rhs.id
    }

    // ── Registry ─────────────────────────────────────────────────────────────

    /// Every supported cooler model (strictly ≥ 27W/30W).
    static let all: [DeviceProfile] = [
        // REDMAGIC (27W - 40W)
        .vcCooler6ProPlus,
        .magcooler8Pro,
        .vcCooler6Pro,
        .magcooler5Pro,
        .magcooler4Pro,

        // Black Shark (27W - 35W)
        .blackSharkMagCooler5Pro,
        .blackSharkMagCooler4Pro,

        // Flydigi (27W - 30W)
        .flydigiB8X,
        .flydigiB7X,

        // iQOO (27W - 30W)
        .iqooCoolingBackClip2Pro,

        // OnePlus / OPPO (27W - 45W)
        .onePlus45WLiquidCooler,
        .onePlus27WCooler,

        // MEMO (30W - 36W)
        .memoCX08,
        .memoCX07
    ]

    /// Matches an advertised device by name, service UUID, or manufacturer data.
    static func matching(deviceName: String, advertisementData: [String: Any]? = nil) -> DeviceProfile? {
        let lower = deviceName.lowercased()

        // 1. Check Manufacturer Data if present
        if let adv = advertisementData,
           let mfgData = adv[CBAdvertisementDataManufacturerDataKey] as? Data {
            // Black Shark manufacturer ID: 0x8F, 0x03
            if mfgData.count >= 2 && mfgData[0] == 0x8F && mfgData[1] == 0x03 {
                if lower.contains("4") || lower.contains("4pro") {
                    return .blackSharkMagCooler4Pro
                }
                return .blackSharkMagCooler5Pro
            }
        }

        // 2. Check Advertised Services if present
        if let adv = advertisementData,
           let services = adv[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            if services.contains(CBUUID(string: "0000FFE0-0000-1000-8000-00805F9B34FB")) {
                if lower.contains("memo") || lower.contains("cx07") || lower.contains("cx08") {
                    return lower.contains("cx08") ? .memoCX08 : .memoCX07
                }
                if lower.contains("b7") { return .flydigiB7X }
                return .flydigiB8X
            }
            if services.contains(CBUUID(string: "0000FFF0-0000-1000-8000-00805F9B34FB")) {
                return .iqooCoolingBackClip2Pro
            }
            if services.contains(CBUUID(string: "0000FEE7-0000-1000-8000-00805F9B34FB")) {
                return lower.contains("45") ? .onePlus45WLiquidCooler : .onePlus27WCooler
            }
            if services.contains(CBUUID(string: "0000A0A0-3C17-D293-8E48-14FE2E4DA212")) {
                if lower.contains("4") || lower.contains("4pro") {
                    return .blackSharkMagCooler4Pro
                }
                return .blackSharkMagCooler5Pro
            }
        }

        // 3. Brand disambiguation by name
        if lower.contains("black shark") || lower.contains("blackshark") || lower.contains("bs ") || lower.hasPrefix("bs") {
            if lower.contains("4") || lower.contains("4pro") {
                return .blackSharkMagCooler4Pro
            }
            return .blackSharkMagCooler5Pro
        }

        if lower.contains("flydigi") || lower.contains("feizhi") {
            if lower.contains("b7") { return .flydigiB7X }
            return .flydigiB8X
        }

        if lower.contains("b8x") { return .flydigiB8X }
        if lower.contains("b7x") { return .flydigiB7X }

        // iQOO Lineup
        if lower.contains("iqoo") || lower.contains("ira2") {
            return .iqooCoolingBackClip2Pro
        }

        // OnePlus / OPPO Lineup
        if lower.contains("oneplus") || lower.contains("oppo cooler") {
            return (lower.contains("45") || lower.contains("liquid")) ? .onePlus45WLiquidCooler : .onePlus27WCooler
        }

        // MEMO Lineup
        if lower.contains("memo") || lower.contains("cx07") || lower.contains("cx08") {
            return lower.contains("cx08") ? .memoCX08 : .memoCX07
        }

        // REDMAGIC specific models
        if lower.contains("8pro") || lower.contains("cooler 8") {
            return .magcooler8Pro
        }
        if lower.contains("6pro+") || lower.contains("6 pro+") || lower.contains("6pro plus") {
            return .vcCooler6ProPlus
        }
        if lower.contains("6pro") || lower.contains("cooler 6") || lower.contains("magcooler 6") {
            return .vcCooler6Pro
        }
        if lower.contains("5pro") || lower.contains("cooler 5") || lower.contains("magcooler 5") {
            return .magcooler5Pro
        }
        if lower.contains("4pro") || lower.contains("cooler 4") || lower.contains("magcooler 4") {
            return .magcooler4Pro
        }

        // 4. Fallback search through all registered profiles
        return all.first { profile in
            profile.nameHints.contains(where: lower.contains)
        }
    }

    /// Loose substrings suggesting a vendor cooler the app has *no* profile for.
    ///
    /// Listed in the picker as unsupported so the user knows it was detected
    /// rather than thinking the app is broken.
    static let vendorHints = [
        "redmagic", "red magic", "magcooler", "magic cooler", "rm cooler", "vc cooler", "nubia",
        "black shark", "blackshark", "funcooler", "magcooler 4", "magcooler 5",
        "flydigi", "feizhi", "b6x", "b7x", "b8x",
        "iqoo", "ira2", "vivo cooler",
        "oneplus", "oppo cooler", "supervooc",
        "memo cooler"
    ]

    static func looksLikeVendorDevice(deviceName: String) -> Bool {
        let lowercased = deviceName.lowercased()
        return vendorHints.contains(where: lowercased.contains)
    }
}

// ── Known Models Registry ───────────────────────────────────────────────────

extension DeviceProfile {

    // ── REDMAGIC Lineup ──────────────────────────────────────────────────────

    /// REDMAGIC VC Cooler 6 Pro+ (advertises as `RM Magcooler 6pro+` or `REDMAGIC Cooler 6 Pro+`) — 40W TEC
    static let vcCooler6ProPlus = DeviceProfile(
        id: "rm-vccooler-6proplus",
        brand: "REDMAGIC",
        modelName: "REDMAGIC VC Cooler 6 Pro+ (40W)",
        ratedWatts: 40,
        hasPhysicalPowerSwitch: true,
        hasTelemetryStream: true,
        nameHints: ["6pro+", "6 pro+", "6pro plus"],
        serviceUUID: CBUUID(string: "d52082ad-e805-9f97-9d4e-1c682d9c9ce6"),
        driverFactory: { RedMagicDriver(profile: $0) }
    )

    /// REDMAGIC Cryo Cooler 8 Pro (advertises as `RM Magcooler 8pro` or `REDMAGIC Cooler 8`) — 36W TEC Liquid
    static let magcooler8Pro = DeviceProfile(
        id: "rm-cryocooler-8pro",
        brand: "REDMAGIC",
        modelName: "REDMAGIC Cryo Cooler 8 Pro (36W)",
        ratedWatts: 36,
        hasPhysicalPowerSwitch: false,
        hasTelemetryStream: true,
        nameHints: ["8pro", "cooler 8", "magcooler 8"],
        serviceUUID: CBUUID(string: "d52082ad-e805-9f97-9d4e-1c682d9c9ce6"),
        driverFactory: { RedMagicDriver(profile: $0) }
    )

    /// REDMAGIC VC Cooler 6 Pro (advertises as `RM Magcooler 6pro`) — 36W TEC
    static let vcCooler6Pro = DeviceProfile(
        id: "rm-vccooler-6pro",
        brand: "REDMAGIC",
        modelName: "REDMAGIC VC Cooler 6 Pro (36W)",
        ratedWatts: 36,
        hasPhysicalPowerSwitch: true,
        hasTelemetryStream: true,
        nameHints: ["6pro", "cooler 6", "magcooler 6"],
        serviceUUID: CBUUID(string: "d52082ad-e805-9f97-9d4e-1c682d9c9ce6"),
        driverFactory: { RedMagicDriver(profile: $0) }
    )

    /// REDMAGIC Magnetic Cooler 5 Pro (advertises as `RM Magcooler 5pro`) — 36W TEC
    static let magcooler5Pro = DeviceProfile(
        id: "rm-magcooler-5pro",
        brand: "REDMAGIC",
        modelName: "REDMAGIC Magnetic Cooler 5 Pro (36W)",
        ratedWatts: 36,
        hasPhysicalPowerSwitch: false,
        hasTelemetryStream: false,
        nameHints: ["5pro", "cooler 5", "magcooler 5"],
        serviceUUID: CBUUID(string: "d52082ad-e805-9f97-9d4e-1c682d9c9ce6"),
        driverFactory: { RedMagicDriver(profile: $0) }
    )

    /// REDMAGIC Magcooler 4 Pro (advertises as `RM Magcooler 4pro`) — 27W TEC
    static let magcooler4Pro = DeviceProfile(
        id: "rm-magcooler-4pro",
        brand: "REDMAGIC",
        modelName: "REDMAGIC Magcooler 4 Pro (27W)",
        ratedWatts: 27,
        hasPhysicalPowerSwitch: true,
        hasTelemetryStream: false,
        nameHints: ["4pro", "cooler 4", "magcooler 4"],
        serviceUUID: CBUUID(string: "d52082ad-e805-9f97-9d4e-1c682d9c9ce6"),
        driverFactory: { RedMagicDriver(profile: $0) }
    )

    // ── Black Shark Lineup ───────────────────────────────────────────────────

    /// Black Shark MagCooler 5 Pro (advertises as `Black Shark MagCooler 5 Pro` / `BS 5Pro`) — 35W TEC
    static let blackSharkMagCooler5Pro = DeviceProfile(
        id: "bs-magcooler-5pro",
        brand: "Black Shark",
        modelName: "Black Shark MagCooler 5 Pro (35W)",
        ratedWatts: 35,
        hasPhysicalPowerSwitch: false,
        hasTelemetryStream: true,
        nameHints: ["black shark 5", "blackshark 5", "magcooler 5 pro", "bs 5pro", "br42"],
        serviceUUID: CBUUID(string: "0000A0A0-3C17-D293-8E48-14FE2E4DA212"),
        driverFactory: { BlackSharkDriver(profile: $0) }
    )

    /// Black Shark MagCooler 4 Pro (advertises as `Black Shark MagCooler 4 Pro` / `BS 4Pro`) — 27W TEC
    static let blackSharkMagCooler4Pro = DeviceProfile(
        id: "bs-magcooler-4pro",
        brand: "Black Shark",
        modelName: "Black Shark MagCooler 4 Pro (27W)",
        ratedWatts: 27,
        hasPhysicalPowerSwitch: false,
        hasTelemetryStream: true,
        nameHints: ["black shark 4", "blackshark 4", "magcooler 4 pro", "bs 4pro"],
        serviceUUID: CBUUID(string: "0000A0A0-3C17-D293-8E48-14FE2E4DA212"),
        driverFactory: { BlackSharkDriver(profile: $0) }
    )

    // ── Flydigi Lineup ───────────────────────────────────────────────────────

    /// Flydigi B8X Magnetic Cooler (advertises as `Flydigi B8X` or `B8X`) — 30W Overclock TEC
    static let flydigiB8X = DeviceProfile(
        id: "fd-b8x",
        brand: "Flydigi",
        modelName: "Flydigi B8X Overclock (30W)",
        ratedWatts: 30,
        hasPhysicalPowerSwitch: false,
        hasTelemetryStream: true,
        nameHints: ["b8x", "flydigi b8x", "feizhi b8x"],
        serviceUUID: CBUUID(string: "0000FFE0-0000-1000-8000-00805F9B34FB"),
        driverFactory: { FlydigiDriver(profile: $0) }
    )

    /// Flydigi B7X Magnetic Cooler (advertises as `Flydigi B7X` or `B7X`) — 27W TEC
    static let flydigiB7X = DeviceProfile(
        id: "fd-b7x",
        brand: "Flydigi",
        modelName: "Flydigi B7X (27W)",
        ratedWatts: 27,
        hasPhysicalPowerSwitch: false,
        hasTelemetryStream: true,
        nameHints: ["b7x", "flydigi b7x", "feizhi b7x"],
        serviceUUID: CBUUID(string: "0000FFE0-0000-1000-8000-00805F9B34FB"),
        driverFactory: { FlydigiDriver(profile: $0) }
    )

    // ── iQOO Lineup ──────────────────────────────────────────────────────────

    /// iQOO Cooling Back Clip 2 Pro (advertises as `iQOO 2 Pro` / `iQOO Clip 2 Pro`) — 27W TEC (30W Peak)
    static let iqooCoolingBackClip2Pro = DeviceProfile(
        id: "iqoo-clip-2pro",
        brand: "iQOO",
        modelName: "iQOO Cooling Back Clip 2 Pro (27W)",
        ratedWatts: 27,
        hasPhysicalPowerSwitch: false,
        hasTelemetryStream: true,
        nameHints: ["iqoo", "ira2", "iqoo cooler", "clip 2 pro"],
        serviceUUID: CBUUID(string: "0000FFF0-0000-1000-8000-00805F9B34FB"),
        driverFactory: { IQOODriver(profile: $0) }
    )

    // ── OnePlus / OPPO Lineup ────────────────────────────────────────────────

    /// OnePlus 45W Liquid Cooler (advertises as `OnePlus 45W Cooler` / `OPPO Liquid Cooler`) — 45W TEC Liquid
    static let onePlus45WLiquidCooler = DeviceProfile(
        id: "op-liquid-45w",
        brand: "OnePlus",
        modelName: "OnePlus 45W Liquid Cooler (45W)",
        ratedWatts: 45,
        hasPhysicalPowerSwitch: false,
        hasTelemetryStream: true,
        nameHints: ["oneplus 45w", "oneplus liquid", "oppo liquid", "45w liquid"],
        serviceUUID: CBUUID(string: "0000FEE7-0000-1000-8000-00805F9B34FB"),
        driverFactory: { OnePlusDriver(profile: $0) }
    )

    /// OnePlus 27W Freezing Point Clip (advertises as `OnePlus 27W Cooler`) — 27W TEC SuperVOOC
    static let onePlus27WCooler = DeviceProfile(
        id: "op-freezing-27w",
        brand: "OnePlus",
        modelName: "OnePlus 27W Freezing Point Clip (27W)",
        ratedWatts: 27,
        hasPhysicalPowerSwitch: false,
        hasTelemetryStream: true,
        nameHints: ["oneplus 27w", "oneplus cooler", "oppo cooler"],
        serviceUUID: CBUUID(string: "0000FEE7-0000-1000-8000-00805F9B34FB"),
        driverFactory: { OnePlusDriver(profile: $0) }
    )

    // ── MEMO Lineup ──────────────────────────────────────────────────────────

    /// MEMO CX08 Magnetic Cooler (advertises as `MEMO CX08` / `CX08 Cooler`) — 36W TEC
    static let memoCX08 = DeviceProfile(
        id: "memo-cx08",
        brand: "MEMO",
        modelName: "MEMO CX08 Magnetic Cooler (36W)",
        ratedWatts: 36,
        hasPhysicalPowerSwitch: false,
        hasTelemetryStream: true,
        nameHints: ["cx08", "memo cx08"],
        serviceUUID: CBUUID(string: "0000FFE0-0000-1000-8000-00805F9B34FB"),
        driverFactory: { MemoDriver(profile: $0) }
    )

    /// MEMO CX07 Magnetic Cooler (advertises as `MEMO CX07` / `CX07 Cooler`) — 30W TEC
    static let memoCX07 = DeviceProfile(
        id: "memo-cx07",
        brand: "MEMO",
        modelName: "MEMO CX07 Magnetic Cooler (30W)",
        ratedWatts: 30,
        hasPhysicalPowerSwitch: false,
        hasTelemetryStream: true,
        nameHints: ["cx07", "memo cx07"],
        serviceUUID: CBUUID(string: "0000FFE0-0000-1000-8000-00805F9B34FB"),
        driverFactory: { MemoDriver(profile: $0) }
    )
}
