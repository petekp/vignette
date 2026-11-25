import AppKit

/// A screenshot's size in px: its size as displayed, after any orientation flag in the file.
struct PixelSize: Equatable {
    let width: Int
    let height: Int

    /// The whole image, in px from its top-left corner.
    var bounds: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }
}

/// The marks and the pins on one screenshot. Geometry is in the screenshot's own px, so a drawing
/// looks the same on any display, and it fits only an image of `pixels`. The sizes set in pt, the
/// stroke width and a text's size, are drawing pt, which become px through `pointScale`.
struct Drawing: Equatable {
    /// The newest file format this build reads and writes. `DrawingStore` leaves a file with a newer
    /// one alone.
    static let version = 2
    /// The format of a file that holds nothing about pins, which every build reads.
    static let versionWithoutPins = 1

    /// The point scales a drawing file or copied marks may carry. Displays are 1 to 3 px per pt;
    /// far outside that, a text is too large to lay out or too small to see.
    static let pointScales: ClosedRange<CGFloat> = 0.5...8
    /// The mark scales a drawing file or copied marks may carry.
    static let markScales: ClosedRange<CGFloat> = 0.05...1

    /// The screenshot's path.
    var key: String
    let pixels: PixelSize
    /// px per drawing pt: the scale of the screen the annotator was on when the drawing was made,
    /// times `markScale`.
    var pointScale: CGFloat
    /// The share of their full size the marks are drawn at, from `MarkScaleRule` when the drawing was
    /// made: 1 on a full-screen capture, less on a smaller one.
    var markScale: CGFloat
    /// In drawing order: the last one is on top, and it is the newest.
    var marks: [Mark]
    /// Drawn above every mark.
    var pins: [Pin]
    /// The number the next pin takes. It never goes down while the drawing's file exists, so a deleted
    /// pin's number is never used again.
    var nextPin: Int
    /// Where a stitch's pieces wear their numbers, in px. A teardrop turns away from them (`PinTeardrop`).
    /// Empty on every other drawing.
    var pieceNumbers: [CGRect]

    init(key: String, pixels: PixelSize, pointScale: CGFloat, markScale: CGFloat = 1, marks: [Mark], pins: [Pin] = [], nextPin: Int = 1,
         pieceNumbers: [CGRect] = []) {
        self.pieceNumbers = pieceNumbers
        self.key = key
        self.pixels = pixels
        self.pointScale = pointScale
        self.markScale = markScale
        self.marks = marks
        self.pins = pins
        self.nextPin = nextPin
    }

    /// Nothing is drawn: no marks and no pins. A screenshot with an empty drawing has no drawing, even
    /// when its file keeps a message.
    var isEmpty: Bool { marks.isEmpty && pins.isEmpty }

    /// The version a file is written as: 2 when it holds pins, a `nextPin` or a history step about pins,
    /// so a build that predates pins leaves it alone rather than writing over the person's comments.
    static func fileVersion(aboutPins: Bool) -> Int { aboutPins ? version : versionWithoutPins }

    /// An empty drawing, sized for an image of `pixels` annotated on `screen`.
    init(key: String, pixels: PixelSize, sizedFor screen: DrawingScreen, rule: MarkScaleRule) {
        let scale = rule.scale(for: pixels, on: screen)
        self.init(key: key, pixels: pixels, pointScale: scale.point, markScale: scale.mark, marks: [])
    }

    /// px per pt of the screen the drawing was made on, which the screenshot's own points are in.
    var screenScale: CGFloat { pointScale / markScale }

    /// The file's JSON, in the format `DrawingStore` reads.
    func encoded() throws -> Data {
        try DrawingJSON.encode(DrawingRecord(version: Self.fileVersion(aboutPins: !pins.isEmpty || nextPin > 1), key: key,
                                             pixels: [pixels.width, pixels.height], pointScale: pointScale,
                                             markScale: markScale == 1 ? nil : markScale, marks: marks.map(MarkRecord.init),
                                             pins: pins.isEmpty ? nil : pins.map(PinRecord.init), nextPin: nextPin > 1 ? nextPin : nil,
                                             pieceNumbers: pieceNumbers.isEmpty ? nil : pieceNumbers.map { [$0.minX, $0.minY, $0.width, $0.height] }))
    }
}

