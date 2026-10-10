import Foundation

/// One note card's wait for its session, from the send to its result card, its "done" notice or
/// nothing. Pure (docs/adr/0003-pure-reducers-decide.md): `LiveNoteCards` runs what it answers.
struct NoteCardWait: Equatable {
    enum Phase: Equatable {
        case unsent
        case watching(TurnWatch)
        /// Sent to a session whose route reports no turns, as a Codex thread's.
        case unwatched(sent: Date)
        /// The turn ended and the window round the ink is being looked at again.
        case lookingAgain
        /// A result card answers the note. An answer that comes later goes on it.
        case resultCard(made: Date)
        case over
    }

    enum Event: Equatable {
        case sent
        /// The client answered; `failed` for an outcome that did not reach the session.
        case delivered(failed: Bool)
        /// One reading of the session's turn, and whether the session has replied to the note by now.
        case turn(SessionTurn?, replied: Bool)
        /// The look at the window answered, and `NoteCardGroups` decided how it ends for this note.
        case lookedAgain(LookOutcome)
        /// The result card the note was waiting on, its own or another note's, could not be written.
        case cardFailed
        /// The session's reply has an answer for live ink, which asks for its result card.
        case answer
    }

    /// How the look at the window ends for one note, as the notes on its window decide it together.
    enum LookOutcome: Equatable {
        /// The session replied to the note, and that reply is its result.
        case replied
        /// A result card answers the note: its own change made it, or another note's on the window.
        case cardMade
        /// Nothing changed under the ink of any note that the session has not replied to.
        case noCard
    }

    enum Effect: Hashable {
        /// Read the session's turn twice a second.
        case watchTurn
        case turnEnded
        case stopWaiting
        /// Look at the window round the ink again, and answer `lookedAgain`. `NoteCardGroups` merges
        /// it across the notes one turn end answers.
        case lookAgain
        case replyIsTheResult
        /// The note card says the session is done, while its file is there.
        case sayDone
        /// `sayDone` without bringing the card up if it is off screen. `NoteCardGroups` answers a note's
        /// `.sayDone` as this when other notes of its group say Done or a result card comes up.
        case sayDoneQuietly
        /// Capture the note's window afresh and draw the answer on it.
        case drawReplyOnFreshCapture
        /// Draw the answer on the note's result card, made from the window when the turn ended.
        case drawReplyOnResultCard
        /// The reply becomes a card on the picture the session was sent.
        case drawReplyOnSentPicture
    }

    private(set) var phase: Phase = .unsent
    /// The client has answered the send.
    private(set) var delivered = false
    /// The route can tell when the session's turn starts and ends.
    let reportsTurns: Bool
    /// The note was on one window.
    let hasWindow: Bool
    /// A picture of the window round the ink was kept as the note went.
    let canLookAgain: Bool

    init(reportsTurns: Bool, hasWindow: Bool, canLookAgain: Bool) {
        self.reportsTurns = reportsTurns
        self.hasWindow = hasWindow
        self.canLookAgain = canLookAgain
    }

    var isWatching: Bool {
        if case .watching = phase { return true }
        return false
    }

    var isLookingAgain: Bool { phase == .lookingAgain }

    /// Nothing can come of the note any more, so its owner can let it go: its send notice has gone
    /// on its card, and no answer can be drawn afresh.
    func isFinished(at now: Date) -> Bool {
        guard delivered else { return false }
        switch phase {
        case .over: return true
        case .unwatched(let sent): return now.timeIntervalSince(sent) > TurnWatch.workingLimit
        case .resultCard(let made): return now.timeIntervalSince(made) > TurnWatch.turnLimit
        case .unsent, .watching, .lookingAgain: return false
        }
    }

