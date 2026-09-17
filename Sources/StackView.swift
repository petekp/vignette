import SwiftUI

@MainActor
struct StackView: View {
    static func staggerStep(count: Int) -> Double {
        let ui = Settings.shared.motionUI
        return min(ui.staggerDelay, ui.staggerTotalMax / Double(max(1, count - 1)))
    }

    @ObservedObject var model: StackModel
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        let layout = StackLayout.current
        return ZStack(alignment: .bottomTrailing) {
            // Fully transparent pixels let events fall through to the window below, so the stack
            // would only scroll over a card; a hair of alpha makes the column catch them. The
            // clear layer fills the panel, which is wider than the column while the strip is out,
            // so the column stays against its right edge; the strip's side catches nothing.
            Color.clear
            Color.black.opacity(model.isStack ? 0.01 : 0)
                .frame(width: layout.maxCardWidth + layout.inset * 2)
            if !model.isStack, let text = model.feedback {
                FeedbackToast(text: text)
                    .padding(layout.inset)
                    .transition(.opacity)
            } else {
                column
                if let strip = stripPlacement {
                    SelectionStrip(model: model, size: strip.size)
                        .offset(x: -(layout.inset + strip.right), y: -(layout.inset + strip.bottom))
                        .animation(Anim.spring(settings.motionUI.relayoutDuration), value: strip)
                        // Scrolling moves it with the cards, at once; the slide-out carries it off screen.
                        .offset(x: stripSlide, y: model.scroll)
                        .animation(Anim.spring(settings.motionUI.slideOutDuration), value: model.slidingOut)
                        .transition(.opacity)
                }
            }
        }
        .animation(layoutAnimation(0.2), value: model.cards.map(\.id))
        .animation(layoutAnimation(0.15), value: model.inSelectionMode)
        .animation(layoutAnimation(0.15), value: model.feedback)
    }

    /// Layout changes animate only while the cards are on screen. While they are offscreen, in
    /// or out, a toast or strip leaving the column would otherwise shift them as they slide in.
    private func layoutAnimation(_ duration: Double) -> Animation? {
        model.offscreen.isEmpty ? Anim.spring(duration * settings.motionScale) : nil
    }

    private var stripPlacement: StackLayout.StripPlacement? {
        guard model.isStack, model.inSelectionMode else { return nil }
        return StackLayout.current.stripPlacement(rows: Config.stripActions.count, selection: model.selectedIndices(),
                                                  cards: model.cards.map(\.size), showsBar: model.showsBar,
                                                  scroll: model.scroll, viewport: model.viewport)
    }

    /// The toast leaves with the bottom card instead of vanishing under it.
    private var barSlide: CGFloat {
        model.slidingOut ? StackLayout.current.offscreenDistance(cardWidth: StackLayout.current.maxCardWidth) : 0
    }

    /// The strip starts a column's width further left, so it needs that much more to clear the screen.
    private var stripSlide: CGFloat {
        let layout = StackLayout.current
        return model.slidingOut ? layout.offscreenDistance(cardWidth: layout.maxCardWidth + layout.stripGap + layout.stripWidth) : 0
    }

    /// The cards, newest at the bottom, pulled down by `scroll`. What leaves the viewport fades
    /// out over the panel's inset instead of being cut.
    private var column: some View {
        let inset = StackLayout.current.inset
        return VStack(alignment: .trailing, spacing: StackLayout.current.spacing) {
            ForEach(Array(model.cards.enumerated().reversed()), id: \.element.id) { index, card in
                CardView(card: card, index: index, model: model)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            if model.isStack, let text = model.feedback {
                FeedbackToast(text: text)
                    .frame(width: StackLayout.current.maxCardWidth, height: StackLayout.current.barHeight)
                    .transition(.opacity)
                    .offset(x: barSlide)
                    .animation(Anim.spring(settings.motionUI.slideOutDuration), value: model.slidingOut)
            }
        }
        .coordinateSpace(name: "stack")
        .offset(y: model.scroll)
        .padding(inset)
        // Trailing, not centered: a lone card narrower than the widest must rest where the stack will put it.
        .frame(width: StackLayout.current.maxCardWidth + inset * 2, height: model.viewport + inset * 2, alignment: .bottomTrailing)
        .mask(
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: inset)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: inset)
            }
        )
    }
}

