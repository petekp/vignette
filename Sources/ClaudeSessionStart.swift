import Foundation

/// The session starts under way, each with the sends waiting for its answer. Every copy of a
/// `ClaudeCodeConnection` shares one, and each send starts on its own pool thread, so it is locked.
final class SessionStartsUnderWay: @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [String: [@Sendable (ClaudeCodeConnection.StartAnswer) -> Void]] = [:]

    /// Adds `answer` to the start of `session`. True when no start of it was under way, so the
    /// caller runs this one.
    func join(_ session: String, answer: @escaping @Sendable (ClaudeCodeConnection.StartAnswer) -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let first = waiting[session] == nil
        waiting[session, default: []].append(answer)
        return first
    }

    /// The start of `session` answered: every send waiting for it gets that answer, and the next
    /// send to it starts again.
    func finish(_ session: String, with result: ClaudeCodeConnection.StartAnswer) {
        lock.lock()
        let answers = waiting.removeValue(forKey: session) ?? []
        lock.unlock()
        for answer in answers { answer(result) }
    }
}

/// Starting a Claude Code session that is not running, for a send to it.
extension ClaudeCodeConnection {
    /// Whether a started session came up: the inbox that holds it, or what the send comes to.
    enum StartAnswer {
        case up(Inbox)
        case failed(SubmissionOutcome)
    }

    /// Starts session `session` in a new Herdr tab and answers once a live inbox holds it, looking
    /// every `startPoll` for up to `startTimeout`. Only the inbox folders made since the launch are
    /// looked at, and only their `session` file until one names it. It blocks on herdr to launch.
    /// A send for a session already starting waits for that start's answer instead.
    func startSession(_ start: SessionStart, session: String, answer: @escaping @Sendable (StartAnswer) -> Void) {
        guard UUID(uuidString: session) != nil else {
            return answer(.failed(.notSubmitted(code: .noAgent, detail: "not a session id: \(session)", reason: SubmissionOutcome.internalReason)))
        }
        // A second process on one session would fork it.
        guard startsUnderWay.join(session, answer: answer) else { return Log.write("[send] session \(session) is starting; waiting for it") }
        let answer: @Sendable (StartAnswer) -> Void = { [startsUnderWay] in startsUnderWay.finish(session, with: $0) }
        // Resumed by hand since it was listed, or up since a start that just answered.
        if let inbox = liveInbox(holding: session) { return answer(.up(inbox)) }
        let before = Set(Self.folders(in: inboxes).map(\.lastPathComponent))
        let began = now()
        switch launch(start, session) {
        case .failed(let detail):
            return answer(.failed(.notSubmitted(code: .sendFailed, detail: "could not start \(session) in \(start.folder): \(detail)",
                                                reason: Self.notStarted)))
        case .started(let tab, let terminal):
            Log.write("[send] started claude \(start.arguments(session: session).joined(separator: " ")) in \(start.folder) tab=\(tab) terminal=\(terminal)")
        }
        look(for: session, in: start, besides: before, since: began, answer: answer)
    }

    private func look(for session: String, in start: SessionStart, besides before: Set<String>, since began: Date,
                      answer: @escaping @Sendable (StartAnswer) -> Void) {
        let made = Self.folders(in: inboxes).filter { !before.contains($0.lastPathComponent) }
        let holding = made.lazy.filter { folder in
            (try? String(contentsOf: folder.appendingPathComponent("session"), encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) == session
        }.compactMap(Self.inbox(at:)).first(where: isLive)
        if let holding {
            Log.write("[send] session \(session) came up after=\(Int(now().timeIntervalSince(began) * 1000))ms")
            return answer(.up(holding))
        }
        guard now().timeIntervalSince(began) < Self.startTimeout else {
            return answer(.failed(.notSubmitted(code: .noAgent, detail: "session \(session) had no live inbox \(Int(Self.startTimeout)) s after it was started in \(start.folder)",
                                                reason: Self.notUpInTime)))
        }
        later(Self.startPoll) { look(for: session, in: start, besides: before, since: began, answer: answer) }
    }
}
