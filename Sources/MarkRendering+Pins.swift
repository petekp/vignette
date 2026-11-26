import AppKit
import CoreText

extension Drawing {
    /// Draws every mark, in order, so the newest is on top, and the pins above them. The context's
    /// transform maps the image's px, from its top-left corner with y down, to whatever it draws on.
    func draw(in ctx: CGContext, style: TextStyle, markStyle: MarkStyle, pins drawn: PinsDrawn = .teardrops) {
        for mark in marks {
            mark.draw(in: ctx, pointScale: pointScale, imageWidth: CGFloat(pixels.width), style: style, markStyle: markStyle)
        }
        switch drawn {
        case .teardrops:
            for pin in pins { pin.draw(in: ctx, pixels: pixels, pointScale: pointScale, markStyle: markStyle, pieceNumbers: pieceNumbers) }
        case .rendered: drawRenderedPins(in: ctx, style: style, markStyle: markStyle)
        case .omitted: break
        }
    }

    /// How a drawer shows the pins.
    enum PinsDrawn {
        /// Each teardrop by the orientation rule alone, as the editor and a card show it.
        case teardrops
        /// As a rendering shows them to a reader who cannot hover: each area's outline, and each
        /// teardrop clear of the ones before it (`renderedTeardrops`).
        case rendered
        /// Not at all: a stitch makes its pieces' pins its own.
        case omitted
    }

    /// A pin's teardrop where a rendering draws it. `moved` is true when the body sits away from the
    /// pin's place, joined to it by a line.
    struct RenderedTeardrop {
        let pin: Pin
        let drop: PinTeardrop
        let moved: Bool
    }

