import CoreGraphics
import Foundation

/// The editor's measures for one drawing at one zoom: where a mark lies, how a point meets it, the
/// handles and dots a selection shows, and the shapes the tools make. Everything is in image px;
/// a size the spec gives in screen pt becomes px through `zoom`, and one in pt through `pointScale`.
struct EditorGeometry {
    let pixels: PixelSize
    let pointScale: CGFloat
    let style: TextStyle
    let metrics: EditorMetrics
    /// Screen pt per image px.
    let zoom: CGFloat
    let layouts: TextLayoutCache
    let arrowhead: ArrowheadStyle

    var image: CGRect { pixels.bounds }

    /// `points` screen pt, in px.
    func screen(_ points: CGFloat) -> CGFloat { points / zoom }

    /// `points` pt, in px.
    func pt(_ points: CGFloat) -> CGFloat { points * pointScale }

    func layout(_ text: Mark.Text) -> TextLayout {
        layouts.layout(text, imageWidth: image.width, pointScale: pointScale, style: style)
    }

    /// The rect a mark covers: a frame, an arrow's body with its arc, or a text's box. The same rect
    /// `Mark.placed` keeps inside the image.
    func extent(of mark: Mark) -> CGRect {
        switch mark.geometry {
        case .rectangle(let frame), .ellipse(let frame): return frame
        case .arrow(let arrow): return ArrowBody(start: arrow.start, end: arrow.end, bend: arrow.bend).bounds
        case .text(let text): return layout(text).box
        }
    }

    func extent(of marks: [Mark]) -> CGRect? {
        marks.map(extent(of:)).reduce(nil) { union, rect in union?.union(rect) ?? rect }
    }

    /// The rect that stays inside the image while a mark moves: its extent, and for a text with no wrap
    /// width the margin beyond its box too, so the box stops at the margin and its lines keep their breaks.
    func movingExtent(of mark: Mark) -> CGRect {
        let extent = extent(of: mark)
        guard case .text(let text) = mark.geometry, text.wrap == nil else { return extent }
        return CGRect(x: extent.minX, y: extent.minY, width: extent.width + image.width * TextLayout.margin, height: extent.height)
    }

    func movingExtent(of marks: [Mark]) -> CGRect? {
        marks.map(movingExtent(of:)).reduce(nil) { union, rect in union?.union(rect) ?? rect }
    }

    /// A mark from outside the editor, or a text that grows, kept inside the image by `Mark.placed`.
    /// Nil when it cannot be.
    func placed(_ mark: Mark) -> Mark? {
        mark.placed(in: pixels, pointScale: pointScale, style: style)
    }

    /// A mark the editor moved or changed, kept inside the image with a text's lines as they are.
    func placedKeepingLines(_ mark: Mark) -> Mark? {
        mark.placed(in: pixels, pointScale: pointScale, style: style, keepingLines: true)
    }

    func translated(_ mark: Mark, by offset: CGVector) -> Mark {
        var moved = mark
        switch mark.geometry {
        case .rectangle(let frame): moved.geometry = .rectangle(frame.offsetBy(dx: offset.dx, dy: offset.dy))
        case .ellipse(let frame): moved.geometry = .ellipse(frame.offsetBy(dx: offset.dx, dy: offset.dy))
        case .arrow(var arrow):
            arrow.start = arrow.start.moved(by: offset)
            arrow.end = arrow.end.moved(by: offset)
            moved.geometry = .arrow(arrow)
        case .text(var text):
            text.origin = text.origin.moved(by: offset)
            moved.geometry = .text(text)
        }
        return moved
    }

    /// `offset` limited so that marks covering `extent` stay inside the image together. An axis on
    /// which they already overflow, as a text wider than the image does, never pushes them further out.
    func clamped(_ offset: CGVector, keeping extent: CGRect) -> CGVector {
        func axis(_ delta: CGFloat, _ low: CGFloat, _ high: CGFloat, _ limit: CGFloat) -> CGFloat {
            min(max(delta, min(-low, 0)), max(limit - high, 0))
        }
        return CGVector(dx: axis(offset.dx, extent.minX, extent.maxX, image.width),
                        dy: axis(offset.dy, extent.minY, extent.maxY, image.height))
    }

