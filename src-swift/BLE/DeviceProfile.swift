import Foundation
import CoreBluetooth

/// Everything the app knows about one cooler model, gathered in one place:
/// how to recognise it in a scan, which GATT characteristics drive it, and how
/// to decode its telemetry frames.
///
/// This is the single seam for supporting another device. To add a model,
/// define a new profile below and append it to `all` — the rest of the app is
/// model-agnostic and follows whichever profile matched during discovery.
/// The full walkthrough is in `docs/ADDING_DEVICES.md`.
///
/// The UUIDs are stored pre-parsed as `CBUUID` because they're compared for
/// every characteristic on every notification, and `CBUUID(string:)` parses
/// on each call.
struct DeviceProfile {

    /// Human-readable model name, for logs and the device picker.
    let modelName: String

    /// Lowercased substrings that identify this model in a scan result.
    ///
    /// Matching is by advertised *name* because these devices omit their
    /// service UUID from the scan record — filtering a scan by service would
    /// never find them.
    let nameHints: [String]

    /// The vendor GATT service that carries all the control characteristics.
    let serviceUUID: CBUUID

    // ── Characteristics ──────────────────────────────────────────────────────

    /// Write `[mode]` — see `CoolingMode`.
    let coolingModeUUID: CBUUID
    /// Write `[percent]`, 0–100.
    let fanSpeedUUID: CBUUID
    /// Write `[effect, R, G, B]` — see `LedEffect`.
    let lightModeUUID: CBUUID
    /// Notify. Reports whether the magnetic mount is seated.
    let hallUUID: CBUUID
    /// Notify. Periodic telemetry frames, decoded by `decodeTelemetry`.
    let telemetryUUID: CBUUID

    // ── Frame decoding ───────────────────────────────────────────────────────

    /// Decodes one frame from `telemetryUUID`, or returns `nil` for frames
    /// that don't parse (wrong marker, truncated).
    let decodeTelemetry: (Data) -> CoolerTelemetry?

    /// Whether a hall-sensor frame means the magnetic mount is attached.
    let decodeMountAttached: (Data) -> Bool

    // ── Derived ──────────────────────────────────────────────────────────────

    /// Characteristics to subscribe to.
    var notifyingUUIDs: Set<CBUUID> { [hallUUID, telemetryUUID] }

    /// Characteristics the app writes to. Resolved at connect and held so
    /// `write` can find them; the device exposes more (a threshold and an
    /// auto-temp flag for its own automation, mapped in `docs/FINDINGS.md`),
    /// but this app runs its own autopilot and drives none of them.
    var writableUUIDs: Set<CBUUID> { [coolingModeUUID, fanSpeedUUID, lightModeUUID] }

    // ── Registry ─────────────────────────────────────────────────────────────

    /// Every model the app can drive, in match order. Add new profiles here.
    static let all: [DeviceProfile] = [.vcCooler6Pro]

    /// The profile whose name hints match an advertised device name, if any.
    static func matching(deviceName: String) -> DeviceProfile? {
        let lowercased = deviceName.lowercased()
        return all.first { $0.nameHints.contains(where: lowercased.contains) }
    }

    /// Loose substrings suggesting a vendor cooler the app has *no* profile for.
    ///
    /// Deliberately broader than any profile's `nameHints`, and used only to
    /// decide what to *show*. A device matching these but no profile is listed
    /// in the picker as unsupported and cannot be connected to — the app has no
    /// idea what its bytes mean. The point is that its owner can see the app
    /// noticed it, and read `docs/ADDING_DEVICES.md` rather than concluding the
    /// app is broken.
    static let vendorHints = [
        "redmagic", "red magic", "magcooler", "magic cooler",
        "rm cooler", "vc cooler", "nubia",
    ]

    static func looksLikeVendorDevice(deviceName: String) -> Bool {
        let lowercased = deviceName.lowercased()
        return vendorHints.contains(where: lowercased.contains)
    }
}

// ── Known models ─────────────────────────────────────────────────────────────

extension DeviceProfile {

    /// REDMAGIC VC Cooler 6 Pro (advertises as `RM Magcooler 6pro`).
    ///
    /// The protocol was reverse-engineered from BLE captures and the vendor
    /// APK; every byte here is documented in `docs/FINDINGS.md`.
    static let vcCooler6Pro = DeviceProfile(
        modelName: "REDMAGIC VC Cooler 6 Pro",
        // Only names this model is actually known to advertise. `rm cooler`
        // used to live here as a guess at sibling models, which meant any
        // "RM Cooler 5" in range was silently driven with 6 Pro byte layouts.
        // It now sits in `vendorHints`, so an unknown RM cooler is listed as
        // unsupported instead of being written to on a hunch.
        nameHints: ["magcooler"],
        serviceUUID: CBUUID(string: "d52082ad-e805-9f97-9d4e-1c682d9c9ce6"),
        coolingModeUUID: CBUUID(string: "00001011-0000-1000-8000-00805f9b34fb"),
        fanSpeedUUID:    CBUUID(string: "00001012-0000-1000-8000-00805f9b34fb"),
        lightModeUUID:   CBUUID(string: "00001013-0000-1000-8000-00805f9b34fb"),
        hallUUID:        CBUUID(string: "00001015-0000-1000-8000-00805f9b34fb"),
        telemetryUUID:   CBUUID(string: "00001016-0000-1000-8000-00805f9b34fb"),
        decodeTelemetry: { data in
            // `[0]=0xAA marker, [2]=cold °C, [3]=hot °C, [7]=ambient °C,
            //  [13..14]=fan RPM little-endian`. Older firmware sends a shorter
            // frame that stops before the RPM field.
            guard data.count >= 8, data[0] == 0xAA else { return nil }
            let rpm = data.count >= 15 ? Int(data[13]) | (Int(data[14]) << 8) : nil
            return CoolerTelemetry(coldC: Int(data[2]),
                                   hotC: Int(data[3]),
                                   ambientC: Int(data[7]),
                                   fanRPM: rpm)
        },
        decodeMountAttached: { data in
            // Byte 0 == 4 means the magnetic mount is seated (5 = detached).
            !data.isEmpty && data[0] == 4
        }
    )
}
