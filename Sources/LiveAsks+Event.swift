import CoreGraphics
import Foundation

extension LiveAsks {
    enum Event: Equatable {
        /// The person drew a mark, or picked one of an answer's: it is the note's ink.
        case drew(Mark.ID)
        /// Esc in the note.
        case noteDiscarded
        /// The marks were taken off the screen: erased, picked, a step or a focus stop done, the
        /// marks of a display unplugged, or anything else that leaves. Each loses its roles and its
        /// finish. The asks, and the marks they are about, stay as they are, but an answer with no
        /// marks left ends.
        case removed(Set<Mark.ID>)
        /// The marks went with their window. They keep their finish, and are no longer the note's ink.
        case windowGone(Set<Mark.ID>)
        /// Something came back for ask `for`, late or not. Unless that ask is under way, it changes
        /// nothing and answers no effects.
        case arrived(Arrival, for: Ask.ID)

        /// The responder was sent the picture of ask `for`, or none since it has it already.
        case pictureSent(fresh: Bool, for: Ask.ID)

        // What LiveInk drew for ask `for`, in the turn its packet, reply or answer was taken.

        /// The note the person asked in became the conversation: the reply, with no words yet, under
        /// their question, which carries the thinking light and takes the answer's words.
        case conversed(Mark, for: Ask.ID)
        case streamed(Mark, for: Ask.ID)
        /// The answer was drawn: its reply, and of its other marks those `shown` now. The next ask
        /// waiting goes to the responder.
        case answered(reply: Mark?, actions: [LiveAnswer.Action], findings: [[Mark.ID]], shown: Set<Mark.ID>, for: Ask.ID)

        /// Reply's field closed with `words` in it, on the panel made for `reply`.
        case drafted(String, reply: Mark.ID?)

        /// A reply was drawn again: to hang from a focus stop, or saying why in its header.
        case replyRedrawn(Mark)
        /// More of ask `for`'s answer, or its failure's note, came on the screen.
        case answerShown(Set<Mark.ID>, for: Ask.ID)
        /// An answer's × or the Esc that closes it. It finishes the answer's marks, and the marks the ask is about, erased or
        /// not, that no other ask is about. The ask ends, and the responder's turn stops when it was
        /// this ask's.
        case dismissed(Ask.ID)
        /// Esc on ask `id`, under way: it stops, and its ink is as it was before it began: ink that was
        /// new is the note's again, and the note opens on it with the ask's words. Ink new to an ask sent
        /// on release goes instead. A reply to put back must be among `shown`. Nothing is said, since the
        /// person stopped it. A session's note stored after this is withdrawn.
        case cancelled(Ask.ID, shown: Set<Mark.ID>)
        /// The time for marks to leave is up.
        case finished(Set<Mark.ID>)
        /// The screen was cleared, or live ink turned off.
        case cleared
    }

    /// The answer Esc closes next, by the same `dismissed` event as its ×: the newest settled one with a
    /// mark not already leaving among `inSight`, the marks on the active Space.
    func newestAnswerToClose(inSight: Set<Mark.ID>) -> Ask.ID? {
        asks.last { !$0.isUnderWay && answerMarks(of: $0.id).contains { !isFinishing($0) && inSight.contains($0) } }?.id
    }
}
