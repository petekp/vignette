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
    static let glyphSize: CGFloat = 0.42
    static let glyphGap: CGFloat = 0.12
    static let glyphSide: CGFloat = 0.5

    var fullWidth: CGFloat { size * (Self.padding * 2 + Self.logoSide + Self.gap) + textWidth }
    /// The narrowest card that shows the words: the capsule, the selection circle, which is `size`
    /// across, and `inset` at both edges and between the two.
    var cardWidthForWords: CGFloat { fullWidth + size + Self.inset * 3 }

    func folds(cardWidth: CGFloat, wasFolded: Bool) -> Bool {
        cardWidth < cardWidthForWords + (wasFolded ? Self.hysteresis : 0)
    }

    /// The folded tab with a glyph beside the logo: the logo's circle, the gap and the glyph.
    var foldedWidthWithGlyph: CGFloat { size * (1 + Self.glyphGap + Self.glyphSide) }

    /// Whether a folded tab keeps its glyph: only while it stays clear of the selection circle, by the
    /// same margins as the words. Narrower, it is the logo alone.
    func keepsGlyph(cardWidth: CGFloat) -> Bool {
        cardWidth >= foldedWidthWithGlyph + size + Self.inset * 3
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

/// Marks a card an agent pushed in with `add?agent=`, or a card that was sent (`Card.Sent`): a white
/// tab saying who or where, with the vendor's logo when the bundle has one (`Agent.logo(for:)`). On a
/// card too narrow for the words it folds to the logo, alone in a circle or beside `glyph`
/// (`AgentBadgeFit`); its trailing edge stays put and the words fade as the capsule closes over them.
struct AgentBadge: View {
    /// The vendor whose logo the tab shows.
    let agent: String
    /// "From Claude", "Sent to vignette", "From Claude · Replied".
    let label: String
    /// An SF Symbol the folded tab keeps beside the logo: a paper plane for sent, a check for replied.
    var glyph: String? = nil
    let size: CGFloat
    /// The card's width as drawn: the stack's narrowing included.
    let cardWidth: CGFloat
    /// The spring a fold runs on when the change that caused it carries none, as a zoom's does.
    let foldDuration: Double
    /// A send the session still holds in its queue: a clock follows the words, and Don't send takes
    /// its place while the pointer is on the tab.
    var queued: Card.Queued? = nil
    var onUnsend: () -> Void = {}
    var onOverControl: (Bool) -> Void = { _ in }
    @State private var wasFolded = false
    @State private var hovered = false

    var body: some View {
        let words = AgentBadgeFit.of(label, size: size)
        // The clock takes the room a folded tab's glyph takes, beside the words or the logo alone.
        let fit = queued == nil ? words
            : AgentBadgeFit(size: size, textWidth: words.textWidth + size * (AgentBadgeFit.glyphGap + AgentBadgeFit.glyphSide))
        let folded = fit.folds(cardWidth: cardWidth, wasFolded: wasFolded)
        let showsGlyph = folded && glyph != nil && fit.keepsGlyph(cardWidth: cardWidth)
        let showsQueued = queued != nil && (!folded || fit.keepsGlyph(cardWidth: cardWidth))
        HStack(spacing: folded ? 0 : size * AgentBadgeFit.gap) {
            logo.frame(width: size * AgentBadgeFit.logoSide, height: size * AgentBadgeFit.logoSide)
            Text(label).font(.system(size: AgentBadgeFit.textSize(size), weight: .semibold))
                .foregroundStyle(.black.opacity(0.85)).lineLimit(1).fixedSize()
                .frame(width: folded ? 0 : nil, alignment: .trailing)
                .clipped()
                .opacity(folded ? 0 : 1)
            if showsGlyph, let glyph {
                Image(systemName: glyph).font(.system(size: size * AgentBadgeFit.glyphSize, weight: .heavy))
                    .foregroundStyle(.black.opacity(0.8))
                    .frame(width: size * AgentBadgeFit.glyphSide)
                    .padding(.leading, size * AgentBadgeFit.glyphGap)
                    .transition(.opacity)
            }
            if showsQueued, let queued {
                QueuedMark(queued: queued, size: size, revealed: hovered, onUnsend: onUnsend, onOverControl: onOverControl)
                    .padding(.leading, folded ? size * AgentBadgeFit.glyphGap : 0)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, size * (folded ? AgentBadgeFit.foldedPadding : AgentBadgeFit.padding))
        .frame(height: size)
        // A hairline edge and a deep shadow: the tab lands on light images too, a white wordmark included.
        .background(Capsule().fill(.white).overlay(Capsule().strokeBorder(.black.opacity(0.22), lineWidth: 0.75)))
        .shadow(color: .black.opacity(0.5), radius: 5, y: 1.5)
        .accessibilityElement(children: queued == nil ? .ignore : .contain)
        .accessibilityLabel(queued.map { "\(label). \($0.reason)" } ?? label)
        .onHover { over in
            guard queued != nil else { return }
            withAnimation(Anim.spring(0.15 * Settings.shared.motionScale)) { hovered = over }
        }
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

/// The clock on a queued send's tab, which turns into Don't send while the pointer is on the tab, and
/// into a spinner while Don't send takes the line out. Its help is why the session holds the line.
private struct QueuedMark: View {
    let queued: Card.Queued
    let size: CGFloat
    let revealed: Bool
    let onUnsend: () -> Void
    let onOverControl: (Bool) -> Void

    var body: some View {
        let showsButton = revealed && !queued.withdrawing
        Button(action: onUnsend) {
            ZStack {
                Image(systemName: "clock.fill").font(.system(size: size * 0.5, weight: .bold)).foregroundStyle(Color.orange)
                    .opacity(showsButton || queued.withdrawing ? 0 : 1)
                Image(systemName: "xmark.circle.fill").font(.system(size: size * 0.58, weight: .bold))
                    .symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.6))
                    .opacity(showsButton ? 1 : 0)
                if queued.withdrawing {
                    ProgressView().controlSize(.mini).scaleEffect(0.7).transition(.opacity)
                }
            }
            .frame(width: size * AgentBadgeFit.glyphSide, height: size)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(queued.withdrawing)
        .help(queued.reason)
        .accessibilityLabel("Don't send")
        .onHover(perform: onOverControl)
    }
}

/// What a card's tab says: the agent the card is from, the session it was sent to, or that it was
/// sent back to the session it came from (`Card.Sent`).
struct CardTab: Equatable {
    let agent: String
    let label: String
    let glyph: String?
    /// Set while the session holds the send's line in its queue: the tab offers Don't send.
    var queued: Card.Queued? = nil

    /// Nil for a card with no tab: a person's screenshot that was never sent.
    init?(_ card: Card) {
        switch (card.agent, card.sent) {
        case (let agent?, .replied?):
            (self.agent, label, glyph) = (agent, Agent.label(for: agent) + " · Replied", "checkmark")
        case (let agent?, _):
            (self.agent, label, glyph) = (agent, Agent.label(for: agent), nil)
        case (nil, .to(let client, let title)?):
            (self.agent, label, glyph) = (client.rawValue, "Sent to " + title, "paperplane.fill")
        case (nil, .queued(let client, let title, let queued)?):
            (self.agent, label, glyph) = (client.rawValue, "Queued for " + title, nil)
            self.queued = queued
        case (nil, .replied?), (nil, nil):
            return nil
        }
    }
}
