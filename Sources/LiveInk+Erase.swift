import CoreGraphics

extension LiveInk {
    /// How far past a stroke's edge a tap still erases it. Wider than the editor's hit margin: nothing
    /// shows which mark a tap would erase, and while inking a tap does nothing else.
    nonisolated static let eraseReach: CGFloat = 12

    /// The index of the mark a tap at `point` erases: the topmost note it is on, or whose stroke it is
    /// near, or else the smallest ellipse it is inside, since a circled thing is where a hand goes to
    /// take the circle off. `noteBox` gives what a note draws, an agent's badge included, so a tap on
    /// the badge or beside it erases the note, as generous as `eraseReach`.
    nonisolated static func markToErase(at point: CGPoint, in marks: [Mark], markStyle: MarkStyle,
                                        noteBox: (Mark) -> CGRect? = { _ in nil }) -> Int? {
        let near = marks.lastIndex { mark in
            if let box = noteBox(mark) { return box.contains(point) }
            guard let distance = EditorGeometry.strokeDistance(from: point, to: mark, pointScale: 1) else { return false }
            return distance <= markStyle.strokeWidth / 2 + eraseReach
        }
        if let near { return near }
        let around = marks.indices.compactMap { index -> (index: Int, area: CGFloat)? in
            guard case .ellipse(let frame) = marks[index].geometry, EditorGeometry.ellipse(frame, contains: point) else { return nil }
            return (index, frame.width * frame.height)
        }
        return around.min { $0.area < $1.area }?.index
    }
}
