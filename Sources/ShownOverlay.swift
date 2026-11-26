import SwiftUI

/// What the band across a card's foot says while an agent's shown notice holds it: who showed it and
/// the agent's message.
struct AgentBand: Equatable {
    let agent: String
    let headline: String
    let message: String?

    /// Nil while another notice holds the card, or none does.
    static func of(notice: CardNotices.Notice?) -> AgentBand? {
        guard case .shown(let shown)? = notice else { return nil }
        return AgentBand(agent: shown.agent, headline: shown.headline, message: shown.message)
    }
}

/// The band: the agent's logo and "From vignette", with the agent's message under it. A band of the system's material across the card's foot, as a notification
/// banner is, so the picture the agent pointed at stays in view.
struct ShownOverlay: View {
    let band: AgentBand
    let corner: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                logo
                Text(band.headline).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            }
            if let message = band.message {
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(band.message.map { "\(band.headline): \($0)" } ?? band.headline)
    }

    @ViewBuilder private var logo: some View {
        if let image = Agent.logo(for: band.agent) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(width: 13, height: 13)
        } else {
            Image(systemName: Agent.fallbackSymbol).font(.system(size: 10, weight: .semibold))
        }
    }
}

extension View {
    /// Darkens a card while the cards an agent showed are up and this one is not among them.
    func shownDim(_ dimmed: Bool, ui: UITweaks) -> some View {
        overlay {
            if dimmed {
                RoundedRectangle(cornerRadius: ui.cardCornerRadius, style: .continuous)
                    .fill(.black.opacity(ui.shownDim))
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(Anim.spring(ui.shownDimFade), value: dimmed)
    }
}
