import AppKit

/// Owns the LED's presentation state and translates it into writes on the
/// cooler's light characteristic.
///
/// Split out of `AppDelegate` because the mapping from "what the user picked"
/// to "what bytes the device wants" is genuinely fiddly: one UI effect can map
/// to two different device effects depending on the breath sub-style, the
/// `auto` effect is driven by temperature on a timer rather than by user input,
/// and every path has to be re-run after a reconnect because the cooler forgets
/// its light state when the link drops.
///
/// Settings are persisted here as they change, so the caller never has to
/// remember to save.
final class LedController {

    private unowned let ble: CoolerBLEManager

    private(set) var effect: LedEffect
    private(set) var breathStyle: BreathStyle
    /// 0…1, used by the stroke and monochrome-breath effects.
    private(set) var hue: Double

    /// The last colour actually written, used to suppress redundant writes in
    /// `auto` — where a new colour is computed every tick but usually matches
    /// the previous one. `nil` means "no colour of ours is showing", either
    /// because the device is driving its own animation or because the cooler
    /// is off.
    private(set) var lastWrittenColor: RGB?

    init(ble: CoolerBLEManager, defaults: UserDefaults = .standard) {
        self.ble = ble
        self.effect = (defaults.object(forKey: Config.Key.ledEffect) as? Int)
            .flatMap(LedEffect.init(rawValue:)) ?? .auto
        self.hue = defaults.double(forKey: Config.Key.ledHue)
        self.breathStyle = BreathStyle(
            persisted: defaults.string(forKey: Config.Key.breathStyle))
    }

    /// The colour the user has dialled in.
    var pickedColor: RGB { RGB(hue: hue) }

    /// Whether the hue picker applies to the current effect.
    var usesPickedColor: Bool { effect.usesPickedColor(breathStyle: breathStyle) }

    // ── User actions ─────────────────────────────────────────────────────────

    func setEffect(_ effect: LedEffect) {
        self.effect = effect
        UserDefaults.standard.set(effect.rawValue, forKey: Config.Key.ledEffect)
        push()
        EventLogger.record("LED effect → \(effect.title)")
    }

    func setBreathStyle(_ style: BreathStyle) {
        breathStyle = style
        UserDefaults.standard.set(style.rawValue, forKey: Config.Key.breathStyle)
        if effect == .breath { push() }
        EventLogger.record("LED breath style → \(style.title)")
    }

    func setHue(_ hue: Double) {
        self.hue = hue.clamped(to: 0...1)
        UserDefaults.standard.set(self.hue, forKey: Config.Key.ledHue)
        // Only the colour-driven effects need a rewrite; the rest ignore RGB.
        if ble.isConnected && usesPickedColor { push() }
    }

    // ── Device sync ──────────────────────────────────────────────────────────

    /// Re-sends the current effect. Call after a reconnect settles — the cooler
    /// comes back up with its light state reset.
    func reapply() { push() }

    /// Drives the `auto` effect's temperature colour. Called every tick; writes
    /// only when the colour actually changes.
    ///
    /// While the cooler is off its LED can't show anything, so the remembered
    /// colour is cleared to force a fresh write when it comes back on.
    func updateAutoColor(dieC: Double?, autopilot: AutopilotPolicy) {
        guard effect == .auto, ble.isConnected else { return }
        guard ble.mode.isOn else {
            lastWrittenColor = nil
            return
        }
        let color = autopilot.heatColor(for: dieC)
        guard color != lastWrittenColor else { return }
        ble.setLight(effect: LedEffect.DeviceEffect.steady.rawValue, color: color)
        lastWrittenColor = color
    }

    /// Writes the current effect to the device and records the resulting colour.
    private func push() {
        switch effect {
        case .off:
            ble.setLight(effect: LedEffect.DeviceEffect.off.rawValue)
            lastWrittenColor = .black

        case .colorful:
            ble.setLight(effect: LedEffect.DeviceEffect.rainbow.rawValue)
            lastWrittenColor = nil // device-driven animation

        case .breath:
            if breathStyle == .colorful {
                ble.setLight(effect: LedEffect.DeviceEffect.colorfulBreath.rawValue)
                lastWrittenColor = nil
            } else {
                let color = pickedColor
                ble.setLight(effect: LedEffect.DeviceEffect.monochromeBreath.rawValue,
                             color: color)
                lastWrittenColor = color
            }

        case .stroke:
            let color = pickedColor
            ble.setLight(effect: LedEffect.DeviceEffect.steady.rawValue, color: color)
            lastWrittenColor = color

        case .auto:
            // Colour comes from updateAutoColor on the next tick; clearing the
            // cache guarantees it writes rather than matching a stale value.
            lastWrittenColor = nil
        }
    }
}
