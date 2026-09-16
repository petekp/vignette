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
        ZStack(alignment: .bottomTrailing) {
            // Fully transparent pixels let events fall through to the window below, so the stack
            // would only scroll over a card; a hair of alpha makes the whole panel catch them.
            Color.black.opacity(model.isStack ? 0.01 : 0)
            if !model.isStack, let text = model.feedback {
                FeedbackToast(text: text)
                    .padding(StackLayout.current.inset)
                    .transition(.opacity)
            } else {
                column
            }
        }
        .animation(layoutAnimation(0.2), value: model.cards.map(\.id))
        .animation(layoutAnimation(0.15), value: model.inSelectionMode)
        .animation(layoutAnimation(0.15), value: model.feedback)
    }

    /// Layout changes animate only while the cards are on screen. While they are offscreen, in
    /// or out, a toast or bar leaving the column would otherwise shift them as they slide in.
    private func layoutAnimation(_ duration: Double) -> Animation? {
        model.offscreen.isEmpty ? .easeOut(duration: duration * settings.motionScale) : nil
    }

    /// The toast and the selection bar leave with the bottom card instead of vanishing under it.
    private var barSlide: CGFloat {
        model.slidingOut ? StackLayout.current.offscreenDistance(cardWidth: StackLayout.current.maxCardWidth) : 0
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
                    .animation(.easeInOut(duration: settings.motionUI.slideOutDuration), value: model.slidingOut)
            } else if model.isStack && model.inSelectionMode {
                SelectionBar(model: model)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .offset(x: barSlide)
                    .animation(.easeInOut(duration: settings.motionUI.slideOutDuration), value: model.slidingOut)
            }
        }
        .coordinateSpace(name: "stack")
        .offset(y: model.scroll)
        .padding(inset)
        .frame(width: StackLayout.current.maxCardWidth + inset * 2, height: model.viewport + inset * 2, alignment: .bottom)
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
    private var selected: Bool { model.selected.contains(card.id) }
    private var focused: Bool { model.focused == card.id }
    private var isOut: Bool { model.outCards.contains(card.id) }
    private var offscreen: Bool { model.offscreen.contains(card.id) }
    private var hasDraft: Bool { model.drafts.contains(card.shot.url.path) }
    private var showsCircle: Bool { model.isStack && !isOut && (hovered || model.inSelectionMode || focused) }
    private var copied: Bool { model.copied.contains(card.id) }
    private var showsButtons: Bool { hovered && !isOut && !model.inSelectionMode && !copied }
    private var showsDrawHint: Bool { showsButtons && !model.overControl && !pressed }

    var body: some View {
        ZStack {
            if isOut {
                // The card is in the annotator; its slot stays reserved.
                RoundedRectangle(cornerRadius: ui.cardCornerRadius, style: .continuous)
                    .fill(.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: ui.cardCornerRadius, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.white.opacity(0.35)))
            } else {
                Group {
                    if let image = card.image {
                        Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                    } else {
                        Color(white: 0.16)   // thumbnail still decoding
                    }
                }
                    .frame(width: card.size.width, height: card.size.height)
                    .overlay(Color.black.opacity(showsButtons ? ui.hoverDim : 0))
                    .clipShape(RoundedRectangle(cornerRadius: ui.cardCornerRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: ui.cardCornerRadius, style: .continuous).stroke(ringColor, lineWidth: ringWidth))
                    .shadow(color: .black.opacity(ui.cardShadowOpacity), radius: ui.cardShadowRadius, y: ui.cardShadowY)
                    .overlay(
                        // Drag out as files; a plain click goes to the model (annotate, or toggle in selection mode).
                        DragSource(urls: { dragURLs() }, image: card.image ?? NSImage(size: card.size),
                                   onPress: { down in model.pressedCard = down ? card.id : (model.pressedCard == card.id ? nil : model.pressedCard) },
                                   onClick: { model.onClickImage(card) })
                    )
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
            if hasDraft && !isOut {
                DraftBadge(size: ui.selectionCircleSize).padding(6).transition(.opacity)
            }
        }
        .overlay(alignment: .topLeading) {
            if showsCircle {
                SelectionCircle(selected: selected, size: ui.selectionCircleSize)
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
        .overlay {
            if copied && !isOut {
                CopiedOverlay(corner: ui.cardCornerRadius).transition(.opacity)
            }
        }
        .animation(copied ? .easeOut(duration: 0.15) : .easeOut(duration: 0.4), value: copied)
        // "Draw" trails the mouse over the card, away from its controls: a click there annotates.
        // Positioned in the card's own coordinates, so it appears where the mouse is.
        .overlay(alignment: .topLeading) {
            if showsDrawHint, let p = pointer {
                DrawHintFollower(point: p)
                    .transition(.asymmetric(insertion: .scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity), removal: .opacity))
            }
        }
        .animation(showsDrawHint ? .spring(response: 0.3, dampingFraction: 0.68) : .easeOut(duration: 0.1), value: showsDrawHint)
        .zIndex(hovered ? 1 : 0)   // the hint may hang over the card below
        .scaleEffect(pressed ? ui.pressScale : (hovered && !isOut ? ui.hoverScale : 1))
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: pressed)
        .animation(.easeOut(duration: ui.hoverRevealDuration), value: hovered)
        .animation(.easeOut(duration: ui.hoverRevealDuration), value: showsButtons)
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
        model.slidingOut ? .easeInOut(duration: ui.slideOutDuration) : Anim.swiftUI(ui.slideInCurve, duration: ui.slideInDuration)
    }

    /// Dragging a selected card carries the whole selection, oldest first.
    private func dragURLs() -> [URL] {
        if selected { return model.selectedCards().map(\.shot.url) }
        return [card.shot.url]
    }
}

