import Foundation

extension Comparable {
    /// Constrains a value to a range — the clamp idiom, spelled once.
    ///
    /// Replaces the `min(max(x, lo), hi)` sandwiches that were scattered across
    /// the fan, hue, temperature and slider-index paths, where the argument
    /// order was easy to get subtly wrong.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
