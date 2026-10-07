import CoreGraphics

/// Where an answer's marks go on the screen, in global top-left points
/// (docs/live-ink-integration-2026-10-04.md, "The answer on the screen"). Pure, so a test places
/// an answer with no window.
///
/// The spike drew answers whose loop sat inside the person's loop and whose label covered the number
/// beside it, so every mark here is placed clear of what is already there: the person's ink, the
/// window's text, and the marks of the answer placed before it.
enum LiveAnswerLayout {
    /// What the layout keeps clear of, and where it may draw.
    struct Scene {
        /// The window the answer is about, less a margin: nothing is drawn outside it.
        var room: CGRect
        /// The person's marks, in global top-left points.
        var ink: [Mark]
        /// The window's text lines, in global top-left points.
        var text: [CGRect]
        /// The tags of the person's notes, in global top-left points.
        var notes: [CGRect] = []
        /// The visible screen the window is on, less a margin. A reply's popover is a window of its
        /// own, so it may hang past the window's edge; nil keeps it in `room`.
        var screen: CGRect? = nil
    }

    struct Sizes {
        /// A note's font size, in pt.
        var textSize: CGFloat
        /// The widest a note wraps at, in pt.
        var textWidth: CGFloat
        var style: TextStyle
    }

    /// The agent named on the answer's notes, whose badge and logo they carry.
    static let agentName = "claude"