    /// `marks` moved by `offset` as a group, shifted back inside the image together when the group
    /// fits, and each then kept inside on its own: as marks from outside, or, `keepingLines`, as
    /// copies of marks on this screenshot, whose texts keep their lines.
    func placedGroup(_ marks: [Mark], offset: CGVector, keepingLines: Bool) -> [Mark] {
        let moved = marks.map { translated($0, by: offset) }
        guard let extent = keepingLines ? movingExtent(of: moved) : extent(of: moved) else { return [] }
        let shift = CGVector(dx: Mark.shiftInside(from: extent.minX, to: extent.maxX, within: image.width) ?? 0,
                             dy: Mark.shiftInside(from: extent.minY, to: extent.maxY, within: image.height) ?? 0)
        return moved.compactMap { mark in
            let back = translated(mark, by: shift)
            return keepingLines ? placedKeepingLines(back) : placed(back)
        }
    }

    // MARK: What a point hits

    /// How far from a stroke's centre line it is hit: half the stroke on screen plus the hit margin.
    var hitBand: CGFloat { pt(Mark.strokeWidth) / 2 + screen(metrics.hitMargin) }

    enum Hit {
        /// On the stroke, this far from its centre line.
        case stroke(CGFloat)
        /// Inside a text's box.
        case box
        /// Inside a rectangle or an ellipse, away from its stroke.
        case inside
    }

    /// How `point` meets `mark`: on its stroke, inside a text's box, or inside a rectangle or an
    /// ellipse, which counts only when `insideCounts`.
    func hit(_ mark: Mark, at point: CGPoint, insideCounts: Bool) -> Hit? {
        switch mark.geometry {
        case .text(let text):
            return layout(text).box.encloses(point) ? .box : nil
        case .rectangle(let frame):
            let distance = Self.distance(from: point, toOutlineOf: frame)
            if distance <= hitBand { return .stroke(distance) }
            return insideCounts && frame.encloses(point) ? .inside : nil
        case .ellipse(let frame):
            let distance = Self.polylineDistance(from: point, along: Self.ellipsePoints(in: frame))
            if distance <= hitBand { return .stroke(distance) }
            return insideCounts && Self.ellipse(frame, contains: point) ? .inside : nil
        case .arrow(let arrow):
            let distance = arrow.body(pointScale: pointScale).distance(to: point)
            return distance <= hitBand ? .stroke(distance) : nil
        }
    }

    static func distance(from point: CGPoint, toOutlineOf frame: CGRect) -> CGFloat {
        if frame.encloses(point) {
            return min(point.x - frame.minX, frame.maxX - point.x, point.y - frame.minY, frame.maxY - point.y)
        }
        return hypot(max(frame.minX - point.x, 0, point.x - frame.maxX), max(frame.minY - point.y, 0, point.y - frame.maxY))
    }

    /// The ellipse inscribed in `frame` as a closed polygon, fine enough for hit testing.
    static func ellipsePoints(in frame: CGRect, count: Int = 96) -> [CGPoint] {
        (0...count).map { step in
            let angle = CGFloat(step) / CGFloat(count) * 2 * .pi
            return CGPoint(x: frame.midX + frame.width / 2 * cos(angle), y: frame.midY + frame.height / 2 * sin(angle))
        }
    }

    static func ellipse(_ frame: CGRect, contains point: CGPoint) -> Bool {
        let a = frame.width / 2, b = frame.height / 2
        guard a > 0, b > 0 else { return false }
        let x = (point.x - frame.midX) / a, y = (point.y - frame.midY) / b
        return x * x + y * y <= 1
    }

