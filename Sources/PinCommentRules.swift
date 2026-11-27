import Foundation

/// One change the person made to a screenshot's pins, as the session reading its comments is told it
/// (ADR 0035). An agent's own changes, its answers and its resolves, are never one.
enum CommentChange: Equatable {
    /// A new comment of the person's. `reopens`: the pin was resolved, and posting reopened it.
    case posted(pin: Pin.ID, comment: UUID, text: String, reopens: Bool)
    /// A comment's words changed. The comment is the person's now, an agent's comment included.
    case edited(pin: Pin.ID, comment: UUID, text: String)
    /// A comment, or its whole pin, was deleted. `text` is the words it had.
    case deleted(pin: Pin.ID, comment: UUID, text: String)
    case resolved(pin: Pin.ID)
    /// A resolved pin was reopened with nothing posted on it.
    case reopened(pin: Pin.ID)

    var pin: Pin.ID {
        switch self {
        case .posted(let pin, _, _, _), .edited(let pin, _, _), .deleted(let pin, _, _), .resolved(let pin), .reopened(let pin): return pin
        }
    }

    var comment: UUID? {
        switch self {
        case .posted(_, let comment, _, _), .edited(_, let comment, _), .deleted(_, let comment, _): return comment
        case .resolved, .reopened: return nil
        }
    }

    /// The person's changes from `before` to `after`, in pin number order, deletions last. Undo and redo
    /// are changes too: undoing a post deletes the comment. A pin still being placed has no number and is
    /// left out.
    static func between(_ before: [Pin], _ after: [Pin]) -> [CommentChange] {
        let was = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var oldComments: [UUID: (pin: Pin.ID, comment: Pin.Comment)] = [:]
        for pin in before { for comment in pin.comments { oldComments[comment.id] = (pin.id, comment) } }
        var changes: [CommentChange] = []
        var kept: Set<UUID> = []
        for pin in after.filter({ $0.number > 0 }).sorted(by: { $0.number < $1.number }) {
            let old = was[pin.id]
            let reopenedByPost = old?.isResolved == true && !pin.isResolved
            var postedHere = false
            for comment in pin.comments {
                kept.insert(comment.id)
                guard !comment.agent else {
                    if oldComments[comment.id] == nil { postedHere = true }
                    continue
                }
                if let prior = oldComments[comment.id]?.comment {
                    if prior.text != comment.text || prior.agent { changes.append(.edited(pin: pin.id, comment: comment.id, text: comment.text)) }
                } else {
                    postedHere = true
                    changes.append(.posted(pin: pin.id, comment: comment.id, text: comment.text, reopens: reopenedByPost))
                }
            }
            guard let old else { continue }
            if !old.isResolved, let resolution = pin.resolved, !resolution.agent { changes.append(.resolved(pin: pin.id)) }
            if reopenedByPost && !postedHere { changes.append(.reopened(pin: pin.id)) }
        }
        for pin in before.sorted(by: { $0.number < $1.number }) {
            for comment in pin.comments where !kept.contains(comment.id) {
                changes.append(.deleted(pin: pin.id, comment: comment.id, text: comment.text))
            }
        }
        return changes
    }
}

/// Which session a screenshot's comments go to: the session of the pin's newest agent comment, else the
/// screenshot's last session, the first of them the session list has (ADR 0035).
enum CommentTarget {
    /// One place a screenshot names a session it exchanged with, and when. Nil is a time no record kept.
    struct Exchange: Equatable {
        let session: AgentAddress
        let at: Date?
    }

    /// The session the screenshot last exchanged with: the session that showed it in this opening, which
    /// is now; else the newest of `exchanges`, a send, a reply and the agents' comments; else the
    /// session its push or live ink result named, the file's oldest event.
    static func last(showedIt: AgentAddress?, exchanges: [Exchange], origin: AgentAddress?) -> AgentAddress? {
        if let showedIt { return showedIt }
        let newest = exchanges.max { ($0.at ?? .distantPast) < ($1.at ?? .distantPast) }
        return newest?.session ?? origin
    }

    /// The agent comments' sessions on `pins`, as exchanges.
    static func exchanges(on pins: [Pin]) -> [Exchange] {
        pins.flatMap { pin in pin.comments.compactMap { comment in comment.session.map { Exchange(session: $0, at: comment.at) } } }
    }

    /// The session of the pin's newest agent comment that named one.
    static func session(of pin: Pin) -> AgentAddress? {
        pin.comments.last { $0.agent && $0.session != nil }?.session
    }

    /// Where a change on `pin` goes: its own session, else `last`, whichever `running` lists first.
    /// Nil when neither runs: the comment stays on the pin, as before live comments.
    static func destination(for pin: Pin?, last: AgentAddress?, running: [AgentDestination]) -> AgentDestination? {
        for session in [pin.flatMap(session(of:)), last].compactMap({ $0 }) {
            if let found = running.first(where: { $0.address == session && $0.start == nil }) { return found }
        }
        return nil
    }