    /// The answer's marks: its reply first, then each mark it points with, and a mark's label beside
    /// it. The reply is a popover hung from the first mark it points with, so the words lead along the
    /// mark to what it points at, placed with that mark's label so that neither covers the other. It
    /// hangs from `asked`, the person's ink the ask was about, when the answer points at nothing, or
    /// points in steps, whose marks come and go. `targets` holds each answer mark's target in global top-left
    /// points, or nil for one whose target was not found, which is dropped. `streamed` is the reply
    /// as it streamed in, which keeps where it hangs and its id: it is being read. `quote` is the
    /// words of the note the person asked with, which the reply's header quotes. `below` is room kept
    /// at the foot of the reply, for its actions. `findings` holds, for each of the answer's marks,
    /// the ids of the mark drawn for it and its label, none for one that was dropped, which the
    /// answer's actions name by index. `tour` holds where the reply hangs while each focus after the
    /// first is shown, by the focus mark's id.
    static func placed(for answer: LiveAnswer, targets: [CGRect?], asked: CGRect, quote: String? = nil, scene: Scene,
                       sizes: Sizes, streamed: Mark? = nil, below: CGFloat = 0)
        -> (marks: [Mark], findings: [[Mark.ID]], tour: [Mark.ID: PopoverPlace]) {
        // No note of the answer covers what the answer points at. `marks` is what nothing may cover:
        // the person's marks and notes, the targets, and what the answer has drawn so far.
        let pointed = targets.compactMap { $0?.insetBy(dx: -4, dy: -4) }
        let text = scene.text.map { $0.insetBy(dx: -2, dy: -2) } + enclosed(in: scene)
        var marks = personsMarks(in: scene) + pointed
        var placed: [Mark] = []
        // A reply that streamed in is being read where it hangs, so the marks keep clear of it.
        var say = streamed.map { grown($0, to: answer.say, sizes: sizes, foot: below) }
        if let body = say?.popover?.body { marks.append(body.insetBy(dx: -spacing, dy: -spacing)) }
        // The first arrow's tail, which later arrows from the same side start level with, so their
        // labels stand in one column, as a person annotating a page lines them up.
        var column: (x: CGFloat, fromRight: Bool)?
        var findings: [[Mark.ID]] = []
        // A focus shows alone, so a later stop's reply only keeps clear of what shows with every stop.
        var staying = marks
        var stops: [(mark: Mark, label: Mark?)] = []
        for (answerMark, target) in zip(answer.marks, targets) {
            findings.append([])
            guard let target else { continue }
            // A mark and its label are placed together: of the ways to point, the one whose label
            // covers least, so a label is not pushed onto another note by where its arrow went.
            var best: (mark: Mark, label: Mark?, cost: CGFloat)?
            // A step is something to click, so a focus in steps is a circle.
            let kind = answer.steps && answerMark.kind == .focus ? .circle : answerMark.kind
            for mark in pointers(kind, at: target, scene: scene, obstacles: marks + text, column: column?.x, zoom: answerMark.zoom) {
                guard let extent = mark.shapeExtent else { continue }
                var total = cost(extent, room: scene.room, obstacles: marks + text)
                if case .arrow(let arrow) = mark.geometry {
                    // A long arrow only when the short one's label has no room.
                    if isLong(arrow) { total += longCost }
                    if let column {
                        total += (arrow.start.x > arrow.end.x) == column.fromRight ? abs(arrow.start.x - column.x) * 4 : otherSide
                    }
                }
                var tag: Mark?
                // A label touches its own mark, so only the others count against it.
                if let label = answerMark.label {
                    let spot = self.label(label, of: mark, room: scene.room, marks: marks, text: text, sizes: sizes)
                    tag = spot?.mark
                    total += spot?.cost ?? missingLabel
                }
                if total < best?.cost ?? .infinity { best = (mark, tag, total) }
            }
            guard let best, let extent = best.mark.shapeExtent else { continue }
            var tag = best.label
            if say == nil, !answer.steps {
                // Its label goes in the room the reply leaves, and the reply goes where the two cover least.
                let hung = hung(answer.say, quote: quote, from: best.mark, spots: spots(from: best.mark), scene: scene, marks: marks,
                                text: text, sizes: sizes, below: below) { body in
                    guard let label = answerMark.label else { return (nil, 0) }
                    let spot = self.label(label, of: best.mark, room: scene.room, marks: marks + [body.insetBy(dx: -spacing, dy: -spacing)],
                                          text: text, sizes: sizes)
                    return (spot?.mark, spot?.cost ?? missingLabel)
                }
                say = hung.reply
                tag = hung.label
                if let body = hung.reply.popover?.body { marks.append(body.insetBy(dx: -spacing, dy: -spacing)) }
            }
            placed.append(best.mark)
            marks.append(extent.insetBy(dx: -spacing, dy: -spacing))
            if column == nil, case .arrow(let arrow) = best.mark.geometry { column = (arrow.start.x, arrow.start.x > arrow.end.x) }
            findings[findings.count - 1] = [best.mark.id] + (tag.map { [$0.id] } ?? [])
            let box = tag.flatMap { noteBox($0, sizes: sizes) }
            if let tag, let box {
                placed.append(tag)
                marks.append(box.insetBy(dx: -spacing, dy: -spacing))
            }
            if best.mark.focus != nil {
                stops.append((best.mark, box == nil ? nil : tag))
            } else {
                staying.append(extent.insetBy(dx: -spacing, dy: -spacing))
                if let box { staying.append(box.insetBy(dx: -spacing, dy: -spacing)) }
            }
        }
        let reply = say ?? hung(answer.say, quote: quote, from: nil, spots: sides(of: asked), scene: scene, marks: marks, text: text,
                                sizes: sizes, below: below).reply
        // A tour moves the reply to each focus in turn, hung from it as from the first, with its label
        // put back beside it. The reply's side comes first, so it slides rather than turning round.
        var tour: [Mark.ID: PopoverPlace] = [:]
        if !answer.steps, stops.count > 1, let first = reply.popover {
            for stop in stops.dropFirst() {
                let spots = spots(from: stop.mark).sorted { $0.edge == first.edge && $1.edge != first.edge }
                let hung = hung(answer.say, quote: quote, from: stop.mark, spots: spots, scene: scene, marks: staying, text: text,
                                sizes: sizes, below: below) { body in
                    guard let tag = stop.label, case .text(let words) = tag.geometry else { return (nil, 0) }
                    let spot = label(words.text, of: stop.mark, room: scene.room, marks: staying + [body.insetBy(dx: -spacing, dy: -spacing)],
                                     text: text, sizes: sizes, keeping: tag)
                    return (spot?.mark, spot?.cost ?? missingLabel)
                }
                guard let place = hung.reply.popover else { continue }
                tour[stop.mark.id] = place
                if let moved = hung.label, let index = placed.firstIndex(where: { $0.id == moved.id }) { placed[index] = moved }
            }
        }
        return ([reply] + placed, findings, tour)
    }

    /// What an arrow from the other side than the answer's first costs, in square points: about a
    /// label covering a line of text, so the arrows come from one side unless that covers more.
    static let otherSide: CGFloat = 3_000

    /// What leaving a label out costs when choosing where its mark goes, in square points: more than
    /// a label covering a few lines of text.
    static let missingLabel: CGFloat = 20_000

