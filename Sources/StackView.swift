import SwiftUI

struct StackView: View {
    @ObservedObject var model: StackModel
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
            if !model.isStack, let text = model.feedback {
                FeedbackToast(text: text)
                    .padding(StackLayout.inset)
                    .transition(.opacity)
            } else {
                VStack(alignment: .trailing, spacing: StackLayout.spacing) {
                    ForEach(Array(model.cards.enumerated().reversed()), id: \.element.id) { index, card in
                        CardView(card: card, index: index, model: model)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                    if model.isStack, let text = model.feedback {
                        FeedbackToast(text: text)
                            .frame(height: StackLayout.barHeight)
                            .transition(.opacity)
                    } else if model.isStack && model.inSelectionMode {
                        SelectionBar(model: model)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(StackLayout.inset)
                .coordinateSpace(name: "stack")
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.cards.map(\.id))
        .animation(.easeOut(duration: 0.15), value: model.inSelectionMode)
        .animation(.easeOut(duration: 0.15), value: model.feedback)
    }
}

private struct CardView: View {
    let card: Card
    let index: Int      // 0 = newest, at the bottom
    @ObservedObject var model: StackModel
    private var hovered: Bool { model.hoveredCard == card.id }
    private var selected: Bool { model.selected.contains(card.id) }
    private var focused: Bool { model.focused == card.id }
    private var isOut: Bool { model.outCards.contains(card.id) }
    private var offscreen: Bool { model.offscreen.contains(card.id) }
    private var showsCircle: Bool { model.isStack && !isOut && (hovered || model.inSelectionMode || focused) }
    private var showsButtons: Bool { hovered && !isOut && !model.inSelectionMode }

    var body: some View {
        ZStack(alignment: .bottom) {
            if isOut {
                // The card is in the annotator; its slot stays reserved.
                RoundedRectangle(cornerRadius: ui.cardCornerRadius, style: .continuous)
                    .fill(.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: ui.cardCornerRadius, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.white.opacity(0.35)))
                    .frame(width: card.size.width, height: card.size.height)
            } else {
                Image(nsImage: card.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: card.size.width, height: card.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: ui.cardCornerRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: ui.cardCornerRadius, style: .continuous).stroke(ringColor, lineWidth: ringWidth))
                    .shadow(color: .black.opacity(ui.cardShadowOpacity), radius: ui.cardShadowRadius, y: ui.cardShadowY)
                    .scaleEffect(hovered && !model.inSelectionMode ? ui.hoverScale : 1)
                    .overlay(
                        // Drag out as files; a plain click goes to the model (annotate, or toggle in selection mode).
                        DragSource(urls: { dragURLs() }, image: card.image) { model.onClickImage(card) }
                    )
            }

            if showsButtons {
                HStack(spacing: ui.buttonSpacing) {
                    ForEach(Config.actions.filter(\.showsOnCard), id: \.id) { action in
                        RoundButton(symbol: action.symbol, help: action.label, ui: ui) { model.onAction(action, [card]) }
                    }
                }
                .padding(.bottom, ui.buttonBottomPadding)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .topLeading) {
            if showsCircle {
                SelectionCircle(selected: selected, size: ui.selectionCircleSize)
                    .padding(6)
                    .transition(.opacity)
                    // A press toggles; dragging from here sweeps selection down or up the column.
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("stack"))
                            .onChanged { value in
                                model.onSweep(value.location.y + StackLayout.inset)
                            }
                            .onEnded { _ in model.onSweepEnd() }
                    )
            }
        }
        .frame(width: card.size.width, height: card.size.height)
        // Past the panel's right edge, which sits just beyond the screen edge, so the card slides off screen.
        .offset(x: offscreen ? card.size.width + StackLayout.inset + StackLayout.margin : 0)
        .animation(slideAnimation.delay(slideDelay), value: offscreen)
        .onHover { inside in
            withAnimation(.easeOut(duration: ui.hoverRevealDuration)) {
                model.hoveredCard = inside ? card.id : (model.hoveredCard == card.id ? nil : model.hoveredCard)
            }
        }
    }

    private var ui: UITweaks { Settings.shared.data.ui }
    private var ringColor: Color {
        if selected { return .accentColor }
        if focused { return .white.opacity(0.9) }
        return .white.opacity(ui.cardBorderOpacity)
    }
    private var ringWidth: CGFloat { selected || focused ? max(2, ui.cardBorderWidth) : ui.cardBorderWidth }

    /// Entrance: newest (bottom) card first. Exit: oldest (top) card first.
    private var slideDelay: Double {
        let order = model.slidingOut ? (model.cards.count - 1 - index) : index
        return Double(max(0, order)) * ui.staggerDelay
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

private struct SelectionBar: View {
    @ObservedObject var model: StackModel
    var body: some View {
        let cards = model.selectedCards()
        HStack(spacing: 4) {
            Text("\(cards.count) selected")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
            ForEach(Config.actions.filter(\.showsInBar), id: \.id) { action in
                Button { model.onAction(action, cards) } label: {
                    Image(systemName: action.symbol).font(.system(size: 12, weight: .semibold)).frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help(action.label + shortcutHint(action))
                .disabled(cards.count < action.minimumCount)
                .opacity(cards.count < action.minimumCount ? 0.35 : 1)
            }
        }
        .padding(.horizontal, 6)
        .frame(width: StackLayout.maxCardWidth, height: StackLayout.barHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.2), lineWidth: 0.5))
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

private struct RoundButton: View {
    let symbol: String
    let help: String
    let ui: UITweaks
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: ui.buttonIconSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: ui.buttonSize, height: ui.buttonSize)
                .background(Circle().fill(.black.opacity(hovered ? ui.buttonHoverOpacity : ui.buttonOpacity)))
                .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovered = $0 }
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
