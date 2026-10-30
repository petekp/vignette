import Foundation

extension LiveNotePopover {
    /// Where the note's words go when the person presses Return.
    enum Target: Equatable {
        /// Claude, kept running by Vignette, which draws its answer on the screen.
        case responder
        /// A working session, through Send. Its answer is drawn beside the ink when it comes.
        case session(AgentDestination)

        var session: AgentDestination? {
            if case .session(let destination) = self { return destination }
            return nil
        }
    }
}