    /// `text` as the label of `mark`, where a hand writes one (`handSpots`): touching an arrow's tail,
    /// away from what it points at, or against a circle's edge. A label away from its mark reads as
    /// another mark's, so it covers the window's text there if it must. Nil when every spot leaves the
    /// room or covers a quarter of itself in `marks`. Answers the label and what its spot costs. A
    /// label already `placed` is moved rather than made again, so it keeps its id.
    private static func label(_ text: String, of mark: Mark, room: CGRect, marks: [CGRect], text lines: [CGRect],
                              sizes: Sizes, keeping placed: Mark? = nil) -> (mark: Mark, cost: CGFloat)? {
        let words = Mark.Geometry.text(Mark.Text(origin: .zero, text: text, wrap: sizes.textWidth, size: sizes.textSize))
        var tag = placed ?? Mark(geometry: words, agent: true, agentName: agentName)
        tag.geometry = words
        tag.isLabel = true
        guard let box = noteBox(tag, sizes: sizes) else { return nil }
        let spot = best(handSpots(box.size, for: mark), size: box.size, room: room, marks: marks, text: lines)
        guard cost(spot.rect, room: room, obstacles: marks) < box.width * box.height / 4 else { return nil }
        return (moved(tag, box: box, to: spot.rect.origin, sizes: sizes), spot.cost)
    }

    /// The least gap between an answer's marks, in pt.
    static let spacing: CGFloat = 12

    // MARK: Pointing

    /// A line this many times wider than tall is boxed rather than circled: an ellipse round it
    /// would cover the lines above and below.
    static let longLine: CGFloat = 8
    /// An arrow's length, and its gap from what it points at, in pt.
    static let arrowLength: CGFloat = 64
    static let arrowGap: CGFloat = 6
    /// How much longer the fallback arrows are, and what drawing one costs, in square points: more
    /// than a label one step down its order, less than leaving it out.
    static let longArrow: CGFloat = 1.9
    static let longCost: CGFloat = 2_000

    private static func isLong(_ arrow: Mark.Arrow) -> Bool {
        hypot(arrow.start.x - arrow.end.x, arrow.start.y - arrow.end.y) > arrowLength * 1.4
    }

    /// The ways to point at `target`, best first: a circle, or each arrow, least covering first. A
    /// circle that would sit on a loop of the person's gives way to the arrows, since two loops round
    /// one thing read as one. A circle is kept inside the room, so one round something at the
    /// window's edge is not cut off. `column` adds arrows from either side whose tails stand at that x.
    /// A focus is a rectangle that draws no stroke: the sharp spot round the target, or with `zoom`
    /// the lens over it, which the rest of the answer keeps clear of.
    static func pointers(_ kind: AnswerMark.Kind, at target: CGRect, scene: Scene, obstacles: [CGRect], column: CGFloat? = nil,
                         zoom: Bool = false) -> [Mark] {
        if kind == .focus {
            var mark = Mark(geometry: .rectangle(zoom ? Focus.lens(over: target, in: scene.room) : Focus.spot(around: target)),
                            agent: true, agentName: agentName)
            mark.focus = FocusPlace(target: target, zoom: zoom)
            return [mark]
        }
        if kind == .circle {
            let round = inside(circle(around: target), scene.room)
            let frame: CGRect = switch round {
            case .ellipse(let frame), .rectangle(let frame): frame
            default: target
            }
            if !scene.ink.contains(where: { overlapsLoop($0, frame) }) {
                return [Mark(geometry: round, agent: true, agentName: agentName)]
            }
        }
        return arrows(to: target, room: scene.room, obstacles: obstacles, column: column).map {
            Mark(geometry: .arrow($0), agent: true, agentName: agentName)
        }
    }

    private static func inside(_ geometry: Mark.Geometry, _ room: CGRect) -> Mark.Geometry {
        switch geometry {
        case .ellipse(let frame) where !frame.intersection(room).isNull: .ellipse(frame.intersection(room))
        case .rectangle(let frame) where !frame.intersection(room).isNull: .rectangle(frame.intersection(room))
        default: geometry
        }
    }

    /// An ellipse padded round `target`, or a box round a long line.
    static func circle(around target: CGRect) -> Mark.Geometry {
        let height = max(target.height, 8)
        if target.width > height * longLine {
            return .rectangle(target.insetBy(dx: -max(4, height * 0.3), dy: -max(3, height * 0.25)))
        }
        // An ellipse through a rect's corners is √2 its size; a little less keeps it off the
        // neighbouring lines while the words stay inside.
        return .ellipse(target.insetBy(dx: -max(8, target.width * 0.18), dy: -max(6, height * 0.4)))
    }

