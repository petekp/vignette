import Foundation

/// What Esc does next while live ink is up: one step back out of it per press, the first that applies
/// (docs/live-ink.md, "Esc"). `LiveInk` holds Esc as a hotkey only while `next` has a step, so with
/// nothing to back out of the key is the frontmost app's.
enum LiveEscape {
    /// The key code of Esc.
    static let keyCode: UInt32 = 53

    enum Step: String, Equatable {
        /// The note closes and listening stops. The ink drawn for it stays.
        case closeNote = "close-note"
        /// Reply's field closes and keeps what was typed.
        case closeReplyField = "close-reply-field"
        /// The ask under way is stopped, and the ink can be asked about again.
        case cancelAsk = "cancel-ask"
        /// The focus run or the steps still to show are let go.
        case endTour = "end-tour"
        /// The reply, its buttons and the agent's marks leave. The person's ink stays.
        case closeAnswer = "close-answer"
        /// Every mark left goes, and the conversation ends.
        case clearInk = "clear-ink"
    }

    /// What `next` reads: which of live ink's things are up.
    struct Snapshot: Equatable {
        var isOn = false
        /// Not while the stack or the annotator holds the screen: they use Esc.
        var screenIsFree = true
        var noteOpen = false
        var replyFieldOpen = false
        /// An ask is under way that Esc can stop: any ask to the responder, and an ask to a session
        /// until its send has been stored, since only a send still in its grace can be withdrawn.
        var askCanBeCancelled = false
        var tourRunning = false
        /// A reply or an agent's mark shows that is not already leaving.
        var answerShown = false
        /// Some mark shows that is not already leaving.
        var marksShown = false
    }

    static func next(_ state: Snapshot) -> Step? {
        guard state.isOn, state.screenIsFree else { return nil }
        if state.noteOpen { return .closeNote }
        if state.replyFieldOpen { return .closeReplyField }
        if state.askCanBeCancelled { return .cancelAsk }
        if state.tourRunning { return .endTour }
        if state.answerShown { return .closeAnswer }
        if state.marksShown { return .clearInk }
        return nil
    }
}
