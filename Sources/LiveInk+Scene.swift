import AppKit

// MARK: Where an answer has room

extension LiveInk {
    func scene(for packet: LivePacket, answering id: LiveAsks.Ask.ID? = nil) -> LiveAnswerLayout.Scene {
        scene(frame: packet.frame, page: packet.page, text: packet.lines.map { packet.global($0.box) }, answering: id)
    }

    /// The window at `frame` with its text at `text`, both in global top-left points. The person's
    /// notes and every answer on the screen but ask `id`'s are what a note keeps clear of.
    func scene(frame: CGRect, page: CGRect?, text: [CGRect], answering id: LiveAsks.Ask.ID? = nil) -> LiveAnswerLayout.Scene {
        let screen = StateReport.screenFrames.first { $0.intersects(frame) } ?? frame
        // A browser's page, not its tabs and toolbar: notes on those read as being about the browser.
        let room = (page ?? frame).intersection(screen).insetBy(dx: 8, dy: 8)
        let ink = self.ink
        let notes = ink.filter { $0.kind == .text }.compactMap { LiveAnswerLayout.noteBox($0, sizes: answerSizes) } + answerBoxes(except: id)
        return LiveAnswerLayout.Scene(room: room.isNull ? frame : room, ink: ink, text: text, notes: notes,
                                      screen: Self.visibleScreen(around: frame))
    }

    /// Where the answers on the screen are, all but ask `id`'s, in global top-left points: each reply's
    /// body and each mark's extent.
    func answerBoxes(except id: LiveAsks.Ask.ID?) -> [CGRect] {
        shownMarks.filter { mark in asks.answer(of: mark.id).map { $0 != id } ?? false }
            .compactMap { $0.shapeExtent ?? LiveAnswerLayout.noteBox($0, sizes: answerSizes) }
    }
}
