import SwiftUI

/// What the band across a card's foot says, from an agent: a shown card's notice, with Keep and Clear
/// when the agent's marks are on top, or, with no notice up, the marks on top and their Keep and Clear.
/// The buttons follow the marks, so a card that still draws them always offers them.
struct AgentBand: Equatable {
    let agent: String
    let headline: String
    let message: String?
    let offersMarks: Bool

    /// Nil while another notice holds the card, or with neither a shown notice nor marks on top.
    static func of(notice: CardNotices.Notice?, marksFrom agent: String?) -> AgentBand? {
        switch notice {
        case .shown(let shown)?:
            return AgentBand(agent: shown.agent, headline: shown.headline, message: shown.message, offersMarks: agent != nil)
        case nil:
            return agent.map { AgentBand(agent: $0, headline: AgentMarksBar.title($0), message: nil, offersMarks: true) }
        default:
            return nil
        }
    }
}

/// The band: the agent's logo and "From Claude", or "Marks from Claude", the agent's message under it,
/// and Keep and Clear when it offers them. A band of the system's material across the card's foot, as a notification
/// banner is, so the picture the agent pointed at stays in view.
struct ShownOverlay: View {
    let band: AgentBand
    let corner: CGFloat
    let onMarks: (_ keep: Bool) -> Void
    let onOverControl: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                logo
                Text(band.headline).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            }
            if let message = band.message {
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            if band.offersMarks {
                AgentMarksButtons(onMarks: onMarks).onHover(perform: onOverControl).padding(.top, 2)
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

/// Keep and Clear for an agent's marks drawn on top of a screenshot: small push buttons, Keep the
/// default one, as a sheet's buttons are, with Clear before it.
struct AgentMarksButtons: View {
    let onMarks: (_ keep: Bool) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button("Clear") { onMarks(false) }
                .help("Take the agent's marks off")
            Button("Keep") { onMarks(true) }
                .buttonStyle(.borderedProminent)
                .help("Add the agent's marks to your drawing")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
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