    /// Each pin's teardrop as a rendering draws it, in number order. A body that would overlap an
    /// earlier pin's body, or cover a piece number, tries the other three orientations that stay inside
    /// the picture, flipped up or down, then left or right, then both. Bodies may touch: teardrops on one
    /// place share their tip. When every orientation overlaps, the body moves to the nearest clear place
    /// inside the picture, in steps of half its side, up to `PinStyle.farthestMove` sides away, and
    /// points back at the pin's place. With no clear place in reach, it stays where the edges put it.
    func renderedTeardrops(markStyle: MarkStyle) -> [RenderedTeardrop] {
        let side = markStyle.pin.side * pointScale, edge = markStyle.edgeWidth * pointScale
        let picture = CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height)
        var bodies: [CGRect] = []
        func drawn(_ square: CGRect) -> CGRect { square.insetBy(dx: -edge, dy: -edge) }
        func clear(_ square: CGRect) -> Bool {
            !pieceNumbers.contains { $0.intersects(drawn(square)) } && !bodies.contains { body in
                let shared = body.intersection(square)
                return shared.width > 0.5 && shared.height > 0.5
            }
        }
        func inside(_ square: CGRect) -> Bool { picture.contains(drawn(square)) }
        let steps = Int(markStyle.pin.farthestMove * 2)
        let moves = (-steps...steps).flatMap { x in (-steps...steps).map { y in CGVector(dx: x, dy: y) } }
            .filter { $0 != .zero }
            .sorted { (hypot($0.dx, $0.dy), $0.dy, -$0.dx) < (hypot($1.dx, $1.dy), $1.dy, -$1.dx) }
        var placed: [RenderedTeardrop] = []
        for pin in pins.sorted(by: { $0.number < $1.number }) {
            let byEdges = PinTeardrop.facing(tip: pin.tip, side: side, edge: edge, in: pixels, avoiding: pieceNumbers, area: pin.area,
                                             leftward: pin.leansLeft)
            let up = byEdges == .upRight || byEdges == .upLeft, right = byEdges == .upRight || byEdges == .downRight
            let turns = [PinTeardrop.orientation(up: !up, right: right), PinTeardrop.orientation(up: up, right: !right),
                         PinTeardrop.orientation(up: !up, right: !right)]
            let square = { (tip: CGPoint, orientation: PinTeardrop.Orientation) in PinTeardrop.square(tip: tip, orientation: orientation, side: side) }
            let offArea = { (body: CGRect) in !(pin.area.map { body.intersects($0.insetBy(dx: 1, dy: 1)) } ?? false) }
            var place = (tip: pin.tip, orientation: byEdges)
            if !clear(square(pin.tip, byEdges)) {
                if let turned = turns.first(where: { inside(square(pin.tip, $0)) && clear(square(pin.tip, $0)) && offArea(square(pin.tip, $0)) }) {
                    place.orientation = turned
                } else if let move = moves.lazy.map({ move -> (tip: CGPoint, orientation: PinTeardrop.Orientation) in
                    (CGPoint(x: pin.tip.x + move.dx * side / 2, y: pin.tip.y + move.dy * side / 2),
                     PinTeardrop.orientation(up: move.dy <= 0, right: move.dx >= 0))
                }).first(where: { inside(square($0.tip, $0.orientation)) && clear(square($0.tip, $0.orientation))
                    && offArea(square($0.tip, $0.orientation)) }) {
                    place = move
                }
            }
            let drop = PinTeardrop(number: pin.number, agent: pin.color == .agent, tip: place.tip, orientation: place.orientation, side: side,
                                   style: markStyle.pin)
            bodies.append(drop.square)
            placed.append(RenderedTeardrop(pin: pin, drop: drop, moved: place.tip != pin.tip))
        }
        return placed
    }

    /// Draws the pins as a rendering shows them: every area's outline as a rectangle in the pin's
    /// colour, then each moved teardrop's line to its place, kept off the pieces' numbers so each
    /// stays readable, then the teardrops.
    func drawRenderedPins(in ctx: CGContext, style: TextStyle, markStyle: MarkStyle) {
        for pin in pins {
            guard case .area(let frame, _) = pin.place else { continue }
            Mark(geometry: .rectangle(frame), agent: pin.color == .agent)
                .draw(in: ctx, pointScale: pointScale, imageWidth: CGFloat(pixels.width), style: style, markStyle: markStyle.painting(pin.maker))
        }
        let drops = renderedTeardrops(markStyle: markStyle)
        ctx.saveGState()
        ctx.setLineCap(.round)
        if !pieceNumbers.isEmpty {
            let outsideNumbers = CGMutablePath()
            outsideNumbers.addRect(CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height))
            pieceNumbers.forEach { outsideNumbers.addRect($0) }
            ctx.addPath(outsideNumbers)
            ctx.clip(using: .evenOdd)
        }
        for placed in drops where placed.moved {
            let line = CGMutablePath()
            line.move(to: placed.pin.tip)
            line.addLine(to: placed.drop.tip)
            MarkShape(stroked: line, filled: nil, lineWidth: markStyle.strokeWidth * pointScale)
                .drawLifted(in: ctx, color: markStyle.painting(placed.pin.maker).color(placed.pin.color), pointScale: pointScale, markStyle: markStyle)
        }
        ctx.restoreGState()
        for placed in drops { placed.pin.draw(placed.drop, in: ctx, pointScale: pointScale, markStyle: markStyle) }
    }
}

extension Rendering {
    /// What a rendering holds besides the screenshot and its drawing.
    enum Layout: Equatable, Sendable {
        /// Nothing: the screenshot's own size. Send's, whose line carries the pins' words.
        case picture
        /// The pins' comments listed below a wide screenshot or right of a tall one (`CommentList`),
        /// for a reader who sees only the image. `textSize` is a new note's text size, in drawing pt.
        /// A drawing without pins renders as `picture` does.
        case withComments(textSize: CGFloat)
    }
}

