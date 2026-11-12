import Foundation

extension LiveAsks {
    /// What comes back for an ask.
    enum Arrival: Equatable {
        /// The packet was captured. Taken only while looking.
        case packetCame
        /// The responder's reply streamed in further. Taken only while asking.
        case replyCame
        case answerCame
        /// The packet could not be captured, the responder failed, or a session refused the note.
        /// `shown` is every mark on the screen, among which an answer to put back must be.
        case failed(reason: String, shown: Set<Mark.ID>)
        /// A session took the note, with `ink` in its picture.
        case sentToSession(ink: Set<Mark.ID>)
    }
}