private struct CardView: View {
    let card: Card
    let index: Int      // 0 = newest, at the bottom
    @ObservedObject var model: StackModel
    @State private var pointer: CGPoint? = nil   // the mouse over this card, in its own coordinates
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
    private var showsCircle: Bool { model.isStack && !isOut && !isForming && (hovered || model.inSelectionMode || focused) }
    private var copied: Bool { model.copied.contains(card.id) }
    private var showsButtons: Bool { showsHover && !model.inSelectionMode && !copied }
    private var showsDrawHint: Bool { showsButtons && !model.overControl && !pressed && !inButtonRow }
    /// The strip along the bottom that holds the buttons, gaps included: a click there is not a draw.
    private var inButtonRow: Bool { pointer.map { $0.y >= card.size.height - 6 - ui.buttonSize } ?? true }

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
                    .frame(width: card.size.width, height: card.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: ui.cardCornerRadius, style: .continuous))
                    .shadow(color: .black.opacity(ui.cardShadowOpacity), radius: ui.cardShadowRadius, y: ui.cardShadowY)
                    .overlay(
                        // Drag out as files; a plain click goes to the model (annotate, or toggle in selection mode).
                        DragSource(urls: { dragURLs() }, image: card.image ?? NSImage(size: card.size),
                                   onPress: { down in model.pressedCard = down ? card.id : (model.pressedCard == card.id ? nil : model.pressedCard) },
                                   onClick: { model.onClickImage(card) })
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
        // After the dim, so a selected or focused card keeps its ring while the dim is up.
        .overlay {
            if !isOut && !isForming {
                RoundedRectangle(cornerRadius: ui.cardCornerRadius, style: .continuous)
                    .stroke(ringColor, lineWidth: ringWidth)
                    .allowsHitTesting(false)
            }
        }
        // Copy in the bottom-left corner with its name, delete in the bottom-right as an icon; a
        // click anywhere else on the card draws.
        .overlay(alignment: .bottomLeading) {
            if showsButtons, let copy = Config.action(id: "copy") {
                PillButton(symbol: copy.symbol, label: copy.label, ui: ui) { model.onAction(copy, [card]) }
                    .onHover { model.overControl = $0 }
                    .padding(6)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showsButtons, let trash = Config.action(id: "trash") {
                RoundButton(symbol: trash.symbol, help: trash.label, ui: ui) { model.onAction(trash, [card]) }
                    .onHover { model.overControl = $0 }
                    .padding(6)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .overlay(alignment: .topTrailing) {
            if let agent = card.agent, !isOut, !isForming {
                AgentBadge(agent: agent, size: ui.selectionCircleSize)
                    .padding(6)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topLeading) {
            if showsCircle {
                SelectionCircle(number: model.selectionNumber(of: card.id), size: ui.selectionCircleSize)
                    .onHover { model.overControl = $0 }
                    .padding(6)
                    .transition(.opacity)
                    // A press toggles; dragging from here sweeps selection down or up the column.
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("stack"))
                            .onChanged { value in model.onSweep(value.location.y) }
                            .onEnded { _ in model.onSweepEnd() }
                    )
            }
        }
        .frame(width: card.size.width, height: card.size.height)
        // The thumbnail fills the card, so an image whose shape differs from the card's box hangs
        // outside it, and the clip that hides it does not shrink the hit area. Without this the
        // card takes hover and clicks everywhere its image reaches, over its neighbours.
        .contentShape(Rectangle())
        .overlay {
            if copied && !isOut && !isForming {
                CopiedOverlay(corner: ui.cardCornerRadius).transition(.opacity)
            }
        }
        .animation(Anim.spring((copied ? 0.15 : 0.4) * motion), value: copied)
        // "Draw" trails the mouse over the card, away from its controls: a click there annotates.
        // Positioned in the card's own coordinates, so it appears where the mouse is.
        .overlay(alignment: .topLeading) {
            if showsDrawHint, let p = pointer {
                DrawHintFollower(point: p)
                    .transition(.asymmetric(insertion: .scale(scale: 0.6, anchor: .bottom).combined(with: .opacity), removal: .opacity))
            }
        }
        .animation(showsDrawHint ? Anim.spring(0.3 * motion, bounce: 0.3) : Anim.spring(0.1 * motion), value: showsDrawHint)
        .zIndex(showsHover ? 1 : 0)   // the hint may hang over the card below
        .scaleEffect(pressed ? ui.pressScale : (showsHover ? ui.hoverScale : 1))
        .animation(Anim.spring(0.25 * motion, bounce: 0.3), value: pressed)
        .animation(Anim.spring(ui.hoverRevealDuration), value: showsHover)
        .animation(Anim.spring(ui.hoverRevealDuration), value: showsButtons)
        // Past the panel's right edge, which sits just beyond the screen edge, so the card slides off screen.
        .offset(x: offscreen ? StackLayout.current.offscreenDistance(cardWidth: card.size.width) : 0)
        .animation(slideAnimation.delay(slideDelay), value: offscreen)
        .onHover { inside in
            model.hoveredCard = inside ? card.id : (model.hoveredCard == card.id ? nil : model.hoveredCard)
        }
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let p): pointer = p
            case .ended: pointer = nil
            }
        }
    }

    private var ui: UITweaks { Settings.shared.motionUI }
    private var motion: Double { Settings.shared.motionScale }
    private var ringColor: Color {
        if selected { return .accentColor }
        if focused { return .white.opacity(0.9) }
        return .white.opacity(ui.cardBorderOpacity)
    }
    private var ringWidth: CGFloat { selected || focused ? max(2, ui.cardBorderWidth) : ui.cardBorderWidth }

    /// Newest (bottom) card first, in and out: the cards nearest the cursor move at once, so a
    /// dismissal feels immediate even when the top of the column is still leaving. The per-card
    /// delay shrinks for tall stacks so the whole column is never slower than `staggerTotalMax`.
    private var slideDelay: Double {
        Double(max(0, index)) * StackView.staggerStep(count: model.cards.count)
    }

    private var slideAnimation: Animation {
        model.slidingOut ? Anim.spring(ui.slideOutDuration) : Anim.swiftUI(ui.slideInCurve, duration: ui.slideInDuration)
    }

    /// Dragging a selected card carries the whole selection, in the order it was selected.
    private func dragURLs() -> [URL] {
        if selected { return model.selectedCards().map(\.shot.url) }
        return [card.shot.url]
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
                Text("\(number)")
                    .font(.system(size: size * 0.6, weight: .bold).monospacedDigit())
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

/// Marks a card an agent pushed in with `add?agent=`.
private struct AgentBadge: View {
    let agent: String
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(Color.purple)
            Image(systemName: Agent.symbol(for: agent)).font(.system(size: size / 2, weight: .bold)).foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
        .help(agent.isEmpty ? "Added by an agent" : "Added by \(agent)")
    }
}

