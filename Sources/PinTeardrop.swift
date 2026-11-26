import AppKit
import QuartzCore

/// How a pin is drawn: a teardrop, a circle `PinStyle.side` pt across with the quarter toward its tip squared off
/// into a point. The tip is the corner of the square the circle fits in, and the pin's number sits in
/// the middle of the round part, the body. The renderer draws it (`Pin.draw`) and `PinLayer` shows the
/// same paths, so a pin looks the same in the editor, on a card, in flight and in a PNG.
///
/// A file stores a pin's place and never how it is drawn, so the orientation is worked out each time,
/// from the picture's edges at the drawing's own size, which every drawer shares.
struct PinTeardrop {
    /// Where the body sits from the tip.
    enum Orientation: Equatable {
        /// Above the tip and to its right, so the tip is the body's bottom-left corner. The usual one:
        /// an area pin's body then sits outside the area, covering nothing it holds.
        case upRight
        case upLeft, downRight, downLeft
    }

    let orientation: Orientation
    /// The square the teardrop fits in, in px.
    let square: CGRect
    /// The teardrop's outline, in px.
    let body: CGPath
    /// The number's letters, as outlines in px.
    let number: CGPath

    /// `pin`'s teardrop in `markStyle` on a drawing of `pointScale` on an image of `pixels`, turned away
    /// from `pieceNumbers` where it can be.
    init(_ pin: Pin, in pixels: PixelSize, pointScale: CGFloat, markStyle: MarkStyle, pieceNumbers: [CGRect] = []) {
        let side = markStyle.pin.side * pointScale
        let orientation = Self.facing(tip: pin.tip, side: side, edge: markStyle.edgeWidth * pointScale, in: pixels, avoiding: pieceNumbers)
        self.init(number: pin.number, agent: pin.color == .agent, tip: pin.tip, orientation: orientation, side: side, style: markStyle.pin)
    }

    /// A teardrop `side` px across whose tip is at `tip`, wearing `number`, or no number for 0.
    init(number: Int, agent: Bool, tip: CGPoint, orientation: Orientation, side: CGFloat, style: PinStyle) {
        self.orientation = orientation
        square = Self.square(tip: tip, orientation: orientation, side: side)
        body = CGPath(ellipseIn: square, transform: nil).union(CGPath(rect: Self.corner(tip: tip, orientation: orientation, side: side), transform: nil))
        self.number = number > 0 ? Self.letters("\(number)", centredIn: square, size: side * style.numberSize, widest: side * style.numberWidth, agent: agent)
            : CGMutablePath()
    }

    /// A cluster: a teardrop widened into a capsule that fills `frame`, its tip at the corner of
    /// `frame` the orientation points from, wearing `label`.
    init(label: String, agent: Bool, orientation: Orientation, frame: CGRect, style: PinStyle) {
        self.orientation = orientation
        square = frame
        let side = frame.height, tip = CGPoint(x: frame.minX, y: frame.minY)
        let right = orientation == .upRight || orientation == .downRight, up = orientation == .upRight || orientation == .upLeft
        let corner = Self.corner(tip: CGPoint(x: right ? tip.x : frame.maxX, y: up ? frame.maxY : tip.y), orientation: orientation, side: side)
        body = CGPath(roundedRect: frame, cornerWidth: side / 2, cornerHeight: side / 2, transform: nil).union(CGPath(rect: corner, transform: nil))
        number = Self.letters(label, centredIn: frame, size: side * style.numberSize, widest: frame.width - side * style.numberWidth / 2, agent: agent)
    }

    /// The quarter of the square toward the tip, which squares the round body off into a point.
    private static func corner(tip: CGPoint, orientation: Orientation, side: CGFloat) -> CGRect {
        let right = orientation == .upRight || orientation == .downRight
        let up = orientation == .upRight || orientation == .upLeft
        return CGRect(x: right ? tip.x : tip.x - side / 2, y: up ? tip.y - side / 2 : tip.y, width: side / 2, height: side / 2)
    }

    /// The tip: the corner of `square` the body points from.
    var tip: CGPoint {
        CGPoint(x: orientation == .upRight || orientation == .downRight ? square.minX : square.maxX,
                y: orientation == .upRight || orientation == .upLeft ? square.maxY : square.minY)
    }

    /// The square a teardrop `side` px across fits in, with its tip at `tip`.
    static func square(tip: CGPoint, orientation: Orientation, side: CGFloat) -> CGRect {
        let right = orientation == .upRight || orientation == .downRight
        let up = orientation == .upRight || orientation == .upLeft
        return CGRect(x: right ? tip.x : tip.x - side, y: up ? tip.y - side : tip.y, width: side, height: side)
    }