    /// Whether `session` knows what `change` is about, so an edit, a delete, a resolve or a reopen is
    /// worth telling it: a comment it was sent or wrote, or, for a resolve or a reopen, any on the pin.
    /// A new comment always goes.
    static func knows(_ session: AgentAddress, _ change: CommentChange, pin: Pin?, delivered: Set<UUID>) -> Bool {
        func known(_ comment: Pin.Comment) -> Bool { delivered.contains(comment.id) || comment.session == session }
        switch change {
        case .posted: return true
        case .edited(_, let id, _), .deleted(_, let id, _):
            return delivered.contains(id) || pin?.comments.contains { $0.id == id && $0.session == session } == true
        case .resolved, .reopened:
            return pin?.comments.contains(where: known) == true
        }
    }
}

/// The changes held for one session during the wait, merged as they come: a comment deleted in the
/// wait is never sent, an edit in the wait changes the words that go, and a resolve undone in the wait
/// goes as nothing.
struct HeldChanges: Equatable {
    struct Item: Equatable {
        var change: CommentChange
        /// The pin's number and where it is, in fractions of the image, when the change was made.
        var number: Int
        var x: Double
        var y: Double
    }

    private(set) var items: [Item] = []
    var isEmpty: Bool { items.isEmpty }

    mutating func add(_ item: Item) {
        switch item.change {
        case .edited(_, let id, let text):
            if let index = items.firstIndex(where: { $0.change.comment == id }) {
                switch items[index].change {
                case .posted(let pin, _, _, let reopens): items[index].change = .posted(pin: pin, comment: id, text: text, reopens: reopens)
                default: items[index].change = item.change
                }
                return
            }
        case .deleted(_, let id, _):
            if let index = items.firstIndex(where: { $0.change.comment == id }) {
                if case .posted = items[index].change { items.remove(at: index); return }
                items[index].change = item.change
                return
            }
        case .resolved(let pin), .reopened(let pin):
            if let index = items.firstIndex(where: { $0.change.comment == nil && $0.change.pin == pin && $0.change != item.change }) {
                items.remove(at: index)
                return
            }
        case .posted:
            break
        }
        items.append(item)
    }

    /// The comments whose words the line carries.
    var comments: [UUID] {
        items.compactMap { item in
            switch item.change {
            case .posted(_, let id, _, _), .edited(_, let id, _): return id
            default: return nil
            }
        }
    }

    /// The line the session gets: what changed, pin by pin, then where, in brackets, as Send's words do.
    func line(file: String) -> String {
        let said = items.map { item -> String in
            let pin = "Pin \(item.number)"
            switch item.change {
            case .posted(_, _, let text, let reopens): return "\(pin)\(reopens ? " (reopened)" : ""): " + Pin.ended(text.asOneLine)
            case .edited(_, _, let text): return "\(pin)'s comment now reads: " + Pin.ended(text.asOneLine)
            case .deleted(_, _, let text): return "\(pin): deleted the comment \"\(text.asOneLine)\"."
            case .resolved: return "\(pin): resolved."
            case .reopened: return "\(pin): reopened."
            }
        }
        var placed: [String] = []
        for item in items {
            var ids = "id \(item.change.pin.uuidString)"
            if let comment = item.change.comment { ids += ", comment \(comment.uuidString)" }
            placed.append("Pin \(item.number) (\(ids)) at \(Int((item.x * 100).rounded()))% across and \(Int((item.y * 100).rounded()))% down")
        }
        let note = "From Vignette: comments on \"\(file)\". " + placed.joined(separator: "; ")
            + ". Answer on the pin with show and pins=, and resolve it when it is done (the vignette skill's references/live-comments.md)."
        return said.joined(separator: " ") + " [\(note)]"
    }
}

/// The turn a delivered comment started, read from the session's turn after the line went in. A turn
/// that runs after the line was taken is the comment's: a session takes a line only between turns.
struct CommentTurnWatch: Equatable {
    /// When the line went in, in the clock the looks run on.
    let since: TimeInterval
    private(set) var working = false

    /// How long a session may read idle after the line went in before the watch decides no turn started:
    /// the monitor takes a line within 0.3 s, and the turn reads busy once Claude Code's prompt hook runs.
    static let startWithin: TimeInterval = 10
    /// How long a turn is watched.
    static let limit: TimeInterval = 30 * 60

    enum Effect: Equatable {
        case wait
        /// The comment's turn is running: the popover shows the working row.
        case started
        /// The watch is over: the turn ended, or none started.
        case ended
    }

    mutating func look(_ turn: SessionTurn?, at now: TimeInterval) -> Effect {
        if now - since >= Self.limit { return .ended }
        switch turn {
        case .waiting?:
            return .wait
        case .busy?:
            guard !working else { return .wait }
            working = true
            return .started
        case .idle?:
            return working || now - since >= Self.startWithin ? .ended : .wait
        case nil:
            return .ended
        }
    }
}
