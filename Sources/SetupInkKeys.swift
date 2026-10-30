import CoreGraphics

/// The page's ⌃ and ⌥ caps, side by side, before and after the session makes them bigger.
enum SetupInkKeys {
    static let size: CGFloat = 24
    static let grown: CGFloat = 40
    static let padding: CGFloat = 5

    static func width(height: CGFloat) -> CGFloat { height * 1.12 }
    static func spacing(height: CGFloat) -> CGFloat { height * 0.16 }

    /// The two caps with the gap between them and the padding either side.
    static func row(height: CGFloat) -> CGSize {
        CGSize(width: 2 * width(height: height) + spacing(height: height) + 2 * padding, height: height)
    }
}