    /// The orientation of a teardrop `side` px across, inside an edge `edge` px wide, whose tip is at
    /// `tip`: up and right, unless that crosses the picture's top edge, when the body goes below the
    /// tip, or its right edge, when the body goes to the left of it. A body that would then cover one of
    /// `avoiding` turns to the first other orientation that covers none and stays inside the picture:
    /// flipped up or down, then left or right, then both. When none does, the edges decide.
    static func facing(tip: CGPoint, side: CGFloat, edge: CGFloat, in pixels: PixelSize, avoiding: [CGRect] = []) -> Orientation {
        let reach = side + edge
        let up = tip.y - reach >= 0, right = tip.x + reach <= CGFloat(pixels.width)
        let byEdges = orientation(up: up, right: right)
        func covers(_ orientation: Orientation) -> Bool {
            let drawn = square(tip: tip, orientation: orientation, side: side).insetBy(dx: -edge, dy: -edge)
            return avoiding.contains { $0.intersects(drawn) }
        }
        guard covers(byEdges) else { return byEdges }
        let picture = CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height)
        let others = [orientation(up: !up, right: right), orientation(up: up, right: !right), orientation(up: !up, right: !right)]
        return others.first { other in
            picture.contains(square(tip: tip, orientation: other, side: side).insetBy(dx: -edge, dy: -edge)) && !covers(other)
        } ?? byEdges
    }

    static func orientation(up: Bool, right: Bool) -> Orientation {
        switch (up, right) {
        case (true, true): return .upRight
        case (true, false): return .upLeft
        case (false, true): return .downRight
        case (false, false): return .downLeft
        }
    }

    /// The face the number is set in: a person's in SF Pro Rounded and an agent's in SF Mono, as their
    /// notes are by default.
    private static func face(agent: Bool) -> CTFontDescriptor {
        let system = NSFont.systemFont(ofSize: 0, weight: .semibold).fontDescriptor
        return (system.withDesign(agent ? .monospaced : .rounded) ?? system) as CTFontDescriptor
    }

    /// `words` as letter outlines, centred in `square`, set at `size` px, or smaller to be no wider than
    /// `widest`.
    private static func letters(_ words: String, centredIn square: CGRect, size: CGFloat, widest: CGFloat, agent: Bool) -> CGPath {
        let face = face(agent: agent)
        func line(_ size: CGFloat) -> (line: CTLine, font: CTFont, width: CGFloat) {
            let font = CTFontCreateWithFontDescriptor(face, size, nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: words, attributes: [.font: font]))
            return (line, font, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
        }
        var set = line(size)
        if set.width > widest { set = line(size * widest / set.width) }
        let origin = CGPoint(x: square.midX - set.width / 2, y: square.midY + CTFontGetCapHeight(set.font) / 2)
        let path = CGMutablePath()
        for run in (CTLineGetGlyphRuns(set.line) as? [CTRun]) ?? [] {
            for case let outline? in NoteTag.GlyphRun(run, at: origin)?.outlines ?? [] { path.addPath(outline) }
        }
        return path
    }

    /// The teardrop as a mark's shape, so it is drawn inside the same white edge with the same shadows.
    var shape: MarkShape { MarkShape(stroked: nil, filled: body, lineWidth: 0) }
}

extension Pin {
    /// Draws the pin's teardrop in its colour, inside its edge, with its number, as `Drawing.draw` does,
    /// for a drawing of `pointScale` on an image of `pixels`.
    func draw(in ctx: CGContext, pixels: PixelSize, pointScale: CGFloat, markStyle: MarkStyle, pieceNumbers: [CGRect] = []) {
        draw(PinTeardrop(self, in: pixels, pointScale: pointScale, markStyle: markStyle, pieceNumbers: pieceNumbers),
             in: ctx, pointScale: pointScale, markStyle: markStyle)
    }

    /// Draws `drop`, this pin's teardrop wherever it is, in the pin's colour.
    func draw(_ drop: PinTeardrop, in ctx: CGContext, pointScale: CGFloat, markStyle: MarkStyle) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineJoin(.round)
        drop.shape.drawLifted(in: ctx, color: markStyle.color(color), pointScale: pointScale, markStyle: markStyle)
        ctx.setFillColor(markStyle.wordColor.cgColor)
        ctx.addPath(drop.number)
        ctx.fillPath()
    }
}
