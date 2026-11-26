import AppKit

/// Where the popover by a pin hangs, in the coordinates of the editor's flipped view. It opens to the
/// right of the teardrop. An area pin with no room on the right hangs it under the area, or over it
/// when there is no room under it, from the teardrop's column, so the area stays in view: left to
/// itself, `NSPopover` flips to the left and covers the area.
struct PinPopoverPlace: Equatable {
    let rect: CGRect
    let edge: NSRectEdge

    /// Whether the area decides the place, fixed when the popover opens so it never jumps sides as
    /// the picture zooms.
    let aroundArea: Bool

    init(teardrop: CGRect, area: CGRect?, roomOnRight: Bool) {
        self.init(teardrop: teardrop, area: area, aroundArea: area != nil && !roomOnRight)
    }

    init(teardrop: CGRect, area: CGRect?, aroundArea: Bool) {
        guard aroundArea, let area else {
            self.rect = teardrop
            self.edge = .maxX
            self.aroundArea = false
            return
        }
        let top = min(teardrop.minY, area.minY), bottom = max(teardrop.maxY, area.maxY)
        self.rect = CGRect(x: teardrop.minX, y: top, width: teardrop.width, height: bottom - top)
        self.edge = .maxY
        self.aroundArea = true
    }

    /// How far past the teardrop's right side the popover reaches on screen: its width, with room for
    /// its arrow and the margin `NSPopover` keeps from the screen's edge, taken generously so the
    /// popover never flips over the area.
    static func reach(width: CGFloat) -> CGFloat { width + 24 }
}
