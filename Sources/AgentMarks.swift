import Foundation

// An agent's marks, which are fractions of the image, turned into a drawing's marks in px.
// `docs/pushed-text-2026-09-19.md` has the numbers behind a text's size and fit.

extension AgentMark {
    /// An agent's text's size, as a fraction of the image's width, so the same sentence covers the
    /// same part of a small crop as of a full capture.
    static let textSize: CGFloat = 0.022
    /// How many times a text is widened and measured again. Wrapping is discrete, so each estimate
    /// is checked rather than trusted, and four reach the room's width from any box this makes.
    static let textFitPasses = 4

    /// `agentMarks` as marks in px on an image of `pixels`, for a drawing at `pointScale`, every one
    /// inside the image and one the drawing file's validator takes. Every mark carries `agent`, and
    /// one that names a colour `colorChosen`; the rest start in `MarkColor.start` for the colour pass.
    /// `tooLong` numbers the texts that are still bigger than the image after fitting, counted from 1
    /// as `invalid-marks` counts them: each keeps its start showing and is cut at the image's edge.
    static func marks(_ agentMarks: [AgentMark], in pixels: PixelSize, pointScale: CGFloat,
                      style: TextStyle) -> (marks: [Mark], tooLong: [Int]) {
        var marks: [Mark] = []
        var tooLong: [Int] = []
        for (index, agentMark) in agentMarks.enumerated() {
            guard var geometry = agentMark.geometry(in: pixels, pointScale: pointScale) else {
                Log.write("[marks] dropped mark=\(index + 1): its fields do not make a mark of type=\(agentMark.type.rawValue)")
                continue
            }
            if case .text(let text) = geometry {
                let fitted = fit(text, in: pixels, pointScale: pointScale, style: style)
                geometry = .text(fitted.text)
                if fitted.tooLong { tooLong.append(index + 1) }
            }
            let named = agentMark.color.flatMap(MarkColor.init(rawValue:))
            let mark = Mark(geometry: geometry, color: named ?? .start, agent: true, colorChosen: named != nil)
            guard let placed = mark.placed(in: pixels, pointScale: pointScale, style: style) else {
                Log.write("[marks] dropped mark=\(index + 1): nothing of it fits inside the image")
                continue
            }
            marks.append(placed)
        }
        return (marks, tooLong)
    }

    /// The mark's geometry in px, before it is placed. Nil when a field its type needs is missing or
    /// out of range, which `parse` refuses but a stored record read back might still hold.
    private func geometry(in pixels: PixelSize, pointScale: CGFloat) -> Mark.Geometry? {
        let width = CGFloat(pixels.width), height = CGFloat(pixels.height)
        let origin = CGPoint(x: x * width, y: y * height)
        switch type {
        case .rectangle, .ellipse:
            guard let w, let h, w > 0, h > 0 else { return nil }
            let frame = CGRect(origin: origin, size: CGSize(width: w * width, height: h * height))
            return type == .rectangle ? .rectangle(frame) : .ellipse(frame)
        case .arrow:
            guard let x2, let y2 else { return nil }
            let end = CGPoint(x: x2 * width, y: y2 * height)
            guard end != origin else { return nil }
            return .arrow(Mark.Arrow(start: origin, end: end))
        case .text:
            guard let text, let checked = try? MarkFields(item: ["text": text], unit: .fraction).text(), w.map({ $0 > 0 }) ?? true else { return nil }
            var mark = Mark.Text(origin: origin, text: checked, size: min(Self.textSize * width / pointScale, Mark.Text.maxSize))
            // It wraps in its `w`, or in the room to the image's right edge less the margin, but
            // never in less than the least room a text is given.
            mark.wrap = w.map { $0 * width } ?? max(TextLayout.minimumRoom * width, TextLayout.lineWidth(of: mark, imageWidth: width))
            return .text(mark)
        }
    }

    /// `text` widened until its lines fit the image's height, then moved inside the image. The box is
    /// measured once it exists rather than predicted, because where the words wrap is not something
    /// the agent could know. `tooLong` when it is still wider or taller than the image.
    private static func fit(_ text: Mark.Text, in pixels: PixelSize, pointScale: CGFloat,
                            style: TextStyle) -> (text: Mark.Text, tooLong: Bool) {
        let width = CGFloat(pixels.width), height = CGFloat(pixels.height), style = style.forAgent(true)
        func box(_ text: Mark.Text) -> CGRect { TextLayout(text, imageWidth: width, pointScale: pointScale, style: style).box }
        // The image less the margin on every side. The margin is a fraction of the width on all four,
        // so the inset is the same number of px all round.
        let margin = TextLayout.margin * width
        let room = CGRect(x: 0, y: 0, width: width, height: height).insetBy(dx: margin, dy: margin)
        var text = text
        // The box's area is about what the words need at their size, so the width the height wants
        // is about `w * h / room height`. It stops at the room's width, the widest a box can be and
        // still sit inside the image.
        for _ in 0..<textFitPasses where !room.isEmpty {
            let current = box(text)
            guard current.height > room.height else { break }
            let wanted = min(room.width, current.width * current.height / room.height)
            // Within a pt of the width it has, no later pass can widen it either.
            guard wanted > current.width + pointScale else { break }
            text.wrap = wanted
        }
        let fitted = box(text)
        // Where there is room to spare the box keeps the margin from the edge; where there is none it
        // goes against the image's own edge, so a box that fits the image exactly is not pushed out.
        // A box bigger than the image keeps its start showing.
        func within(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat { min(max(value, low), max(low, high)) }
        let insetX = fitted.width <= room.width ? margin : 0
        let insetY = fitted.height <= room.height ? margin : 0
        text.origin = CGPoint(x: within(fitted.minX, insetX, width - insetX - fitted.width),
                              y: within(fitted.minY, insetY, height - insetY - fitted.height))
        return (text, fitted.width > width || fitted.height > height)
    }
}
