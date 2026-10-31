import Foundation

/// Whether each agent can answer live ink, checked without sending a message.
extension LiveResponder {
    /// Whether an agent can answer, as its own tools report it (`ResponderDriver.availability()`).
    enum Availability: Equatable {
        /// The first check has not answered. An ask is sent while it runs, and fails if the agent cannot answer.
        case checking
        case ready
        case notInstalled
        case signedOut

        /// Whether a note aimed at the agent may send its ask.
        var canAnswer: Bool { self == .checking || self == .ready }
    }
}
