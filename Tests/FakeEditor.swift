import Foundation

/// The editor's open drawing, without a window: a join adds the marks and answers the drawing.
@MainActor
final class FakeEditor: OpenDrawing {
    var drawing: Drawing
    var isOpen = true

    init(_ drawing: Drawing) { self.drawing = drawing }

    func drawing(of key: ScreenshotKey) -> Drawing? { isOpen && drawing.key == key.path ? drawing : nil }

    func rekey(_ old: ScreenshotKey, to new: ScreenshotKey) {
        if drawing.key == old.path { drawing.key = new.path }
    }

    func join(_ marks: [Mark], pins: [AgentPin], by author: AgentAuthor) -> Drawing? {
        guard !marks.isEmpty || !pins.isEmpty else { return nil }
        drawing.marks += marks
        drawing = drawing.taking(AgentPin.join(pins, by: author, onto: drawing).pins)
        return drawing
    }

    func name(_ sender: String, of session: AgentAddress) -> Drawing? {
        let named = drawing.naming(session, sender)
        guard named != drawing else { return nil }
        drawing = named
        return drawing
    }
}
