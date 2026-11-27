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
    static let version = 3
    /// The format of a file that holds nothing about pins, which every build reads.
    static let versionWithoutPins = 1
    /// The format of a file that holds pins and no resolved pin, which every build since pins reads.
    static let versionWithPins = 2

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

    /// The version a file is written as: 3 when it or its history holds a resolved pin, 2 when it holds
    /// pins, a `nextPin` or a history step about pins, and 1 otherwise. A build that predates pins, or
    /// resolved pins, then leaves the file alone rather than writing over what it cannot keep.
    static func fileVersion(aboutPins: Bool, resolving: Bool = false) -> Int {
        resolving ? version : aboutPins ? versionWithPins : versionWithoutPins
    }

    /// Whether a file's `pins` list holds a resolved pin.
    static func mentionsResolved(_ pins: [Any]) -> Bool {
        pins.contains { ($0 as? [String: Any])?["resolved"] != nil }
    }

    /// The drawing as Copy, Done, a drag, Copy Drawing's rendering and Send carry it: without its resolved
    /// pins, whose asks are done. A stitch and Copy Drawing's paste inside Vignette keep them.
    var handedOver: Drawing {
        var drawing = self
        drawing.pins.removeAll(where: \.isResolved)
        return drawing
    }

    /// An empty drawing, sized for an image of `pixels` annotated on `screen`.
    init(key: String, pixels: PixelSize, sizedFor screen: DrawingScreen, rule: MarkScaleRule) {
        let scale = rule.scale(for: pixels, on: screen)
        self.init(key: key, pixels: pixels, pointScale: scale.point, markScale: scale.mark, marks: [])
    }

    /// px per pt of the screen the drawing was made on, which the screenshot's own points are in.
    var screenScale: CGFloat { pointScale / markScale }

    /// The file's JSON, in the format `DrawingStore` reads.
    func encoded() throws -> Data {
        try DrawingJSON.encode(DrawingRecord(version: Self.fileVersion(aboutPins: !pins.isEmpty || nextPin > 1, resolving: pins.contains(where: \.isResolved)), key: key,
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
        guard let list = try json(value, of: "marks") as? [[String: Any]] else {
            throw MarkProblem("expected a JSON array of marks")
        }
        guard !list.isEmpty || allowingEmpty else { throw MarkProblem("no marks in it") }
        guard list.count <= maxCount else { throw MarkProblem("\(list.count) marks; at most \(maxCount)") }
        return try list.enumerated().map { index, item in
            do { return try AgentMark(validating: item) }
            catch { throw MarkProblem("mark \(index + 1): \(error)") }
        }
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
