import Foundation

/// The light effects offered in the UI.
///
/// Mirrors the vendor app's three effects (Colorful / Breath / Stroke) plus two
/// of this app's own: `off`, and `auto`, which paints a steady colour derived
/// from the Mac's temperature.
///
/// The raw values are UI ordering — they index the segmented control and are
/// persisted — and are deliberately *not* the device's effect bytes. Use
/// `LedEffect.DeviceEffect` for those; the two happen to overlap in places,
/// which is exactly why conflating them would be a trap.
enum LedEffect: Int, CaseIterable {
    case off = 0
    case colorful
    case breath
    case stroke
    case auto

    var title: String {
        switch self {
        case .off:      return "Off"
        case .colorful: return "Colorful"
        case .breath:   return "Breath"
        case .stroke:   return "Stroke"
        case .auto:     return "Auto"
        }
    }

    /// Byte 0 of the light characteristic. Verified on-device:
    ///
    /// | Byte | Behaviour                                     | Uses RGB |
    /// |------|-----------------------------------------------|----------|
    /// | 0    | off                                           | no       |
    /// | 1    | rainbow — all colours at once                  | no       |
    /// | 2    | colourful breath — breathes through the wheel  | no       |
    /// | 3    | monochrome breath — breathes the given colour  | yes      |
    /// | 4    | steady single colour                          | yes      |
    enum DeviceEffect: UInt8 {
        case off = 0
        case rainbow = 1
        case colorfulBreath = 2
        case monochromeBreath = 3
        case steady = 4
    }

    /// True when this effect's colour comes from the user's hue picker, so the
    /// UI knows whether to show it.
    func usesPickedColor(breathStyle: BreathStyle) -> Bool {
        switch self {
        case .stroke: return true
        case .breath: return breathStyle == .monochrome
        default:      return false
        }
    }
}

/// The two sub-styles of the Breath effect: cycle the whole colour wheel, or
/// breathe a single chosen colour.
enum BreathStyle: String {
    case colorful
    case monochrome

    var title: String { self == .colorful ? "Colorful" : "Monochrome" }

    init(persisted raw: String?) {
        self = (raw == BreathStyle.monochrome.rawValue) ? .monochrome : .colorful
    }
}
