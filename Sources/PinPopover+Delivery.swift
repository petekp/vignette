import AppKit

/// What the open pin's popover says about its comments reaching a session (ADR 0035, look A): each
/// comment's state on its top line, a row while the turn a comment started runs, and the session a
/// new comment goes to in the field's placeholder.
struct PinLiveComments: Equatable {
    var shown: [UUID: CommentDeliveries.Shown] = [:]
    /// The agent whose turn, started by a comment on this pin, is running.
    var working: AgentClient?
    /// The session a comment posted now goes to, as "Claude · vignette". Nil when it stays on the pin.
    var target: String?

    /// What a person calls the agent in these words.
    static func name(of client: AgentClient) -> String { client == .claude ? "Claude" : "Codex" }
}

extension CommentDeliveries.Shown {
    /// The words after the comment's time (`docs/voice.md`).
    var words: String {
        let agent = PinLiveComments.name(of: client)
        switch state {
        case .sending: return "Sending to \(agent)"
        case .sent: return "Sent to \(agent)"
        case .queued: return "Queued for \(agent)"
        case .uncertain: return "Not confirmed"
        case .failed: return "Not sent"
        }
    }

    /// The reason said under the comment's words, for a line that did not go or that Codex still holds.
    var note: String? {
        switch state {
        case .sending, .sent: return nil
        case .queued, .uncertain, .failed: return reason
        }
    }
}

extension PinPopover {
    /// The row under the comments while the turn a comment started runs: the agent's avatar, the
    /// system's small spinner, and "Claude is working". The spinner stands still at `ui.motion` 0 and
    /// under Reduce Motion.
    static func workingRow(_ client: AgentClient, avatarSize: CGFloat, gap: CGFloat) -> NSView {
        let avatar = NSImageView()
        avatar.imageScaling = .scaleProportionallyUpOrDown
        avatar.wantsLayer = true
        avatar.layer?.cornerRadius = avatarSize / 2
        avatar.layer?.masksToBounds = true
        PinHoverCard.paint(avatar, as: .agent(client.rawValue))
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = true
        if Settings.shared.motionScale > 0 { spinner.startAnimation(nil) }
        let words = NSTextField(labelWithString: "\(PinLiveComments.name(of: client)) is working")
        words.font = .preferredFont(forTextStyle: .subheadline)
        words.textColor = .secondaryLabelColor
        let row = NSStackView(views: [avatar, words, spinner])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = gap
        for view in [avatar, spinner] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalToConstant: avatarSize).isActive = true
            view.heightAnchor.constraint(equalToConstant: avatarSize).isActive = true
        }
        row.setAccessibilityElement(true)
        row.setAccessibilityRole(.staticText)
        row.setAccessibilityLabel(words.stringValue)
        return row
    }

    /// A comment's words, with `note` under them in the secondary grey.
    static func words(_ text: String, note: String?, color: NSColor) -> NSAttributedString {
        let body = NSFont.preferredFont(forTextStyle: .body)
        let words = NSMutableAttributedString(string: text, attributes: [.font: body, .foregroundColor: color])
        if let note {
            words.append(NSAttributedString(string: "\n" + note, attributes: [
                .font: NSFont.preferredFont(forTextStyle: .subheadline), .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }
        return words
    }
}
