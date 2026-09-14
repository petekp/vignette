import SwiftUI

struct StackView: View {
    @ObservedObject var model: StackModel

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
            if let card = model.expandingCard {
                ExpandingCard(card: card)
            } else if let text = model.feedback {
                FeedbackToast(text: text)
                    .padding(StackLayout.inset)
                    .transition(.opacity)
            } else {
                VStack(alignment: .trailing, spacing: StackLayout.spacing) {
                    ForEach(model.cards.reversed()) { card in
                        CardView(card: card, model: model)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(StackLayout.inset)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.cards.map(\.id))
    }
}

/// The card while it grows into the annotation window. Fills the panel, keeps aspect.
private struct ExpandingCard: View {
    let card: Card
    var body: some View {
        Image(nsImage: card.image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CardView: View {
    let card: Card
    @ObservedObject var model: StackModel
    private var hovered: Bool { model.hoveredCard == card.id }

    var body: some View {
        ZStack(alignment: .bottom) {
            Image(nsImage: card.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: card.size.width, height: card.size.height)
                .background(Color(white: 0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(0.7), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                .scaleEffect(hovered ? 1.03 : 1)
                .contentShape(Rectangle())
                .onTapGesture { model.onAnnotate(card) }

            if hovered {
                HStack(spacing: 8) {
                    RoundButton(symbol: "doc.on.doc", help: "Copy") { model.onCopy(card) }
                    RoundButton(symbol: "pencil.tip.crop.circle", help: "Annotate") { model.onAnnotate(card) }
                    RoundButton(symbol: "trash", help: "Delete") { model.onDelete(card) }
                }
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: card.size.width, height: card.size.height)
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) {
                model.hoveredCard = inside ? card.id : (model.hoveredCard == card.id ? nil : model.hoveredCard)
            }
        }
    }
}

private struct RoundButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.black.opacity(hovered ? 0.85 : 0.6)))
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
