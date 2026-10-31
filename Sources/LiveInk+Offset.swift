import CoreGraphics

extension LiveInk {
    /// The least offset that puts `rect` inside `frame`, or its top-left corner at `frame`'s on a side
    /// where it is the larger.
    static func offset(moving rect: CGRect, into frame: CGRect) -> CGVector {
        func shift(_ min: CGFloat, _ max: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
            Mark.shiftInside(from: min - low, to: max - low, within: high - low) ?? low - min
        }
        return CGVector(dx: shift(rect.minX, rect.maxX, frame.minX, frame.maxX), dy: shift(rect.minY, rect.maxY, frame.minY, frame.maxY))
    }
}
