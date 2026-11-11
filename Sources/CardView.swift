import SwiftUI

struct CardView: View, Equatable {
    let card: Card
    /// Where the card waits in the slide's stagger: its index from the newest, at the bottom, or
    /// from the lowest card in view while the column slides out.
    let place: Int
    let state: CardState
    let ui: UITweaks
    /// How wide the stack is drawn; see `StackLayout.widthScale`.
    let widthScale: CGFloat
    let motion: Double
    /// For the card's actions, which read it when they run. Not observed.
    let model: StackModel

    nonisolated static func == (a: CardView, b: CardView) -> Bool {
        a.card == b.card && a.place == b.place && a.state == b.state && a.ui == b.ui
            && a.widthScale == b.widthScale && a.motion == b.motion && a.model === b.model
    }

    private var hovered: Bool { state.hovered }
    private var pressed: Bool { state.pressed }
    private var selected: Bool { state.selectionNumber != nil }
    private var focused: Bool { state.focused }
    private var isOut: Bool { state.isOut }
    private var isForming: Bool { state.isForming }
    private var offscreen: Bool { state.offscreen }
    /// The card's image is in its slot, not in the transition layer.
    private var inSlot: Bool { !isOut && !isForming }
    /// What is drawn over the card comes in on this as the card lands. It is the spring the notice
    /// leaves on and its check grows on, so the scrim, the check and the rest arrive together.
    private var landing: Animation { Anim.spring(0.4 * motion) }
    /// What is drawn over the card goes on this as the card leaves: the hover state's reveal, which
    /// it already left on when the pointer was on the card.
    private var leaving: Animation { Anim.spring(ui.hoverRevealDuration) }
    /// The card itself is under the mouse. A slot whose image is in the transition layer is not:
    /// the flight is what the eye follows, so the hover state arrives with the card that lands.
    private var showsHover: Bool { hovered && inSlot }
    private var showsCircle: Bool { state.offersSelection && inSlot && (hovered || state.inSelectionMode || focused) }
    private var notice: CardNotices.Notice? { state.notice }
    /// The dim and the buttons go as the card is pressed, so a drag that follows lifts a picture of
    /// the card as it then looks: the drag image carries neither.
    private var showsButtons: Bool { showsHover && !pressed && !state.dragged && !state.inSelectionMode && notice == nil }
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
    private var size: NSSize { layout.drawn(card.size) }
    private var layout: StackLayout { StackLayout(ui: ui, widthScale: widthScale) }