/// The screen a new drawing is sized for: its backing scale, px per pt, and its size in pt.
struct DrawingScreen: Equatable {
    var scale: CGFloat
    var size: CGSize
}

extension DrawingScreen {
    init(_ screen: NSScreen) {
        self.init(scale: screen.backingScaleFactor, size: screen.frame.size)
    }
}

/// How big a new drawing's marks are, against the screen it is made on (`docs/mark-scale-2026-10-27.md`).
/// A screenshot as big as the screen keeps full-size marks. A smaller one shrinks them by `power` of its
/// size against the screen's, measured by area, to no less than the size at which a new note's text
/// still reaches a reader that resizes the image (`Stitch.readerScale`) at `smallestNoteText` px.
struct MarkScaleRule: Equatable {
    /// 0 keeps full-size marks on every screenshot; 1 shrinks them in step with its size.
    var power: CGFloat
    /// px, after the reader's resize.
    var smallestNoteText: CGFloat
    /// A new note's size, in drawing pt.
    var newTextSize: CGFloat

    /// The mark scale for an image of `pixels` on `screen`, and the point scale it gives.
    func scale(for pixels: PixelSize, on screen: DrawingScreen) -> (mark: CGFloat, point: CGFloat) {
        let screenScale = min(max(screen.scale, Drawing.pointScales.lowerBound), Drawing.pointScales.upperBound)
        let image = CGSize(width: CGFloat(pixels.width) / screenScale, height: CGFloat(pixels.height) / screenScale)
        let screenArea = screen.size.width * screen.size.height
        let share = screenArea > 0 ? image.width * image.height / screenArea : 1
        let curve = pow(max(share, 0), power / 2)
        let reader = Stitch.readerScale(CGSize(width: pixels.width, height: pixels.height))
        let floor = smallestNoteText / (newTextSize * screenScale * reader)
        var mark = min(1, max(curve.isFinite ? curve : 1, floor.isFinite ? floor : 1))
        mark = max(mark, Drawing.pointScales.lowerBound / screenScale, Drawing.markScales.lowerBound)
        return (mark, screenScale * mark)
    }
}

/// The kinds of mark, by the name a drawing file and an agent's `marks=` give them.
enum MarkKind: String, Codable, CaseIterable {
    case ellipse, rectangle, arrow, text
}

/// The colour a mark is drawn in, which says who drew it: a person's marks are red and every agent's
/// are indigo. A white edge around every mark keeps it visible whatever it is drawn over
/// (`docs/mark-colour-2026-09-29.md`), so the colour carries only its author.
enum MarkColor: CaseIterable {
    case person
    case agent
}

/// One mark on a drawing, in px.
struct Mark: Equatable, Identifiable {
    /// Names the mark while the app runs, so a selection or an undo step follows it across deletes
    /// and reorders. Never written to a file: a mark read back gets a new one.
    let id: UUID
    var geometry: Geometry
    /// An agent made it: it is drawn in the agent's colour, and reopening the drawing never selects it.
    var agent: Bool
    /// Which agent made it, as `add?agent=` or a reply's client names it (`Agent.clean`): what the
    /// badge on its note says. Nil for a person's mark, and for an agent's from before the name was kept.
    var agentName: String?
    /// An agent's note that names another of its marks, as a live answer's labels do. It is drawn
    /// without the badge, since the answer's reply names the agent once. Never written to a file.
    var isLabel = false
    /// For an agent's reply to a person's note, the note's words, which the reply's popover shows
    /// above the reply, where the person typed them. Never written to a file.
    var quote: String?
    /// For a live answer's reply, Vignette's word on it, which its row shows after who answers: why
    /// the ask failed. Never written to a file.
    var notice: String?
    /// For a live answer's reply, the name its row gives who answers, when it is not the agent's: for
    /// a note sent to a session, the title the note's target showed. Never written to a file.
    var answerer: String?
    /// For a live answer's reply, where it hangs as a popover; a text without it is a note. Never
    /// written to a file.
    var popover: PopoverPlace?
    /// For a live answer's focus mark, a rectangle that draws no stroke: where the agent pulls focus.
    /// Never written to a file.
    var focus: FocusPlace?