    static func polylineDistance(from point: CGPoint, along points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).map { ArrowBody(start: $0, end: $1, bend: 0).distance(to: point) }.min() ?? .infinity
    }

    // MARK: The selection outline

    /// How far outside a mark's ink the selection outline's centre line runs, in px: half the
    /// outline's width on screen, so all of it lies outside the mark.
    var outlineOffset: CGFloat { screen(metrics.selectionOutlineWidth) / 2 }

    /// The rect a mark's ink covers, in px: a stroke's whole width, an arrowhead, and a text's
    /// letters with their outline.
    func inkExtent(of mark: Mark) -> CGRect {
        if case .text(let text) = mark.geometry {
            let outline = pt(Mark.Text.outlineWidth)
            return layout(text).box.insetBy(dx: -outline, dy: -outline)
        }
        guard let shape = mark.shape(pointScale: pointScale, arrowhead: arrowhead) else { return extent(of: mark) }
        var ink = CGRect.null
        if let stroked = shape.stroked { ink = ink.union(stroked.boundingBoxOfPath.insetBy(dx: -shape.lineWidth / 2, dy: -shape.lineWidth / 2)) }
        if let filled = shape.filled { ink = ink.union(filled.boundingBoxOfPath) }
        return ink
    }

    /// The frame drawn around selected marks: their ink grown by `outlineOffset`, so the outline lies
    /// outside every stroke. Each side stays that far inside the image, where the window ends, so it
    /// is seen; there it crosses a stroke that runs along the image's edge.
    func selectionFrame(of marks: [Mark]) -> CGRect? {
        guard let ink = marks.map(inkExtent(of:)).reduce(nil, { $0?.union($1) ?? $1 }), !ink.isNull else { return nil }
        let grown = ink.insetBy(dx: -outlineOffset, dy: -outlineOffset)
        let room = image.insetBy(dx: outlineOffset, dy: outlineOffset)
        let minX = max(grown.minX, room.minX), maxX = min(grown.maxX, room.maxX)
        let minY = max(grown.minY, room.minY), maxY = min(grown.maxY, room.maxY)
        guard maxX > minX, maxY > minY else { return grown }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// One mark's selection or hover outline, in px: a rectangle's or a text's selection frame, and the
    /// outer edge of an ellipse's or an arrow's ink grown by `outlineOffset`, so it runs outside the stroke.
    func outline(of mark: Mark) -> CGPath {
        let frame = { CGPath(rect: selectionFrame(of: [mark]) ?? extent(of: mark), transform: nil) }
        var parts: [CGPath] = []
        switch mark.geometry {
        case .rectangle, .text: return frame()
        case .ellipse(let bounds): parts.append(CGPath(ellipseIn: bounds, transform: nil))  // fills the ring's hole
        case .arrow: break
        }
        guard let shape = mark.shape(pointScale: pointScale, arrowhead: arrowhead) else { return frame() }
        let grow = 2 * outlineOffset
        if let stroked = shape.stroked {
            parts.append(stroked.copy(strokingWithWidth: shape.lineWidth + grow, lineCap: .round, lineJoin: .round, miterLimit: 10))
        }
        if let filled = shape.filled {
            parts.append(filled)
            parts.append(filled.copy(strokingWithWidth: grow, lineCap: .round, lineJoin: .round, miterLimit: 10))
        }
        guard let first = parts.first else { return frame() }
        return parts.dropFirst().reduce(first) { $0.union($1) }
    }

    // MARK: Handles and dots

    /// The resize handles of a single selected mark, on `frame`, the frame drawn around it: the four
    /// corners, then the four edges, in the order a press tries them. Along an axis on which the
    /// mark, `markSize` px, is under `smallSide` on screen, the hit areas lie outside the frame, so
    /// each corner can still be taken. A hit area with no room outside the image moves inside it,
    /// since the window ends at the image.
    func handles(around frame: CGRect, of id: Mark.ID, markSize: CGSize) -> [EditorCore.Handle] {
        let smallX = markSize.width * zoom < metrics.smallSide
        let smallY = markSize.height * zoom < metrics.smallSide
        // The span a hit area of `size` covers across a side at `at`: centred on it, or outside the
        // mark, on the side `outward` points to.
        func across(_ at: CGFloat, outward: Int, size: CGFloat, small: Bool) -> (low: CGFloat, high: CGFloat) {
            guard small else { return (at - size / 2, at + size / 2) }
            return outward < 0 ? (at - size, at) : (at, at + size)
        }
        let corner = screen(metrics.cornerHitSize), edge = screen(metrics.edgeHitSize), drawn = screen(metrics.handleSize)
        return EditorCore.HandlePosition.allCases.map { position in
            let x: (low: CGFloat, high: CGFloat)
            let y: (low: CGFloat, high: CGFloat)
            let sideX = position.xSide < 0 ? frame.minX : frame.maxX
            let sideY = position.ySide < 0 ? frame.minY : frame.maxY
            var square: CGRect?
            if position.isCorner {
                x = across(sideX, outward: position.xSide, size: corner, small: smallX)
                y = across(sideY, outward: position.ySide, size: corner, small: smallY)
                square = CGRect(x: sideX - drawn / 2, y: sideY - drawn / 2, width: drawn, height: drawn)
            } else if position.xSide != 0 {
                x = across(sideX, outward: position.xSide, size: edge, small: smallX)
                y = (frame.minY, frame.maxY)
            } else {
                x = (frame.minX, frame.maxX)
                y = across(sideY, outward: position.ySide, size: edge, small: smallY)
            }
            let dx = Mark.shiftInside(from: x.low, to: x.high, within: image.width) ?? 0
            let dy = Mark.shiftInside(from: y.low, to: y.high, within: image.height) ?? 0
            return EditorCore.Handle(mark: id, position: position, square: square,
                                     hitArea: CGRect(x: x.low + dx, y: y.low + dy, width: x.high - x.low, height: y.high - y.low))
        }
    }

    /// Where an arrow's three dots sit. The middle one is at the bend point, pushed out along the
    /// perpendicular on a short arrow until the whole of it is clear of the end dots' hit areas.
    func dotCenters(of arrow: Mark.Arrow) -> [(kind: EditorCore.DotKind, center: CGPoint)] {
        let length = hypot(arrow.end.x - arrow.start.x, arrow.end.y - arrow.start.y)
        guard length > 0 else { return [(.start, arrow.start), (.end, arrow.end)] }
        let clear = screen(metrics.dotHitRadius + metrics.dotRadius)
        var middle = arrow
        if hypot(length / 2, arrow.bend) < clear {
            middle.bend = (arrow.bend < 0 ? -1 : 1) * (clear * clear - length * length / 4).squareRoot()
            // A straight arrow along an edge has room on one side only.
            if arrow.bend == 0, !image.encloses(middle.bendPoint) { middle.bend = -middle.bend }
        }
        return [(.start, arrow.start), (.end, arrow.end), (.middle, middle.bendPoint)]
    }

    // MARK: The brush

    /// Whether a brush covering `brush` selects `mark`: its outline crosses the brush, or it lies
    /// wholly inside. A brush inside a hollow rectangle or ellipse crosses nothing; a text's box is solid.
    func brush(_ brush: CGRect, selects mark: Mark) -> Bool {
        switch mark.geometry {
        case .text(let text):
            return layout(text).box.intersects(brush)
        case .rectangle(let frame):
            guard frame.intersects(brush) || brush.contains(frame) else { return false }
            let inside = brush.minX > frame.minX && brush.maxX < frame.maxX && brush.minY > frame.minY && brush.maxY < frame.maxY
            return !inside
        case .ellipse(let frame):
            let nearest = CGPoint(x: min(max(frame.midX, brush.minX), brush.maxX), y: min(max(frame.midY, brush.minY), brush.maxY))
            guard Self.ellipse(frame, contains: nearest) || brush.contains(frame) else { return false }
            let corners = [CGPoint(x: brush.minX, y: brush.minY), CGPoint(x: brush.maxX, y: brush.minY),
                           CGPoint(x: brush.minX, y: brush.maxY), CGPoint(x: brush.maxX, y: brush.maxY)]
            return !corners.allSatisfy { Self.ellipse(frame, contains: $0) }
        case .arrow(let arrow):
            let body = arrow.body(pointScale: pointScale)
            let points = (0...32).map { body.point(at: CGFloat($0) / 32) }
            if points.contains(where: brush.encloses) { return true }
            return zip(points, points.dropFirst()).contains { Self.segment($0, $1, crosses: brush) }
        }
    }

    static func segment(_ a: CGPoint, _ b: CGPoint, crosses rect: CGRect) -> Bool {
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
        return (0..<4).contains { segments(a, b, cross: corners[$0], corners[($0 + 1) % 4]) }
    }

    static func segments(_ a: CGPoint, _ b: CGPoint, cross c: CGPoint, _ d: CGPoint) -> Bool {
        func side(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> CGFloat { (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x) }
        let d1 = side(c, d, a), d2 = side(c, d, b), d3 = side(a, b, c), d4 = side(a, b, d)
        return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))
    }

    // MARK: Reading order

    /// The marks in reading order: rows from the top, each row from the left. A mark whose top is
    /// within `rowTolerance` of the top of the row's first mark joins that row.
    func readingOrder(_ marks: [Mark]) -> [Mark.ID] {
        let tolerance = pt(EditorCore.rowTolerance)
        let sorted = marks.map { (id: $0.id, extent: extent(of: $0)) }.sorted { ($0.extent.minY, $0.extent.minX) < ($1.extent.minY, $1.extent.minX) }
        var rows: [[(id: Mark.ID, extent: CGRect)]] = []
        for item in sorted {
            if let top = rows.last?.first?.extent.minY, item.extent.minY - top <= tolerance {
                rows[rows.count - 1].append(item)
            } else {
                rows.append([item])
            }
        }
        return rows.flatMap { $0.sorted { $0.extent.minX < $1.extent.minX }.map(\.id) }
    }

    // MARK: Shapes the tools make

    /// A point moved inside the image.
    func inside(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), image.width), y: min(max(point.y, 0), image.height))
    }

    /// The rectangle a drag from `start` to `pointer` draws: to the pointer exactly, a square in the
    /// pointer's quadrant with `square`, centred on `start` with `centred`, and stopped at the edges.
    func newRectangle(from start: CGPoint, to pointer: CGPoint, square: Bool, centred: Bool) -> CGRect {
        var dx = pointer.x - start.x, dy = pointer.y - start.y
        // The room from `start` to the edge a drag reaches toward, or to the nearer edge when centred.
        let roomX = centred ? min(start.x, image.width - start.x) : (dx < 0 ? start.x : image.width - start.x)
        let roomY = centred ? min(start.y, image.height - start.y) : (dy < 0 ? start.y : image.height - start.y)
        if square {
            let side = min(max(abs(dx), abs(dy)), roomX, roomY)
            dx = dx < 0 ? -side : side
            dy = dy < 0 ? -side : side
        } else {
            dx = dx < 0 ? -min(-dx, roomX) : min(dx, roomX)
            dy = dy < 0 ? -min(-dy, roomY) : min(dy, roomY)
        }
        if centred {
            return CGRect(x: start.x - abs(dx), y: start.y - abs(dy), width: 2 * abs(dx), height: 2 * abs(dy))
        }
        return CGRect(x: min(start.x, start.x + dx), y: min(start.y, start.y + dy), width: abs(dx), height: abs(dy))
    }

    /// Where an arrow from `start` ends with the pointer at `pointer`: the pointer, stopped at the
    /// image's edges, or with `snapping` on the nearest 15° step from `start` at the pointer's
    /// distance, shortened to stay inside.
    func arrowEnd(from start: CGPoint, toward pointer: CGPoint, snapping: Bool) -> CGPoint {
        guard snapping else { return inside(pointer) }
        let dx = pointer.x - start.x, dy = pointer.y - start.y
        let angle = (atan2(dy, dx) / EditorCore.snapAngle).rounded() * EditorCore.snapAngle
        let direction = CGVector(dx: cos(angle), dy: sin(angle))
        var length = hypot(dx, dy)
        // Leave room to the edge the direction runs into, on each axis.
        if direction.dx > 1e-9 { length = min(length, (image.width - start.x) / direction.dx) }
        if direction.dx < -1e-9 { length = min(length, -start.x / direction.dx) }
        if direction.dy > 1e-9 { length = min(length, (image.height - start.y) / direction.dy) }
        if direction.dy < -1e-9 { length = min(length, -start.y / direction.dy) }
        return inside(CGPoint(x: start.x + direction.dx * max(length, 0), y: start.y + direction.dy * max(length, 0)))
    }

    /// `frame` resized by dragging `handle` by `delta`. The opposite side stays, or the centre with
    /// `fromCenter`; `proportional` keeps the shape. The dragged side stops at the image's edge and
    /// flips past the opposite one; a side never shrinks below one px.
    func resized(_ frame: CGRect, by handle: EditorCore.HandlePosition, delta: CGVector, proportional: Bool, fromCenter: Bool) -> CGRect {
        struct Axis {
            var low: CGFloat, high: CGFloat, limit: CGFloat
            var center: CGFloat { (low + high) / 2 }
        }
        let axes = [Axis(low: frame.minX, high: frame.maxX, limit: image.width), Axis(low: frame.minY, high: frame.maxY, limit: image.height)]
        let sides = [handle.xSide, handle.ySide]
        let moves = [delta.dx, delta.dy]
        // Each axis as a scale of the distance from its fixed point to the dragged side: 1 unchanged,
        // negative flipped. An axis the handle does not drag keeps 1 unless the shape is kept.
        var fixed: [CGFloat] = [0, 0], reach: [CGFloat] = [0, 0], scale: [CGFloat] = [1, 1]
        var allowed: [ClosedRange<CGFloat>] = [0...0, 0...0]
        for i in 0..<2 {
            let axis = axes[i]
            let aboutCenter = fromCenter || sides[i] == 0
            fixed[i] = aboutCenter ? axis.center : (sides[i] < 0 ? axis.high : axis.low)
            reach[i] = (sides[i] < 0 ? axis.low : axis.high) - fixed[i]
            // A side with no length has no scale to take.
            guard reach[i] != 0, reach[i].isFinite else { return frame }
            if sides[i] != 0 { scale[i] = (fixed[i] + reach[i] + moves[i] - fixed[i]) / reach[i] }
            if aboutCenter {
                let most = min(fixed[i], axis.limit - fixed[i]) / abs(reach[i])
                allowed[i] = -most...most
            } else {
                let a = (0 - fixed[i]) / reach[i], b = (axis.limit - fixed[i]) / reach[i]
                allowed[i] = min(a, b)...max(a, b)
            }
        }
        if proportional {
            var size = sides[0] != 0 && sides[1] != 0 ? max(abs(scale[0]), abs(scale[1])) : abs(sides[0] != 0 ? scale[0] : scale[1])
            for i in 0..<2 {
                let sign: CGFloat = sides[i] != 0 && scale[i] < 0 ? -1 : 1
                size = min(size, sign > 0 ? allowed[i].upperBound : -allowed[i].lowerBound)
            }
            for i in 0..<2 { scale[i] = (sides[i] != 0 && scale[i] < 0 ? -1 : 1) * size }
        }
        var spans: [(CGFloat, CGFloat)] = []
        for i in 0..<2 {
            var s = min(max(scale[i], allowed[i].lowerBound), allowed[i].upperBound)
            let smallest = 1 / abs(reach[i]) / (fromCenter || sides[i] == 0 ? 2 : 1)
            if abs(s) < smallest { s = s < 0 ? -smallest : smallest }
            let moved = fixed[i] + reach[i] * s
            spans.append(fromCenter || sides[i] == 0 ? (fixed[i] - abs(reach[i] * s), fixed[i] + abs(reach[i] * s)) : (min(fixed[i], moved), max(fixed[i], moved)))
        }
        let result = CGRect(x: spans[0].0, y: spans[1].0, width: spans[0].1 - spans[0].0, height: spans[1].1 - spans[1].0)
        return result.width > 0 && result.height > 0 && [result.minX, result.minY, result.width, result.height].allSatisfy(\.isFinite) ? result : frame
    }

    /// A text resized by dragging `handle` by `delta`. A left or right edge sets the wrap width and
    /// keeps the top; a corner, or the top or bottom edge, scales the whole text, font included,
    /// about the opposite side, or the centre with `fromCenter`.
    func resized(_ text: Mark.Text, by handle: EditorCore.HandlePosition, delta: CGVector, fromCenter: Bool) -> Mark.Text {
        let box = layout(text).box
        var result = text
        if handle.ySide == 0 {
            let narrowest = pt(text.size)
            var left = box.minX, right = box.maxX
            if handle.xSide > 0 {
                right = min(max(box.maxX + delta.dx, 0), image.width)
                if fromCenter { left = min(max(box.minX - delta.dx, 0), image.width) }
                right = max(right, min(left + narrowest, image.width))
            } else {
                left = min(max(box.minX + delta.dx, 0), image.width)
                if fromCenter { right = min(max(box.maxX - delta.dx, 0), image.width) }
                left = min(left, max(right - narrowest, 0))
            }
            result.origin.x = left
            result.wrap = max(right - left, 1)
            return result
        }
        let anchor = CGPoint(x: fromCenter ? box.midX : (handle.xSide < 0 ? box.maxX : box.minX),
                             y: fromCenter ? box.midY : (handle.ySide < 0 ? box.maxY : box.minY))
        let corner = CGPoint(x: handle.xSide < 0 ? box.minX : box.maxX, y: handle.ySide < 0 ? box.minY : box.maxY)
        let dragged = inside(CGPoint(x: corner.x + delta.dx, y: corner.y + delta.dy))
        // A scale along the axes the handle drags, measured toward the side it started on, so a
        // text shrinks rather than flips when the pointer passes the anchor.
        var scales: [CGFloat] = []
        if handle.xSide != 0, corner.x != anchor.x { scales.append((dragged.x - anchor.x) / (corner.x - anchor.x)) }
        if corner.y != anchor.y { scales.append((dragged.y - anchor.y) / (corner.y - anchor.y)) }
        guard let wanted = scales.max(), wanted.isFinite else { return text }
        let size = min(max(text.size * wanted, EditorCore.smallestTextSize), Mark.Text.maxSize)
        let scale = size / text.size
        result.size = size
        result.wrap = text.wrap.map { $0 * scale }
        result.origin = CGPoint(x: anchor.x + (text.origin.x - anchor.x) * scale, y: anchor.y + (text.origin.y - anchor.y) * scale)
        return result
    }

    /// The origin of a new text whose first line has its left end and vertical centre at `point`.
    func textOrigin(at point: CGPoint, size: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: point.y - pt(size) * style.lineHeight / 2)
    }
}

