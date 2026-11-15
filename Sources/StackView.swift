import SwiftUI

@MainActor
struct StackView: View {
    static func staggerStep(count: Int) -> Double {
        let ui = Settings.shared.motionUI
        return min(ui.staggerDelay, ui.staggerTotalMax / Double(max(1, count - 1)))
    }

    @ObservedObject var model: StackModel
    @ObservedObject private var settings = Settings.shared

    /// The layout at the stack's current width; `StackLayout.current` is the same at rest.
    private var layout: StackLayout { StackLayout.current.at(widthScale: model.widthScale) }

    var body: some View {
        let layout = self.layout
        return ZStack(alignment: .bottomTrailing) {
            // Fully transparent pixels let events fall through to the window below, so the stack
            // would only scroll over a card; a hair of alpha makes the column catch them, out to
            // `catchReach` on its left. The clear layer fills the panel, which is wider than the
            // column while the strip is out, so the column stays against its right edge; the
            // strip's side catches nothing.
            Color.clear
            // Lone thumbnails catch nothing between the cards, except while a swipe has moved
            // them: the fingers' next events must still reach the panel where the cards were.
            Color.black.opacity(model.isStack || model.swipe != 0 ? 0.01 : 0)
                .frame(width: layout.columnWidth + layout.inset + layout.catchReach(annotating: model.annotating))
                // The panel runs down to the screen's edge; the Dock's room at the bottom of it
                // stays clear, so a click on a Dock icon under the column still reaches the Dock.
                .padding(.bottom, model.safeBottom)
            // The swipe moves the column with the fingers, outside every animation.
            column.offset(x: model.swipe)
            if let strip = stripPlacement {
                let reveal = layout.stripReveal(rows: StackLayout.stripRows)
                // The strip's box is always the grown width, with the strip against its
                // trailing edge, so the right edge sits where the placement put it whether the
                // labels are out or not and the growth goes left, away from the cards.
                SelectionStrip(cards: model.selectedCards(), size: strip.size, reveal: reveal,
                               ui: layout.ui, motion: settings.motionScale, model: model)
                    .equatable()
                    .offset(x: -(layout.inset + strip.right), y: -(layout.inset + model.safeBottom + strip.bottom))
                    .animation(Anim.spring(settings.motionUI.relayoutDuration), value: strip)
                    // Scrolling moves it with the cards, at once, and it shifts up with them for a
                    // new card; the slide-out carries it off screen.
                    .offset(x: stripSlide, y: model.scroll + stripLift)
                    .animation(Anim.spring(settings.motionUI.slideOutDuration), value: model.slidingOut)
                    .offset(x: model.swipe)
                    .transition(.opacity)
            }
        }
        .animation(layoutAnimation(0.2), value: model.cards.map(\.id))
        .animation(layoutAnimation(0.15), value: model.inSelectionMode)
        .animation(layoutAnimation(0.15), value: model.annotating)
    }

    /// Layout changes animate only while cards are on screen. While the whole column is offscreen,
    /// in or out, a strip leaving the column would otherwise shift the cards as they slide
    /// in. A card joining a visible column changes the layout with animations off, and the others
    /// shift up with `StackModel.lift` instead (`ThumbnailController.shiftUp`).
    private func layoutAnimation(_ duration: Double) -> Animation? {
        let anyOnScreen = model.cards.contains { !model.offscreen.contains($0.id) }
        guard anyOnScreen else { return nil }
        return Anim.spring(duration * settings.motionScale)
    }

    private var stripPlacement: StackLayout.StripPlacement? {
        // The strip stands aside while the annotator has an image: it hangs to the left of the
        // column, inside the room the frame may grow into. The selection stays; the strip is back
        // when the session ends.
        guard model.isStack, model.inSelectionMode, !model.annotating else { return nil }
        return layout.stripPlacement(rows: Config.stripRows.count, selection: model.selectedIndices(),
                                     cards: model.cards.map { layout.drawn($0.size) },
                                     scroll: model.scroll, viewport: model.viewport)
    }