    init(id: UUID = UUID(), geometry: Geometry, agent: Bool = false, agentName: String? = nil) {
        self.id = id
        self.geometry = geometry
        self.agent = agent
        self.agentName = agent ? agentName : nil
    }

    var color: MarkColor { agent ? .agent : .person }

    enum Geometry: Equatable {
        /// The frame. Its width and height are more than 0 in a mark read from a file or a paste.
        case rectangle(CGRect)
        /// Fills its frame. Its width and height are more than 0 in a mark read from a file or a paste.
        case ellipse(CGRect)
        case arrow(Arrow)
        case text(Text)
    }

    /// The head is at `end`. The ends differ.
    struct Arrow: Equatable {
        var start: CGPoint
        var end: CGPoint
        /// The signed distance in px from the middle of the line between the ends to the arc,
        /// measured on the perpendicular (`bendPoint`). 0 is straight. Always 0 with `via`.
        var bend: CGFloat = 0
        /// The points between the ends that a freehand arrow passes through, in order. Its body is the
        /// smooth curve through the ends and these (`ArrowBody.init(through:)`). Empty for an arrow
        /// that is straight or bends on an arc.
        var via: [CGPoint] = []

        /// The most points `via` may hold in a file or a paste.
        static let maxVia = 500
    }

    struct Text: Equatable {
        /// The top-left corner of the box.
        var origin: CGPoint
        /// Plain text, possibly several lines. A mark read from a file or a paste holds some, within
        /// `MarkFields`' limits; the editor holds an empty one while it is being typed.
        var text: String
        /// The width the words wrap at, in px. Nil wraps them at the image's edge (`TextLayout.lineWidth`).
        var wrap: CGFloat?
        /// The font size, in pt.
        var size: CGFloat

        /// The largest size a text read from a file or a paste may have, in pt.
        static let maxSize: CGFloat = 1000
    }

    var kind: MarkKind {
        switch geometry {
        case .rectangle: return .rectangle
        case .ellipse: return .ellipse
        case .arrow: return .arrow
        case .text: return .text
        }
    }
}

extension Mark {
    /// A mark as a drawing file or a paste holds it, in px: one item of its `marks` list. Throws the
    /// one thing wrong with it.
    init(validating item: Any) throws {
        guard let item = item as? [String: Any] else { throw MarkProblem("not an object") }
        let fields = MarkFields(item: item, unit: .px)
        let kind = try fields.kind()
        let geometry: Geometry
        switch kind {
        case .rectangle, .ellipse:
            let frame = CGRect(x: try fields.number("x"), y: try fields.number("y"),
                               width: try fields.size("w"), height: try fields.size("h"))
            geometry = kind == .rectangle ? .rectangle(frame) : .ellipse(frame)
        case .arrow:
            let ends = try fields.arrowEnds()
            let via = try fields.via()
            geometry = .arrow(Arrow(start: ends.start, end: ends.end, bend: via.isEmpty ? try fields.optionalNumber("bend") ?? 0 : 0, via: via))
        case .text:
            let size = try fields.size("size")
            guard size <= Text.maxSize else { throw MarkProblem("size must be at most \(Int(Text.maxSize))") }
            geometry = .text(Text(origin: CGPoint(x: try fields.number("x"), y: try fields.number("y")),
                                  text: try fields.text(), wrap: try fields.optionalSize("wrap"), size: size))
        }
        self.init(geometry: geometry, agent: try fields.flag("agent"), agentName: try fields.agentName())
    }
}

