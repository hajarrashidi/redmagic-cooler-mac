import Foundation

/// Compile-time configuration: the keys we persist under and the tuning
/// constants for the control loop.
///
/// Everything here is a deliberate tuning choice or a fact about the app
/// itself. Facts about the *hardware* — GATT UUIDs, discovery name hints,
/// telemetry frame layouts — live in `BLE/DeviceProfile.swift`, one profile
/// per supported model.
enum Config {

    // ── BLE timing ───────────────────────────────────────────────────────────

    enum BLE {
        /// How long to keep collecting scan hits before offering a picker.
        static let scanSettleWindow: TimeInterval = 4.0
        /// Delay before retrying after a dropped or failed link.
        static let reconnectDelay: TimeInterval = 5.0
        /// CoreBluetooth's `connect()` never times out on its own, and neither
        /// does GATT discovery. If the link isn't fully `.ready` within this
        /// window — typically because a stale link from a previous instance
        /// still owns the device's single connection slot, or discovery has
        /// stalled — cancel and retry rather than hanging forever.
        static let connectTimeout: TimeInterval = 8.0
        /// Grace period for a stale system-level link to drop before reconnecting.
        static let staleLinkClearTimeout: TimeInterval = 3.0
        /// The cooler applies mode and fan writes in order, but rejects a fan
        /// value that arrives in the same connection interval as a mode change.
        /// Fan writes are deferred by this much to stay clear of that.
        static let fanWriteDelay: TimeInterval = 0.2
        /// Time allowed for an off-write pair to flush before dropping the
        /// link. It has to outlast `fanWriteDelay`, because `apply` defers the
        /// fan write by that much: drop the link in between and the cooler is
        /// left with its TEC off and its fan still spinning at the old speed.
        static let disconnectFlushDelay: TimeInterval = fanWriteDelay + 0.3
    }

    // ── Persisted settings keys ──────────────────────────────────────────────

    /// `UserDefaults` keys. Renaming one silently resets that setting for every
    /// existing user, so treat these as a migration surface.
    enum Key {
        static let preferredDevice = "PreferredDeviceUUID"
        static let preferredDeviceProfileId = "PreferredDeviceProfileId"
        static let appMode         = "AppMode"             // AppMode.rawValue
        static let engageC         = "AutopilotEngageTempC" // Double, °C
        static let shutoffC        = "AutopilotShutoffTempC" // Double, °C
        static let smartMaxMinFan  = "SmartMaxMinFanPercent" // Int, 0…100
        // Read only when migrating settings from builds with Standard/Custom.
        static let legacyAutoProfile = "AutoProfile"
        static let legacyCustomEngageC = "CustomEngageTempC"
        static let manualStep      = "ManualSliderStep"    // Int, 0…9
        static let manualTimeout   = "ManualTimeoutHours"  // Int; 0 = unlimited
        static let ledEffect       = "LedEffect"           // LedEffect.rawValue
        static let ledHue          = "LedHue"              // Double, 0…1
        static let breathStyle     = "BreathStyle"         // BreathStyle.rawValue
        static let cachedMacModel  = "CachedMacModelName"
        static let skippedVersion  = "SkippedUpdateVersion" // String, a release tag
        static let lastUpdateCheck = "LastUpdateCheck"      // Double, epoch seconds
    }

    // ── Updates ──────────────────────────────────────────────────────────────

    /// Where `UpdateChecker` looks, and how often.
    enum Updates {
        /// The repository releases are published from.
        static let repository = "Despensativo/redmagic-cooler-mac"

        /// `/releases/latest` already excludes drafts and prereleases, so
        /// nothing needs filtering on our side.
        static let latestReleaseAPI = URL(
            string: "https://api.github.com/repos/\(repository)/releases/latest")!

        /// Fallback landing page, used if a release ever omits its own URL.
        static let releasesPage = URL(
            string: "https://github.com/\(repository)/releases/latest")!

        /// Minimum gap between network checks. Persisted, so it survives relaunch.
        static let checkInterval: TimeInterval = 24 * 60 * 60
        /// Give up quickly — a missed check just retries tomorrow.
        static let requestTimeout: TimeInterval = 10
    }

    // ── Links ────────────────────────────────────────────────────────────────

    enum Links {
        /// The porting guide, offered in the device picker to whoever has a
        /// cooler the app can see but has no profile for.
        static let addingDevices = URL(
            string: "https://github.com/\(Updates.repository)/blob/main/docs/ADDING_DEVICES.md")!