private struct SelectionCircle: View {
    let selected: Bool
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(selected ? Color.accentColor : Color.black.opacity(0.45))
            Circle().stroke(.white, lineWidth: 1.5)
            if selected { Image(systemName: "checkmark").font(.system(size: size / 2, weight: .bold)).foregroundStyle(.white) }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
    }
}

/// Marks a card whose annotations are still in the editor's memory.
private struct DraftBadge: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(Color.orange)
            Image(systemName: "pencil").font(.system(size: size / 2, weight: .bold)).foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
        .help("Has unsaved annotations")
    }
}

/// Under the column while cards are selected: the count and the bulk actions.
private struct SelectionBar: View {
    @ObservedObject var model: StackModel
    var body: some View {
        let cards = model.selectedCards()
        HStack(spacing: 2) {
            Text("\(cards.count)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(minWidth: 20, minHeight: 20)
                .background(Color.accentColor, in: Capsule())
                .padding(.leading, 8)
            Spacer(minLength: 4)
            ForEach(Config.actions.filter(\.showsInBar), id: \.id) { action in
                Button { model.onAction(action, cards) } label: {
                    Image(systemName: action.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 30, height: 28)
                }
                .buttonStyle(TactileButtonStyle(shape: .rounded))
                .help(action.label + shortcutHint(action))
                .disabled(cards.count < action.minimumCount)
                .opacity(cards.count < action.minimumCount ? 0.35 : 1)
            }
        }
        .padding(.horizontal, 4)
        .frame(width: StackLayout.current.maxCardWidth, height: StackLayout.current.barHeight)
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
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovered)
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
        .onAppear { withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) { landed = true } }
        .allowsHitTesting(false)
    }
}

/// Appears at the pointer and then eases after it; the first position is never animated, or the
/// hint would slide in from wherever the view's initial offset was.
private struct DrawHintFollower: View {
    let point: CGPoint
    @State private var shown: CGPoint? = nil

    var body: some View {
        let p = shown ?? point
        // Its bottom-right corner sits just up and left of the pointer: a frame from the card's
        // top-left corner to that spot, with the hint aligned to its far corner.
        DrawHint()
            .frame(width: max(0, p.x - 6), height: max(0, p.y - 6), alignment: .bottomTrailing)
            .onAppear { shown = point }
            .onChange(of: point) { _, new in
                withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.86)) { shown = new }
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
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
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
            .padding(.horizontal, 12)
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
