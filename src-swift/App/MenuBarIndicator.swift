import Foundation

/// How the menu-bar item presents itself.
///
/// Raw values are persisted under `Config.Key.indicatorStyle`.
enum MenuBarIndicator: String {
    /// The RedMagic logo, tinted by temperature, with the reading beside it.
    case icon
    /// A plain text label — for menu bars where a coloured glyph is noise.
    case text

    init(persisted raw: String?) {
        self = (raw == MenuBarIndicator.text.rawValue) ? .text : .icon
    }
}
