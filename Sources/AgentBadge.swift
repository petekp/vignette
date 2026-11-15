import SwiftUI

/// Whether a card's agent badge says who it is from or folds to the logo alone. The badge shows its
/// words only while the whole capsule fits inside the card with `inset` on both sides and clear of
/// the selection circle in the other top corner, so it never reaches past the card's edge or under
/// the circle, however narrow the stack or the card's shape makes the card.
struct AgentBadgeFit {
    /// The capsule's height, which is also the folded badge's diameter.
    let size: CGFloat
    /// The words' width, rounded up (`ButtonLabel.width`), so the rule never lets through a capsule
    /// a hair wider than it measured.
    let textWidth: CGFloat

    /// The badge's margin from the card's edges: the padding every corner control is given.
    static let inset = CardView.buttonPad
    /// How much more room than it needs a folded badge waits for before it unfolds. A pinch zoom
    /// moves the stack's width with the fingers, a hundredth of the card box at a time (1.88 pt at the
    /// default 188 pt box), and a hand held near the threshold would otherwise fold and unfold the
    /// badge with each step.
    static let hysteresis: CGFloat = 4

    static let logoSide: CGFloat = 0.62
    static let gap: CGFloat = 0.22
    static let padding: CGFloat = 0.4
    static let foldedPadding: CGFloat = (1 - logoSide) / 2

    var fullWidth: CGFloat { size * (Self.padding * 2 + Self.logoSide + Self.gap) + textWidth }
    /// The narrowest card that shows the words: the capsule, the selection circle, which is `size`
    /// across, and `inset` at both edges and between the two.
    var cardWidthForWords: CGFloat { fullWidth + size + Self.inset * 3 }

    func folds(cardWidth: CGFloat, wasFolded: Bool) -> Bool {
        cardWidth < cardWidthForWords + (wasFolded ? Self.hysteresis : 0)
    }

    /// The fit for `label` at `size`. The words are measured once per label and size: the stack
    /// asks on every frame while it narrows, for every card it has built.
    @MainActor static func of(_ label: String, size: CGFloat) -> AgentBadgeFit {
        let key = TextKey(label: label, size: size)
        if let width = textWidths[key] { return AgentBadgeFit(size: size, textWidth: width) }
        let width = ButtonLabel.width(label, size: textSize(size))
        textWidths[key] = width
        return AgentBadgeFit(size: size, textWidth: width)
    }

    static func textSize(_ size: CGFloat) -> CGFloat { size * 0.55 }

    private struct TextKey: Hashable {
        let label: String
        let size: CGFloat
    }
    @MainActor private static var textWidths: [TextKey: CGFloat] = [:]
}

/// Marks a card an agent pushed in with `add?agent=`: a white tab saying who, with the vendor's
/// logo when the bundle has one (`Agent.logo(for:)`). On a card too narrow for the words it folds
/// to the logo alone in a circle (`AgentBadgeFit`); its trailing edge stays put and the words fade
/// as the capsule closes over them.
struct AgentBadge: View {
    let agent: String
    let size: CGFloat
    /// The card's width as drawn: the stack's narrowing included.
    let cardWidth: CGFloat
    /// The spring a fold runs on when the change that caused it carries none, as a zoom's does.
    let foldDuration: Double
    @State private var wasFolded = false

    var body: some View {
        let label = Agent.label(for: agent)
        let folded = AgentBadgeFit.of(label, size: size).folds(cardWidth: cardWidth, wasFolded: wasFolded)
        HStack(spacing: folded ? 0 : size * AgentBadgeFit.gap) {
            logo.frame(width: size * AgentBadgeFit.logoSide, height: size * AgentBadgeFit.logoSide)
            Text(label).font(.system(size: AgentBadgeFit.textSize(size), weight: .semibold))
                .foregroundStyle(.black.opacity(0.85)).lineLimit(1).fixedSize()
                .frame(width: folded ? 0 : nil, alignment: .trailing)
                .clipped()
                .opacity(folded ? 0 : 1)
        }
        .padding(.horizontal, size * (folded ? AgentBadgeFit.foldedPadding : AgentBadgeFit.padding))
        .frame(height: size)
        // A hairline edge and a deep shadow: the tab lands on light images too, a white wordmark included.
        .background(Capsule().fill(.white).overlay(Capsule().strokeBorder(.black.opacity(0.22), lineWidth: 0.75)))
        .shadow(color: .black.opacity(0.5), radius: 5, y: 1.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        // A fold that comes with the stack's own spring rides it, so the capsule and the card move in
        // step and the capsule stays inside the card all the way. A zoom sets the width with
        // animations disabled, and the fold brings its own spring.
        .transaction(value: folded) { transaction in
            guard transaction.animation == nil || transaction.disablesAnimations else { return }
            transaction.disablesAnimations = false
            transaction.animation = Anim.spring(foldDuration)
        }
        .onChange(of: folded, initial: true) { _, now in wasFolded = now }
    }

    @ViewBuilder private var logo: some View {
        if let logo = Agent.logo(for: agent) {
            // The tab is white in either appearance, so a one-colour logo is drawn black like the name.
            Image(nsImage: logo).resizable().aspectRatio(contentMode: .fit)
                .foregroundStyle(.black.opacity(0.85))
        } else {
            Image(systemName: Agent.fallbackSymbol).font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(.black.opacity(0.8))
        }
    }
}
