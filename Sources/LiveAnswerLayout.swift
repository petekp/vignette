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

    /// The answer's marks: its reply (`reply`), then each mark it points with, and a mark's label
    /// beside it. `asked` is the person's ink the ask was about, and `question` the tag of the note
    /// they asked with, if they wrote one. `targets` holds each answer mark's target in global
    /// top-left points, or nil for one whose target was not found, which is dropped. The reply comes
    /// first, so it gets the spot under the question. `streamed` is the reply's note as it streamed
    /// in, which keeps its place and its id. `below` is room kept under the reply's note, for its actions.
    static func marks(for answer: LiveAnswer, targets: [CGRect?], asked: CGRect, question: CGRect? = nil, scene: Scene, sizes: Sizes,
                      streamed: Mark? = nil, below: CGFloat = 0) -> [Mark] {
        placed(for: answer, targets: targets, asked: asked, question: question, scene: scene, sizes: sizes, streamed: streamed, below: below).marks
    }

    /// `marks(for:)`, and for each of the answer's marks the ids of the mark drawn for it and its
    /// label, none for one that was dropped, which the answer's actions name by index.
    static func placed(for answer: LiveAnswer, targets: [CGRect?], asked: CGRect, question: CGRect? = nil, scene: Scene, sizes: Sizes,
                       streamed: Mark? = nil, below: CGFloat = 0) -> (marks: [Mark], findings: [[Mark.ID]]) {
        // No note of the answer covers what the answer points at. `marks` is what nothing may cover:
        // the person's marks and notes, the targets, and what the answer has drawn so far.
        let pointed = targets.compactMap { $0?.insetBy(dx: -4, dy: -4) }
        let text = scene.text.map { $0.insetBy(dx: -2, dy: -2) }
        var marks = personsMarks(in: scene) + pointed
        var placed: [Mark] = []
        let say = streamed.map { grown($0, to: answer.say, near: question ?? asked, scene: scene, sizes: sizes) }
            ?? reply(answer.say, question: question, near: asked, scene: scene, obstacles: marks + text, pointed: pointed, sizes: sizes,
                     below: below)
        placed.append(say)
        if let box = noteBox(say, sizes: sizes) {
            marks.append(CGRect(x: box.minX, y: box.minY, width: box.width, height: box.height + below).insetBy(dx: -spacing, dy: -spacing))
        }
        // The first arrow's tail, which later arrows from the same side start level with, so their
        // labels stand in one column, as a person annotating a page lines them up.
        var column: (x: CGFloat, fromRight: Bool)?
        var findings: [[Mark.ID]] = []
        for (answerMark, target) in zip(answer.marks, targets) {
            findings.append([])
            guard let target else { continue }
            // A mark and its label are placed together: of the ways to point, the one whose label
            // covers least, so a label is not pushed onto another note by where its arrow went.
            var best: (mark: Mark, label: Mark?, cost: CGFloat)?
            for mark in pointers(answerMark.kind, at: target, scene: scene, obstacles: marks + text, column: column?.x) {
                guard let extent = mark.shapeExtent else { continue }
                var total = cost(extent, room: scene.room, obstacles: marks + text)
                if case .arrow(let arrow) = mark.geometry, let column {
                    total += (arrow.start.x > arrow.end.x) == column.fromRight ? abs(arrow.start.x - column.x) * 4 : otherSide
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
            placed.append(best.mark)
            findings[findings.count - 1] = [best.mark.id] + (best.label.map { [$0.id] } ?? [])
            marks.append(extent.insetBy(dx: -spacing, dy: -spacing))
            if column == nil, case .arrow(let arrow) = best.mark.geometry { column = (arrow.start.x, arrow.start.x > arrow.end.x) }
            if let tag = best.label, let box = noteBox(tag, sizes: sizes) {
                placed.append(tag)
                marks.append(box.insetBy(dx: -spacing, dy: -spacing))
            }
        }
        return (placed, findings)
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
    /// room or covers a quarter of itself in `marks`. Answers the label and what its spot costs.
    private static func label(_ text: String, of mark: Mark, room: CGRect, marks: [CGRect], text lines: [CGRect],
                              sizes: Sizes) -> (mark: Mark, cost: CGFloat)? {
        var tag = Mark(geometry: .text(Mark.Text(origin: .zero, text: text, wrap: sizes.textWidth, size: sizes.textSize)),
                       agent: true, agentName: agentName)
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

    /// A circle round `target`, or an arrow at it. A circle that would sit on a loop of the person's
    /// is drawn as an arrow instead, since two loops round one thing read as one. A circle is kept
    /// inside the room, so one round something at the window's edge is not cut off.
    static func pointer(_ kind: AnswerMark.Kind, at target: CGRect, scene: Scene, obstacles: [CGRect]) -> Mark {
        pointers(kind, at: target, scene: scene, obstacles: obstacles)[0]
    }

    /// The ways to point at `target`, best first: a circle, or each arrow, least covering first.
    /// `column` adds arrows from either side whose tails stand at that x.
    static func pointers(_ kind: AnswerMark.Kind, at target: CGRect, scene: Scene, obstacles: [CGRect], column: CGFloat? = nil) -> [Mark] {
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

    /// An arrow ending `arrowGap` from `target`, from the side whose span covers least.
    static func arrow(to target: CGRect, room: CGRect, obstacles: [CGRect]) -> Mark.Arrow {
        arrows(to: target, room: room, obstacles: obstacles)[0]
    }

    /// The arrows ending `arrowGap` from `target`, one from each side, least covering first. With a
    /// `column`, also the arrows from the right and the left whose tails stand at that x, when it
    /// leaves them a usable length.
    static func arrows(to target: CGRect, room: CGRect, obstacles: [CGRect], column: CGFloat? = nil) -> [Mark.Arrow] {
        let length = arrowLength, gap = arrowGap
        // Each starts below and out to one side, as a hand draws an arrow, except the ones from
        // above and below.
        var candidates: [(start: CGPoint, end: CGPoint)] = [
            (CGPoint(x: target.maxX + gap + length * 0.8, y: target.midY + length * 0.6), CGPoint(x: target.maxX + gap, y: target.midY)),
            (CGPoint(x: target.minX - gap - length * 0.8, y: target.midY + length * 0.6), CGPoint(x: target.minX - gap, y: target.midY)),
            (CGPoint(x: target.midX + length * 0.3, y: target.maxY + gap + length * 0.95), CGPoint(x: target.midX, y: target.maxY + gap)),
            (CGPoint(x: target.midX + length * 0.3, y: target.minY - gap - length * 0.95), CGPoint(x: target.midX, y: target.minY - gap)),
        ]
        if let column {
            for end in [CGPoint(x: target.maxX + gap, y: target.midY), CGPoint(x: target.minX - gap, y: target.midY)] {
                let reach = abs(column - end.x)
                guard (column > end.x) == (end.x > target.midX), reach >= length * 0.5, reach <= length * 3 else { continue }
                candidates.append((CGPoint(x: column, y: end.y + length * 0.6), end))
            }
        }
        return candidates.map { Mark.Arrow(start: $0.start, end: $0.end) }
            .sorted { cost(span($0.start, $0.end), room: room, obstacles: obstacles) < cost(span($1.start, $1.end), room: room, obstacles: obstacles) }
    }

    private static func span(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)).insetBy(dx: -4, dy: -4)
    }

    // MARK: Notes

    /// What a note keeps clear of: the person's ink and notes, and the window's text.
    static func obstacles(in scene: Scene) -> [CGRect] {
        personsMarks(in: scene) + scene.text.map { $0.insetBy(dx: -2, dy: -2) }
    }

    /// The person's ink and notes, with room round them.
    private static func personsMarks(in scene: Scene) -> [CGRect] {
        scene.ink.compactMap(\.shapeExtent).map { $0.insetBy(dx: -6, dy: -6) } + scene.notes.map { $0.insetBy(dx: -spacing, dy: -spacing) }
    }

    /// Where the person's note about `mark` goes, as a hand puts one (`handSpots`). `size` is the
    /// note's tag, at the width it may grow to, and `under` the room kept below it. It may cover the
    /// window's text beside the ink, but never goes elsewhere: a note away from its ink reads as being
    /// about something else. Answers the tag's rect and whether it grows to the left, keeping its
    /// right edge at the ink.
    static func noteSpot(_ size: CGSize, under: CGFloat = 0, for mark: Mark, scene: Scene) -> (rect: CGRect, growsLeft: Bool) {
        let marks = scene.ink.filter { $0.id != mark.id }.compactMap(\.shapeExtent).map { $0.insetBy(dx: -4, dy: -4) } + scene.notes
        let spot = best(handSpots(size, under: under, for: mark), size: size, under: under, room: scene.room, marks: marks, text: scene.text)
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

    /// The gap between the person's note and the reply under it, in pt: close, so the two read as a
    /// question and its answer.
    static let threadGap: CGFloat = 8

    /// The answer's reply, hung under `question`, the person's note that asked, and left-aligned with
    /// it, so the question, the reply and the actions under it read as one thread, or right above it
    /// when the room ends under it. It may cover the window's text there, as the question does.
    /// Without a question, or where every spot would leave the room or cover what the answer points
    /// at, the person's ink or another note, it goes beside `near`, the ink, clear of `obstacles`.
    /// `below` is room kept under it.
    static func reply(_ text: String, question: CGRect?, near: CGRect, scene: Scene, obstacles: [CGRect], pointed: [CGRect] = [],
                      sizes: Sizes, below: CGFloat = 0) -> Mark {
        let mark = Mark(geometry: .text(Mark.Text(origin: .zero, text: text, wrap: sizes.textWidth, size: sizes.textSize)),
                        agent: true, agentName: agentName)
        if let question, let box = noteBox(mark, sizes: sizes) {
            let size = CGSize(width: box.width, height: box.height + below)
            func clamped(_ x: CGFloat) -> CGFloat { max(scene.room.minX, min(x, scene.room.maxX - size.width)) }
            let others = scene.notes.filter { !$0.insetBy(dx: -1, dy: -1).contains(question) }
            let ink = scene.ink.compactMap(\.shapeExtent).map { $0.insetBy(dx: -4, dy: -4) }
            // Under the question, or right above it when the room or the person's ink ends it there;
            // aligned with its left edge, or its right when it sits left of its ink.
            for y in [question.maxY + threadGap, question.minY - threadGap - size.height] {
                for x in [clamped(question.minX), clamped(question.maxX - size.width)] {
                    let spot = CGRect(origin: CGPoint(x: x, y: y), size: size)
                    if cost(spot, room: scene.room, obstacles: pointed + others + ink) < 1 { return moved(mark, box: box, to: spot.origin, sizes: sizes) }
                }
            }
        }
        return note(text, near: near, scene: scene, obstacles: obstacles, sizes: sizes, below: below)
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

    /// `note` with its words now `text`, as a reply streams in. It keeps the edge nearest `near`, so
    /// it grows away from the ink.
    static func grown(_ note: Mark, to text: String, near: CGRect, scene: Scene, sizes: Sizes) -> Mark {
        guard case .text(var words) = note.geometry, let old = noteBox(note, sizes: sizes) else { return note }
        words.text = text
        var grown = note
        grown.geometry = .text(words)
        guard let new = noteBox(grown, sizes: sizes) else { return note }
        var origin = words.origin
        if old.maxX <= near.minX { origin.x -= new.width - old.width }
        if old.maxY <= near.minY, old.maxX > near.minX, old.minX < near.maxX { origin.y -= new.height - old.height }
        words.origin = origin
        grown.geometry = .text(words)
        // Text it grows over stays covered rather than the note jumping while it is read; the note
        // moves only to keep inside the room and off the person's marks.
        let marks = scene.ink.compactMap(\.shapeExtent).filter { !$0.contains(old) } + scene.notes
        if let box = noteBox(grown, sizes: sizes), cost(box, room: scene.room, obstacles: marks) < 1 { return grown }
        var placed = self.note(text, near: near, scene: scene, obstacles: obstacles(in: scene), sizes: sizes)
        placed = Mark(id: note.id, geometry: placed.geometry, agent: note.agent, agentName: note.agentName)
        return placed
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

    /// The tag `mark` draws, with the badge across its top edge, in global top-left points.
    static func noteBox(_ mark: Mark, sizes: Sizes) -> CGRect? {
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
