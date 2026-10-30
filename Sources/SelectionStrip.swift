import SwiftUI

/// Beside the selected cards: the bulk actions, in one vertical strip. `StackLayout` places it
/// and sizes it; the rows here fill that size exactly. The count is on the cards themselves.
/// The cursor on the strip names every button: the right edge stays put and the strip grows to the
/// left, into the room the panel keeps for it, so a label never covers a card. The icons travel
/// left with it; each row is one button, icon and label together, so the cursor is still on the row
/// it was on when the label arrives under it.
struct SelectionStrip: View {
    @ObservedObject var model: StackModel
    let size: NSSize        // the icon column, as the placement sized it
    let reveal: CGFloat     // how far the labels put the strip's left edge out
    /// The greyed row under the pointer. Its reason is drawn here rather than left to `.help`:
    /// AppKit shows a window's tooltips only while its app is active, and the stack never
    /// activates Vignette.
    @State private var explained: String? = nil
    private var ui: UITweaks { Settings.shared.motionUI }

    var body: some View {
        let cards = model.selectedCards()
        // The labels are always out while the strip is up: a selection is the moment the rows'
        // names and shortcuts are wanted, whichever hand built it.
        let revealed = true
        let out = reveal
        let labelBox = StackLayout.current.stripLabelBox(reveal: reveal)
        let shots = cards.map(\.shot)
        VStack(spacing: ui.buttonSpacing) {
            // A row keeps its identity when it changes what it shows (Draw and Open share one), so it
            // moves with the strip; as two identities, the old one faded out where it had been.
            ForEach(Config.stripRows, id: \.[0].id) { row in
                let action = Config.stripAction(in: row, for: shots)
                let reason = action.unavailableReason(for: shots)
                Button { model.onAction(action, cards) } label: {
                    HStack(spacing: 0) {
                        // The icon column keeps its width with or without a symbol, so the labels
                        // still line up against it.
                        Group { if let symbol = action.symbol { Image(systemName: symbol) } }
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: ui.buttonSize, height: ui.buttonSize)
                        RevealedLabel(text: action.label, shortcut: action.key?.glyphs ?? "",
                                      size: StackLayout.stripLabelSize,
                                      width: reveal, box: labelBox, revealed: revealed)
                    }
                }
                .buttonStyle(TactileButtonStyle(shape: .rounded, hoverScale: 1))
                .disabled(reason != nil)
                .opacity(reason != nil ? 0.35 : 1)
                .accessibilityHint(reason ?? "")
                .onHover { inside in
                    if inside, reason != nil { explained = action.id }
                    else if explained == action.id { explained = nil }
                }
                .overlay(alignment: .top) {
                    if let reason, explained == action.id {
                        UnavailableReason(text: reason)
                            .offset(y: ui.buttonSize + ui.buttonSpacing)
                            .transition(.opacity)
                    }
                }
                // Over the rows below it, which a VStack otherwise draws on top.
                .zIndex(explained == action.id ? 1 : 0)
            }
        }
        .animation(Anim.spring(0.15 * Settings.shared.motionScale), value: explained)
        .frame(width: size.width + out, height: size.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.15), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        // The box stays the grown width and the strip sits against its trailing edge: the right
        // edge never moves, and the labels grow into the room on the left that the box holds open.
        .frame(width: size.width + reveal, alignment: .trailing)
    }
}

/// Why a greyed strip row cannot run on the selection, under the row.
/// One line, centered on the row: it may overhang the strip into the panel's inset, and a reason
/// wider than that would be cut off at the window's edge.
private struct UnavailableReason: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black.opacity(0.85)))
            .allowsHitTesting(false)
    }
}
