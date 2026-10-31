import AppKit

extension LiveNotePopover {
    /// Where the note's words go when the person presses Return.
    enum Target: Equatable {
        /// An agent Vignette keeps running, which draws its answer on the screen (`LiveResponders`).
        case responder(AgentClient)
        /// A working session, through Send. Its answer is drawn beside the ink when it comes.
        case session(AgentDestination)

        var session: AgentDestination? {
            if case .session(let destination) = self { return destination }
            return nil
        }

        var responder: AgentClient? {
            if case .responder(let client) = self { return client }
            return nil
        }

        /// The agent the words go to: the responder's, or the session's.
        var agent: AgentClient {
            switch self {
            case .responder(let client): client
            case .session(let destination): destination.client
            }
        }
    }

    /// An agent a note can be aimed at, as live ink offers it.
    struct Responder: Equatable {
        let client: AgentClient
        /// What the note calls it.
        let name: String
        /// Why it cannot answer, or nil when it can.
        let problem: String?
        /// Whether the note may be aimed at it: false while it is not installed or not signed in.
        let canPick: Bool

        /// Claude, able to answer, as setup's note offers it.
        static let claude = Responder(client: .claude, name: "Claude", problem: nil, canPick: true)
        /// Codex, as setup's note offers it where only Codex can answer.
        static let codex = Responder(client: .codex, name: "Codex", problem: nil, canPick: true)

        /// `agent`, able to answer, as setup's note offers it.
        static func able(_ agent: AgentClient) -> Responder { agent == .codex ? .codex : .claude }
    }

    /// The target a note starts on once its sessions are listed, newest first in `list`: the session
    /// `pick`, else the responder picked by hand on this note, else the one the conversation is with,
    /// else the one used last among those that can answer (`DestinationChoice.responder`), else the
    /// first running session, since only a person starts one, else the first responder, which says why
    /// it cannot answer.
    static func start(pick: AgentDestination?, handPicked: AgentClient?, conversing: AgentClient?,
                      responders: [Responder], list: [AgentDestination]) -> Target {
        if let pick { return .session(pick) }
        let answering = responders.filter(\.canPick).map(\.client)
        let client = handPicked ?? conversing ?? DestinationChoice.responder(among: list, answering: answering)
        if let client { return .responder(client) }
        if let first = list.first { return .session(first) }
        return .responder(responders.first?.client ?? .claude)
    }

    /// The responder a new note starts on, as `start` decides it once `candidates` are listed, with
    /// `remembered` the session the note before went to and no pick yet; nil when it starts on a
    /// session. With no listing, the sessions are taken to be none.
    static func startingResponder(listed candidates: DestinationChoice.Candidates?, remembered: AgentDestination?,
                          conversing: AgentClient?, among responders: [Responder]) -> AgentClient? {
        guard let candidates else { return start(pick: nil, handPicked: nil, conversing: conversing, responders: responders, list: []).responder }
        let answer = DestinationChoice.choose(candidates, for: .liveNote(.remembered(remembered)))
        return start(pick: answer.pick, handPicked: nil, conversing: conversing, responders: responders, list: answer.list).responder
    }

    /// What a note aimed at `responder` says when it cannot answer: why, then the agent that can
    /// answer instead, when one can.
    static func problem(of responder: Responder?, among responders: [Responder]) -> String? {
        guard let responder, let problem = responder.problem else { return nil }
        guard let other = responders.first(where: { $0.client != responder.client && $0.canPick && $0.problem == nil }) else { return problem }
        return "\(problem) \(other.name) can answer instead."
    }

    /// The menu's row for `responder`: picked by `action`, except while it cannot be picked, when the
    /// row has no action and says why under its name.
    static func item(for responder: Responder, selected: Bool, action: Selector, target: AnyObject) -> NSMenuItem {
        // A menu enables any item with an action, so a row that cannot be picked has none.
        let item = NSMenuItem(title: "\(responder.name), on the screen", action: responder.canPick ? action : nil, keyEquivalent: "")
        item.image = SessionMenu.logo(for: responder.client)
        item.state = selected ? .on : .off
        item.representedObject = responder.client.rawValue
        item.target = target
        if let problem = responder.problem {
            item.toolTip = problem
            if #available(macOS 14.4, *) { item.subtitle = problem }
        }
        return item
    }

    /// The menu's row for a session, picked by `action`.
    static func item(for row: SessionMenu.Row, selected: Bool, action: Selector, target: AnyObject) -> NSMenuItem {
        let item = SessionMenu.item(for: row, selected: selected)
        item.action = action
        item.target = target
        item.representedObject = row.destination
        return item
    }

    /// Where a menu of `size` opens: under the target's `button`, or beside the note's `body` when the
    /// `visible` screen has no room below it, so it never covers the words being typed. In AppKit's
    /// screen points, the menu's top-left corner.
    static func menuPoint(_ size: CGSize, under button: CGRect, beside body: CGRect, on visible: CGRect) -> CGPoint {
        let point = CGPoint(x: button.minX, y: button.minY - menuGap)
        guard point.y - size.height < visible.minY + menuGap else { return point }
        let left = body.minX - menuGap - size.width
        return CGPoint(x: left >= visible.minX + menuGap ? left : body.maxX + menuGap,
                       y: max(visible.minY + menuGap, button.minY) + size.height)
    }

    /// Between the target and its list, and between the list and the screen's edge, in points.
    private static let menuGap: CGFloat = 4
}
