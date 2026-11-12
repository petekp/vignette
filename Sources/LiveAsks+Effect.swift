import Foundation

extension LiveAsks {
    enum Effect: Equatable {
        /// Ask `id` is over: let go of everything kept for it. It comes before the effects on its marks.
        case ended(Ask.ID)
        /// Ask the responder, with ask `id`'s packet. Every ask before it to the responder has ended.
        case send(Ask.ID)
        /// Stop the responder's turn: the ask it was answering was stopped or dismissed.
        case interrupt
        /// Send the note to the session, as a card of the ink `about`.
        case share(about: Set<Mark.ID>)
        /// Lay out the reply so far and draw it, then send `streamed`.
        case showReply
        /// Lay out the answer and draw it, then send `answered`.
        case drawAnswer
        /// The answer is back as it was before its button was picked. Show its set-aside marks `aside`
        /// again, then draw `reply` again, saying `reason` in its header when there is one, and send
        /// `replyRedrawn`.
        case restore(reply: Mark.ID, reason: String?, aside: Set<Mark.ID>)
        /// Say `reason` in a reply hung from ask `id`'s ink, and send `answerShown`.
        case say(Ask.ID, String)
        /// Say `reason` in `reply`'s row, in place of its words, and send `replyRedrawn`.
        case notice(reply: Mark.ID, reason: String)
        /// Take these marks off the screen.
        case remove(Set<Mark.ID>)
        /// Ink is the note's again: open the note on it, with the keys and with `words`, or give the keys
        /// to the note up already, which keeps its own words.
        case reopenNote(words: String)
        /// The note of an ask Esc stopped was stored after all: take the send back.
        case withdraw
        /// Let go of ask `id`'s steps, focus and buttons, then take these marks off. The ask has already
        /// taken their part as its answer. May be empty.
        case removeAnswer(Ask.ID, Set<Mark.ID>)
        /// Let go of ask `id`'s steps, focus and buttons, and hide these marks where they are. The ask
        /// has already taken their part as its answer.
        case setAside(Ask.ID, Set<Mark.ID>)
        /// These marks are leaving: show them going, and send `finished` once they have.
        case finish(Set<Mark.ID>, LiveMarksLayer.Finish)
    }
}
