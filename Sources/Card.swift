import AppKit

struct Card: Identifiable, Equatable {
    let id: UUID
    let shot: Screenshot
    var image: NSImage?       // thumbnail-sized; nil until decoded
    let pointSize: NSSize     // the screenshot in points, for the annotator frame
    let size: NSSize          // the card on screen
    let agent: String?        // the agent that added the file (see Agent); nil for a capture
    var duration: TimeInterval? = nil   // a recording's length, for its badge; nil for an image
    /// The drawing's marks, drawn over the thumbnail; nil for a screenshot with no drawing.
    var marks: MarkLayers? = nil

    func with(image: NSImage?) -> Card { var card = self; card.image = image; return card }
    func with(shot: Screenshot) -> Card {
        Card(id: id, shot: shot, image: image, pointSize: pointSize, size: size, agent: agent, duration: duration, marks: marks)
    }
    func with(size: NSSize) -> Card {
        Card(id: id, shot: shot, image: image, pointSize: pointSize, size: size, agent: agent, duration: duration, marks: marks)
    }
    func with(pointSize: NSSize, size: NSSize, duration: TimeInterval?) -> Card {
        Card(id: id, shot: shot, image: image, pointSize: pointSize, size: size, agent: agent, duration: duration, marks: marks)
    }
}

/// One drawing's layers are one object, which redraws itself in place, so two are the same only
/// when they are the same object.
extension MarkLayers: Equatable {
    nonisolated static func == (a: MarkLayers, b: MarkLayers) -> Bool { a === b }
}