    /// Whether `mark` is a loop of the person's that covers most of `frame`, or most of which `frame` covers.
    private static func overlapsLoop(_ mark: Mark, _ frame: CGRect) -> Bool {
        guard case .ellipse(let loop) = mark.geometry else { return false }
        let shared = loop.intersection(frame)
        guard !shared.isNull else { return false }
        let smaller = min(loop.width * loop.height, frame.width * frame.height)
        return smaller > 0 && shared.width * shared.height / smaller > 0.5
    }

    /// The arrows ending `arrowGap` from `target`, one from each side, least covering first. With a
    /// `column`, also the arrows from the right and the left whose tails stand at that x, when it
    /// leaves them a usable length.
    static func arrows(to target: CGRect, room: CGRect, obstacles: [CGRect], column: CGFloat? = nil) -> [Mark.Arrow] {
        let length = arrowLength, gap = arrowGap
        // Each starts below and out to one side, as a hand draws an arrow, except the ones from
        // above and below. The longer ones are for a label that has no room at a short one's tail.
        var candidates: [(start: CGPoint, end: CGPoint)] = [1, longArrow].flatMap { scale -> [(start: CGPoint, end: CGPoint)] in
            let length = length * scale
            return [
                (CGPoint(x: target.maxX + gap + length * 0.8, y: target.midY + length * 0.6), CGPoint(x: target.maxX + gap, y: target.midY)),
                (CGPoint(x: target.minX - gap - length * 0.8, y: target.midY + length * 0.6), CGPoint(x: target.minX - gap, y: target.midY)),
                (CGPoint(x: target.midX + length * 0.3, y: target.maxY + gap + length * 0.95), CGPoint(x: target.midX, y: target.maxY + gap)),
                (CGPoint(x: target.midX + length * 0.3, y: target.minY - gap - length * 0.95), CGPoint(x: target.midX, y: target.minY - gap)),
            ]
        }
        if let column {
            for end in [CGPoint(x: target.maxX + gap, y: target.midY), CGPoint(x: target.minX - gap, y: target.midY)] {
                let reach = abs(column - end.x)
                guard (column > end.x) == (end.x > target.midX), reach >= length * 0.5, reach <= length * 3 else { continue }
                candidates.append((CGPoint(x: column, y: end.y + length * 0.6), end))
            }
        }
        // Of two that cover as much, the short one first.
        func covered(_ arrow: Mark.Arrow) -> CGFloat {
            cost(span(arrow.start, arrow.end), room: room, obstacles: obstacles) + (isLong(arrow) ? 1 : 0)
        }
        return candidates.map { Mark.Arrow(start: $0.start, end: $0.end) }.sorted { covered($0) < covered($1) }
    }

