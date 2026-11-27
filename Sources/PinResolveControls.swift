import AppKit

/// A pin popover's resolve controls. Over a resolved pin's comments, who resolved it and when, with
/// Reopen. Under an open pin's field, Resolve, which says Reply and Resolve while the field holds words.
@MainActor
final class PinResolveControls: NSObject {
    /// "Resolved by Claude, 1 min. ago", in the secondary label colour, and Reopen at its trailing edge.
    let resolvedLine = NSView()
    /// Resolve at the trailing edge.
    let resolveLine = NSView()
    private let resolvedWords = NSTextField(labelWithString: "")
    private let reopen = NSButton()
    private let resolve = NSButton()
    private let send: (EditorCore.ComposerInput) -> Void

    /// Each line is `width` wide, with at least `gap` between its words and its button.
    init(width: CGFloat, gap: CGFloat, send: @escaping (EditorCore.ComposerInput) -> Void) {
        self.send = send
        super.init()
        resolvedWords.font = .preferredFont(forTextStyle: .subheadline)
        resolvedWords.textColor = .secondaryLabelColor
        resolvedWords.lineBreakMode = .byTruncatingTail
        resolvedWords.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for (button, title, action) in [(reopen, "Reopen", #selector(reopenPressed)), (resolve, "Resolve", #selector(resolvePressed))] {
            button.title = title
            button.bezelStyle = .push
            button.controlSize = .small
            button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            button.target = self
            button.action = action
        }
        Self.lay(resolvedLine, leading: resolvedWords, trailing: reopen, width: width, gap: gap)
        Self.lay(resolveLine, leading: nil, trailing: resolve, width: width, gap: gap)
    }

    /// Who resolved `pin`, said as of `now`, or Resolve, which a new pin goes without.
    func show(_ pin: Pin, now: Date) {
        if let resolution = pin.resolved {
            let ago = PinHoverCard.Words.ago(resolution.at, now: now)
            resolvedWords.stringValue = (["Resolved by \(PinHoverCard.Words.resolver(resolution))", ago].compactMap { $0 }).joined(separator: ", ")
        }
        resolvedLine.isHidden = pin.resolved == nil
        resolveLine.isHidden = pin.resolved != nil || pin.number == 0
    }

    /// Resolve says Reply and Resolve while the field holds words.
    func showReplying(_ replying: Bool) {
        let title = replying ? "Reply and Resolve" : "Resolve"
        if resolve.title != title { resolve.title = title }
    }

    @objc private func resolvePressed() { send(.resolve) }
    @objc private func reopenPressed() { send(.reopen) }

    /// `row`, `width` wide, with `leading` and `trailing` on its centre line.
    private static func lay(_ row: NSView, leading: NSView?, trailing: NSView, width: CGFloat, gap: CGFloat) {
        for view in [leading, trailing].compactMap({ $0 }) {
            view.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(view)
        }
        var constraints = [row.widthAnchor.constraint(equalToConstant: width),
                           trailing.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                           trailing.topAnchor.constraint(equalTo: row.topAnchor), trailing.bottomAnchor.constraint(equalTo: row.bottomAnchor)]
        if let leading {
            constraints += [leading.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                            leading.centerYAnchor.constraint(equalTo: trailing.centerYAnchor),
                            leading.trailingAnchor.constraint(lessThanOrEqualTo: trailing.leadingAnchor, constant: -gap)]
        }
        for constraint in constraints { constraint.isActive = true }
    }
}
