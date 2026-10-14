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
    ///
    /// Idempotent: calling it again with nothing changed leaves the existing area
    /// alone. Replacing a tracking area while the pointer is inside the row throws
    /// away the pending "mouse exited", and the highlight then never clears.
    func setHoverTracking(enabled: Bool) {
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let current = trackingAreas.filter { $0.owner === self }
        if enabled, current.count == 1, current[0].options == options { return }
        if !enabled, current.isEmpty { return }

        current.forEach(removeTrackingArea)
        guard enabled else { return }
        // .activeAlways rather than .activeInActiveApp: this is a menu-bar app
        // that never becomes the active application just because its menu is
        // open, so an "active app" tracking area can go the whole session
        // without firing once. .inVisibleRect keeps it matched to the row as it
        // resizes, so it never needs rebuilding for that.
        addTrackingArea(NSTrackingArea(rect: .zero, options: options, owner: self))
    }
}
