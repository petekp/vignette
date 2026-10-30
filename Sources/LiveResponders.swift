import Foundation

/// Live ink's responders, one for each agent that answers on the screen, Claude Code's and Codex's;
/// which of them can answer; which one the conversation is with; and what each conversation has been
/// sent. The note picks among them (`LiveNotePopover.Target.start`), and the responder never changes
/// under a conversation: until the screen is cleared, a note starts on the agent the last ask went to
/// (docs/adr/0026-codex-answers-live-ink-too.md).
@MainActor
final class LiveResponders {
    private let all: [AgentClient: LiveResponder]
    /// Whether each agent is installed and signed in, as the last check found (`check`).
    private(set) var availability: [AgentClient: LiveResponder.Availability] = [.claude: .checking, .codex: .checking]
    /// The agent the asks since the screen was last cleared went to.
    private(set) var conversing: AgentClient?
    /// The picture each agent's conversation has, and the ids of the text lines sent with it, so a
    /// follow-up about the same window, showing the same text, sends no picture and only the lines
    /// near its ink not sent yet.
    private var pictures: [AgentClient: (conversation: Int, subject: LivePacket.Subject, text: String, lines: Set<String>)] = [:]

    init(drivers: [any ResponderDriver] = [ClaudeDriver(), CodexDriver()]) {
        all = Dictionary(uniqueKeysWithValues: drivers.map { ($0.client, LiveResponder(driver: $0)) })
    }

    /// The agents a note offers, Claude first: Claude always, and Codex unless its check found no
    /// codex. Each says why it cannot answer: its check's answer, else why its process stopped. Only
    /// one that is not installed or not signed in cannot be picked; one that stopped starts again
    /// at the next ask.
    var offers: [LiveNotePopover.Responder] {
        AgentClient.allCases.compactMap { client in
            let checked = availability[client] ?? .checking
            guard let responder = all[client], client == .claude || checked != .notInstalled else { return nil }
            var stopped: String?
            if case .failed(let reason) = responder.state { stopped = reason }
            return LiveNotePopover.Responder(client: client, name: responder.driver.name,
                                             problem: checked.problem(for: client) ?? stopped, canPick: checked.canAnswer)
        }
    }

    /// The agents the last check found unable to answer, which a note opening checks again: the person
    /// may have installed one or signed in since.
    var unable: [AgentClient] { AgentClient.allCases.filter { !(availability[$0]?.canAnswer ?? true) } }

    /// Asks each of `clients` whether it can answer: every agent when live ink turns on, and those
    /// that could not when a note opens. `changed` runs after each answer.
    func check(_ clients: [AgentClient] = AgentClient.allCases, then changed: @escaping () -> Void) {
        for client in clients {
            Task { @MainActor [weak self] in
                let found = await LiveResponder.availability(of: client)
                guard let self else { return }
                availability[client] = found
                Log.write("[live-ink] responder \(found) agent=\(client.rawValue)")
                changed()
            }
        }
    }

    /// Starts `client`'s process ahead of an ask, so its first answer does not wait for a cold start.
    func prepare(_ client: AgentClient) {
        guard availability[client]?.canAnswer ?? false else { return }
        all[client]?.prepare()
    }

    /// Hands `client` the ask, and the conversation goes on with it. Answers why not when it cannot
    /// answer.
    func ask(_ ask: LiveResponder.Ask, to client: AgentClient) -> LiveResponder.Failure? {
        let checked = availability[client] ?? .checking
        guard checked.canAnswer, let responder = all[client] else {
            Log.write("[live-ink] not asking: \(client.rawValue) cannot answer")
            return LiveResponder.Failure(reason: checked.problem(for: client) ?? "", detail: "\(client.rawValue) \(checked)")
        }
        conversing = client
        responder.ask(ask)
        guard !Self.asked(client) else { return nil }
        Settings.shared.update {
            switch client {
            case .claude: $0.liveInkAskedClaude = true
            case .codex: $0.liveInkAskedCodex = true
            }
        }
        return nil
    }

    /// Whether a live ink ask has gone to `client`, which ends the note's line about what it sees.
    static func asked(_ client: AgentClient) -> Bool {
        switch client {
        case .claude: Settings.shared.data.liveInkAskedClaude
        case .codex: Settings.shared.data.liveInkAskedCodex
        }
    }

    /// What an ask about `packet` sends `client`'s conversation `conversation`, with `note` as its words
    /// and `near` the text lines near its ink: the pictures, unless that conversation has this window
    /// with this text already, then the lines it has not been sent, then the ask itself. Answers
    /// whether the pictures went.
    func content(of packet: LivePacket, note: String, ink: [Mark], new: Set<Mark.ID>, near: [LivePacket.Line],
                 to client: AgentClient, conversation: Int) -> (parts: [LiveResponder.Part], fresh: Bool) {
        let last = pictures[client]
        let same = last.map { $0.conversation == conversation && $0.subject == packet.subject && $0.text == packet.textSignature } ?? false
        let sent = same ? last?.lines ?? [] : []
        let unsent = near.filter { !sent.contains($0.id) }
        pictures[client] = (conversation, packet.subject, packet.textSignature, sent.union(unsent.map(\.id)))
        var parts: [LiveResponder.Part] = []
        if !same {
            parts.append(.picture(packet.picture))
            if let detail = packet.detail { parts.append(.picture(detail.png)) }
            for window in packet.alone { parts.append(.picture(window.picture)) }
        }
        if let lines = LivePacket.textLines(unsent) { parts.append(.text(lines)) }
        parts.append(.text(packet.message(note: note, ink: ink, new: new, freshPicture: !same)))
        return (parts, !same)
    }

    /// The ids of the text lines `client`'s conversation has been sent, the only ones its answer may name.
    func linesSent(to client: AgentClient) -> Set<String> { pictures[client]?.lines ?? [] }

    /// Stops the turn under way, whichever agent has it. One with nothing under way does nothing.
    func cancel() { all.values.forEach { $0.cancel() } }

    /// Ends every conversation, as clearing the screen does.
    func stop() {
        all.values.forEach { $0.stop() }
        conversing = nil
        pictures = [:]
    }

    /// For `[state] liveInk.responders`: each agent's process and its check.
    var stateJSON: [String: Any] {
        var json: [String: Any] = ["conversing": conversing?.rawValue ?? NSNull()]
        for (client, responder) in all {
            var state = responder.stateJSON
            state["availability"] = String(describing: availability[client] ?? .checking)
            json[client.rawValue] = state
        }
        return json
    }
}
