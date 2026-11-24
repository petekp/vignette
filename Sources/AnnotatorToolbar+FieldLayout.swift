import SwiftUI

// MARK: Where the message field's box and the target in its top row go as the box grows

/// The message field's box as it grows: its height, which SwiftUI animates, how far it may reach
/// below its slot on the bar, and the screen's pixels per point. The box and the target in its top
/// row are placed from this one value, so the two rise together.
struct FieldGrowth {
    var height: CGFloat
    let below: CGFloat
    let scale: CGFloat

    /// How far the box rises out of the top of a slot `slot` tall: by as much as it would reach past
    /// `below` under the slot. In whole pixels, rounded up, so the box's top edge and the target in
    /// its top row land on the pixel grid and the box stays within `below`.
    func rise(slot: CGFloat) -> CGFloat {
        let past = max(0, height - slot)
        let up = min(max(0, past - max(0, below)), past)
        return scale > 0 ? (up * scale).rounded(.up) / scale : up
    }
}

/// Places the message field in its slot on the bar: from the slot's top down, and once it would
/// reach further down than `growth.below` allows, moved up by the rest, out of the top of the bar.
struct GrowingField: Layout {
    var growth: FieldGrowth

    var animatableData: CGFloat {
        get { growth.height }
        set { growth.height = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let up = growth.rise(slot: bounds.height)
        for subview in subviews {
            subview.place(at: CGPoint(x: bounds.minX, y: bounds.minY - up), anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: max(growth.height, bounds.height)))
        }
    }
}

/// Places the target in the message field's box's top row: in its slot on the bar, and as far up as
/// the box rises out of the bar (`GrowingField`), on the same animated height, so the two move as
/// one. Alone (`following` false) it stays in its slot.
struct FollowsFieldTop: Layout {
    var growth: FieldGrowth
    let following: Bool

    var animatableData: CGFloat {
        get { growth.height }
        set { growth.height = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(proposal) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let up = following ? growth.rise(slot: bounds.height) : 0
        for subview in subviews {
            subview.place(at: CGPoint(x: bounds.minX, y: bounds.minY - up), anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
        }
    }
}