/// Beside the selected cards: the bulk actions, in one vertical strip. `StackLayout` places it
/// and sizes it; the rows here fill that size exactly. The count is on the cards themselves.
private struct SelectionStrip: View {
    @ObservedObject var model: StackModel
    let size: NSSize
    private var ui: UITweaks { Settings.shared.motionUI }

    var body: some View {
        let cards = model.selectedCards()
        VStack(spacing: ui.buttonSpacing) {
            ForEach(Config.stripActions, id: \.id) { action in
                Button { model.onAction(action, cards) } label: {
                    Image(systemName: action.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: ui.buttonSize, height: ui.buttonSize)
                }
                .buttonStyle(TactileButtonStyle(shape: .rounded))
                .help(action.label + shortcutHint(action))
                .disabled(cards.count < action.minimumCount)
                .opacity(cards.count < action.minimumCount ? 0.35 : 1)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.15), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }

    private func shortcutHint(_ action: ShotAction) -> String {
        guard let key = action.key else { return "" }
        var s = " ("
        if key.modifiers.contains(.control) { s += "⌃" }
        if key.modifiers.contains(.option) { s += "⌥" }
        if key.modifiers.contains(.shift) { s += "⇧" }
        if key.modifiers.contains(.command) { s += "⌘" }
        switch key.character {
        case "\r": s += "↩"
        case "\u{7f}": s += "⌫"
        default: s += key.character.uppercased()
        }
        return s + ")"
    }
}

/// Buttons that react to hover and press with a small scale, so they feel physical.
struct TactileButtonStyle: ButtonStyle {
    enum Shape { case circle, rounded, capsule }
    let shape: Shape
    @State private var hovered = false
    private var motion: Double { Settings.shared.motionScale }