    var body: some View {
        ZStack {
            if !inSlot {
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
                        DragSource(items: { model.dragItems(model.dragCards(from: card.id)) }, image: card.image ?? NSImage(size: size),
                                   onPress: { down in model.pressedCard = down ? card.id : (model.pressedCard == card.id ? nil : model.pressedCard) },
                                   onDrag: { model.drag(card.id, $0) },
                                   onClick: { model.onClickImage(card) },
                                   marks: card.marks, picture: card.image?.size, corner: ui.cardCornerRadius, restSize: card.size)
                    )
                    // The image itself never fades: a card landing from the annotator takes over
                    // from its flight in one frame, and what is drawn over it is what animates.
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
        // grows out of the resting border rather than switching on, and shrinks back into it. It is
        // there, 0 wide, while the slot is empty, so a card that lands focused grows its ring too.
        .overlay {
            let shape = ui.ring(cornerRadius: ui.cardCornerRadius)
            ZStack {
                if inSlot {
                    // The flight draws this border too, so it changes hands at once both ways, as the
                    // image does. A fade on leaving would outline the empty slot.
                    shape.stroke(.white.opacity(ui.cardBorderOpacity), lineWidth: ui.cardBorderWidth)
                        .transition(.identity)
                }
                shape.stroke(ringColor, lineWidth: ringWidth)
            }
            // A card leaving its slot shrinks its ring away with the badge and the notice.
            .landing(inSlot, landing, leaving: leaving)
            .animation(Anim.spring(0.22 * motion), value: ringWidth)
            .animation(Anim.spring(0.22 * motion), value: selected)
            .allowsHitTesting(false)
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
            if let agent = card.agent, inSlot {
                AgentBadge(agent: agent, size: ui.selectionCircleSize)
                    .padding(CardView.buttonPad)
                    .transition(.opacity)
            } else if card.shot.kind == .recording, inSlot {
                RecordingBadge(duration: card.duration, size: ui.selectionCircleSize)
                    .padding(CardView.buttonPad)
            }
        }
        .overlay(alignment: .topLeading) {
            // Its own fade, so a circle that comes with the keyboard's focus fades in as a hovered one
            // does. One that comes with a landing card takes the landing's.
            ZStack(alignment: .topLeading) { if showsCircle {
                SelectionCircle(number: state.selectionNumber, size: ui.selectionCircleSize)
                    .padding(CardView.hitSlop(.topLeading))
                    .contentShape(Rectangle())
                    .onHover { model.overControl = $0 }
                    // A press toggles; dragging from here sweeps selection down or up the column.
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("stack"))
                            .onChanged { value in
                                if model.sweepCard != card.id { model.sweepCard = card.id }
                                model.onSweep(value.location.y)
                            }
                            .onEnded { _ in
                                model.sweepCard = nil
                                model.onSweepEnd()
                            }
                    )
                    .padding(CardView.hitSlop(.topLeading).negated)
                    .padding(CardView.buttonPad)
                    .transition(.opacity)
            } }
            .landing(inSlot, landing)
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
            if let notice, inSlot {
                Group {
                    switch notice {
                    case .copied(let label): CopiedOverlay(corner: ui.cardCornerRadius, label: label)
                    case .notCopied(let reason): CopiedOverlay(corner: ui.cardCornerRadius, label: "Not copied", failure: reason)
                    case .send(let send):
                        SendOverlay(notice: send, corner: ui.cardCornerRadius,
                                    onUnsend: { if let unsend = Config.action(id: "unsend") { model.onAction(unsend, [card]) } },
                                    onOverControl: { model.overControl = $0 })
                    }
                }
                .transition(.opacity)
            }
        }
        // What is drawn over the card comes in as the card lands and goes as it leaves: the flight
        // carries only the image and its border.
        .landing(inSlot, landing, leaving: leaving)
        .animation(Anim.spring((notice == nil ? 0.4 : 0.15) * motion), value: notice?.kind)
        .scaleEffect(pressed || state.dragged ? ui.pressScale : (showsHover ? ui.hoverScale : 1))
        .animation(Anim.spring(0.25 * motion, bounce: 0.3), value: pressed)
        // A card coming back from a drag settles without the press's bounce.
        .animation(Anim.spring(0.25 * motion), value: state.dragged)
        .animation(Anim.spring(ui.hoverRevealDuration), value: showsHover)
        .animation(Anim.spring(ui.hoverRevealDuration), value: showsButtons)
        // Past the panel's right edge, which sits just beyond the screen edge, so the card slides off screen.
        .offset(x: offscreen ? layout.offscreenDistance(cardWidth: size.width) : 0)
        .animation(slideAnimation.delay(slideDelay), value: offscreen)
        .onHover { inside in
            guard !model.holdsHover else { return }
            model.hoveredCard = inside ? card.id : (model.hoveredCard == card.id ? nil : model.hoveredCard)
        }
    }

    /// The ring a selected or focused card wears over its resting border. It is 0 wide on any other card.
    private var ringColor: Color { selected ? .accentColor : .white.opacity(0.9) }
    private var ringWidth: CGFloat { inSlot && (selected || focused) ? max(2, ui.cardBorderWidth) : 0 }

    /// Newest (bottom) card first, in and out: the cards nearest the cursor move at once, so a
    /// dismissal feels immediate even when the top of the column is still leaving. The per-card
    /// delay shrinks for tall stacks so the whole column is never slower than `staggerTotalMax`.
    private var slideDelay: Double {
        if state.entering { return insertLead }
        let place = state.slidingOut ? self.place : state.entranceRank ?? self.place
        return Double(max(0, place)) * StackView.staggerStep(count: state.cardCount)
    }

    private var slideAnimation: Animation {
        if state.slidingOut { return Anim.spring(ui.slideOutDuration) }
        // A card joining a visible column moves as a lone thumbnail does, after `insertLead`.
        return Anim.swiftUI(ui.slideInCurve, duration: ui.slideInDuration)
    }

    /// How long a card joining a visible column waits, so it never overlaps the card above it. The
    /// cards above shift up by its slot, its height and the spacing, on `ui.shiftUpDuration`'s spring,
    /// and the card above clears the slot once it has risen the new card's height. The new card
    /// reaches the column's width once it is less than its own width from rest.
    private var insertLead: Double {
        let card = layout.drawn(self.card.size)
        let clears = Anim.reaches(Double(card.height / (card.height + layout.spacing)), spring: ui.shiftUpDuration)
        let travel = layout.offscreenDistance(cardWidth: card.width)
        let arrives = Anim.reaches(Double(1 - card.width / travel), curve: ui.slideInCurve, duration: ui.slideInDuration)
        return max(0, clears - arrives)
    }
}

private extension View {
    /// `animation` for what changes as a card takes its slot back, and `leaving` for what changes
    /// as it gives the slot up. Inside a view's own animations, it wins over them at that moment.
    /// Without `leaving`, a card leaving keeps the animation the change already has.
    func landing(_ inSlot: Bool, _ animation: Animation, leaving: Animation? = nil) -> some View {
        transaction(value: inSlot) { transaction in
            if inSlot { transaction.animation = animation } else if let leaving { transaction.animation = leaving }
        }
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
