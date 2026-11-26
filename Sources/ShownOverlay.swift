import SwiftUI

/// What a card an agent showed says: the agent's logo and "From Claude", the agent's message under
/// it, and Keep and Clear when the agent brought marks. A band of the system's material across the
/// card's foot, as a notification banner is, so the picture the agent pointed at stays in view.
struct ShownOverlay: View {
    let shown: Shown
    let hasMarks: Bool
    let corner: CGFloat
    let onMarks: (_ keep: Bool) -> Void
    let onOverControl: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                logo
                Text(shown.headline).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            }
            if let message = shown.message {
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            if hasMarks {
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
        .accessibilityLabel(shown.message.map { "\(shown.headline): \($0)" } ?? shown.headline)
    }

    @ViewBuilder private var logo: some View {
        if let image = Agent.logo(for: shown.agent) {
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
