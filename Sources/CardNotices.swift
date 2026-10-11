import Foundation

/// What a card sent to an agent shows: where it went and how the delivery went.
struct SendNotice: Equatable {
    /// `inGrace`: the send is stored and its line has not gone to the client; the card shows the grace
    /// running out and a way to cancel (`Grace`).
    /// `replyFailed`: the agent's reply to this send arrived and could not be made a card.
    /// `queued`: the client holds the send, but nothing reads it until the session is opened.
    /// `done`: the session's turn on a live ink note ended with nothing to show as a result card.
    enum State: Equatable { case inGrace, sending, sent, queued, uncertain, failed, replyFailed, done }
    let request: String   // the request's id, so an answer to an earlier send is never taken for this one's
    let client: AgentClient
    let project: String
    var state: State
    /// What went wrong and what to do about it, once a delivery has failed or gone unconfirmed.
    var reason: String? = nil
    /// Set while `inGrace`.
    var grace: Grace? = nil

    /// A send's grace period, in `ProcessInfo.systemUptime` seconds: the clock of the deadline the
    /// request will be handed over at, so a card shown late still counts down to the same moment.
    struct Grace: Equatable {
        let deadline: TimeInterval
        let length: TimeInterval

        /// How much of the grace is left at `now`: 1 at its start, 0 at the deadline, clamped.
        func remaining(at now: TimeInterval) -> Double {
            guard length > 0 else { return 0 }
            return min(1, max(0, (deadline - now) / length))
        }
    }

    /// The states a card shows, in order, when its notice goes from `previous` to `next`. A line that
    /// went and was answered in one turn still shows Sending in between.
    static func steps(from previous: State, to next: State) -> [State] {
        previous == .inGrace && next != .sending ? [.sending, next] : [next]
    }
}

/// What a card says about something that happened to it, by file path: a card shown again for the
/// same file says the same, and a lone thumbnail's card leaves the panel while it is in the annotator.
///
/// A card shows one notice at a time, and the newest wins. A send waiting for its answer keeps its
/// claim to that answer whatever the card shows meanwhile, so a failure is never lost behind a copy
/// made while the send was out.
struct CardNotices {
    enum Notice: Equatable {
        case copied(label: String)
        case notCopied(reason: String)
        case send(SendNotice)

        enum Kind: Hashable { case copied, notCopied, send }
        var kind: Kind {
            switch self {
            case .copied: return .copied
            case .notCopied: return .notCopied
            case .send: return .send
            }
        }
    }

    /// What happened to a file.
    enum Event: Equatable {
        case copied(label: String)
        case notCopied(reason: String)
        /// A send is stored and its card is going home; it waits for `answered`. With a `grace` the
        /// line has not gone yet: the card counts it down until `released` or `cancelled`.
        case sending(request: String, client: AgentClient, project: String, grace: SendNotice.Grace? = nil)
        /// The grace of `request` ended and its line is going to the client.
        case released(request: String)
        /// `request` was cancelled before its line went: its notice goes and no answer is waited for.
        case cancelled(request: String)
        /// The client answered for `request`.
        case answered(request: String, state: SendNotice.State, reason: String?)
        /// The agent's reply to `request` arrived and could not be made a card.
        case replyFailed(request: String, client: AgentClient, reason: String)
        /// The session's turn on `request`, a live ink note, ended with no result card.
        case finished(request: String, client: AgentClient, project: String)
    }

    /// A notice the card now shows. `hold`: when to call `expire(_:on:)`, nil while a send waits for
    /// its answer.
    struct Posted: Equatable {
        let id: Int
        let hold: TimeInterval?
    }

    private var shown: [String: (id: Int, notice: Notice)] = [:]
    private var awaitingAnswer: [String: SendNotice] = [:]
    private var lastID = 0

    /// Nil when there is nothing to show: an answer to a request that is not the one waiting, a
    /// failed reply while a later send waits, or a send that worked on a card nobody will see.
    /// `seen`: the card is on screen, in the annotator, or on its way home; a card that is not
    /// comes up to say anything else. `noticeHold` is how long a notice holds; one that explains
    /// something holds three times as long.
    mutating func post(_ event: Event, on file: String, seen: Bool, noticeHold: TimeInterval) -> Posted? {
        let notice: Notice
        switch event {
        case .copied(let label):
            notice = .copied(label: label)
        case .notCopied(let reason):
            notice = .notCopied(reason: reason)
        case .sending(let request, let client, let project, let grace):
            let send = SendNotice(request: request, client: client, project: project, state: grace == nil ? .sending : .inGrace, grace: grace)
            awaitingAnswer[file] = send
            return show(.send(send), on: file, hold: nil)
        case .released(let request):
            guard var send = awaitingAnswer[file], send.request == request, send.state == .inGrace else { return nil }
            send.state = .sending
            send.grace = nil
            awaitingAnswer[file] = send
            if let current = shown[file], case .send(let shownSend) = current.notice, shownSend.request == request {
                shown[file] = (current.id, .send(send))
            }
            return nil
        case .cancelled(let request):
            if awaitingAnswer[file]?.request == request { awaitingAnswer[file] = nil }
            if case .send(let shownSend)? = shown[file]?.notice, shownSend.request == request { shown[file] = nil }
            return nil
        case .answered(let request, let state, let reason):
            guard var send = awaitingAnswer[file], send.request == request else { return nil }
            awaitingAnswer[file] = nil
            send.state = state
            send.reason = reason
            // A card no longer on screen says nothing more about a delivery that worked.
            guard seen || Self.explains(state) else {
                if case .send(let shownSend)? = shown[file]?.notice, shownSend.request == request { shown[file] = nil }
                return nil
            }
            notice = .send(send)
        case .replyFailed(let request, let client, let reason):
            if let later = awaitingAnswer[file], later.request != request { return nil }
            notice = .send(SendNotice(request: request, client: client, project: client.label, state: .replyFailed, reason: reason))
        case .finished(let request, let client, let project):
            if let later = awaitingAnswer[file], later.request != request { return nil }
            notice = .send(SendNotice(request: request, client: client, project: project, state: .done))
        }
        return show(notice, on: file, hold: noticeHold * (Self.explains(notice) ? 3 : 1))
    }

    /// Takes a notice down if it is still the one `id` posted. A send still in its grace comes back
    /// when a notice that covered it goes, so Don't send is never lost behind a Copied.
    mutating func expire(_ id: Int, on file: String) {
        guard shown[file]?.id == id else { return }
        shown[file] = nil
        if let send = awaitingAnswer[file], send.state == .inGrace { _ = show(.send(send), on: file, hold: nil) }
    }

    func notice(on file: String) -> Notice? { shown[file]?.notice }

    /// A send on one of `files` is still waiting for its answer.
    func awaitsAnswer(on files: some Sequence<String>) -> Bool {
        files.contains { awaitingAnswer[$0] != nil }
    }

    private mutating func show(_ notice: Notice, on file: String, hold: TimeInterval?) -> Posted {
        lastID += 1
        shown[file] = (lastID, notice)
        return Posted(id: lastID, hold: hold)
    }

    /// A notice with a sentence to read and act on.
    private static func explains(_ notice: Notice) -> Bool {
        switch notice {
        case .copied: return false
        case .notCopied: return true
        case .send(let send): return explains(send.state)
        }
    }

    private static func explains(_ state: SendNotice.State) -> Bool { state != .inGrace && state != .sending && state != .sent && state != .done }
}
