import AppKit

/// The line over a resolved pin's comments: who resolved it and when, in the secondary label colour,
/// from the writers' names' left edge (`PinPopover.wordsIndent`). The ✓ that resolves and reopens the
/// pin ends its first comment's top line (`CommentRow`, `ResolveAction`).
@MainActor
final class PinResolveControls {
    /// "Resolved by Claude, 1 min. ago".
    let resolvedLine = NSView()
    private let resolvedWords = NSTextField(labelWithString: "")

    /// The line is `width` wide.
    init(width: CGFloat) {
        resolvedWords.font = .preferredFont(forTextStyle: .subheadline)
        resolvedWords.textColor = .secondaryLabelColor
        resolvedWords.lineBreakMode = .byTruncatingTail
        resolvedWords.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        resolvedWords.translatesAutoresizingMaskIntoConstraints = false
        resolvedLine.addSubview(resolvedWords)
        [resolvedLine.widthAnchor.constraint(equalToConstant: width),
                                     resolvedWords.leadingAnchor.constraint(equalTo: resolvedLine.leadingAnchor, constant: PinPopover.wordsIndent),
                                     resolvedWords.trailingAnchor.constraint(lessThanOrEqualTo: resolvedLine.trailingAnchor),
                                     resolvedWords.topAnchor.constraint(equalTo: resolvedLine.topAnchor),
                                     resolvedWords.bottomAnchor.constraint(equalTo: resolvedLine.bottomAnchor)].forEach { $0.isActive = true }
    }

    /// Who resolved `pin`, said as of `now`, a change fading over `duration`.
    func show(_ pin: Pin, now: Date, over duration: Double) {
        guard let resolution = pin.resolved else { return }
        let ago = PinHoverCard.Words.ago(resolution.at, now: now)
        let words = (["Resolved by \(PinHoverCard.Words.resolver(resolution))", ago].compactMap { $0 }).joined(separator: ", ")
        guard resolvedWords.stringValue != words else { return }
        PopoverFade.change(resolvedWords, over: duration) { resolvedWords.stringValue = words }
    }
}

/// What the ✓ on a pin's first comment does when pressed.
enum ResolveAction: Equatable {
    /// Resolves the open pin, posting the field's words first while it holds some.
    case resolve(replying: Bool)
    /// Reopens the resolved pin, posting the field's words first while it holds some.
    case reopen

    var symbol: String {
        switch self {
        case .resolve: "checkmark.circle"
        case .reopen: "checkmark.circle.fill"
        }
    }

    /// Its tooltip.
    var help: String {
        switch self {
        case .resolve(replying: false): "Resolve pin. It turns grey and is left out of copies and Send."
        case .resolve(replying: true): "Post your reply and resolve the pin"
        case .reopen: "Reopen"
        }
    }

    /// Its name to VoiceOver.
    var name: String {
        switch self {
        case .resolve(replying: false): "Resolve pin"
        case .resolve(replying: true): "Reply and resolve pin"
        case .reopen: "Reopen pin"
        }
    }
}