/// A rendering's list of its pins and their comments, in px from the list's top-left corner: one row
/// per pin in number order, each with the pin's teardrop and number, then its comments in order, one
/// paragraph each, in the font of a person's or an agent's note.
struct CommentList {
    struct Row {
        let pin: Pin
        let drop: PinTeardrop
        let words: CTFrame
        let wordsFrame: CGRect
        /// The hairline above the row; nil for the first.
        let rule: CGRect?
    }

    /// The list's largest area below a screenshot, as a share of the screenshot's, or `smallestCap` px
    /// when that is more. Beside one, the list is no taller than the screenshot, or than `smallestCap`
    /// px allows. Either way a large capture's bitmap about doubles at most.
    static let areaShare: CGFloat = 1
    static let smallestCap: CGFloat = 4_000_000
    static let background = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    static let ink = CGColor(srgbRed: 0x1d / 255, green: 0x1d / 255, blue: 0x1f / 255, alpha: 1)
    static let hairline = CGColor(srgbRed: 0xe5 / 255, green: 0xe5 / 255, blue: 0xea / 255, alpha: 1)

    /// Below the screenshot, rather than right of it.
    let below: Bool
    let size: CGSize
    let rows: [Row]
    /// What the last line says when some pins' rows did not fit, and where.
    let notShown: (words: CTFrame, frame: CGRect)?

    /// The list for `drawing`'s pins with comments set at `textSize` drawing pt, or nil when it has no pins.
    init?(_ drawing: Drawing, textSize: CGFloat, style: TextStyle, markStyle: MarkStyle) {
        guard !drawing.pins.isEmpty else { return nil }
        let pinStyle = markStyle.pin
        let size = textSize * drawing.pointScale, side = pinStyle.side * drawing.pointScale
        let picture = CGSize(width: drawing.pixels.width, height: drawing.pixels.height)
        let margin = size, pad = size * pinStyle.listRowPadding, gap = size * pinStyle.listWordsGap, wordsX = margin + side + gap
        below = picture.width >= picture.height
        let wordsWidth = below ? min(max(picture.width - wordsX - margin, pinStyle.listNarrowest * size), pinStyle.listWidestBelow * size)
            : pinStyle.listWidthBeside * size
        let width = below ? max(picture.width, wordsX + wordsWidth + margin) : wordsX + wordsWidth + margin
        let tallest = below ? max(picture.width * picture.height * Self.areaShare, Self.smallestCap) / width
            : max(picture.height, Self.smallestCap / width)
        let person = style.font(size: size)
        let lineHeight = CTFontGetAscent(person) + CTFontGetDescent(person) + CTFontGetLeading(person)
        let wordsTop = max(0, (side - lineHeight) / 2)
        let hairline = max(1, drawing.pointScale)
        let pins = drawing.pins.sorted { $0.number < $1.number }
        let lastLine = { (count: Int) in Self.frame(Self.notShownWords(count), font: person, width: wordsWidth + side + gap) }
        var rows: [Row] = [], y = margin, notShown: (words: CTFrame, frame: CGRect)?
        for (index, pin) in pins.enumerated() {
            let set = Self.frame(Self.words(of: pin, size: size, spacing: pinStyle.listParagraphSpacing, style: style), font: person, width: wordsWidth)
            let height = pad * 2 + max(side, wordsTop + set.height)
            let left = pins.count - index - 1
            let reserve = left > 0 ? lastLine(left).height + pad * 2 : 0
            guard y + height + reserve + margin <= tallest else {
                let line = lastLine(pins.count - index)
                notShown = (line.frame, CGRect(x: margin, y: y + pad, width: line.width, height: line.height))
                y += pad * 2 + line.height
                break
            }
            let drop = PinTeardrop(number: pin.number, agent: pin.color == .agent, tip: CGPoint(x: margin, y: y + pad + side),
                                   orientation: .upRight, side: side, style: pinStyle)
            rows.append(Row(pin: pin, drop: drop, words: set.frame,
                            wordsFrame: CGRect(x: wordsX, y: y + pad + wordsTop, width: set.width, height: set.height),
                            rule: rows.isEmpty ? nil : CGRect(x: margin, y: y - hairline / 2, width: width - 2 * margin, height: hairline)))
            y += height
        }
        self.rows = rows
        self.notShown = notShown
        self.size = CGSize(width: width.rounded(.up), height: below ? (y + margin).rounded(.up) : max(picture.height, (y + margin).rounded(.up)))
    }

