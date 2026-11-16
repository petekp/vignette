import Foundation

/// What the live ink page shows when it appears, as steps at times from then. Pure, so a test can
/// play it without a window. The hand writes the title, circles the keys and sends a note about them
/// to a Claude Code session. The readings of that session's turn are what `NoteCardWait` reads, as
/// it reads a real note's, and its end starts the done finish.
enum SetupInkDemo {
    enum Beat: Equatable {
        /// The hand holds Control and Option, or lets go.
        case chord(down: Bool)
        /// Writes stroke `index` of the title, over `SetupInkDemo.writing[index]`.
        case write(Int)
        case circleKeys
        case openNote
        /// The note's words, as typed so far.
        case type(String)
        /// Tab: the note's target moves to the next in its list.
        case nextTarget
        case send
        /// One reading of the session's turn.
        case reading(SessionTurn)
        /// The session's change: the page's keys grow.
        case growKeys
        /// The page's words come in, once the title is written.
        case showWords
    }

    struct Step: Equatable {
        let at: TimeInterval
        let beat: Beat
    }

    static let writing: [TimeInterval] = [1.15, 0.2, 1.2]
    /// The hand's pause after each stroke of the title but the last, before the next.
    static let writingPauses: [TimeInterval] = [0.12, 0.16]
    /// When each stroke of the title starts, from the first stroke's start.
    static let writingStarts: [TimeInterval] = [0, writing[0] + writingPauses[0], writing[0] + writingPauses[0] + writing[1] + writingPauses[1]]
    static let circling: TimeInterval = 0.75
    static let words = "make these keys bigger"
    /// How long the keys take to grow, at full motion: slowly, so it reads as the session's work.
    static let growing: TimeInterval = 1.4
    /// How often a session's turn is read, as `LiveNoteCards` reads it.
    static let readingEvery: TimeInterval = 0.5

    static let steps: [Step] = {
        var steps: [Step] = []
        var at: TimeInterval = 0.5
        func add(_ beat: Beat, after gap: TimeInterval = 0) {
            at += gap
            steps.append(Step(at: at, beat: beat))
        }
        add(.chord(down: true))
        add(.write(0), after: 0.15)
        add(.write(1), after: writing[0] + writingPauses[0])
        add(.write(2), after: writing[1] + writingPauses[1])
        add(.chord(down: false), after: writing[2] + 0.1)
        add(.showWords, after: 0.25)
        add(.chord(down: true), after: 0.9)
        add(.circleKeys, after: 0.12)
        add(.chord(down: false), after: circling + 0.08)
        add(.openNote, after: 0.05)
        at += 0.45
        for count in 1...words.count { add(.type(String(words.prefix(count))), after: 0.055) }
        add(.nextTarget, after: 0.5)
        add(.nextTarget, after: 0.6)
        add(.send, after: 0.7)
        // The session takes the note at once and works, then its turn ends. The readings run a tick
        // past `TurnWatch.idleSettle`, since they land on display refreshes rather than to the millisecond.
        let sent = at
        steps.append(Step(at: sent + 0.1, beat: .reading(.busy)))
        for tick in 0...5 { steps.append(Step(at: sent + 0.35 + Double(tick) * readingEvery, beat: .reading(.idle))) }
        steps.append(Step(at: sent + 0.7, beat: .growKeys))
        return steps.sorted { $0.at < $1.at }
    }()
}