    func makeBody(configuration: Configuration) -> some View {
        let fill: AnyShapeStyle = hovered ? AnyShapeStyle(.white.opacity(0.18)) : AnyShapeStyle(.clear)
        return configuration.label
            .foregroundStyle(.primary)
            .background {
                switch shape {
                case .circle: Circle().fill(fill)
                case .rounded: RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill)
                case .capsule: Capsule().fill(fill)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.9 : (hovered ? 1.08 : 1))
            .animation(Anim.spring(0.2 * motion, bounce: 0.3), value: configuration.isPressed)
            .animation(Anim.spring(0.12 * motion), value: hovered)
            .onHover { hovered = $0 }
    }
}

/// Flush over a card after a copy: the veil fades in, the mark springs in, and both fade out.
private struct CopiedOverlay: View {
    let corner: CGFloat
    @State private var landed = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous).fill(.black.opacity(0.55))
            VStack(spacing: 2) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(.green)
                Text("Copied").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            }
            .scaleEffect(landed ? 1 : 0.3)
            .opacity(landed ? 1 : 0)
        }
        .onAppear { withAnimation(Anim.spring(0.4 * Settings.shared.motionScale, bounce: 0.45)) { landed = true } }
        .allowsHitTesting(false)
    }
}

/// Appears at the pointer and then eases after it; the first position is never animated, or the
/// hint would slide in from wherever the view's initial offset was.
private struct DrawHintFollower: View {
    let point: CGPoint
    @State private var shown: CGPoint? = nil
    @State private var width: CGFloat = 0

    var body: some View {
        let p = shown ?? point
        // Centered just above the pointer: a frame from the card's top-left corner to a spot half
        // the hint's width right of the pointer, with the hint aligned to its far corner. Its width
        // is measured, so the hint stays hidden until the first measurement lands.
        DrawHint()
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { width = g.size.width }
                    .onChange(of: g.size.width) { _, new in width = new }
            })
            .opacity(width > 0 ? 1 : 0)
            .frame(width: max(0, p.x + width / 2), height: max(0, p.y - 8), alignment: .bottomTrailing)
            .onAppear { shown = point }
            .onChange(of: point) { _, new in
                withAnimation(Anim.spring(0.18 * Settings.shared.motionScale, bounce: 0.15)) { shown = new }
            }
    }
}

private struct DrawHint: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "scribble.variable").font(.system(size: 11, weight: .semibold))
            Text("Draw").font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(.black.opacity(0.7)))   // plain, unlike the material action buttons
        .fixedSize()
        .allowsHitTesting(false)
    }
}

private struct PillButton: View {
    let symbol: String
    let label: String
    let ui: UITweaks
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: ui.buttonIconSize - 1, weight: .semibold))
                Text(label).font(.system(size: ui.buttonIconSize - 1, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .frame(height: ui.buttonSize)
            .background(Capsule().fill(.regularMaterial))
            .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        }
        .buttonStyle(TactileButtonStyle(shape: .capsule))
    }
}

private struct RoundButton: View {
    let symbol: String
    let help: String
    let ui: UITweaks
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
        }
        .buttonStyle(TactileButtonStyle(shape: .circle))
        .help(help)
    }
}

private struct FeedbackToast: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(text).font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }
}