// MARK: - Placing a mark inside an image

extension Mark {
    /// This mark inside `image`: moved in where it fits, and cut to the image where it does not. A text
    /// without a wrap width near the right edge moves left (`TextLayout.leftEdge`), except with
    /// `keepingLines`, for a text the editor moved: the move already stopped where its lines keep their
    /// breaks, and moving it left then would make it jump. A text wider or taller than the image keeps
    /// its start showing. Nil when the mark has a number that is not finite, a rectangle or ellipse has
    /// no area, or an arrow's ends meet at an edge.
    func placed(in image: PixelSize, pointScale: CGFloat, style: TextStyle, keepingLines: Bool = false) -> Mark? {
        let bounds = image.bounds
        var placed = self
        switch geometry {
        case .rectangle(let frame), .ellipse(let frame):
            guard [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite) else { return nil }
            let x = Self.fit(frame.minX, frame.width, within: bounds.width)
            let y = Self.fit(frame.minY, frame.height, within: bounds.height)
            let inside = CGRect(x: x.origin, y: y.origin, width: x.length, height: y.length)
            // A paste that scales a very thin side down can leave it 0.
            guard inside.width > 0, inside.height > 0 else { return nil }
            placed.geometry = kind == .rectangle ? .rectangle(inside) : .ellipse(inside)
        case .arrow(var arrow) where !arrow.via.isEmpty:
            let points = [arrow.start] + arrow.via + [arrow.end]
            guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
            // Moved in whole when its curve fits, else each point stopped at the edge.
            let curve = arrow.exactBody.bounds
            let dx = Self.shiftInside(from: curve.minX, to: curve.maxX, within: bounds.width)
            let dy = Self.shiftInside(from: curve.minY, to: curve.maxY, within: bounds.height)
            func inside(_ point: CGPoint) -> CGPoint {
                CGPoint(x: dx.map { point.x + $0 } ?? min(max(point.x, 0), bounds.width),
                        y: dy.map { point.y + $0 } ?? min(max(point.y, 0), bounds.height))
            }
            arrow.start = inside(arrow.start)
            arrow.end = inside(arrow.end)
            arrow.via = arrow.via.map(inside)
            arrow.bend = 0
            guard arrow.start != arrow.end else { return nil }
            placed.geometry = .arrow(arrow)
        case .arrow(var arrow):
            guard [arrow.start.x, arrow.start.y, arrow.end.x, arrow.end.y, arrow.bend].allSatisfy(\.isFinite) else { return nil }
            (arrow.start.x, arrow.end.x) = Self.fitEnds(arrow.start.x, arrow.end.x, within: bounds.width)
            (arrow.start.y, arrow.end.y) = Self.fitEnds(arrow.start.y, arrow.end.y, within: bounds.height)
            guard arrow.start != arrow.end else { return nil }
            arrow.bend = arrow.largestBend(arrow.bend, inside: bounds)
            placed.geometry = .arrow(arrow)
        case .text(var text):
            let style = style.forMark(self)
            guard [text.origin.x, text.origin.y, text.size, text.wrap ?? 0].allSatisfy(\.isFinite),
                  (text.size * pointScale).isFinite else { return nil }
            if let wrap = text.wrap, wrap > bounds.width { text.wrap = bounds.width }
            if !keepingLines {
                text.origin.x = TextLayout.leftEdge(of: text, imageWidth: bounds.width, pointScale: pointScale, style: style)
            }
            func layoutBox() -> CGRect { TextLayout(text, imageWidth: bounds.width, pointScale: pointScale, style: style).box }
            var box = layoutBox()
            if box.minX < 0 || box.maxX > bounds.maxX {
                // A text without a wrap width wraps at the image's edge, so moving it left gives it
                // more room and a new box; at x 0 it has the most room the image can give.
                text.origin.x = box.minX < 0 ? 0 : max(0, bounds.width - box.width)
                box = layoutBox()
                if box.maxX > bounds.maxX {
                    text.origin.x = 0
                    box = layoutBox()
                }
            }
            guard [box.width, box.height].allSatisfy(\.isFinite) else { return nil }
            text.origin.y = box.height > bounds.height ? 0 : min(max(text.origin.y, 0), bounds.height - box.height)
            placed.geometry = .text(text)
        }
        return placed
    }

