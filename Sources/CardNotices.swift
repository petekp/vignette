import Foundation

/// What a card sent to an agent shows: where it went and how the delivery went.
struct SendNotice: Equatable {
    /// `replyFailed`: the agent's reply to this send arrived and could not be made a card.
    /// `queued`: the client holds the send, but nothing reads it until the session is opened.
    enum State: Equatable { case sending, sent, queued, uncertain, failed, replyFailed }
    let request: String   // the request's id, so an answer to an earlier send is never taken for this one's
    let client: AgentClient
    let project: String
    var state: State
    /// What went wrong and what to do about it, once a delivery has failed or gone unconfirmed.
    var reason: String? = nil
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
        /// A send is stored and its card is going home; it waits for `answered`.
        case sending(request: String, client: AgentClient, project: String)
        /// The client answered for `request`.
        case answered(request: String, state: SendNotice.State, reason: String?)
        /// The agent's reply to `request` arrived and could not be made a card.
        case replyFailed(request: String, client: AgentClient, reason: String)
    }

    /// A notice the card now shows. `hold`: when to call `expire(_:on:)`, nil while a send waits for
    /// its answer.
    struct Posted: Equatable {
        let id: Int
        let hold: TimeInterval?
    }

    private var shown: [String: (id: Int, notice: Notice)] = [:]
    private var waiting: [String: SendNotice] = [:]
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
        case .sending(let request, let client, let project):
            let send = SendNotice(request: request, client: client, project: project, state: .sending)
            waiting[file] = send
            return show(.send(send), on: file, hold: nil)
        case .answered(let request, let state, let reason):
            guard var send = waiting[file], send.request == request else { return nil }
            waiting[file] = nil
            send.state = state
            send.reason = reason
            // A card no longer on screen says nothing more about a delivery that worked.
            guard seen || Self.explains(state) else {
                if case .send(let shownSend)? = shown[file]?.notice, shownSend.request == request { shown[file] = nil }
                return nil
            }
            notice = .send(send)
        case .replyFailed(let request, let client, let reason):
            if let later = waiting[file], later.request != request { return nil }
            notice = .send(SendNotice(request: request, client: client, project: client.label, state: .replyFailed, reason: reason))
        }
        return show(notice, on: file, hold: noticeHold * (Self.explains(notice) ? 3 : 1))
    }

    /// Takes a notice down if it is still the one `id` posted.
    mutating func expire(_ id: Int, on file: String) {
        if shown[file]?.id == id { shown[file] = nil }
    }

    func notice(on file: String) -> Notice? { shown[file]?.notice }

    /// A send on one of `files` is still waiting for its answer.
    func awaitsAnswer(on files: some Sequence<String>) -> Bool {
        files.contains { waiting[$0] != nil }
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

    private static func explains(_ state: SendNotice.State) -> Bool { state != .sending && state != .sent }
}
