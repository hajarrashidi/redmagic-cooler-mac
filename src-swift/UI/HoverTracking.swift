import AppKit

extension NSView {
    /// Rebuilds the single tracking area that gives a row its hover highlight.
    ///
    /// For rows that *are* a menu item's view — `BannerView`, `MenuActionRow`.
    /// A view nested inside one of those never sees the cursor at all, however
    /// its tracking area is set up, because `NSMenu` tracks the mouse itself
    /// and delivers to the item's view; those route hover down by hand instead
    /// (see `PillButton.isHovered`).
    ///
    /// Call from `updateTrackingAreas()`, passing whatever makes the row
    /// interactive right now — a click handler being set, or the row being
    /// enabled — so a row that stops being clickable stops highlighting too.
    func setHoverTracking(enabled: Bool) {
        trackingAreas.forEach(removeTrackingArea)
        guard enabled else { return }
        // .activeAlways rather than .activeInActiveApp: this is a menu-bar app
        // that never becomes the active application just because its menu is
        // open, so an "active app" tracking area can go the whole session
        // without firing once.
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self))
    }
}
