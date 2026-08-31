import Foundation

/// Compile-time configuration: the cooler's GATT contract, the keys we persist
/// under, and the tuning constants for the control loop.
///
/// Everything here is a fact about the hardware or a deliberate tuning choice.
/// Values discovered by probing the device are documented in `docs/FINDINGS.md`.
enum Config {

    // ── GATT contract ────────────────────────────────────────────────────────

    /// The cooler's vendor service. Note it is *not* advertised in the scan
    /// record, so discovery matches on device name instead (see `BLE.nameHints`).
    enum GATT {
        static let service = "d52082ad-e805-9f97-9d4e-1c682d9c9ce6"

        /// Write `[mode]` — see `CoolingMode`.
        static let coolingMode = "00001011-0000-1000-8000-00805f9b34fb"
        /// Write `[percent]`, 0–100. Firmware maps this to a U-shaped RPM curve.
        static let fanSpeed    = "00001012-0000-1000-8000-00805f9b34fb"
        /// Write `[effect, R, G, B]` — see `LedEffect`.
        static let lightMode   = "00001013-0000-1000-8000-00805f9b34fb"
        /// Write `[celsius]`, 0–60. The device's own auto-engage threshold.
        static let tempThresh  = "00001014-0000-1000-8000-00805f9b34fb"
        /// Notify. Byte 0 == 4 means the magnetic mount is attached.
        static let hall        = "00001015-0000-1000-8000-00805f9b34fb"
        /// Notify. `[0xAA, _, cold, hot, _, _, _, ambient, …, rpmLo, rpmHi]`.
        static let telemetry   = "00001016-0000-1000-8000-00805f9b34fb"
        /// Write `[0|1]`. Enables the device's own temperature automation.
        static let autoTemp    = "00001018-0000-1000-8000-00805f9b34fb"
    }

    // ── Device discovery ─────────────────────────────────────────────────────

    enum BLE {
        /// Lowercased substrings that identify a cooler in a scan result.
        static let nameHints = ["magcooler", "rm cooler"]

        /// How long to keep collecting scan hits before offering a picker.
        static let scanSettleWindow: TimeInterval = 4.0
        /// Delay before retrying after a dropped or failed link.
        static let reconnectDelay: TimeInterval = 5.0
        /// CoreBluetooth's `connect()` never times out on its own. If `didConnect`
        /// doesn't arrive within this window — typically because a stale link
        /// from a previous instance still owns the device's single connection
        /// slot — cancel and retry rather than hanging in `.connecting` forever.
        static let connectTimeout: TimeInterval = 8.0
        /// Grace period for a stale system-level link to drop before reconnecting.
        static let staleLinkClearTimeout: TimeInterval = 3.0
        /// The cooler applies mode and fan writes in order, but rejects a fan
        /// value that arrives in the same connection interval as a mode change.
        /// Fan writes are deferred by this much to stay clear of that.
        static let fanWriteDelay: TimeInterval = 0.2
        /// Time allowed for pending writes to flush before dropping the link.
        static let disconnectFlushDelay: TimeInterval = 0.3
    }

    // ── Persisted settings keys ──────────────────────────────────────────────

    /// `UserDefaults` keys. Renaming one silently resets that setting for every
    /// existing user, so treat these as a migration surface.
    enum Key {
        static let preferredDevice = "PreferredDeviceUUID"
        static let indicatorStyle  = "IndicatorStyle"      // MenuBarIndicator.rawValue
        static let appMode         = "AppMode"             // AppMode.rawValue
        static let autoProfile     = "AutoProfile"         // AutoProfile.rawValue
        static let customEngageC   = "CustomEngageTempC"   // Double, °C
        static let manualStep      = "ManualSliderStep"    // Int, 0…9
        static let manualFanSpeed  = "ManualFanSpeed"      // Int, 0…100
        static let ledEffect       = "LedEffect"           // LedEffect.rawValue
        static let ledHue          = "LedHue"              // Double, 0…1
        static let breathStyle     = "BreathStyle"         // BreathStyle.rawValue
        static let cachedMacModel  = "CachedMacModelName"
    }

    // ── Control loop timing ──────────────────────────────────────────────────

    enum Timing {
        /// Master tick: telemetry refresh, IPC poll, UI refresh.
        static let poll: TimeInterval = 1.0
        /// How often the autopilot re-evaluates, in ticks of `poll`.
        static let autopilotEveryTicks = 3
        /// How often settings are re-asserted to the device, in ticks of `poll`.
        /// The cooler occasionally drops a write; this makes state self-healing.
        static let heartbeatEveryTicks = 30
        /// How long controls stay disabled after a user-initiated change, so a
        /// second command can't race the first.
        static let switchLockout: TimeInterval = 1.4
        /// Hard cap on quit: never hang waiting for a BLE teardown callback.
        static let terminationDeadline: TimeInterval = 2.0
        /// How long launch waits for a previous instance to release the device.
        static let instanceHandoffTimeout: TimeInterval = 3.5
    }

    // ── Autopilot tuning ─────────────────────────────────────────────────────

    enum Autopilot {
        /// Degrees the die must fall *below* a tier's engage point before that
        /// tier releases — stops the cooler oscillating around a threshold.
        static let hysteresisC: Double = 5.0
        /// How long the temperature must stay low before stepping down a tier.
        static let cooldownDwell: TimeInterval = 15.0

        static let customEngageDefaultC: Double = 65.0
        static let customEngageMinC: Double = 45.0
        static let customEngageMaxC: Double = 85.0
    }

    // ── Runtime IPC files ────────────────────────────────────────────────────

    /// Files in `$HOME` shared with the `cooler` CLI. See `IPC/` and the header
    /// comment in `cooler` for the protocol.
    enum Paths {
        private static let home = FileManager.default.homeDirectoryForCurrentUser

        static let pid    = home.appendingPathComponent(".cooler.pid")
        static let status = home.appendingPathComponent(".cooler_status.json")
        static let command = home.appendingPathComponent(".cooler_cmd.json")
        static let log    = home.appendingPathComponent(".cooler.log")
    }
}
