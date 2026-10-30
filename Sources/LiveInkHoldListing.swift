/// A chord hold's listing of the sessions, by the hold's number (`LiveInk.inkings`), and its latest
/// answer. The note opened from that hold gets every later answer, however often the chord is pressed
/// after: the note does not list again while it keeps the keys.
@MainActor
final class LiveInkHoldListing {
    let hold: Int
    private(set) var candidates: DestinationChoice.Candidates?
    weak var note: LiveNotePopover?

    init(hold: Int) { self.hold = hold }

    /// Takes an answer and hands it to the note. Answers whether it is the first complete one, which
    /// decides the responder to start.
    func answer(_ candidates: DestinationChoice.Candidates) -> Bool {
        let decides = candidates.complete && self.candidates?.complete != true
        self.candidates = candidates
        note?.setSessions(candidates)
        return decides
    }
}
