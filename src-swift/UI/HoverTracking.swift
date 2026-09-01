import AppKit

extension NSView {
    /// Rebuilds the single tracking area that gives a row its hover highlight.
    ///
    /// Both hand-drawn clickable rows — `BannerView` and `MenuActionRow` —
    /// carried their own copy of this, including the options list, which is the
    /// part that is easy to get subtly wrong: omit `.activeInActiveApp` and the
    /// highlight sticks after the menu closes.
    ///
    /// Call from `updateTrackingAreas()`, passing whatever makes the row
    /// interactive right now — a click handler being set, or the row being
    /// enabled — so a row that stops being clickable stops highlighting too.
    func setHoverTracking(enabled: Bool) {
        trackingAreas.forEach(removeTrackingArea)
        guard enabled else { return }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeInActiveApp],
                                       owner: self))
    }
}
