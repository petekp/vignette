import CoreGraphics

/// The note's window captured afresh for its result card (docs/glossary.md), as plain values, and
/// where a session's answer goes on it.
struct ResultCard {
    /// The window, in global top-left points, when it was captured.
    let frame: CGRect
    /// The capture's size.
    let pixels: PixelSize
    /// The capture's pixels per point (`LivePacket.scale`).
    let pointScale: CGFloat
    /// A browser's page, in global top-left points.
    let page: CGRect?
    /// The window's text, in reading order.
    let lines: [LivePacket.Line]

    /// `answer` drawn as this card draws it (`LiveAnswer.cardMarks`), each mark at what it names in
    /// these lines (`AnswerMark.target`), every line counting as sent. `ink`, in global top-left points,
    /// is what the note was about. `notDrawn` is the indexes of the answer's marks with no target on
    /// the window. On the main actor, as `LivePacket.Line.box(of:)` is.
    @MainActor func marks(for answer: LiveAnswer, about ink: CGRect, style: TextStyle, agent: String?) -> (marks: [AgentMark], notDrawn: [Int]) {
        let sent = Set(lines.map(\.id))
        // A rect in global top-left points as fractions of the capture, or nil when none of it is on it.
        func fraction(_ rect: CGRect) -> CGRect? {
            let inside = rect.intersection(frame)
            guard !inside.isNull else { return nil }
            return CGRect(x: (inside.minX - frame.minX) / frame.width, y: (inside.minY - frame.minY) / frame.height,
                          width: inside.width / frame.width, height: inside.height / frame.height)
        }
        let targets = answer.marks.map { mark -> CGRect? in
            guard var found = mark.target(in: lines, sent: sent).map({ LivePacket.global($0, in: frame) }) else { return nil }
            // A box from the words is tight round their letters, so a ring round it needs room.
            // An arrow points at the words themselves.
            if mark.kind != .arrow, mark.words != nil || mark.line != nil {
                found = found.insetBy(dx: -(found.width * 0.2 + 8), dy: -(found.height * 0.45 + 6))
            }
            return fraction(found)
        }
        let notDrawn = targets.indices.filter { targets[$0] == nil }
        let canvas = LiveAnswer.Canvas(pixels: pixels, pointScale: pointScale, style: style, agent: agent, page: page.flatMap(fraction))
        return (answer.cardMarks(targets: targets, about: fraction(ink), text: lines.map(\.box), on: canvas), notDrawn)
    }
}
