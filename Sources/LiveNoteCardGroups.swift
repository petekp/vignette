import CoreGraphics
import Foundation

/// Every live ink note's wait this launch, and the notes one turn end answers together: notes sent
/// to one session whose waits end in the same reading of its turn, on one window, share one look at
/// the window and at most one result card. `LiveNoteCards` runs the actions it answers.
struct NoteCardGroups: Equatable {
    /// What notes must share to share a look: the session they went to and the window they were on.
    struct SessionWindow: Hashable {
        /// `AgentDestination.id`.
        let session: String
        let window: CGWindowID?
    }

    struct Reading: Equatable {
        let request: String
        let turn: SessionTurn?
        let replied: Bool
    }

    enum Input: Equatable {
        case sent(String, SessionWindow, reportsTurns: Bool, canLookAgain: Bool)
        case delivered(String, failed: Bool)
        /// One reading of each watched note's session's turn, all from one tick.
        case turns([Reading])
        /// A group's look answered: `changed`, the members whose own region changed (empty when the
        /// window could not be compared); `replied`, the members the session has replied to by now;
        /// `uncompared`, the members whose region could not be compared, as when their window changed size.
        case looked([String], changed: Set<String>, replied: Set<String>, uncompared: Set<String> = [])
        /// The result card for these requests could not be written.
        case cardFailed([String])
        case answer(String)
    }

    enum Action: Equatable {
        case watchTurn
        /// One note's effect. `NoteCardGroups` answers a note's `.watchTurn` and `.lookAgain` as `.watchTurn` and `.look`.
        case note(String, NoteCardWait.Effect)
        /// Capture the window once and compare each request's region, in send order.
        case look([String])
        /// One result card for these requests, the one whose change made it first; each takes it
        /// for late answers.
        case makeResultCard(for: [String])
    }

    private struct Entry: Equatable {
        var wait: NoteCardWait
        let sessionWindow: SessionWindow
        let sequence: Int
    }

    private var entries: [String: Entry] = [:]
    private var nextSequence = 0

    subscript(request: String) -> NoteCardWait? { entries[request]?.wait }

    var isWatchingAny: Bool { entries.values.contains { $0.wait.isWatching } }

    /// Every list the answer holds is in send order, whatever order the input lists requests in.
    mutating func handle(_ input: Input, at now: Date) -> [Action] {
        var actions: [Action] = []
        switch input {
        case .sent(let request, let window, let reportsTurns, let canLookAgain):
            guard entries[request] == nil else { return [] }
            var wait = NoteCardWait(reportsTurns: reportsTurns, hasWindow: window.window != nil, canLookAgain: canLookAgain)
            for effect in wait.handle(.sent, at: now) {
                actions.append(effect == .watchTurn ? .watchTurn : .note(request, effect))
            }
            entries[request] = Entry(wait: wait, sessionWindow: window, sequence: nextSequence)
            nextSequence += 1

        case .delivered(let request, let failed):
            actions = step(request, .delivered(failed: failed), at: now)

        case .answer(let request):
            actions = step(request, .answer, at: now)

        case .turns(let readings):
            // Notes that end in one `.turns` input on an equal window share a look; one that ends in
            // a later input gets a look of its own.
            var looks: [SessionWindow: [String]] = [:]
            var windows: [SessionWindow] = []
            let known = readings.compactMap { reading in entries[reading.request].map { (reading, $0.sequence) } }
            for (reading, _) in known.sorted(by: { $0.1 < $1.1 }) {
                guard var entry = entries[reading.request], entry.wait.isWatching else { continue }
                let effects = entry.wait.handle(.turn(reading.turn, replied: reading.replied), at: now)
                entries[reading.request] = entry
                for effect in effects {
                    guard effect == .lookAgain else {
                        actions.append(.note(reading.request, effect))
                        continue
                    }
                    if looks[entry.sessionWindow] == nil { windows.append(entry.sessionWindow) }
                    looks[entry.sessionWindow, default: []].append(reading.request)
                }
            }
            actions += windows.compactMap { looks[$0].map(Action.look) }

        case .looked(let requests, let changed, let replied, let uncompared):
            let looking = requests.compactMap { id in entries[id].flatMap { $0.wait.isLookingAgain ? (id, $0.sequence) : nil } }
            let live = looking.sorted { $0.1 < $1.1 }.map(\.0)
            // A reply is its note's own result, and a region that could not be compared says nothing
            // about the card, so neither makes the card nor is answered by it.
            let members = live.filter { !replied.contains($0) && !uncompared.contains($0) }
            let maker = members.first { changed.contains($0) }
            var done: [Action] = []
            for id in live {
                let outcome: NoteCardWait.LookOutcome = replied.contains(id) ? .replied : (maker != nil && members.contains(id) ? .cardMade : .noCard)
                done += step(id, .lookedAgain(outcome), at: now)
            }
            // The card is asked for before any Done notice.
            if let maker { actions.append(.makeResultCard(for: [maker] + members.filter { $0 != maker })) }
            actions += done

        case .cardFailed(let requests):
            let sequenced = requests.compactMap { id in entries[id].map { (id, $0.sequence) } }
            for (id, _) in sequenced.sorted(by: { $0.1 < $1.1 }) { actions += step(id, .cardFailed, at: now) }
        }
        // A Codex note's wait ends with no input of its own, so every input lets the finished ones go.
        entries = entries.filter { !$0.value.wait.isFinished(at: now) }
        return actions
    }

    private mutating func step(_ request: String, _ event: NoteCardWait.Event, at now: Date) -> [Action] {
        guard var entry = entries[request] else { return [] }
        let effects = entry.wait.handle(event, at: now)
        entries[request] = entry
        return effects.map { .note(request, $0) }
    }
}