    /// The selected cards' lift while they shift up for a new card; they share one.
    private var stripLift: CGFloat {
        (model.selectedCards().first.flatMap { model.lift[$0.id] } ?? 0) * model.liftFraction
    }

    /// The strip slides out on its own spring, unless the swipe carries it with the column.
    private var stripSlide: CGFloat {
        guard model.slidingOut, !model.swipeExit else { return 0 }
        return layout.stripExitDistance
    }

    /// The cards, newest at the bottom, pulled down by `scroll`. What leaves the viewport fades
    /// out over the panel's inset instead of being cut.
    private var column: some View {
        let inset = layout.inset
        let shadowRoom = layout.cardShadowRoom
        let safeBottom = model.safeBottom
        return CardColumn(model: model, layout: layout, motion: settings.motionScale, scroll: model.scroll,
                          liftFraction: model.liftFraction, widthScale: model.widthScale)
        .offset(y: model.scroll)
        .padding(inset)
        // The Dock's room, so the newest card rests above the Dock rather than on it.
        .padding(.bottom, safeBottom)
        // Trailing, not centered: a lone card narrower than the widest must rest where the stack will put it.
        .frame(width: layout.columnWidth + inset * 2, height: model.viewport + safeBottom + inset * 2, alignment: .bottomTrailing)
        .mask(
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: inset)
                Color.black
                // The newest card rests on the viewport's bottom edge and its shadow falls in the
                // inset below it, so the fade starts under that shadow: a card in the column and
                // the same card in flight have to cast the same shadow, or one of them steps when
                // it takes the other's place. A card shadow falls downwards, so the top fade never
                // reaches one and keeps the whole inset.
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: max(0, inset - shadowRoom))
                // The Dock's room draws nothing: a card scrolled down fades out at the Dock's top
                // edge instead of covering it. The whole mask is lifted by the safe area, so the
                // fade's tail reaches the same two points past that edge (the inset less the
                // margin) by which the panel hangs past the screen's edge without a Dock.
                Color.clear.frame(height: safeBottom)
            }
        )
    }
}

/// Buttons that react to hover and press with a small scale, so they feel physical.
struct TactileButtonStyle: ButtonStyle {
    enum Shape { case circle, rounded, capsule }
    let shape: Shape
    /// Where the hover scale grows from. A button that grows a label to the right scales from its
    /// leading edge, so the two motions pull the same way.
    var anchor: UnitPoint = .center
    /// 1 for the strip's rows, where the label coming out is the hover and a scale on top of it
    /// would stretch the label and move the icon out from under the cursor. A card's Copy keeps the
    /// scale and anchors it to its leading edge, so the scale and the label pull the same way.
    var hoverScale: CGFloat = 1.08
    /// Room the label is padded by so that presses around the button reach it (`hitSlop` on the
    /// buttons below). The hover fill stays on the button itself.
    var hitSlop = EdgeInsets()
    @State private var hovered = false
    private var motion: Double { Settings.shared.motionScale }

    func makeBody(configuration: Configuration) -> some View {
        let fill: AnyShapeStyle = hovered ? AnyShapeStyle(.white.opacity(0.18)) : AnyShapeStyle(.clear)
        let pressed = configuration.isPressed
        // The springs reach only the fill and the scales. Around the whole label they also carried
        // any change to the label made in the same update, such as a new width when a menu opened
        // by the press closes, which then moved on its own spring while the controls around it
        // moved on another.
        return configuration.label
            .foregroundStyle(.primary)
            .background {
                Group {
                    switch shape {
                    case .circle: Circle().fill(fill)
                    case .rounded: RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill)
                    case .capsule: Capsule().fill(fill)
                    }
                }
                .padding(hitSlop)
                .animation(Anim.spring(0.12 * motion), value: hovered)
            }
            .animation(Anim.spring(0.12 * motion)) { $0.scaleEffect(hovered && !pressed ? hoverScale : 1, anchor: anchor) }
            .animation(Anim.spring(0.2 * motion, bounce: 0.3)) { $0.scaleEffect(pressed ? 0.9 : 1, anchor: anchor) }
            .onHover { hovered = $0 }
    }
}

