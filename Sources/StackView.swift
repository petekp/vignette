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
            // would only scroll over a card; a hair of alpha makes the column catch them. The
            // clear layer fills the panel, which is wider than the column while the strip is out,
            // so the column stays against its right edge; the strip's side catches nothing.
            Color.clear
            Color.black.opacity(model.isStack ? 0.01 : 0)
                .frame(width: layout.columnWidth + layout.inset * 2)
                // The panel runs down to the screen's edge; the Dock's room at the bottom of it
                // stays clear, so a click on a Dock icon under the column still reaches the Dock.
                .padding(.bottom, model.safeBottom)
            column
            if let strip = stripPlacement {
                let reveal = layout.stripReveal(rows: StackLayout.stripRows)
                // The strip's box is always the grown width, with the strip against its
                // trailing edge, so the right edge sits where the placement put it whether the
                // labels are out or not and the growth goes left, away from the cards.
                SelectionStrip(model: model, size: strip.size, reveal: reveal)
                    .offset(x: -(layout.inset + strip.right), y: -(layout.inset + model.safeBottom + strip.bottom))
                    .animation(Anim.spring(settings.motionUI.relayoutDuration), value: strip)
                    // Scrolling moves it with the cards, at once, and it shifts up with them for a
                    // new card; the slide-out carries it off screen.
                    .offset(x: stripSlide, y: model.scroll + stripLift)
                    .animation(Anim.spring(settings.motionUI.slideOutDuration), value: model.slidingOut)
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
        model.selectedCards().first.flatMap { model.lift[$0.id] } ?? 0
    }

    /// The strip starts a column's width further left, and its labels reach further still, so it
    /// needs that much more to clear the screen.
    private var stripSlide: CGFloat {
        guard model.slidingOut else { return 0 }
        let reach = layout.columnWidth + layout.stripGap + layout.stripWidth
            + layout.stripReveal(rows: StackLayout.stripRows)
        return layout.offscreenDistance(cardWidth: reach)
    }

    /// The cards, newest at the bottom, pulled down by `scroll`. What leaves the viewport fades
    /// out over the panel's inset instead of being cut.
    private var column: some View {
        let inset = layout.inset
        let shadowRoom = layout.cardShadowRoom
        let safeBottom = model.safeBottom
        return VStack(alignment: .trailing, spacing: layout.spacing) {
            ForEach(Array(model.cards.enumerated().reversed()), id: \.element.id) { index, card in
                CardView(card: card, index: index, model: model)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .coordinateSpace(name: "stack")
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

private struct CardView: View {
    let card: Card
    let index: Int      // 0 = newest, at the bottom
    @ObservedObject var model: StackModel
    private var hovered: Bool { model.hoveredCard == card.id }
    private var pressed: Bool { model.pressedCard == card.id }
    private var selected: Bool { model.isSelected(card.id) }
    private var focused: Bool { model.focused == card.id }
    private var isOut: Bool { model.outCards.contains(card.id) }
    /// The card's image is in the transition layer, flying into or out of a stitch. The slot keeps
    /// its place in the column and draws nothing, so the image is never on screen twice.
    private var isForming: Bool { model.forming.contains(card.id) }
    private var offscreen: Bool { model.offscreen.contains(card.id) }
    /// The card itself is under the mouse. A slot whose image is in the transition layer is not:
    /// the flight is what the eye follows, so the hover state arrives with the card that lands.
    private var showsHover: Bool { hovered && !isOut && !isForming }
    private var showsCircle: Bool { model.offersSelection && !isOut && !isForming && (hovered || model.inSelectionMode || focused) }
    private var notice: CardNotices.Notice? { model.notices.notice(on: card.shot.url.path) }
    private var showsButtons: Bool { showsHover && !model.inSelectionMode && notice == nil }
    /// The padding every corner control is given.
    static let buttonPad: CGFloat = 6
    /// How far a corner control's hit area reaches past it into the card.
    static let hitReach: CGFloat = 8

    /// A corner control's extra hit area: out to the card's edges on the corner's two sides, where
    /// the padding is, and `hitReach` into the card on the other two.
    static func hitSlop(_ corner: Alignment) -> EdgeInsets {
        let top = corner.vertical == .top, leading = corner.horizontal == .leading
        return EdgeInsets(top: top ? buttonPad : hitReach, leading: leading ? buttonPad : hitReach,
                          bottom: top ? hitReach : buttonPad, trailing: leading ? hitReach : buttonPad)
    }
    /// The card on screen. `Card.size` is its size at rest; the stack narrows while the annotator
    /// is beside it, and every card narrows with it.
    private var size: NSSize { StackLayout.current.at(widthScale: model.widthScale).drawn(card.size) }

    var body: some View {
        ZStack {
            if isOut || isForming {
                // The card's image is in the transition layer: in the annotator, or on its way
                // into a stitch. The slot stays reserved, and empty, so the image is never on
                // screen twice and the card flies back to the same place.
                Color.clear
            } else {
                Group {
                    if let image = card.image {
                        Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                    } else {
                        Color(white: 0.16)   // thumbnail still decoding
                    }
                }
                    .frame(width: size.width, height: size.height)
                    .background(Color(nsColor: Config.matte))
                    .clipShape(RoundedRectangle(cornerRadius: ui.cardCornerRadius, style: .continuous))
                    .shadow(color: .black.opacity(ui.cardShadowOpacity), radius: ui.cardShadowRadius, y: ui.cardShadowY)
                    .overlay(
                        // Drag out as files or drawings; a plain click goes to the model (annotate, or toggle in selection mode).
                        DragSource(items: { model.dragItems(dragCards()) }, image: card.image ?? NSImage(size: size),
                                   onPress: { down in model.pressedCard = down ? card.id : (model.pressedCard == card.id ? nil : model.pressedCard) },
                                   onClick: { model.onClickImage(card) },
                                   marks: card.marks, picture: card.image?.size, corner: ui.cardCornerRadius, restSize: card.size)
                    )
                    // The image itself never fades: a card landing from the annotator takes over
                    // from its flight in one frame, and the hover state around it is what animates.
                    .transition(.identity)
            }

        }
        // Darkens the card behind its buttons. Outside the branch above, so it fades in with them
        // when a card lands under a waiting mouse instead of appearing at full strength at once.
        .overlay {
            if showsButtons {
                RoundedRectangle(cornerRadius: ui.cardCornerRadius, style: .continuous)
                    .fill(.black.opacity(ui.hoverDim))
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        // After the dim, so a selected or focused card keeps its ring while the dim is up. The ring
        // grows out of the resting border rather than switching on, and shrinks back into it.
        .overlay {
            if !isOut && !isForming {
                let shape = RoundedRectangle(cornerRadius: ui.cardCornerRadius, style: .continuous)
                ZStack {
                    shape.stroke(.white.opacity(ui.cardBorderOpacity), lineWidth: ui.cardBorderWidth)
                    shape.stroke(ringColor, lineWidth: ringWidth)
                }
                .animation(Anim.spring(0.22 * motion), value: ringWidth)
                .animation(Anim.spring(0.22 * motion), value: selected)
                .allowsHitTesting(false)
            }
        }
        // Copy in the bottom-left corner, delete in the bottom-right, both as icons; Copy says its
        // name while the cursor is on it. A click anywhere else on the card draws.
        .overlay(alignment: .bottomLeading) {
            if showsButtons, let copy = Config.action(id: "copy"), let symbol = copy.symbol {
                RevealButton(symbol: symbol, label: copy.label, ui: ui, hitSlop: CardView.hitSlop(.bottomLeading)) { model.onAction(copy, [card]) }
                    .onHover { model.overControl = $0 }
                    .padding(CardView.buttonPad)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showsButtons, let trash = Config.action(id: "trash"), let symbol = trash.symbol {
                RoundButton(symbol: symbol, help: trash.label + (trash.key.map { " (\($0.glyphs))" } ?? ""), ui: ui, hitSlop: CardView.hitSlop(.bottomTrailing)) { model.onAction(trash, [card]) }
                    .onHover { model.overControl = $0 }
                    .padding(CardView.buttonPad)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .overlay(alignment: .topTrailing) {
            if let agent = card.agent, !isOut, !isForming {
                AgentBadge(agent: agent, size: ui.selectionCircleSize)
                    .padding(CardView.buttonPad)
                    .transition(.opacity)
            } else if card.shot.kind == .recording, !isOut, !isForming {
                RecordingBadge(duration: card.duration, size: ui.selectionCircleSize)
                    .padding(CardView.buttonPad)
            }
        }
        .overlay(alignment: .topLeading) {
            // Its own fade, so a circle that comes with the keyboard's focus fades in as a hovered one does.
            ZStack(alignment: .topLeading) { if showsCircle {
                SelectionCircle(number: model.selectionNumber(of: card.id), size: ui.selectionCircleSize)
                    .padding(CardView.hitSlop(.topLeading))
                    .contentShape(Rectangle())
                    .onHover { model.overControl = $0 }
                    // A press toggles; dragging from here sweeps selection down or up the column.
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("stack"))
                            .onChanged { value in model.onSweep(value.location.y) }
                            .onEnded { _ in model.onSweepEnd() }
                    )
                    .padding(CardView.hitSlop(.topLeading).negated)
                    .padding(CardView.buttonPad)
                    .transition(.opacity)
            } }
            .animation(Anim.spring(0.2 * motion), value: showsCircle)
        }
        .frame(width: size.width, height: size.height)
        // The thumbnail fills the card, so an image whose shape differs from the card's box hangs
        // outside it, and the clip that hides it does not shrink the hit area. Without this the
        // card takes hover and clicks everywhere its image reaches, over its neighbours.
        .contentShape(Rectangle())
        // What happened to the card, from the moment it lands until it has said so. One kind of
        // notice cross-fades into the next; a send keeps its overlay as its state changes.
        .overlay {
            if let notice, !isOut && !isForming {
                Group {
                    switch notice {
                    case .copied(let label): CopiedOverlay(corner: ui.cardCornerRadius, label: label)
                    case .notCopied(let reason): CopiedOverlay(corner: ui.cardCornerRadius, label: "Not copied", failure: reason)
                    case .send(let send): SendOverlay(notice: send, corner: ui.cardCornerRadius)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(Anim.spring((notice == nil ? 0.4 : 0.15) * motion), value: notice?.kind)
        .zIndex(showsHover ? 1 : 0)   // the hover scale may hang over the card below
        .scaleEffect(pressed ? ui.pressScale : (showsHover ? ui.hoverScale : 1))
        .animation(Anim.spring(0.25 * motion, bounce: 0.3), value: pressed)
        .animation(Anim.spring(ui.hoverRevealDuration), value: showsHover)
        .animation(Anim.spring(ui.hoverRevealDuration), value: showsButtons)
        // Past the panel's right edge, which sits just beyond the screen edge, so the card slides off screen.
        .offset(x: offscreen ? StackLayout.current.offscreenDistance(cardWidth: size.width) : 0)
        .animation(slideAnimation.delay(slideDelay), value: offscreen)
        // Outside the slide's animation, which would otherwise take over the lift's spring.
        .offset(y: model.lift[card.id] ?? 0)
        .onHover { inside in
            model.hoveredCard = inside ? card.id : (model.hoveredCard == card.id ? nil : model.hoveredCard)
        }
    }

    private var ui: UITweaks { Settings.shared.motionUI }
    private var motion: Double { Settings.shared.motionScale }
    /// The ring a selected or focused card wears over its resting border. It is 0 wide on any other card.
    private var ringColor: Color { selected ? .accentColor : .white.opacity(0.9) }
    private var ringWidth: CGFloat { selected || focused ? max(2, ui.cardBorderWidth) : 0 }

    /// Newest (bottom) card first, in and out: the cards nearest the cursor move at once, so a
    /// dismissal feels immediate even when the top of the column is still leaving. The per-card
    /// delay shrinks for tall stacks so the whole column is never slower than `staggerTotalMax`.
    private var slideDelay: Double {
        if model.entering == card.id { return insertLead }
        return Double(max(0, index)) * StackView.staggerStep(count: model.cards.count)
    }

    private var slideAnimation: Animation {
        if model.slidingOut { return Anim.spring(ui.slideOutDuration) }
        // A card joining a visible column moves as a lone thumbnail does, after `insertLead`.
        return Anim.swiftUI(ui.slideInCurve, duration: ui.slideInDuration)
    }

    /// How long a card joining a visible column waits, so it never overlaps the card above it. The
    /// cards above shift up by its slot, its height and the spacing, on `ui.shiftUpDuration`'s spring,
    /// and the card above clears the slot once it has risen the new card's height. The new card
    /// reaches the column's width once it is less than its own width from rest.
    private var insertLead: Double {
        let layout = StackLayout.current.at(widthScale: model.widthScale)
        let card = layout.drawn(self.card.size)
        let clears = Anim.reaches(Double(card.height / (card.height + layout.spacing)), spring: ui.shiftUpDuration)
        let travel = layout.offscreenDistance(cardWidth: card.width)
        let arrives = Anim.reaches(Double(1 - card.width / travel), curve: ui.slideInCurve, duration: ui.slideInDuration)
        return max(0, clears - arrives)
    }

    /// Dragging a selected card carries the whole selection, in the order it was selected.
    private func dragCards() -> [Card] {
        selected ? model.selectedCards() : [card]
    }
}

/// Empty while the card is only hovered or focused; once it is selected it carries the card's
/// place in the selection, which is the number Stitch will draw on it.
private struct SelectionCircle: View {
    let number: Int?
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(number != nil ? Color.accentColor : Color.black.opacity(0.45))
            Circle().stroke(.white, lineWidth: 1.5)
            if let number {
                // SF Rounded at proportional widths: monospaced digits pad a "1" to the width of a
                // "0" and leave it floating, and two digits at the bold weight reach the ring.
                Text("\(number)")
                    .font(.system(size: size * 0.56, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 2)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
    }
}

/// Marks a card an agent pushed in with `add?agent=`: a white tab saying who, with the vendor's
/// logo when the bundle has one (`Agent.logo(for:)`).
private struct AgentBadge: View {
    let agent: String
    let size: CGFloat
    var body: some View {
        HStack(spacing: size * 0.22) {
            if let logo = Agent.logo(for: agent) {
                // The tab is white in either appearance, so a one-colour logo is drawn black like the name.
                Image(nsImage: logo).resizable().aspectRatio(contentMode: .fit)
                    .foregroundStyle(.black.opacity(0.85))
                    .frame(width: size * 0.62, height: size * 0.62)
            } else {
                Image(systemName: Agent.fallbackSymbol).font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.black.opacity(0.8))
            }
            Text(Agent.label(for: agent)).font(.system(size: size * 0.55, weight: .semibold))
                .foregroundStyle(.black.opacity(0.85)).lineLimit(1).fixedSize()
        }
        .padding(.horizontal, size * 0.4)
        .frame(height: size)
        // A hairline edge and a deep shadow: the tab lands on light images too, a white wordmark included.
        .background(Capsule().fill(.white).overlay(Capsule().strokeBorder(.black.opacity(0.22), lineWidth: 0.75)))
        .shadow(color: .black.opacity(0.5), radius: 5, y: 1.5)
    }
}

/// Marks a card as a screen recording rather than a screenshot, since its poster frame alone looks
/// like one, and a click on it opens it instead of drawing. Shows the length once it has been read.
private struct RecordingBadge: View {
    let duration: TimeInterval?
    let size: CGFloat
    var body: some View {
        HStack(spacing: size * 0.2) {
            Image(systemName: "video.fill").font(.system(size: size * 0.45, weight: .semibold))
            if let duration { Text(RecordingBadge.format(duration)).font(.system(size: size * 0.55, weight: .semibold).monospacedDigit()) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, size * 0.35)
        .frame(height: size)
        .background(Capsule().fill(.black.opacity(0.7)))
        .fixedSize()
        .allowsHitTesting(false)
    }

    /// m:ss, or h:mm:ss past an hour, to the nearest second. Never 0:00: a clip under half a second
    /// still recorded something.
    static func format(_ seconds: TimeInterval) -> String {
        let total = max(1, Int(seconds.rounded()))
        let (h, m, s) = (total / 3600, total / 60 % 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// Beside the selected cards: the bulk actions, in one vertical strip. `StackLayout` places it
/// and sizes it; the rows here fill that size exactly. The count is on the cards themselves.
/// The cursor on the strip names every button: the right edge stays put and the strip grows to the
/// left, into the room the panel keeps for it, so a label never covers a card. The icons travel
/// left with it; each row is one button, icon and label together, so the cursor is still on the row
/// it was on when the label arrives under it.
private struct SelectionStrip: View {
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
private struct CopiedOverlay: View {
    let corner: CGFloat
    let label: String
    var failure: String? = nil
    @State private var landed = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous).fill(.black.opacity(0.55))
            VStack(spacing: 2) {
                Image(systemName: failure == nil ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(failure == nil ? .green : .red)
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

/// The Copied notice's counterpart for a send: the destination's logo, a badge on it for the
/// delivery, and where it went. The words go on a card too narrow for them, the project name last.
/// A delivery usually answers about as the card lands, so the sending state, once on screen, holds
/// `sendingHold` before it gives way: two steps rather than one state flickering into the next.
private struct SendOverlay: View {
    let notice: SendNotice
    let corner: CGFloat
    @State private var landed = false
    @State private var shown: SendNotice.State?
    @State private var since = Date()
    private static let sendingHold: TimeInterval = 0.45

    private var state: SendNotice.State { shown ?? notice.state }

    private var words: String {
        switch state {
        case .sending: return "Sending to \(notice.project)"
        case .sent: return "Sent to \(notice.project)"
        case .queued: return "Queued for \(notice.project)"
        case .uncertain: return "Check \(notice.project)"
        case .failed: return "Not sent"
        case .replyFailed: return "Reply not shown"
        }
    }

    var body: some View {
        let motion = Settings.shared.motionScale
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous).fill(.black.opacity(0.55))
            VStack(spacing: 5) {
                logo
                // A failure's reason goes first when the card is too short for it, then the words.
                ViewThatFits(in: .vertical) {
                    if let reason = notice.reason, state != .sending && state != .sent {
                        VStack(spacing: 3) {
                            headline
                            Text(reason).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                                .multilineTextAlignment(.center).lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    headline
                    Color.clear.frame(width: 1, height: 1)
                }
                .id(words)
                .transition(.blurReplace)
                .padding(.horizontal, 8)
            }
            .scaleEffect(landed ? 1 : 0.3)
            .opacity(landed ? 1 : 0)
        }
        .onAppear {
            shown = notice.state
            since = Date()
            withAnimation(Anim.spring(0.4 * motion, bounce: 0.45)) { landed = true }
        }
        .onChange(of: notice.state) { _, next in
            let wait = shown == .sending ? max(0, Self.sendingHold - Date().timeIntervalSince(since)) : 0
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                withAnimation(Anim.spring(0.35 * motion, bounce: 0.35)) { shown = next }
            }
        }
        .allowsHitTesting(false)
    }

    /// The words, or the project alone on a card too narrow for them, or nothing.
    private var headline: some View {
        ViewThatFits(in: .horizontal) {
            label(words)
            if state != .failed && state != .replyFailed { label(notice.project) }
            Color.clear.frame(width: 1, height: 1)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            .lineLimit(1).fixedSize()
    }

    /// The agent's logo on a white disc, as on a card an agent sent, with the delivery at its corner.
    private var logo: some View {
        ZStack {
            Circle().fill(.white).frame(width: 30, height: 30)
            if let image = Agent.logo(for: notice.client.rawValue) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .foregroundStyle(.black.opacity(0.85))
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: Agent.fallbackSymbol).font(.system(size: 14, weight: .bold)).foregroundStyle(.black.opacity(0.8))
            }
        }
        .overlay(alignment: .bottomTrailing) { badge.offset(x: 5, y: 4) }
    }

    /// On a white ring, which parts it from the disc it sits on.
    private var badge: some View {
        ZStack {
            Circle().fill(.white).frame(width: 18, height: 18)
            Group {
                switch state {
                case .sending:
                    ZStack {
                        Circle().fill(Color(white: 0.18)).frame(width: 15, height: 15)
                        ProgressView().controlSize(.mini).environment(\.colorScheme, .dark).scaleEffect(0.8)
                    }
                case .sent:
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 15, weight: .bold))
                        .symbolRenderingMode(.palette).foregroundStyle(.white, .green)
                case .queued:
                    // One layer, its hands cut out, so they show the white ring beneath.
                    Image(systemName: "clock.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.orange)
                case .uncertain, .failed, .replyFailed:
                    Image(systemName: "exclamationmark.circle.fill").font(.system(size: 15, weight: .bold))
                        .symbolRenderingMode(.palette).foregroundStyle(.white, state == .uncertain ? Color.orange : Color.red)
                }
            }
            .id(state)
            // The next state pops in while the last one only fades, so the ring is never empty.
            .transition(.asymmetric(insertion: .scale(scale: 0.3).combined(with: .opacity), removal: .opacity))
        }
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

/// A label beside an icon, out while `revealed`, with its shortcut after it. The width and the
/// opacity are animated from that one bool by whatever animation the caller puts around it; the
/// label is never inserted or removed, because a removal transition starts again from nothing and
/// jumps when the cursor leaves halfway. `width` is the room `stripReveal` measured; `box` is the
/// part of it the text sits in, the same for every row, so the shortcuts line up in a column.
private struct RevealedLabel: View {
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
private struct RevealButton: View {
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

private struct RoundButton: View {
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
