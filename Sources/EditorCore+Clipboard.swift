import CoreGraphics
import Foundation

extension EditorCore {
    /// Cmd+C and Cmd+X: the selected marks, or, for Cmd+C, the drawing when nothing is selected.
    mutating func copy() {
        let marks = drawing.marks.filter { selection.contains($0.id) }
        guard !marks.isEmpty else {
            emit(.copyDrawing(drawingForHost))
            return
        }
        let order = geometry.readingOrder(marks)
        let words = order.compactMap { id -> String? in
            guard case .text(let text)? = mark(id)?.geometry else { return nil }
            return text.text
        }
        emit(.copyMarks(CopiedMarks(pointScale: drawing.pointScale, markScale: drawing.markScale, marks: marks),
                        text: words.isEmpty ? nil : words.joined(separator: "\n")))
    }

    mutating func paste(_ content: PasteContent) {
        if gesture != nil { cancelGesture() }
        if typing != nil { endTyping() }
        switch content {
        case .marks(let copied):
            pasteMarks(copied)
        case .text(let string):
            let words = Self.capped(string.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
            guard !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let image = geometry.image
            let at = pointer.flatMap { image.encloses($0) ? $0 : nil } ?? CGPoint(x: image.midX, y: image.midY)
            let size = metrics.newTextSize
            let text = Mark.Text(origin: geometry.textOrigin(at: at, size: size), text: words, wrap: nil, size: size)
            guard let mark = geometry.placed(Mark(geometry: .text(text))) else { return }
            insert([mark])
        case .image, .other:
            emit(.beep)
        }
    }

    /// Copied marks keep their places and their boxes in the screenshot's points, and a text keeps
    /// its size in drawing pt with its lines, so it takes the size of the notes already there. On the
    /// same screenshot, while the marks they came from are still there, they land 10 pt right and
    /// down, and 10 pt more for each copy already there, with their texts' lines as they were;
    /// anywhere else, where the originals were, placed as marks from outside.
    private mutating func pasteMarks(_ copied: CopiedMarks) {
        let factor = drawing.screenScale / copied.screenScale, lines = drawing.pointScale / copied.pointScale
        let converted = copied.marks.map { mark -> Mark in
            var mark = Self.fresh(mark)
            switch mark.geometry {
            case .rectangle(let frame): mark.geometry = .rectangle(Self.scaled(frame, by: factor))
            case .ellipse(let frame): mark.geometry = .ellipse(Self.scaled(frame, by: factor))
            case .arrow(var arrow):
                arrow.start = CGPoint(x: arrow.start.x * factor, y: arrow.start.y * factor)
                arrow.end = CGPoint(x: arrow.end.x * factor, y: arrow.end.y * factor)
                arrow.bend *= factor
                arrow.via = arrow.via.map { CGPoint(x: $0.x * factor, y: $0.y * factor) }
                mark.geometry = .arrow(arrow)
            case .text(var text):
                text.origin = CGPoint(x: text.origin.x * factor, y: text.origin.y * factor)
                text.wrap = text.wrap.map { $0 * lines }
                mark.geometry = .text(text)
            }
            return mark
        }
        // A mark already where one of them would land means the originals, or copies of them, are here.
        func present(_ marks: [Mark]) -> Bool {
            marks.contains { candidate in drawing.marks.contains { $0.geometry == candidate.geometry } }
        }
        guard present(converted) else {
            return insert(geometry.placedGroup(converted, offset: .zero, keepingLines: false))
        }
        let step = geometry.pt(Self.copyOffset)
        func landing(_ copies: Int) -> [Mark] {
            geometry.placedGroup(converted, offset: CGVector(dx: step * CGFloat(copies), dy: step * CGFloat(copies)), keepingLines: true)
        }
        var copies = 1
        var candidate = landing(1)
        while present(candidate), copies < 1000 {
            copies += 1
            let next = landing(copies)
            // Held against an edge, another step lands in the same place.
            if next.map(\.geometry) == candidate.map(\.geometry) { break }
            candidate = next
        }
        insert(candidate)
    }

    private static func scaled(_ rect: CGRect, by factor: CGFloat) -> CGRect {
        CGRect(x: rect.minX * factor, y: rect.minY * factor, width: rect.width * factor, height: rect.height * factor)
    }
}