    mutating func handle(_ event: Event, at now: Date) -> [Effect] {
        switch (phase, event) {
        case (.unsent, .sent):
            guard reportsTurns else {
                phase = .unwatched(sent: now)
                return [.stopWaiting]
            }
            phase = .watching(TurnWatch(asked: now))
            return [.watchTurn]

        case (.watching(var watch), .turn(let turn, let replied)):
            let verdict = watch.read(turn, at: now)
            switch verdict {
            case .stillWaiting:
                phase = .watching(watch)
                return []
            case .ended:
                guard canLookAgain else {
                    phase = .over
                    return [.turnEnded, replied ? .replyIsTheResult : .sayDone]
                }
                phase = .lookingAgain
                return [.turnEnded, .lookAgain]
            case .stoppedWaiting:
                phase = .over
                return [.stopWaiting] + (replied ? [.replyIsTheResult] : [])
            }

        case (.lookingAgain, .lookedAgain(let look)):
            switch look {
            case .replied:
                phase = .over
                return [.replyIsTheResult]
            case .cardMade:
                phase = .resultCard(made: now)
                return []
            case .noCard:
                phase = .over
                return [.sayDone]
            }

        case (.resultCard, .cardFailed):
            // The card that answered the note is not there, so the note says what it would have said.
            phase = .over
            return [.sayDone]

        case (_, .delivered(let failed)):
            delivered = true
            switch phase {
            case .watching, .unwatched, .lookingAgain, .resultCard: if failed { phase = .over }
            case .unsent, .over: break
            }
            return []

        case (.watching, .answer) where hasWindow:
            return [.drawReplyOnFreshCapture]
        case (.resultCard(let made), .answer):
            // As long as a turn may run, so the note is let go once no answer can still come.
            guard now.timeIntervalSince(made) <= TurnWatch.turnLimit else {
                phase = .over
                return [.drawReplyOnSentPicture]
            }
            return [.drawReplyOnResultCard]
        case (.unwatched(let sent), .answer):
            guard now.timeIntervalSince(sent) <= TurnWatch.workingLimit else {
                phase = .over
                return [.drawReplyOnSentPicture]
            }
            return [hasWindow ? .drawReplyOnFreshCapture : .drawReplyOnSentPicture]
        case (_, .answer):
            return [.drawReplyOnSentPicture]

        default:
            return []
        }
    }
}

/// How long a note card's turn is waited on, from readings of its session's turn. Pure, like
/// `ListeningEnd`: the clock is an input, and it is the wall clock, so a Mac asleep past a limit
/// stops waiting at the next reading.
struct TurnWatch: Equatable {
    /// How long a note's turn is waited on once the session has the request, with no word that its
    /// turn started, as from a route that cannot tell.
    static let workingLimit: TimeInterval = 180
    /// How long a turn the session said it started may run, and how long after the ask a request
    /// may still wait in the inbox, before Vignette stops waiting on it.
    static let turnLimit: TimeInterval = 30 * 60
    /// How long the turn must stay idle to count as over: requests handed over together can run as
    /// turns one after another, idle for a moment between them.
    static let idleSettle: TimeInterval = 2

    enum Verdict: Equatable { case stillWaiting, ended, stoppedWaiting }

    /// When the request was sent.
    let asked: Date
    /// Since when the session has had the request.
    private(set) var since: Date
    /// The turn was seen to start.
    private(set) var seenBusy = false
    /// Since when the turn has been idle after it was seen to start.
    private(set) var idleSince: Date?

    init(asked: Date) {
        self.asked = asked
        since = asked
    }

    /// One reading of the session's turn, nil when its route cannot tell.
    mutating func read(_ turn: SessionTurn?, at now: Date) -> Verdict {
        switch turn {
        case .waiting:
            // The request is still in the inbox, so a turn under way is another one's.
            seenBusy = false
            idleSince = nil
            since = now
        case .busy:
            seenBusy = true
            idleSince = nil
        case .idle where seenBusy:
            let idle = idleSince ?? now
            idleSince = idle
            return now.timeIntervalSince(idle) >= Self.idleSettle ? .ended : .stillWaiting
        case .idle, nil:
            break
        }
        // A request still in the inbox counts from the ask, and anything else from when the session took it.
        let waited = now.timeIntervalSince(turn == .waiting ? asked : since)
        return waited > (turn == .busy || turn == .waiting ? Self.turnLimit : Self.workingLimit) ? .stoppedWaiting : .stillWaiting
    }
}