    private static func span(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)).insetBy(dx: -4, dy: -4)
    }

    // MARK: Notes

    /// What a note keeps clear of: the person's ink and notes, what their loops enclose, and the
    /// window's text.
    static func obstacles(in scene: Scene) -> [CGRect] {
        personsMarks(in: scene) + enclosed(in: scene) + scene.text.map { $0.insetBy(dx: -2, dy: -2) }
    }

    /// The person's strokes and notes, with room round them.
    private static func personsMarks(in scene: Scene) -> [CGRect] {
        scene.ink.flatMap { strokes(of: $0, pad: 6) } + scene.notes.map { $0.insetBy(dx: -spacing, dy: -spacing) }
    }

    /// What the person's loops and boxes enclose, which a note avoids as it avoids text: it covers
    /// what they pointed at, but a loop round a whole page leaves nowhere else.
    private static func enclosed(in scene: Scene) -> [CGRect] {
        scene.ink.compactMap { mark -> CGRect? in
            switch mark.geometry {
            case .ellipse(let frame), .rectangle(let frame): frame
            default: nil
            }
        }
    }

    /// The line `mark` draws, as small rects along it with `pad` round each: a loop is its outline,
    /// not the area it encloses, so a note inside a loop round a whole page covers none of it.
    static func strokes(of mark: Mark, pad: CGFloat) -> [CGRect] {
        let points: [CGPoint]
        switch mark.geometry {
        case .ellipse(let frame):
            points = (0...36).map { step in
                let angle = CGFloat(step) / 36 * 2 * .pi
                return CGPoint(x: frame.midX + frame.width / 2 * cos(angle), y: frame.midY + frame.height / 2 * sin(angle))
            }
        case .rectangle(let frame):
            points = [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.maxY),
                      CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.minX, y: frame.minY)]
        case .arrow(let arrow):
            let via = arrow.via.isEmpty ? (arrow.bend != 0 ? [arrow.bendPoint] : []) : arrow.via
            let stride = max(1, via.count / 24)
            points = [arrow.start] + Swift.stride(from: 0, to: via.count, by: stride).map { via[$0] } + [arrow.end]
        case .text:
            return []
        }
        let lines = zip(points, points.dropFirst()).map { a, b in
            CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)).insetBy(dx: -pad, dy: -pad)
        }
        // An arrow's head is wider than its line.
        if case .arrow(let arrow) = mark.geometry { return lines + [CGRect(origin: arrow.end, size: .zero).insetBy(dx: -pad - 8, dy: -pad - 8)] }
        return lines
    }

    /// Where the person's note about `mark` goes, as a hand puts one (`handSpots`). `size` is the
    /// note's tag, at the width it may grow to, and `under` the room kept below it. It may cover the
    /// window's text beside the ink, but never goes elsewhere: a note away from its ink reads as being
    /// about something else. Answers the tag's rect and whether it grows to the left, keeping its
    /// right edge at the ink.
    static func noteSpot(_ size: CGSize, under: CGFloat = 0, for mark: Mark, scene: Scene) -> (rect: CGRect, growsLeft: Bool) {
        let others = LiveAnswerLayout.Scene(room: scene.room, ink: scene.ink.filter { $0.id != mark.id }, text: scene.text)
        let marks = others.ink.flatMap { strokes(of: $0, pad: 4) } + scene.notes
        let spot = best(handSpots(size, under: under, for: mark), size: size, under: under, room: scene.room, marks: marks,
                        text: scene.text + enclosed(in: others))
        return (spot.rect, spot.growsLeft)
    }

    /// Where a hand writes about `mark`, most natural first: touching an arrow's tail on the side
    /// away from its head, or against a loop's or a box's edge, or just inside the top of a loop. Each
    /// is a top-left corner for a box of `size` with `under` kept below it, and whether the box grows
    /// to the left, keeping its right edge at the mark.
    static func handSpots(_ size: CGSize, under: CGFloat = 0, for mark: Mark) -> [(origin: CGPoint, growsLeft: Bool)] {
        let gap: CGFloat = 6, w = size.width, h = size.height
        if case .arrow(let arrow) = mark.geometry {
            let away = leaving(arrow)
            let t = arrow.start
            // Each spot touches the tail, with the direction from the tail to the note's middle. Only
            // the spots straight above it keep `under` clear, since their chip would cross the tail.
            let candidates: [(CGPoint, Bool, CGVector)] = [
                (CGPoint(x: t.x + gap, y: t.y - h / 2), false, CGVector(dx: 1, dy: 0)),
                (CGPoint(x: t.x - gap - w, y: t.y - h / 2), true, CGVector(dx: -1, dy: 0)),
                (CGPoint(x: t.x - 24, y: t.y - gap - h - under), false, CGVector(dx: 0.3, dy: -1)),
                (CGPoint(x: t.x + 24 - w, y: t.y - gap - h - under), true, CGVector(dx: -0.3, dy: -1)),
                (CGPoint(x: t.x - 24, y: t.y + gap), false, CGVector(dx: 0.3, dy: 1)),
                (CGPoint(x: t.x + 24 - w, y: t.y + gap), true, CGVector(dx: -0.3, dy: 1)),
                (CGPoint(x: t.x + gap, y: t.y - gap - h), false, CGVector(dx: 1, dy: -1)),
                (CGPoint(x: t.x - gap - w, y: t.y - gap - h), true, CGVector(dx: -1, dy: -1)),
                (CGPoint(x: t.x + gap, y: t.y + gap), false, CGVector(dx: 1, dy: 1)),
                (CGPoint(x: t.x - gap - w, y: t.y + gap), true, CGVector(dx: -1, dy: 1)),
            ]
            func facing(_ v: CGVector) -> CGFloat { (v.dx * away.dx + v.dy * away.dy) / hypot(v.dx, v.dy) }
            return candidates.sorted { facing($0.2) > facing($1.2) }.map { ($0.0, $0.1) }
        }
        guard let extent = mark.shapeExtent else { return [] }
        return [
            (CGPoint(x: extent.maxX + gap, y: extent.midY - h / 2), false),
            (CGPoint(x: extent.minX, y: extent.minY - gap - h - under), false),
            (CGPoint(x: extent.minX - gap - w, y: extent.midY - h / 2), true),
            (CGPoint(x: extent.minX, y: extent.maxY + gap), false),
            (CGPoint(x: extent.maxX - w, y: extent.minY - gap - h - under), true),
            (CGPoint(x: extent.maxX - w, y: extent.maxY + gap), true),
            // Inside the top of a loop that fills the room, under the loop's top.
            (CGPoint(x: extent.midX - w / 2, y: extent.minY + gap * 2), false),
        ]
    }

    /// The way an arrow leaves its tail, as a unit vector from the stroke back to the tail: measured
    /// over the stroke's first `tailReach` pt, so a hook near the head does not turn it.
    static func leaving(_ arrow: Mark.Arrow) -> CGVector {
        let path = [arrow.start] + (arrow.via.isEmpty && arrow.bend != 0 ? [arrow.bendPoint] : arrow.via) + [arrow.end]
        var along = arrow.end, travelled: CGFloat = 0
        for (a, b) in zip(path, path.dropFirst()) {
            travelled += hypot(b.x - a.x, b.y - a.y)
            if travelled >= tailReach { along = b; break }
        }
        let length = max(hypot(along.x - arrow.start.x, along.y - arrow.start.y), 1)
        return CGVector(dx: (arrow.start.x - along.x) / length, dy: (arrow.start.y - along.y) / length)
    }

    /// How much of a stroke from its tail says which way it leaves, in pt.
    static let tailReach: CGFloat = 24

    /// Of `spots`, the one covering least: `marks` count fully, and the window's `text` a little,
    /// since a note covering a word beside its ink reads better than one away from it. Each step down
    /// the order costs about a short word.
    private static func best(_ spots: [(origin: CGPoint, growsLeft: Bool)], size: CGSize, under: CGFloat = 0, room: CGRect,
                             marks: [CGRect], text: [CGRect]) -> (rect: CGRect, growsLeft: Bool, cost: CGFloat) {
        var best = (rect: CGRect(origin: spots.first?.origin ?? .zero, size: size), growsLeft: spots.first?.growsLeft ?? false,
                    cost: CGFloat.infinity)
        for (rank, spot) in spots.enumerated() {
            let rect = CGRect(origin: spot.origin, size: CGSize(width: size.width, height: size.height + under))
            let covered = cost(rect, room: room, obstacles: marks) * 4 + cost(rect, room: room, obstacles: text) * 0.25 + CGFloat(rank) * 300
            if covered < best.cost { best = (CGRect(origin: spot.origin, size: size), spot.growsLeft, covered) }
        }
        return best
    }

    /// Where a reply hangs from a mark it points with: off the middle of a circle's or a box's side,
    /// or from an arrow's tail, so the words lead along the arrow to what it points at.
    private static func spots(from mark: Mark) -> [(at: CGRect, edge: PopoverPlace.Edge)] {
        guard case .arrow(let arrow) = mark.geometry else { return sides(of: mark.shapeExtent ?? .null) }
        let tail = CGRect(x: arrow.start.x - 0.5, y: arrow.start.y - 0.5, width: 1, height: 1)
        return PopoverPlace.Edge.allCases.map { (tail, $0) }
    }

    /// The reply as a popover hung from `ink`, the person's ink the ask was about, off the middle of
    /// one of its sides, clear of the person's marks and notes: an answer that points at nothing, or
    /// that points in steps, and a reply as it streams in, before its marks are known.
    static func reply(_ text: String, quote: String?, from ink: CGRect, scene: Scene, sizes: Sizes, below: CGFloat = 0) -> Mark {
        hung(text, quote: quote, from: nil, spots: sides(of: ink), scene: scene, marks: personsMarks(in: scene),
             text: scene.text.map { $0.insetBy(dx: -2, dy: -2) } + enclosed(in: scene), sizes: sizes, below: below).reply
    }

    /// A popover's arrow stands this far off the edge of what it hangs from, in pt, clear of its stroke.
    static let standOff: CGFloat = 3

    /// The middle of each side of `frame`, where a popover's arrow points, `standOff` outside it, in
    /// the order a popover is tried: under, over, right, left.
    private static func sides(of frame: CGRect) -> [(at: CGRect, edge: PopoverPlace.Edge)] {
        let off = standOff
        func point(_ x: CGFloat, _ y: CGFloat) -> CGRect { CGRect(x: x - 0.5, y: y - 0.5, width: 1, height: 1) }
        return [(point(frame.midX, frame.maxY + off), .below), (point(frame.midX, frame.minY - off), .above),
                (point(frame.maxX + off, frame.midY), .right), (point(frame.minX - off, frame.midY), .left)]
    }

    /// The reply's popover at the first of `spots` whose body covers nothing and stays on the screen.
    /// Failing that, of the spots clear of `marks`, the person's and the answer's, the one covering
    /// least of the window's `text`, and failing those, the one covering least, with `marks` counting
    /// fully and `text` a little. Each step down the order costs a little. Marks come first: one under
    /// the reply is a part of the conversation hidden, and on a page of text some text is always
    /// covered. A reply hung from `mark` touches it, so only that mark's strokes count against it.
    /// `beside` places a note that must keep clear of the body, such as the mark's label, and answers
    /// what it costs, which counts with the body's.
    private static func hung(_ text: String, quote: String?, from mark: Mark?, spots: [(at: CGRect, edge: PopoverPlace.Edge)],
                             scene: Scene, marks: [CGRect], text lines: [CGRect], sizes: Sizes, below: CGFloat,
                             beside: (CGRect) -> (note: Mark?, cost: CGFloat) = { _ in (nil, 0) }) -> (reply: Mark, label: Mark?) {
        let size = ReplyContent.size(text, agent: agentName, quote: quote, wrap: sizes.textWidth, foot: below)
        let room = scene.screen ?? scene.room
        let around = marks + (mark.map { strokes(of: $0, pad: 4) } ?? [])
        var best: (place: PopoverPlace, note: Mark?, clear: Bool, cost: CGFloat)?
        for (rank, spot) in spots.enumerated() {
            let body = PopoverPlace.body(size, hungFrom: spot.at, edge: spot.edge)
            let onMarks = cost(body, room: room, obstacles: around), onText = cost(body, room: room, obstacles: lines)
            let place = PopoverPlace(anchor: mark?.id, at: spot.at, edge: spot.edge, body: body, foot: below)
            let note = beside(body)
            // Under a square point is rounding, as in `place`.
            if onMarks + onText + note.cost < 1 { best = (place, note.note, true, 0); break }
            let clear = onMarks < 1 && note.cost < missingLabel
            let total = onMarks * 4 + onText * 0.25 + CGFloat(rank) * 300 + note.cost
            if best.map({ clear != $0.clear ? clear : total < $0.cost }) ?? true { best = (place, note.note, clear, total) }
        }
        var reply = Mark(geometry: .text(Mark.Text(origin: best?.place.body.origin ?? .zero, text: text, wrap: sizes.textWidth, size: sizes.textSize)),
                         agent: true, agentName: agentName)
        reply.quote = quote
        reply.popover = best?.place
        return (reply, best?.note)
    }

    /// `mark`, a note whose box is `box`, with that box's top-left moved to `origin`.
    private static func moved(_ mark: Mark, box: CGRect, to origin: CGPoint, sizes: Sizes) -> Mark {
        guard case .text(let text) = mark.geometry else { return mark }
        var moved = mark
        // The box starts above the text's origin by the badge's overlap. The wrap stays the widest a
        // note may be, so a reply that streams in wraps where the whole reply will.
        moved.geometry = .text(Mark.Text(origin: CGPoint(x: origin.x - box.minX, y: origin.y - box.minY), text: text.text,
                                         wrap: sizes.textWidth, size: sizes.textSize))
        return moved
    }

    /// `reply` with its words now `text`, as it streams in, and `foot` points kept at its foot. It
    /// keeps where it hangs, so it grows away from what it hangs from rather than moving while it is
    /// read.
    static func grown(_ reply: Mark, to text: String, sizes: Sizes, foot: CGFloat = 0) -> Mark {
        guard case .text(var words) = reply.geometry, var place = reply.popover else { return reply }
        words.text = text
        place.foot = foot
        let size = ReplyContent.size(text, agent: reply.agentName, quote: reply.quote, wrap: words.wrap ?? sizes.textWidth, foot: foot)
        place.body = PopoverPlace.body(size, hungFrom: place.at, edge: place.edge)
        words.origin = place.body.origin
        var grown = reply
        grown.geometry = .text(words)
        grown.popover = place
        return grown
    }

    /// A note of `text` in the agent's style, placed beside `near`, with `below` points of room
    /// kept under it.
    /// `byPerson` makes it the person's note, measured in their font.
    static func note(_ text: String, near: CGRect, scene: Scene, obstacles: [CGRect], sizes: Sizes, below: CGFloat = 0,
                     byPerson: Bool = false) -> Mark {
        let mark = Mark(geometry: .text(Mark.Text(origin: .zero, text: text, wrap: sizes.textWidth, size: sizes.textSize)),
                        agent: !byPerson, agentName: agentName)
        let box = noteBox(mark, sizes: sizes) ?? CGRect(x: 0, y: 0, width: sizes.textWidth, height: sizes.textSize * 2)
        let spot = place(CGSize(width: box.width, height: box.height + below), near: near, room: scene.room, obstacles: obstacles)
        return moved(mark, box: box, to: spot.origin, sizes: sizes)
    }

    /// The person's note, whose tag starts at `spot`'s left edge, centred on it from top to bottom,
    /// as their words take the place of the note panel they were typed in.
    static func note(_ text: String, at spot: CGRect, sizes: Sizes) -> Mark {
        let mark = Mark(geometry: .text(Mark.Text(origin: .zero, text: text, wrap: sizes.textWidth, size: sizes.textSize)))
        let box = noteBox(mark, sizes: sizes) ?? CGRect(x: 0, y: 0, width: sizes.textWidth, height: sizes.textSize * 2)
        var moved = mark
        moved.geometry = .text(Mark.Text(origin: CGPoint(x: spot.minX - box.minX, y: spot.midY - box.height / 2 - box.minY), text: text,
                                         wrap: sizes.textWidth, size: sizes.textSize))
        return moved
    }

    /// The tag `mark` draws, with the badge across its top edge, or a reply's popover body, in global
    /// top-left points.
    static func noteBox(_ mark: Mark, sizes: Sizes) -> CGRect? {
        if let body = mark.popover?.body { return body }
        guard case .text(let text) = mark.geometry else { return nil }
        let layout = TextLayout(text, imageWidth: .greatestFiniteMagnitude, pointScale: 1, style: sizes.style.forMark(mark))
        let badge = layout.badge == nil ? 0 : sizes.textSize * sizes.style.badgeOverlap
        return CGRect(x: layout.box.minX, y: layout.box.minY - badge, width: layout.box.width, height: layout.box.height + badge)
    }

    /// Where a box of `size` goes: beside `near`, inside `room`, covering as little of `obstacles` as
    /// it can. The spots beside it are tried first, then the rest of the room, nearest first; the
    /// first that covers nothing wins, and failing one, the one covering least, with its distance
    /// as a small cost. Ported from the first spike's tag placement.
    private static func place(_ size: CGSize, near: CGRect, room: CGRect, obstacles: [CGRect]) -> CGRect {
        let gap: CGFloat = 10
        var spots = [
            CGPoint(x: near.maxX + gap, y: near.midY - size.height / 2),
            CGPoint(x: near.minX - gap - size.width, y: near.midY - size.height / 2),
            CGPoint(x: near.midX - size.width / 2, y: near.maxY + gap),
            CGPoint(x: near.midX - size.width / 2, y: near.minY - gap - size.height),
            CGPoint(x: near.minX, y: near.maxY + gap),
            CGPoint(x: near.maxX - size.width, y: near.maxY + gap),
            CGPoint(x: near.minX, y: near.minY - gap - size.height),
            CGPoint(x: near.maxX - size.width, y: near.minY - gap - size.height),
        ]
        func distance(_ origin: CGPoint) -> CGFloat {
            let rect = CGRect(origin: origin, size: size)
            let dx = max(0, near.minX - rect.maxX, rect.minX - near.maxX), dy = max(0, near.minY - rect.maxY, rect.minY - near.maxY)
            return hypot(dx, dy)
        }
        var far: [CGPoint] = []
        if room.width >= size.width, room.height >= size.height {
            for x in stride(from: room.minX, through: room.maxX - size.width, by: 12) {
                for y in stride(from: room.minY, through: room.maxY - size.height, by: 12) { far.append(CGPoint(x: x, y: y)) }
            }
        }
        spots += far.sorted { distance($0) < distance($1) }
        var best = spots[0], bestCost = CGFloat.infinity
        for origin in spots {
            let covered = cost(CGRect(origin: origin, size: size), room: room, obstacles: obstacles)
            // Under a square point is rounding: a rect inside the room measured 3e-11 outside it.
            if covered < 1 { return CGRect(origin: origin, size: size) }
            let total = covered + distance(origin) * 2
            if total < bestCost { best = origin; bestCost = total }
        }
        return CGRect(origin: best, size: size)
    }

    /// What a rect covers: the area of `obstacles` under it, and four times the area outside `room`.
    static func cost(_ rect: CGRect, room: CGRect, obstacles: [CGRect]) -> CGFloat {
        let inside = rect.intersection(room)
        let outside = rect.width * rect.height - (inside.isNull ? 0 : inside.width * inside.height)
        let covered = obstacles.reduce(CGFloat(0)) { total, obstacle in
            let shared = rect.intersection(obstacle)
            return total + (shared.isNull ? 0 : shared.width * shared.height)
        }
        return outside * 4 + covered
    }
}
