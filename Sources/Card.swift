import AppKit

struct Card: Identifiable, Equatable {
    let id: UUID
    let shot: Screenshot
    var image: NSImage?       // thumbnail-sized; nil until decoded
    let pointSize: NSSize     // the screenshot in points, for the annotator frame
    let size: NSSize          // the card on screen
    let agent: String?        // the agent that added the file (see Agent); nil for a capture
    /// The name of the session that pushed the file, which its tab says (`Agent.sender(of:)`). Nil
    /// until the session list answers, and for a push whose session has no name.
    var sender: String? = nil
    var duration: TimeInterval? = nil   // a recording's length, for its badge; nil for an image
    /// The drawing's marks, drawn over the thumbnail; nil for a screenshot with no drawing.
    var marks: MarkLayers? = nil
    /// An agent's marks that `show` brought, drawn on top until the person keeps or clears them (`PendingMarks`).
    var agentMarks: AgentMarksDrawn? = nil
    /// What the card's tab says about the last send of its file (`Agent.Sent`). Nil for a file never
    /// sent, and for an agent's card sent anywhere but back to the session it came from.
    var sent: Sent? = nil

    enum Sent: Equatable {
        /// A person's screenshot: "Sent to" the session, with the client's logo.
        case to(AgentClient, title: String)
        /// A person's screenshot whose line the session still holds in its queue: "Queued for" the
        /// session, with Don't send on the tab.
        case queued(AgentClient, title: String, Queued)
        /// An agent's card sent back to the session it came from: "From Claude · Replied".
        case replied

        /// What the tab says about `sent` on a card from `agent`, nil for a person's screenshot, that
        /// came from `origin` (`ScreenshotRequests.origin(of:)`).
        static func of(_ sent: Agent.Sent, agent: String?, origin: AgentDestination?) -> Sent? {
            guard agent != nil else { return .to(sent.client, title: sent.title) }
            return origin?.address == sent.address ? .replied : nil
        }
    }

    /// The agent whose marks are on top, the session's name when it is known, and their layers.
    struct AgentMarksDrawn: Equatable {
        let agent: String
        let sender: String?
        let layers: MarkLayers
    }

    /// Why the session's queue holds the line, and whether Don't send is taking it out.
    struct Queued: Equatable {
        let reason: String
        let withdrawing: Bool
    }

    func with(image: NSImage?) -> Card { var card = self; card.image = image; return card }
    func with(shot: Screenshot) -> Card {
        Card(id: id, shot: shot, image: image, pointSize: pointSize, size: size, agent: agent, sender: sender, duration: duration, marks: marks, sent: sent)
    }
    func with(size: NSSize) -> Card {
        Card(id: id, shot: shot, image: image, pointSize: pointSize, size: size, agent: agent, sender: sender, duration: duration, marks: marks, sent: sent)
    }
    func with(pointSize: NSSize, size: NSSize, duration: TimeInterval?) -> Card {
        Card(id: id, shot: shot, image: image, pointSize: pointSize, size: size, agent: agent, sender: sender, duration: duration, marks: marks, sent: sent)
    }
}

/// One drawing's layers are one object, which redraws itself in place, so two are the same only
/// when they are the same object.
extension MarkLayers: Equatable {
    nonisolated static func == (a: MarkLayers, b: MarkLayers) -> Bool { a === b }
}