    /// A span moved inside `0...limit`, or cut to it when it is longer.
    private static func fit(_ origin: CGFloat, _ length: CGFloat, within limit: CGFloat) -> (origin: CGFloat, length: CGFloat) {
        guard length < limit else { return (0, limit) }
        return (min(max(origin, 0), limit - length), length)
    }

    /// Two ends on one axis moved together inside `0...limit` when the gap between them fits, else
    /// each stopped at the edge.
    private static func fitEnds(_ a: CGFloat, _ b: CGFloat, within limit: CGFloat) -> (CGFloat, CGFloat) {
        guard let shift = shiftInside(from: min(a, b), to: max(a, b), within: limit) else {
            return (min(max(a, 0), limit), min(max(b, 0), limit))
        }
        return (a + shift, b + shift)
    }

    /// How far a span from `low` to `high` moves to lie inside `0...limit`, or nil when it is longer.
    static func shiftInside(from low: CGFloat, to high: CGFloat, within limit: CGFloat) -> CGFloat? {
        guard high - low <= limit else { return nil }
        return low < 0 ? -low : (high > limit ? limit - high : 0)
    }
}

// MARK: - Copied marks

/// Marks on the clipboard, in a pasteboard type of Vignette's own: the marks as a drawing file holds
/// them, and the point and mark scales of the drawing they came from, so a paste keeps their places
/// in the screenshot's points and their sizes in drawing pt. Any app can write the type, so the marks
/// go through the same validator as a file's.
struct CopiedMarks: Equatable {
    static let pasteboardType = NSPasteboard.PasteboardType(Identity.bundleID + ".marks")

    let pointScale: CGFloat
    let markScale: CGFloat
    let marks: [Mark]

    init(pointScale: CGFloat, markScale: CGFloat = 1, marks: [Mark]) {
        self.pointScale = pointScale
        self.markScale = markScale
        self.marks = marks
    }

    /// px per pt of the screen the marks' drawing was made on.
    var screenScale: CGFloat { pointScale / markScale }

    func encoded() throws -> Data {
        try DrawingJSON.encode(CopiedMarksRecord(version: Drawing.versionWithoutPins, pointScale: pointScale,
                                                 markScale: markScale == 1 ? nil : markScale, marks: marks.map(MarkRecord.init)))
    }

    /// Nil when `data` is not copied marks this build can read, or none of its marks passes the
    /// validator. A mark that fails is dropped, with a log line.
    init?(data: Data) {
        guard let object = (try? DrawingJSON.object(from: data)) as? [String: Any],
              let version = DrawingJSON.wholeNumber(object["version"]), (1...Drawing.version).contains(version),
              let scale = DrawingJSON.number(object["pointScale"]), Drawing.pointScales.contains(scale),
              let markScale = object["markScale"] == nil ? 1 : DrawingJSON.number(object["markScale"]), Drawing.markScales.contains(markScale),
              let list = object["marks"] as? [Any] else {
            Log.write("[paste] error the clipboard's marks are not ones this build reads")
            return nil
        }
        guard !list.isEmpty else {
            Log.write("[paste] error the clipboard's marks list is empty")
            return nil
        }
        var marks: [Mark] = []
        for (index, item) in list.enumerated() {
            do { marks.append(try Mark(validating: item)) }
            catch { Log.write("[paste] dropped mark=\(index + 1): \(error)") }
        }
        guard !marks.isEmpty else { return nil }
        self.init(pointScale: scale, markScale: markScale, marks: marks)
    }
}