    /// The size of a rendering of a screenshot of `pixels` with this list beside it.
    func canvas(for pixels: PixelSize) -> PixelSize {
        below
            ? PixelSize(width: max(pixels.width, Int(size.width)), height: pixels.height + Int(size.height))
            : PixelSize(width: pixels.width + Int(size.width), height: max(pixels.height, Int(size.height)))
    }

    /// Where the list starts on that canvas.
    func origin(for pixels: PixelSize) -> CGPoint {
        below ? CGPoint(x: 0, y: pixels.height) : CGPoint(x: pixels.width, y: 0)
    }

    /// Draws the rows, in a context whose units are px from the top-left with y down.
    func draw(in ctx: CGContext, at origin: CGPoint, pointScale: CGFloat, markStyle: MarkStyle) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.translateBy(x: origin.x, y: origin.y)
        ctx.setFillColor(Self.hairline)
        for row in rows { if let rule = row.rule { ctx.fill(rule) } }
        for row in rows {
            row.pin.draw(row.drop, in: ctx, pointScale: pointScale, markStyle: markStyle)
            Self.draw(row.words, in: row.wordsFrame, ctx: ctx)
        }
        if let notShown { Self.draw(notShown.words, in: notShown.frame, ctx: ctx) }
    }

    /// The pin's comments, one paragraph each, in the font of the note its writer would write.
    static func words(of pin: Pin, size: CGFloat, spacing: CGFloat, style: TextStyle) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = size * spacing
        let words = NSMutableAttributedString()
        for (index, comment) in pin.comments.enumerated() {
            let font = comment.agent ? style.forAgent(named: comment.agentName).font(size: size) : style.font(size: size)
            let text = comment.text + (index < pin.comments.count - 1 ? "\n" : "")
            words.append(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph]))
        }
        return words
    }

    static func notShownWords(_ count: Int) -> NSAttributedString {
        NSAttributedString(string: count == 1 ? "1 more pin didn't fit. You can read it in Vignette."
                                              : "\(count) more pins didn't fit. You can read them in Vignette.")
    }

    /// `words` set `width` px wide, in `font` where they name none, and the height they take.
    private static func frame(_ words: NSAttributedString, font: CTFont, width: CGFloat) -> (frame: CTFrame, width: CGFloat, height: CGFloat) {
        let set = NSMutableAttributedString(attributedString: words)
        let whole = NSRange(location: 0, length: set.length)
        set.enumerateAttribute(.font, in: whole) { value, range, _ in if value == nil { set.addAttribute(.font, value: font, range: range) } }
        set.enumerateAttribute(.foregroundColor, in: whole) { value, range, _ in if value == nil { set.addAttribute(.foregroundColor, value: ink, range: range) } }
        let setter = CTFramesetterCreateWithAttributedString(set)
        let fits = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(), nil, CGSize(width: width, height: .greatestFiniteMagnitude), nil)
        // A frame exactly as tall as the suggestion can drop its last line, so it gets room to spare.
        let height = fits.height.rounded(.up)
        let frame = CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: CGRect(x: 0, y: 0, width: width, height: height * 2), transform: nil), nil)
        return (frame, width, height)
    }

    /// Draws `frame` with its first line at the top of `rect`, in a context whose y runs down.
    private static func draw(_ frame: CTFrame, in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.textMatrix = .identity
        ctx.translateBy(x: rect.minX, y: rect.minY + rect.height * 2)
        ctx.scaleBy(x: 1, y: -1)
        CTFrameDraw(frame, ctx)
    }
}