/// Flush over a card after a copy: the veil fades in, the mark springs in, and both fade out. A
/// copy that failed shows its reason under the label, as a failed send does.
struct CopiedOverlay: View {
    let corner: CGFloat
    let label: String
    var failure: String? = nil
    @State private var landed = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous).fill(.black.opacity(0.55))
            VStack(spacing: 2) {
                if failure == nil {
                    CheckCoin(diameter: 22)
                } else {
                    Image(systemName: "exclamationmark.circle.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(.red)
                }
                Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                if let failure {
                    Text(failure).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8).padding(.top, 1)
                }
            }
            .scaleEffect(landed ? 1 : 0.3)
            .opacity(landed ? 1 : 0)
        }
        .onAppear { withAnimation(Anim.spring(0.4 * Settings.shared.motionScale, bounce: 0.45)) { landed = true } }
        .allowsHitTesting(false)
    }
}

/// A label beside an icon, out while `revealed`, with its shortcut after it. The width and the
/// opacity are animated from that one bool by whatever animation the caller puts around it; the
/// label is never inserted or removed, because a removal transition starts again from nothing and
/// jumps when the cursor leaves halfway. `width` is the room `stripReveal` measured; `box` is the
/// part of it the text sits in, the same for every row, so the shortcuts line up in a column.
struct RevealedLabel: View {
    let text: String
    var shortcut: String = ""
    let size: CGFloat
    let width: CGFloat
    var box: CGFloat = 0
    let revealed: Bool

    var body: some View {
        // The same font ButtonLabel measured; the text keeps its own width and the frame around it
        // is what grows, so the label is uncovered from the icon outwards.
        HStack(spacing: 0) {
            Text(text).font(.system(size: size, weight: .semibold))
            if !shortcut.isEmpty {
                Spacer(minLength: StackLayout.stripShortcutGap)
                // Dimmer than the label: the name is what you read, the keys are what you use.
                Text(shortcut).font(.system(size: size, weight: .semibold)).opacity(0.55)
            }
        }
        .frame(width: shortcut.isEmpty ? nil : box, alignment: .leading)
        .fixedSize()
        .frame(width: revealed ? width : 0, alignment: .leading)
        .opacity(revealed ? 1 : 0)
        .clipped()
        .contentShape(Rectangle())   // clipping hides the text; the hit area has to shrink with it
    }
}

/// An icon button whose label comes out beside it while the cursor is on it. At rest it is the same
/// circle as the other icon buttons. It grows to the right, from a leading edge that never moves,
/// so the icon stays under the cursor and the buttons around it stay where they are.
struct RevealButton: View {
    let symbol: String
    let label: String
    let ui: UITweaks
    var hitSlop = EdgeInsets()
    let action: () -> Void
    @State private var hovered = false

    private var labelSize: CGFloat { ui.buttonIconSize - 1 }
    private var revealWidth: CGFloat { ButtonLabel.width(label, size: labelSize) + ui.buttonSpacing * 2 }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Image(systemName: symbol).font(.system(size: ui.buttonIconSize, weight: .semibold))
                    .frame(width: ui.buttonSize, height: ui.buttonSize)
                RevealedLabel(text: label, size: labelSize, width: revealWidth, revealed: hovered)
            }
            .foregroundStyle(.white)
            .frame(height: ui.buttonSize)
            .background(Capsule().fill(.regularMaterial))
            .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            // In the label, since a button acts only on presses on its label.
            .padding(hitSlop)
            .contentShape(Rectangle())
        }
        .buttonStyle(TactileButtonStyle(shape: .capsule, anchor: .leading, hitSlop: hitSlop))
        .onHover { hovered = $0 }
        .padding(hitSlop.negated)
        .animation(Anim.spring(ui.hoverRevealDuration), value: hovered)
    }
}

