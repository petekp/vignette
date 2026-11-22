import SwiftUI

// MARK: How the bar's controls rest, come and go, and show the keyboard's focus

/// A control that cannot be used now, beside a send in progress or a Reply with nothing new: it fades
/// back, on a spring rather than in one frame, and takes no clicks. Not `.disabled`, whose look
/// AppKit's controls switch in one frame.
struct Resting: ViewModifier {
    let resting: Bool
    init(while resting: Bool) { self.resting = resting }
    func body(content: Content) -> some View {
        content
            .opacity(resting ? 0.4 : 1)
            .allowsHitTesting(!resting)
            .animation(Anim.spring(0.3 * Settings.shared.motionScale), value: resting)
    }
}

/// A control drawn at `fraction` of its own width and cut at its trailing edge, so one the offer adds
/// or takes away opens or closes in the bar's row (`ToolbarView.slot`).
struct Reveal: ViewModifier, Animatable {
    var fraction: CGFloat
    var animatableData: CGFloat {
        get { fraction }
        set { fraction = newValue }
    }

    func body(content: Content) -> some View {
        PartWidth(fraction: fraction) { content }
            // Cut only while it opens or closes: the focus ring is drawn outside the control.
            .clipShape(Rectangle().inset(by: fraction < 1 ? 0 : -20))
    }
}

/// Its one subview at its own size, laid out as `fraction` of its width.
struct PartWidth: Layout {
    var fraction: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let view = subviews.first else { return .zero }
        let size = view.sizeThatFits(.unspecified)
        return CGSize(width: size.width * max(fraction, 0), height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: .unspecified)
    }
}

/// The ring around the control the keyboard's focus is on, in the system's focus colour. It comes in
/// from a little larger, as AppKit's does.
struct FocusRing: ViewModifier {
    static let radius: CGFloat = 9.5
    let on: Bool
    /// Smaller for the target inside the message field's box, whose trailing edge is a hairline.
    var trailingRadius = FocusRing.radius
    func body(content: Content) -> some View {
        content
            .overlay {
                if on {
                    UnevenRoundedRectangle(topLeadingRadius: Self.radius, bottomLeadingRadius: Self.radius,
                                           bottomTrailingRadius: trailingRadius, topTrailingRadius: trailingRadius, style: .continuous)
                        .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 3)
                        .padding(-3)
                        .allowsHitTesting(false)
                        .transition(.scale(scale: 1.25).combined(with: .opacity))
                }
            }
            .animation(Anim.spring(0.2 * Settings.shared.motionScale), value: on)
    }
}
