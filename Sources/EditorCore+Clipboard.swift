import CoreGraphics
import Foundation

extension EditorCore {
    /// Cmd+C and Cmd+X: the selected marks and pins, or, for Cmd+C, the drawing when nothing is selected.
    mutating func copy() {
        let marks = drawing.marks.filter { selection.contains($0.id) }, pins = selectedPins
        guard !marks.isEmpty || !pins.isEmpty else {
            emit(.copyDrawing(drawingForHost))
            return
        }
        let order = geometry.readingOrder(marks)
        var words = order.compactMap { id -> String? in
            guard case .text(let text)? = mark(id)?.geometry else { return nil }
            return text.text
        }
        if !pins.isEmpty { words.append(Pin.lineWords(pins)) }
        emit(.copyItems(CopiedItems(pointScale: drawing.pointScale, markScale: drawing.markScale, marks: marks, pins: pins),
                        text: words.isEmpty ? nil : words.joined(separator: "\n")))
    }

    /// The selected pins that Copy, Cut and Duplicate take: every one but a pin before its first
    /// comment, which is in no hand-over either.
    var selectedPins: [Pin] { drawing.pins.filter { selection.contains($0.id) && $0.number > 0 } }

    mutating func paste(_ content: PasteContent) {
        if gesture != nil { cancelGesture() }
        if typing != nil { endTyping() }
        switch content {
        case .items(let copied):
            pasteItems(copied)
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

    /// Copied marks and pins keep their places in the screenshot's points, marks keep their boxes,
    /// and a text keeps its size in drawing pt with its lines, so it takes the size of the notes
    /// already there. On the same screenshot, while the marks or pins they came from are still there,
    /// they land 10 pt right and down, and 10 pt more for each copy already there, with their texts'
    /// lines as they were; anywhere else, where the originals were, placed as marks from outside. Each
    /// pasted pin takes a new number and a new `id`, since its original may still be on the screenshot.
    private mutating func pasteItems(_ copied: CopiedItems) {
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
        let pins = copied.pins.map { pin -> Pin in
            var pin = Self.fresh(pin)
            switch pin.place {
            case .point(let point): pin.place = .point(CGPoint(x: point.x * factor, y: point.y * factor))
            case .area(let frame, let corner): pin.place = .area(Self.scaled(frame, by: factor), tip: corner)
            }
            return pin
        }
        // A mark or a pin already where one of them would land means the originals, or copies of them, are here.
        func present(_ group: (marks: [Mark], pins: [Pin])) -> Bool {
            group.marks.contains { candidate in drawing.marks.contains { $0.geometry == candidate.geometry } }
                || group.pins.contains { candidate in drawing.pins.contains { $0.place == candidate.place } }
        }
        guard present((converted, pins)) else {
            let placed = placedGroup(converted, pins, offset: .zero, keepingLines: false)
            return insert(placed.marks, pins: placed.pins)
        }
        let step = geometry.pt(Self.copyOffset)
        func landing(_ copies: Int) -> (marks: [Mark], pins: [Pin]) {
            placedGroup(converted, pins, offset: CGVector(dx: step * CGFloat(copies), dy: step * CGFloat(copies)), keepingLines: true)
        }
        var copies = 1
        var candidate = landing(1)
        while present(candidate), copies < 1000 {
            copies += 1
            let next = landing(copies)
            // Held against an edge, another step lands in the same place.
            if next.marks.map(\.geometry) == candidate.marks.map(\.geometry), next.pins.map(\.place) == candidate.pins.map(\.place) { break }
            candidate = next
        }
        insert(candidate.marks, pins: candidate.pins)
    }

    /// `marks` and `pins` moved by `offset` as one group, shifted back inside the image together when
    /// the group fits, and each then kept inside on its own (`EditorGeometry.placedGroup`).
    private func placedGroup(_ marks: [Mark], _ pins: [Pin], offset: CGVector, keepingLines: Bool) -> (marks: [Mark], pins: [Pin]) {
        guard !pins.isEmpty else { return (geometry.placedGroup(marks, offset: offset, keepingLines: keepingLines), []) }
        var whole = offset
        let moved = marks.map { geometry.translated($0, by: offset) }
        let markExtent = keepingLines ? geometry.movingExtent(of: moved) : geometry.extent(of: moved)
        let extents = pins.map { $0.moved(by: offset).extent } + [markExtent].compactMap { $0 }
        if let extent = extents.reduce(nil, { union, rect in union?.union(rect) ?? rect }) {
            whole.dx += Mark.shiftInside(from: extent.minX, to: extent.maxX, within: geometry.image.width) ?? 0
            whole.dy += Mark.shiftInside(from: extent.minY, to: extent.maxY, within: geometry.image.height) ?? 0
        }
        return (geometry.placedGroup(marks, offset: whole, keepingLines: keepingLines),
                pins.compactMap { $0.moved(by: whole).placed(in: drawing.pixels) })
    }

    /// Copies of the selected marks and pins 10 pt right and down, kept inside the image, selected.
    mutating func duplicate() {
        let marks = drawing.marks.filter { selection.contains($0.id) }, pins = selectedPins
        guard !marks.isEmpty || !pins.isEmpty else { return }
        let offset = geometry.pt(Self.copyOffset)
        let placed = placedGroup(marks.map(Self.fresh), pins.map(Self.fresh), offset: CGVector(dx: offset, dy: offset), keepingLines: true)
        insert(placed.marks, pins: placed.pins, as: .duplicate)
    }

    /// Puts `marks` on top and `pins` after the others as one step named `name`, selected. The pins take
    /// new numbers from `nextPin` in the order of the numbers they had. Pins past `Pin.maxCount` are
    /// left out, with a beep.
    mutating func insert(_ marks: [Mark], pins: [Pin] = [], as name: StepName = .paste) {
        let room = max(Pin.maxCount - drawing.pins.count, 0)
        let kept = pins.sorted { $0.number < $1.number }.prefix(room)
        defer { if kept.count < pins.count { emit(.beep) } }
        guard !marks.isEmpty || !kept.isEmpty else { return }
        step(named: name) { core in
            for mark in marks { core.add(mark) }
            for var pin in kept {
                pin.number = core.drawing.nextPin
                core.drawing.nextPin += 1
                core.drawing.pins.append(pin)
            }
            core.selection = Set(marks.map(\.id).filter { core.mark($0) != nil } + kept.map(\.id))
        }
    }

    /// A mark with the same fields and a new id.
    static func fresh(_ mark: Mark) -> Mark {
        Mark(geometry: mark.geometry, agent: mark.agent, agentName: mark.agentName)
    }

    /// A pin with the same place, comments and number, and new ids.
    static func fresh(_ pin: Pin) -> Pin {
        Pin(id: UUID(), number: pin.number, place: pin.place, comments: pin.comments.map(\.copied))
    }

    private static func scaled(_ rect: CGRect, by factor: CGFloat) -> CGRect {
        CGRect(x: rect.minX * factor, y: rect.minY * factor, width: rect.width * factor, height: rect.height * factor)
    }
}