struct RoundButton: View {
    let symbol: String
    let help: String
    let ui: UITweaks
    var hitSlop = EdgeInsets()
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: ui.buttonIconSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: ui.buttonSize, height: ui.buttonSize)
                .background(Circle().fill(.regularMaterial))
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                .padding(hitSlop)
                .contentShape(Rectangle())
        }
        .buttonStyle(TactileButtonStyle(shape: .circle, hitSlop: hitSlop))
        .padding(hitSlop.negated)
        .help(help)
    }
}

extension EdgeInsets {
    /// Padding by these insets takes back padding by the originals, so a view can take more room for
    /// its hit area without moving anything around it.
    var negated: EdgeInsets { EdgeInsets(top: -top, leading: -leading, bottom: -bottom, trailing: -trailing) }
}

/// The column's cards. A card is built only while its slot is within `reach` of the view, or while
/// the model keeps it built (`StackModel.keptBuilt`). Every other slot is an empty frame of the
/// card's size, so each card sits where a column of built cards puts it, and the controller's
/// frames (`StackLayout.cardFrame`) hold for every card. The view is read at the scroll, lift and
/// width drawn in this frame: SwiftUI hands an `Animatable` view each frame's value while they
/// animate, so a spring that carries the column far builds the cards it passes on the way, before
/// they come into view. Each card is drawn its lift below its slot here, not in `CardView`, so a
/// card built while the lifts spring starts where the spring is.
private struct CardColumn: View, Animatable {
    @ObservedObject var model: StackModel
    let layout: StackLayout
    let motion: Double
    var scroll: CGFloat
    var liftFraction: CGFloat
    var widthScale: CGFloat

    nonisolated var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(scroll, liftFraction), widthScale) }
        set { (scroll, liftFraction, widthScale) = (newValue.first.first, newValue.first.second, newValue.second) }
    }

    var body: some View {
        let drawnNow = StackLayout(ui: layout.ui, widthScale: widthScale)
        let sizes = model.cards.map { drawnNow.drawn($0.size) }
        let lifts = liftFraction == 0 || model.lift.isEmpty ? []
            : model.cards.map { (model.lift[$0.id] ?? 0) * liftFraction }
        let viewTop = scroll + model.viewport
        let reach = model.viewport * StackLayout.reach
        let built = drawnNow.cards(meeting: (scroll - reach)...(viewTop + reach), sizes: sizes, lifts: lifts)
        // The column slides out from the lowest card in view, so a column scrolled far up leaves at once.
        let lowestInView = drawnNow.cards(meeting: scroll...viewTop, sizes: sizes, lifts: lifts).first ?? 0
        let kept = model.keptBuilt
        return VStack(alignment: .trailing, spacing: layout.spacing) {
            ForEach(Array(model.cards.enumerated().reversed()), id: \.element.id) { index, card in
                let size = layout.drawn(card.size)
                ZStack {
                    if built.contains(index) || kept.contains(card.id) {
                        CardView(card: card, place: model.slidingOut ? index - lowestInView : index,
                                 state: CardState(of: card, in: model), ui: layout.ui,
                                 widthScale: layout.widthScale, motion: motion, model: model)
                            .equatable()
                            .offset(y: index < lifts.count ? lifts[index] : 0)
                            // Built or let go out of view, at once: a fade would still be running
                            // if a fling brought it in.
                            .transition(.identity)
                    }
                }
                .frame(width: size.width, height: size.height)
                .zIndex(model.hoveredCard == card.id ? 1 : 0)   // the hover scale may hang over the card below
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .coordinateSpace(name: "stack")
    }
}