        /// System Settings → Privacy & Security → Bluetooth. The only way back
        /// once Bluetooth access has been refused — the system prompt is
        /// one-shot, so the app cannot ask again itself.
        static let bluetoothPrivacySettings = URL(
            string: "x-apple.systempreferences:com.apple.preference.security"
                  + "?Privacy_Bluetooth")!
    }

    // ── Control loop timing ──────────────────────────────────────────────────

    enum Timing {
        /// Master tick: telemetry refresh, control loop, and UI refresh.
        static let poll: TimeInterval = 1.0
        /// How often the autopilot re-evaluates, in ticks of `poll`.
        static let autopilotEveryTicks = 3
        /// How often settings are re-asserted to the device, in ticks of `poll`.
        /// The cooler occasionally drops a write; this makes state self-healing.
        static let heartbeatEveryTicks = 30
        /// How often to *consider* an update check, in ticks of `poll`.
        /// `UpdateChecker` throttles the actual request to `Updates.checkInterval`;
        /// this only decides how promptly a long-running app notices it is due.
        static let updateCheckEveryTicks = 3_600
        /// How long controls stay disabled after a user-initiated change, so a
        /// second command can't race the first.
        static let switchLockout: TimeInterval = 1.4
        /// Hard cap on quit: never hang waiting for a BLE teardown callback.
        static let terminationDeadline: TimeInterval = 2.0
        /// How long launch waits for a previous instance to release the device.
        static let instanceHandoffTimeout: TimeInterval = 3.5
    }

    // ── Autopilot tuning & Step-Ladder ───────────────────────────────────────

    enum Autopilot {
        /// Deterministic 4-stage Step-Ladder Trigger Thresholds (°C)
        static let tier1TriggerC: Double = 50.0 // Min active cooling floor (40% fan)
        static let tier2TriggerC: Double = 60.0 // Medium cooling (60% fan)
        static let tier3TriggerC: Double = 65.0 // High boost (80% fan)
        static let tier4TriggerC: Double = 70.0 // Full Turbo limit (100% fan)

        /// Asymmetric Anti-Chattering Release Thresholds (°C)
        static let tier1ReleaseC: Double = 46.0 // 4°C buffer below 50°C (allows fanless idle Mac at 43-45°C to release to Standby)
        static let tier2ReleaseC: Double = 55.0 // 5°C buffer below 60°C
        static let tier3ReleaseC: Double = 61.0 // 4°C buffer below 65°C
        static let tier4ReleaseC: Double = 66.0 // 4°C buffer below 70°C

        /// Step-down anti-chattering dwell time (seconds)
        static let stepDownDwellSeconds: TimeInterval = 20.0
        /// Standby-to-Tier 1 wake confirmation dwell (seconds) to reject transient 1-second micro-spikes
        static let standbyWakeDwellSeconds: TimeInterval = 4.0
        /// Thermal velocity drop threshold (°C/s): if die drops faster than this, compress dwell to 3s
        static let velocityBypassRateCPerSec: Double = -1.0
        static let fastDwellSeconds: TimeInterval = 3.0

        /// Legacy slider compatibility constants
        static let hysteresisC: Double = 5.0
        static let cooldownDwell: TimeInterval = 20.0
        static let tempMinC: Double = 30.0
        static let tempMaxC: Double = 80.0
        static let engageDefaultC: Double = 50.0
        static let engageMinC: Double = tempMinC + 2.0
        static let engageMaxC: Double = tempMaxC
        static let shutoffDefaultC: Double = 38.0
        static let shutoffMinC: Double = tempMinC
        static let shutoffMaxC: Double = engageMaxC - 2.0
        static let smartMaxMinFanDefault: UInt8 = 40
        static let shutoffFloorC: Double = 38.0
    }

    // ── Safety Governor ──────────────────────────────────────────────────────

    enum Safety {
        /// Universal condensation cutoff: whenever Mac die drops below this temperature,
        /// TEC and fan are forcefully commanded to Standby (0W / 0%) across ALL modes.
        static let condensationCutoffC: Double = 36.0

        /// Asymmetric re-arm threshold: cooler remains off until Mac die warms back to this temperature.
        static let condensationRearmC: Double = 38.0
    }

    // ── Diagnostics ──────────────────────────────────────────────────────────

    enum Paths {
        private static let home = FileManager.default.homeDirectoryForCurrentUser

        static let log    = home.appendingPathComponent(".cooler.log")
    }

}
