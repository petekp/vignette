import Foundation

/// What Esc does next while live ink is up: one step back out of it per press, the first that applies
/// (docs/live-ink.md, "Esc"). `LiveInk` holds Esc as a hotkey only while `next` has a step, so with
/// nothing to back out of the key is the frontmost app's.
enum LiveEscape {
    /// The key code of Esc.
    static let keyCode: UInt32 = 53

    enum Step: String, Equatable {
        /// The note closes, listening stops, and its ink, all the ink no ask has been about, goes. Only
        /// while the note has the keys.
        case discardNote = "discard-note"
        /// Reply's field closes and keeps what was typed.
        case closeReplyField = "close-reply-field"
        /// The newest ask under way or waiting its turn is stopped, and its ink can be asked about again.
        case cancelAsk = "cancel-ask"
        /// The focus run or the steps still to show are let go.
        case endTour = "end-tour"
        /// The newest answer's reply, its buttons and the agent's marks leave. The person's ink stays.
        case closeAnswer = "close-answer"
        /// Every mark left goes, and the conversation ends.
        case clearInk = "clear-ink"
    }

    /// What `next` reads: which of live ink's things are up.
    struct Snapshot: Equatable {
        var isOn = false
        /// Not while the stack or the annotator holds the screen: they use Esc.
        var screenIsFree = true
        /// The note's target menu is up. It closes on Esc, which the held key would take from it.
        var menuOpen = false
        var note: Note = .none
        var replyFieldOpen = false
        /// An ask is under way that Esc can stop: any ask to the responder, waiting its turn or not, and
        /// an ask to a session until its send has been stored, since only a send still in its grace can
        /// be withdrawn.
        var askCanBeCancelled = false
        var tourRunning = false
        /// A reply or an agent's mark of an answer that has come, or a failure, shows that is not
        /// already leaving.
        var answerShown = false
        /// Some mark shows that is not already leaving.
        var marksShown = false
    }

    enum Note: Equatable {
        case none
        case hasKeys
        /// Up, shown or hidden with its ink, while the person is in another app. Esc is that app's, so
        /// a press meant there never takes the note's words, nor anything else live ink shows.
        case withoutKeys
    }

    static func next(_ state: Snapshot) -> Step? {
        guard state.isOn, state.screenIsFree, !state.menuOpen, state.note != .withoutKeys else { return nil }
        if state.note == .hasKeys { return .discardNote }
        if state.replyFieldOpen { return .closeReplyField }
        if state.askCanBeCancelled { return .cancelAsk }
        if state.tourRunning { return .endTour }
        if state.answerShown { return .closeAnswer }
        if state.marksShown { return .clearInk }
        return nil
    }
}