// MARK: - Agents' marks

/// One mark an agent supplied with `add?marks=` or in a reply. Every number is a fraction of the
/// image: `x` and `y` from its top-left corner, `w` and `h` of its size, `x2` and `y2` where an arrow
/// points, so a mark does not depend on the screenshot's pixel size. `parse` checks them.
///
/// On a text mark `w` is the box the words wrap in, and it is optional: without it the words wrap
/// as a person's note does, at `noteMaxWidth` or the right edge, and never narrower than
/// `TextLayout.minimumRoom` (`AgentMarks`). `h` is the wrap's, never the mark's.
struct AgentMark: Codable, Equatable {
    let type: MarkKind
    let x: Double
    let y: Double
    var w: Double?
    var h: Double?
    var x2: Double?
    var y2: Double?
    var text: String?
    /// A colour the agent named. It is accepted, so a skill from before agents' marks had one colour
    /// still pushes, and ignored: every agent's mark is drawn in `MarkColor.agent`.
    var color: String?

    /// How many marks one push may carry.
    static let maxCount = 100

    /// The most `marks=` may be. A hundred marks is a few kilobytes; a larger file is a mistake,
    /// and `add` reads it on the main thread, so the size is checked before anything is read.
    static let maxBytes = 256 * 1024

    /// The marks for `add?marks=<value>`: the JSON itself when the value starts with a bracket or a
    /// brace, else the path to a file holding it. Throws the one thing wrong with it, worded for
    /// the error line: the index and the field, never what the file said, which the log would
    /// otherwise carry. Numbers are fractions of the image, so a pixel coordinate is caught here.
    /// `allowingEmpty` accepts `[]`, for a reply that brings its own image and no marks.
    static func parse(_ value: String, allowingEmpty: Bool = false) throws -> [AgentMark] {
        let data: Data
        if value.hasPrefix("[") || value.hasPrefix("{") {
            guard value.utf8.count <= maxBytes else { throw MarkProblem(tooBig(value.utf8.count)) }
            data = Data(value.utf8)
        } else {
            let url = URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
            // Nil for a directory or anything that is not a regular file, which is also the answer
            // for a pipe or a device that `Data(contentsOf:)` would read until it blocked.
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                throw MarkProblem("cannot read \(url.path)")
            }
            guard size <= maxBytes else { throw MarkProblem(tooBig(size)) }
            guard let read = try? Data(contentsOf: url) else { throw MarkProblem("cannot read \(url.path)") }
            data = read
        }
        guard let list = (try? DrawingJSON.object(from: data)) as? [[String: Any]] else {
            throw MarkProblem("expected a JSON array of marks")
        }
        guard !list.isEmpty || allowingEmpty else { throw MarkProblem("no marks in it") }
        guard list.count <= maxCount else { throw MarkProblem("\(list.count) marks; at most \(maxCount)") }
        return try list.enumerated().map { index, item in
            do { return try AgentMark(validating: item) }
            catch { throw MarkProblem("mark \(index + 1): \(error)") }
        }
    }

    private static func tooBig(_ bytes: Int) -> String {
        "\(bytes / 1024) KB of marks; at most \(maxBytes / 1024) KB"
    }
}

extension AgentMark {
    fileprivate init(validating item: [String: Any]) throws {
        let fields = MarkFields(item: item, unit: .fraction)
        type = try fields.kind()
        x = try fields.number("x")
        y = try fields.number("y")
        color = item["color"] as? String
        switch type {
        case .ellipse, .rectangle:
            w = try fields.size("w")
            h = try fields.size("h")
        case .arrow:
            let end = try fields.arrowEnds().end
            x2 = end.x
            y2 = end.y
        case .text:
            text = try fields.text()
            // The box the words wrap in, optional: without it the text wraps at the image's edge.
            w = try fields.optionalSize("w").map(Double.init)
        }
    }
}
