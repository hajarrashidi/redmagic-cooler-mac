import AppKit

/// A small window for the cold plate limit: the plate temperature below which
/// the app holds cooling back, to keep the plate from going far under the room's
/// dew point and freezing or soaking what is around it.
///
/// Shown and typed in the user's temperature unit, handed back in °C.
final class PlateLimitWindow: NSObject, NSWindowDelegate, NSTextFieldDelegate {

    /// Called with whether the limit is on and the temperature in °C. The
    /// temperature is valid whenever the limit is on.
    var onSave: ((_ enabled: Bool, _ floorC: Double) -> Void)?

    private let unit = SystemInfo.temperatureUnit()
    private var window: NSWindow?
    private let enabledBox = NSButton(checkboxWithTitle: "Hold cooling back when the cold plate is too cold",
                                      target: nil, action: nil)
    private let field = NSTextField()
    private let message = NSTextField(wrappingLabelWithString: "")
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)
    private var savedFloorC = Config.PlateLimit.defaultC

    func show(enabled: Bool, floorC: Double) {
        savedFloorC = floorC
        if window == nil { buildWindow() }
        enabledBox.state = enabled ? .on : .off
        field.stringValue = format(toDisplay(floorC).rounded())
        refreshState()

        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    // ── Window ───────────────────────────────────────────────────────────────

    private func buildWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 260),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "Plate Limit"
        window.isReleasedWhenClosed = false
        window.delegate = self

        let intro = NSTextField(wrappingLabelWithString:
            "A thermoelectric plate run for long can fall far below the room's dew point, "
            + "which frosts it and wets whatever it touches. The app has no humidity reading, "
            + "so it watches the plate itself: while the plate is colder than this limit, "
            + "cooling is stepped down a level at a time until it recovers, and the cooler "
            + "shows a notice. The level you chose stays selected.")
        intro.font = .systemFont(ofSize: 11)
        intro.textColor = .secondaryLabelColor
        intro.preferredMaxLayoutWidth = 360

        enabledBox.target = self
        enabledBox.action = #selector(toggled)

        let title = NSTextField(labelWithString: "Limit")
        title.widthAnchor.constraint(equalToConstant: 50).isActive = true
        field.alignment = .right
        field.delegate = self
        field.widthAnchor.constraint(equalToConstant: 70).isActive = true
        let row = NSStackView(views: [title, field, NSTextField(labelWithString: unit.suffix)])
        row.spacing = 8

        message.font = .systemFont(ofSize: 11)
        message.preferredMaxLayoutWidth = 360

        let reset = NSButton(title: "Reset", target: self, action: #selector(reset))
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.keyEquivalent = "\r"
        let buttons = NSStackView(views: [reset, NSView(), cancel, saveButton])
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.widthAnchor.constraint(equalToConstant: 360).isActive = true

        let stack = NSStackView(views: [intro, enabledBox, row, message, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.setCustomSpacing(16, after: intro)

        window.contentView = stack
        window.setContentSize(stack.fittingSize)
        self.window = window
    }

    // ── Values ───────────────────────────────────────────────────────────────

    private func toDisplay(_ celsius: Double) -> Double {
        unit == .fahrenheit ? celsius * 9 / 5 + 32 : celsius
    }

    private func fromDisplay(_ value: Double) -> Double {
        unit == .fahrenheit ? (value - 32) * 5 / 9 : value
    }

    private func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// The typed limit in °C, if it is a number inside the allowed range.
    private func typedFloorC() -> Double? {
        guard let value = Double(field.stringValue.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        let celsius = fromDisplay(value)
        return (Config.PlateLimit.minC...Config.PlateLimit.maxC).contains(celsius) ? celsius : nil
    }

    // ── State ────────────────────────────────────────────────────────────────

    private func refreshState() {
        let on = enabledBox.state == .on
        field.isEnabled = on

        guard on else {
            message.stringValue = "Off: nothing limits how cold the plate gets, apart from the manual auto-off timer."
            message.textColor = .systemOrange
            saveButton.isEnabled = true
            return
        }
        if let celsius = typedFloorC() {
            message.stringValue = "Cooling is held back while the plate is under "
                + SystemInfo.formatTemp(celsius) + "."
            message.textColor = .secondaryLabelColor
            saveButton.isEnabled = true
        } else {
            let low = SystemInfo.formatTemp(Config.PlateLimit.minC)
            let high = SystemInfo.formatTemp(Config.PlateLimit.maxC)
            message.stringValue = "Enter a temperature between \(low) and \(high)."
            message.textColor = .systemRed
            saveButton.isEnabled = false
        }
    }

    func controlTextDidChange(_ obj: Notification) { refreshState() }

    @objc private func toggled() { refreshState() }

    @objc private func reset() {
        field.stringValue = format(toDisplay(Config.PlateLimit.defaultC).rounded())
        enabledBox.state = .on
        refreshState()
    }

    @objc private func cancel() { window?.close() }

    @objc private func save() {
        let on = enabledBox.state == .on
        if let celsius = typedFloorC() {
            onSave?(on, celsius)
        } else if !on {
            onSave?(false, savedFloorC)
        } else {
            return
        }
        window?.close()
    }
}