extension CGRect {
    /// `contains`, counting the right and bottom edges too.
    func encloses(_ point: CGPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }
}

extension CGPoint {
    func moved(by offset: CGVector) -> CGPoint { CGPoint(x: x + offset.dx, y: y + offset.dy) }
}

/// Text layouts the editor has made, so a hover, a key or a typed character does not lay every text
/// out again. A layout depends only on its key, so a stored one is always right. Not safe to share
/// between threads.
final class TextLayoutCache {
    private struct Key: Hashable {
        let text: String
        let wrap: CGFloat?
        let size: CGFloat
        let x: CGFloat
        let y: CGFloat
        let imageWidth: CGFloat
        let pointScale: CGFloat
        let weight: CGFloat
        let lineHeight: CGFloat
    }

    /// Past this many layouts the cache starts again, so texts moved or typed into leave nothing behind.
    static let capacity = 256
    private var layouts: [Key: TextLayout] = [:]

    func layout(_ text: Mark.Text, imageWidth: CGFloat, pointScale: CGFloat, style: TextStyle) -> TextLayout {
        let key = Key(text: text.text, wrap: text.wrap, size: text.size, x: text.origin.x, y: text.origin.y,
                      imageWidth: imageWidth, pointScale: pointScale, weight: style.weight.rawValue, lineHeight: style.lineHeight)
        if let layout = layouts[key] { return layout }
        let layout = TextLayout(text, imageWidth: imageWidth, pointScale: pointScale, style: style)
        if layouts.count >= Self.capacity { layouts.removeAll(keepingCapacity: true) }
        layouts[key] = layout
        return layout
    }
}
