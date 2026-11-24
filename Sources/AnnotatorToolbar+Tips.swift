import SwiftUI

struct TipSpots: PreferenceKey {
    struct Spot { let anchor: Anchor<CGRect>; let text: String? }
    static let defaultValue: [AnnotatorToolbar.Model.Control: Spot] = [:]
    static func reduce(value: inout [AnnotatorToolbar.Model.Control: Spot], nextValue: () -> [AnnotatorToolbar.Model.Control: Spot]) {
        value.merge(nextValue()) { $1 }
    }
}

/// A control with a tooltip. The bar draws its own: AppKit shows a window's tooltips only while it is
/// key or was the last one clicked, and the editor's window holds the keys, so the bar's never came.
struct TipSpot: ViewModifier {
    let control: AnnotatorToolbar.Model.Control
    let text: String?
    let hover: (AnnotatorToolbar.Model.Control, Bool) -> Void
    func body(content: Content) -> some View {
        content
            .onHover { hover(control, $0) }
            .anchorPreference(key: TipSpots.self, value: .bounds) { [control: TipSpots.Spot(anchor: $0, text: text)] }
            .accessibilityHint(text ?? "")
    }
}

/// A tooltip as macOS draws one.
struct TipLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(BehindWindowBlur(cornerRadius: 5, material: .toolTip))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
            .fixedSize()
    }
}

/// Puts a tooltip centred under or over `target`, kept inside the panel: over it when `below` is
/// false, unless the panel has no room above, as over a target risen with the message field's box.
struct TipPlacement: Layout {
    let target: CGRect
    let below: Bool
    /// From the control's edge past the bar's, which is 7 pt further.
    static let gap: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let x = min(max(target.midX - size.width / 2, 4), bounds.width - 4 - size.width)
            let over = target.minY - Self.gap - size.height
            let y = below || over < 4 ? target.maxY + Self.gap : over
            subview.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(size))
        }
    }
}
