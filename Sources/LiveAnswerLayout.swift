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

    /// The answer's marks: its reply as a note beside `asked`, the person's ink the ask was about,
    /// then each mark it points with, and a mark's label beside it. `targets` holds each answer
    /// mark's target in global top-left points, or nil for one whose target was not found, which is
    /// dropped. The reply comes first, so it gets the spot nearest the ink. `streamed` is the reply's
    /// note as it streamed in, which keeps its place and its id.
    static func marks(for answer: LiveAnswer, targets: [CGRect?], asked: CGRect, scene: Scene, sizes: Sizes, streamed: Mark? = nil) -> [Mark] {
        var obstacles = obstacles(in: scene)
        var placed: [Mark] = []
        let say = streamed.map { grown($0, to: answer.say, near: asked, scene: scene, sizes: sizes) }
            ?? note(answer.say, near: asked, scene: scene, obstacles: obstacles, sizes: sizes)
        placed.append(say)
        if let box = noteBox(say, sizes: sizes) { obstacles.append(box.insetBy(dx: -8, dy: -8)) }
        for (answerMark, target) in zip(answer.marks, targets) {
            guard let target else { continue }
            let mark = pointer(answerMark.kind, at: target, scene: scene, obstacles: obstacles)
            placed.append(mark)
            if let extent = mark.shapeExtent { obstacles.append(extent.insetBy(dx: -6, dy: -6)) }
            if let label = answerMark.label, let extent = mark.shapeExtent {
                // An arrow's label goes at its tail, away from what it points at.
                var near = extent
                if case .arrow(let arrow) = mark.geometry { near = CGRect(origin: arrow.start, size: .zero).insetBy(dx: -4, dy: -4) }
                let tag = note(label, near: near, scene: scene, obstacles: obstacles, sizes: sizes)
                placed.append(tag)
                if let box = noteBox(tag, sizes: sizes) { obstacles.append(box.insetBy(dx: -8, dy: -8)) }
            }
        }
        return placed
    }

    // MARK: Pointing

    /// A line this many times wider than tall is boxed rather than circled: an ellipse round it
    /// would cover the lines above and below.
    static let longLine: CGFloat = 8
    /// An arrow's length, and its gap from what it points at, in pt.
    static let arrowLength: CGFloat = 64
    static let arrowGap: CGFloat = 6

    /// A circle round `target`, or an arrow at it. A circle that would sit on a loop of the person's
    /// is drawn as an arrow instead, since two loops round one thing read as one.
    static func pointer(_ kind: AnswerMark.Kind, at target: CGRect, scene: Scene, obstacles: [CGRect]) -> Mark {
        if kind == .circle {
            let round = circle(around: target)
            let frame: CGRect = switch round {
            case .ellipse(let frame), .rectangle(let frame): frame
            default: target
            }
            if !scene.ink.contains(where: { overlapsLoop($0, frame) }) {
                return Mark(geometry: round, agent: true, agentName: agentName)
            }
        }
        return Mark(geometry: .arrow(arrow(to: target, room: scene.room, obstacles: obstacles)), agent: true, agentName: agentName)
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
        let length = arrowLength, gap = arrowGap
        // Each starts below and out to one side, as a hand draws an arrow, except the ones from
        // above and below.
        let candidates: [(start: CGPoint, end: CGPoint)] = [
            (CGPoint(x: target.maxX + gap + length * 0.8, y: target.midY + length * 0.6), CGPoint(x: target.maxX + gap, y: target.midY)),
            (CGPoint(x: target.minX - gap - length * 0.8, y: target.midY + length * 0.6), CGPoint(x: target.minX - gap, y: target.midY)),
            (CGPoint(x: target.midX + length * 0.3, y: target.maxY + gap + length * 0.95), CGPoint(x: target.midX, y: target.maxY + gap)),
            (CGPoint(x: target.midX + length * 0.3, y: target.minY - gap - length * 0.95), CGPoint(x: target.midX, y: target.minY - gap)),
        ]
        let best = candidates.min { a, b in cost(span(a.start, a.end), room: room, obstacles: obstacles)
            < cost(span(b.start, b.end), room: room, obstacles: obstacles) }!
        return Mark.Arrow(start: best.start, end: best.end)
    }

    private static func span(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)).insetBy(dx: -4, dy: -4)
    }

    // MARK: Notes

    /// What a note keeps clear of: the person's ink and the window's text.
    static func obstacles(in scene: Scene) -> [CGRect] {
        scene.ink.compactMap(\.shapeExtent).map { $0.insetBy(dx: -6, dy: -6) } + scene.text.map { $0.insetBy(dx: -2, dy: -2) }
    }

    /// `note` with its words now `text`, as a reply streams in. It keeps the edge nearest `near`, so
    /// it grows away from the ink, and moves only when growing there would cover something.
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
        if let box = noteBox(grown, sizes: sizes), cost(box, room: scene.room, obstacles: obstacles(in: scene)) < 1 { return grown }
        var placed = self.note(text, near: near, scene: scene, obstacles: obstacles(in: scene), sizes: sizes)
        placed = Mark(id: note.id, geometry: placed.geometry, agent: note.agent, agentName: note.agentName)
        return placed
    }

    /// A note of `text` in the agent's style, placed beside `near`.
    static func note(_ text: String, near: CGRect, scene: Scene, obstacles: [CGRect], sizes: Sizes) -> Mark {
        let mark = Mark(geometry: .text(Mark.Text(origin: .zero, text: text, wrap: sizes.textWidth, size: sizes.textSize)),
                        agent: true, agentName: agentName)
        let box = noteBox(mark, sizes: sizes) ?? CGRect(x: 0, y: 0, width: sizes.textWidth, height: sizes.textSize * 2)
        let spot = place(box.size, near: near, room: scene.room, obstacles: obstacles)
        var moved = mark
        // The box starts above the text's origin by the badge's overlap. The wrap stays the widest a
        // note may be, so a reply that streams in wraps where the whole reply will.
        moved.geometry = .text(Mark.Text(origin: CGPoint(x: spot.minX - box.minX, y: spot.minY - box.minY), text: text,
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
    static func place(_ size: CGSize, near: CGRect, room: CGRect, obstacles: [CGRect]) -> CGRect {
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
