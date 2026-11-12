import AppKit

// MARK: A note sent to a session

extension LiveInk {
    /// The person's words as a note beside the ink `about`, at the note panel's tag, `spot`, or clear
    /// of the window's text, in global top-left points. Nil for no words.
    func noteMark(_ words: String, about: Set<Mark.ID>, packet: LivePacket, at spot: CGRect?) -> Mark? {
        let words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        let near = marks.filter { about.contains($0.id) }.compactMap(\.shapeExtent).reduce(CGRect.null) { $0.union($1) }
        guard !words.isEmpty, spot != nil || !near.isNull else { return nil }
        let scene = scene(for: packet)
        return spot.map { LiveAnswerLayout.note(words, at: $0, sizes: answerSizes) }
            ?? LiveAnswerLayout.note(words, near: near, scene: scene, obstacles: LiveAnswerLayout.obstacles(in: scene), sizes: answerSizes,
                                     agent: nil)
    }
}
