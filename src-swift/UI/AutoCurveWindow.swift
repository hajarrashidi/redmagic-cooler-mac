import AppKit

/// A small window for setting the temperature at which each stage of the
/// connected cooler engages in Auto mode, in place of the ladder derived from
/// the threshold slider.
///
/// There is one row per step of the cooler's own slider after Off (the 8 Pro's
/// eight levels and Diablo, say), so Auto can use every one. Values are shown
/// and typed in the user's temperature unit and handed back in °C, which is what
/// the autopilot and the saved setting use.
final class AutoCurveWindow: NSObject, NSWindowDelegate, NSTextFieldDelegate {

    /// Called with whether the curve is switched on and one temperature in °C per
    /// stage. The temperatures are valid whenever the curve is on.
    var onSave: ((_ enabled: Bool, _ temperaturesC: [Double]) -> Void)?

    private let unit = SystemInfo.temperatureUnit()
    private var window: NSWindow?
    private let enabledBox = NSButton(checkboxWithTitle: "Use a custom curve",
                                      target: nil, action: nil)
    private var fields = [NSTextField]()
    private var stageNames = [String]()
    private let message = NSTextField(wrappingLabelWithString: "")
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)
    private var defaultCurveC = [Double]()
    private var savedCurveC = [Double]()

    /// - Parameters:
    ///   - stageNames: the connected cooler's steps above Off, lowest first.
    ///   - enabled: whether a custom curve is currently in use.
    ///   - curveC: the curve to show, one temperature per stage.
    ///   - defaultCurveC: what Reset puts back.
    func show(stageNames: [String], enabled: Bool, curveC: [Double], defaultCurveC: [Double]) {
        self.stageNames = stageNames
        self.defaultCurveC = defaultCurveC
        savedCurveC = curveC
        buildWindow()

        enabledBox.state = enabled ? .on : .off
        fill(with: curveC)
        refreshState()

        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    // ── Window ───────────────────────────────────────────────────────────────

    /// Rebuilt on every show, because the stages belong to whichever cooler is
    /// connected.
    private func buildWindow() {
        let window = self.window ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                                             styleMask: [.titled, .closable],
                                             backing: .buffered, defer: false)
        window.title = "Auto Curve"
        window.isReleasedWhenClosed = false
        window.delegate = self

        let intro = NSTextField(wrappingLabelWithString:
            "Auto mode steps through your cooler's stages as the Mac gets hotter. A stage "
            + "engages when the Mac reaches its temperature and is released "
            + "\(Int(Config.Autopilot.cooldownDwell)) seconds after the Mac drops below it. "
            + "Below the first temperature the cooler is off.")
        intro.font = .systemFont(ofSize: 11)
        intro.textColor = .secondaryLabelColor
        intro.preferredMaxLayoutWidth = 360

        enabledBox.target = self
        enabledBox.action = #selector(toggled)

        fields = []
        var rows = [NSView]()
        for name in stageNames {
            let title = NSTextField(labelWithString: name)
            title.widthAnchor.constraint(equalToConstant: 90).isActive = true

            let field = NSTextField()
            field.alignment = .right
            field.delegate = self
            field.widthAnchor.constraint(equalToConstant: 70).isActive = true
            fields.append(field)

            let suffix = NSTextField(labelWithString: unit.suffix)
            let row = NSStackView(views: [title, field, suffix])
            row.spacing = 8
            rows.append(row)
        }

        message.font = .systemFont(ofSize: 11)
        message.preferredMaxLayoutWidth = 360

        let reset = NSButton(title: "Reset", target: self, action: #selector(reset))
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.keyEquivalent = "\r"
        let spacer = NSView()
        let buttons = NSStackView(views: [reset, spacer, cancel, saveButton])
        buttons.spacing = 8

        let stack = NSStackView(views: [intro, enabledBox] + rows + [message, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.setCustomSpacing(16, after: intro)
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.widthAnchor.constraint(equalToConstant: 360).isActive = true

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

    /// A temperature *difference* in the user's unit, for the help text.
    private func delta(_ celsius: Double) -> String {
        let value = unit == .fahrenheit ? celsius * 9 / 5 : celsius
        return "\(Int(value.rounded()))\(unit.suffix)"
    }

    private func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private func fill(with curveC: [Double]) {
        for (field, celsius) in zip(fields, curveC) {
            field.stringValue = format(toDisplay(celsius).rounded())
        }
    }

    /// The fields as °C, or `nil` if any is not a number.
    private func typedCurveC() -> [Double]? {
        let values = fields.compactMap {
            Double($0.stringValue.trimmingCharacters(in: .whitespaces))
        }
        return values.count == fields.count ? values.map(fromDisplay) : nil
    }

    // ── State ────────────────────────────────────────────────────────────────

    /// Enables the fields and Save to match the checkbox and what is typed, and
    /// says in plain words what is wrong when it can't be saved.
    private func refreshState() {
        let on = enabledBox.state == .on
        fields.forEach { $0.isEnabled = on }

        guard on else {
            message.stringValue = "The ladder from the engage threshold slider is in use."
            message.textColor = .secondaryLabelColor
            saveButton.isEnabled = true
            return
        }
        guard let curve = typedCurveC() else {
            message.stringValue = "Enter a number for every stage."
            message.textColor = .systemRed
            saveButton.isEnabled = false
            return
        }
        if AutopilotPolicy.isValidCurve(curve, stages: fields.count) {
            message.stringValue = "Cooling starts at "
                + SystemInfo.formatTemp(curve[0]) + " and reaches "
                + (stageNames.last ?? "the last stage") + " at "
                + SystemInfo.formatTemp(curve[curve.count - 1]) + "."
            message.textColor = .secondaryLabelColor
            saveButton.isEnabled = true
        } else {
            let low = SystemInfo.formatTemp(Config.Autopilot.curveMinC)
            let high = SystemInfo.formatTemp(Config.Autopilot.curveMaxC)
            message.stringValue = "Each stage must be hotter than the one before it, by at least "
                + delta(1) + ", and between \(low) and \(high)."
            message.textColor = .systemRed
            saveButton.isEnabled = false
        }
    }

    func controlTextDidChange(_ obj: Notification) { refreshState() }

    @objc private func toggled() { refreshState() }

    @objc private func reset() {
        fill(with: defaultCurveC)
        refreshState()
    }

    @objc private func cancel() { window?.close() }

    @objc private func save() {
        let on = enabledBox.state == .on
        if let curve = typedCurveC(), AutopilotPolicy.isValidCurve(curve, stages: fields.count) {
            onSave?(on, curve)
        } else if !on {
            // Switching the curve off needs no valid values; keep the last good ones.
            onSave?(false, savedCurveC)
        } else {
            return
        }
        window?.close()
    }
}
