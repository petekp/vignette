import Foundation

/// What Esc does next while live ink is up: one step back out of it per press, the first that applies
/// (docs/live-ink.md, "Esc"). `LiveInk` holds Esc as a hotkey only while `next` has a step, so with
/// nothing to back out of the key is the frontmost app's. While the chord is held Esc cancels the hold.
/// Right after the chord is let go, Esc is live ink's wherever the pointer is: the person has not gone
/// anywhere else. Later, past the note and Reply's field, which have the keys, a step applies only
/// while the pointer is on live ink: otherwise the person is typing in another app, where Esc stops a
/// terminal's agent, closes a dialog or leaves a mode.
enum LiveEscape {
    /// The key code of Esc.
    static let keyCode: UInt32 = 53

    enum Step: String, Equatable {
        /// The chord is held, or a stroke outlives it: inking stops, and the ink drawn and the words
        /// heard in this hold go, with the note opened in it. Nothing is sent.
        case cancelHold = "cancel-hold"
        /// The note closes, listening stops, and its ink, all the ink no ask has been about, goes.
        /// While the note has the keys, or right after the chord is let go.
        case discardNote = "discard-note"
        /// Reply's field closes and keeps what was typed.
        case closeReplyField = "close-reply-field"
        /// The newest ask under way or waiting its turn is stopped, and its ink can be asked about again.
        case cancelAsk = "cancel-ask"
        /// The newest ask under way, which went by itself when the person stopped talking, is stopped,
        /// and its ink and words go with it.
        case discardAsk = "discard-ask"
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
        /// The chord is held, or a stroke that outlived it is still going.
        var inking = false
        /// The chord was let go and the person has not gone anywhere since: no press off the ink, no
        /// switch to another app, and the answer has not come (`LiveEscapeAfterRelease`).
        var justLetGo = false
        /// The chord was let go with no ink and no note, and listening goes on for the last words.
        var listeningAfterRelease = false
        var note: Note = .none
        var replyFieldOpen = false
        /// An ask is under way that Esc can stop: any ask to the responder, waiting its turn or not, and
        /// an ask to a session until its send has been stored, since only a send still in its grace can
        /// be withdrawn.
        var askCanBeCancelled = false
        /// The ask Esc would stop went by itself when the person stopped talking.
        var askSentOnRelease = false
        var tourRunning = false
        /// A reply or an agent's mark of an answer that has come, or a failure, shows that is not
        /// already leaving.
        var answerShown = false
        /// Some mark shows that is not already leaving.
        var marksShown = false
        /// The pointer is on a mark or a reply that shows on the active Space. Read only when a step
        /// needs it (`needsPointer`).
        var pointerOnInk = false
    }

    enum Note: Equatable {
        case none
        case hasKeys
        /// Up, shown or hidden with its ink, while the person is in another app. Esc is that app's, so
        /// a press meant there never takes the note's words, nor anything else live ink shows.
        case withoutKeys
    }

    static func next(_ state: Snapshot) -> Step? {
        guard state.isOn, state.screenIsFree, !state.menuOpen else { return nil }
        if state.inking { return .cancelHold }
        if state.note == .hasKeys || (state.note == .withoutKeys && state.justLetGo) { return .discardNote }
        if state.note == .none, state.listeningAfterRelease { return .discardNote }
        guard state.note == .none else { return nil }
        if state.replyFieldOpen { return .closeReplyField }
        if state.askCanBeCancelled, state.pointerOnInk || state.justLetGo {
            return state.askSentOnRelease ? .discardAsk : .cancelAsk
        }
        guard state.pointerOnInk else { return nil }
        if state.tourRunning { return .endTour }
        if state.answerShown { return .closeAnswer }
        if state.marksShown { return .clearInk }
        return nil
    }

    /// Whether `next` reads `pointerOnInk`: where the pointer is changes the step.
    static func needsPointer(_ state: Snapshot) -> Bool {
        var pointed = state, away = state
        pointed.pointerOnInk = true
        away.pointerOnInk = false
        return next(pointed) != next(away)
    }
}
