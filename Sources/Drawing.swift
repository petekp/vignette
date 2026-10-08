import AppKit

/// A screenshot's size in px: its size as displayed, after any orientation flag in the file.
struct PixelSize: Equatable {
    let width: Int
    let height: Int

    /// The whole image, in px from its top-left corner.
    var bounds: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }
}

/// The marks drawn on one screenshot. Geometry is in the screenshot's own px, so a drawing looks the
/// same on any display, and it fits only an image of `pixels`. The sizes set in pt, the stroke width
/// and a text's size, become px through `pointScale`.
struct Drawing: Equatable {
    /// The file format's version. `DrawingStore` leaves a file with a newer one alone.
    static let version = 1

    /// The point scales a drawing file or copied marks may carry. Displays are 1 to 3 px per pt;
    /// far outside that, a text is too large to lay out or too small to see.
    static let pointScales: ClosedRange<CGFloat> = 0.5...8

    /// The screenshot's path.
    let key: String
    let pixels: PixelSize
    /// px per pt: the scale of the display the annotator was on when the drawing's first mark was made.
    var pointScale: CGFloat
    /// In drawing order: the last one is on top, and it is the newest.
    var marks: [Mark]

    /// The file's JSON, in the format `DrawingStore` reads.
    func encoded() throws -> Data {
        try DrawingJSON.encode(DrawingRecord(version: Self.version, key: key, pixels: [pixels.width, pixels.height],
                                             pointScale: pointScale, marks: marks.map(MarkRecord.init)))
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
    /// For an agent's reply to a person's note, the note's words, which the reply's popover quotes in
    /// its header. Never written to a file.
    var quote: String?
    /// For a live answer's reply, Vignette's word on it, which its header shows in the quote's place:
    /// why the person's follow-up to it failed. Never written to a file.
    var notice: String?
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

// MARK: - Checking marks from outside the process

/// What is wrong with a mark from outside the process, in the words an error or a log line uses:
/// the mark and the field, never what the field held.
struct MarkProblem: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// One mark's fields as JSONSerialization decoded them, read through the checks every mark from
/// outside the process passes: a drawing file, a paste, an agent's `marks=`, a reply. The type is
/// known, numbers are finite, a text holds something and at most
/// `maxTextLength` characters, sizes are more than 0, and an arrow's ends differ.
struct MarkFields {
    /// What a number is: px, which may be anything finite, or a fraction of the image, from 0 to 1.
    enum Unit { case px, fraction }

    static let maxTextLength = 2000
    /// A limit on the bytes as well, since one character can carry any number of combining marks.
    static let maxTextBytes = 100_000

    let item: [String: Any]
    let unit: Unit

    func kind() throws -> MarkKind {
        guard let name = item["type"] as? String else { throw MarkProblem("no type") }
        guard let kind = MarkKind(rawValue: name) else {
            throw MarkProblem("unknown type; use \(MarkKind.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        return kind
    }

    func number(_ key: String) throws -> CGFloat {
        guard let number = DrawingJSON.number(item[key]), unit == .px || (0...1).contains(number) else {
            switch unit {
            case .px: throw MarkProblem("\(key) must be a finite number")
            case .fraction: throw MarkProblem("\(key) must be a number from 0 to 1, a fraction of the image")
            }
        }
        return number
    }

    /// Nil when the mark leaves the field out.
    func optionalNumber(_ key: String) throws -> CGFloat? {
        item[key] == nil ? nil : try number(key)
    }

    func size(_ key: String) throws -> CGFloat {
        let value = try number(key)
        guard value > 0 else { throw MarkProblem("\(key) must be more than 0") }
        return value
    }

    /// Nil when the mark leaves the field out.
    func optionalSize(_ key: String) throws -> CGFloat? {
        item[key] == nil ? nil : try size(key)
    }

    /// Spaces and empty lines alone count as no text, as they do when typing ends.
    func text() throws -> String {
        guard let text = item["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MarkProblem("text is missing")
        }
        guard text.utf8.count <= Self.maxTextBytes else { throw MarkProblem("text is longer than \(Self.maxTextBytes) bytes") }
        guard text.count <= Self.maxTextLength else { throw MarkProblem("text is longer than \(Self.maxTextLength) characters") }
        return text
    }

    /// False when the mark leaves the field out.
    func flag(_ key: String) throws -> Bool {
        guard let raw = item[key] else { return false }
        guard let flag = raw as? NSNumber, CFGetTypeID(flag) == CFBooleanGetTypeID() else {
            throw MarkProblem("\(key) must be true or false")
        }
        return flag.boolValue
    }

    /// The name of the agent that made the mark, as it may be stored (`Agent.clean`). Nil when the
    /// mark leaves it out or it holds nothing.
    func agentName() throws -> String? {
        guard let raw = item["agentName"] else { return nil }
        guard let name = raw as? String else { throw MarkProblem("agentName must be a string") }
        return Agent.clean(name).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// A freehand arrow's `via`: a list of `[x, y]` pairs, in px. Empty when the mark leaves it out.
    func via() throws -> [CGPoint] {
        guard let raw = item["via"] else { return [] }
        guard let pairs = raw as? [Any] else { throw MarkProblem("via must be a list of [x, y] points") }
        guard pairs.count <= Mark.Arrow.maxVia else { throw MarkProblem("via has more than \(Mark.Arrow.maxVia) points") }
        return try pairs.map { pair in
            guard let pair = pair as? [Any], pair.count == 2, let x = DrawingJSON.number(pair[0]), let y = DrawingJSON.number(pair[1]) else {
                throw MarkProblem("via must be a list of [x, y] points")
            }
            return CGPoint(x: x, y: y)
        }
    }

    /// An arrow's `x`, `y` and `x2`, `y2`.
    func arrowEnds() throws -> (start: CGPoint, end: CGPoint) {
        let start = CGPoint(x: try number("x"), y: try number("y"))
        let end = CGPoint(x: try number("x2"), y: try number("y2"))
        guard start != end else { throw MarkProblem("the arrow ends where it starts") }
        return (start, end)
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

// MARK: - The file's encoding

/// A mark as a drawing file and a paste write it: flat fields, without the ones its type does not
/// use, and without `bend`, `via`, `wrap`, `agent` and `agentName` at their defaults. A text's `size`
/// is always written. A mark's colour is not: it follows from `agent`.
private struct MarkRecord: Encodable {
    let type: MarkKind
    let x: CGFloat
    let y: CGFloat
    var w: CGFloat?
    var h: CGFloat?
    var x2: CGFloat?
    var y2: CGFloat?
    var bend: CGFloat?
    var via: [[CGFloat]]?
    var text: String?
    var wrap: CGFloat?
    var size: CGFloat?
    var agent: Bool?
    var agentName: String?

    init(_ mark: Mark) {
        switch mark.geometry {
        case .rectangle(let frame), .ellipse(let frame):
            x = frame.minX
            y = frame.minY
            w = frame.width
            h = frame.height
        case .arrow(let arrow):
            x = arrow.start.x
            y = arrow.start.y
            x2 = arrow.end.x
            y2 = arrow.end.y
            bend = arrow.bend == 0 ? nil : arrow.bend
            via = arrow.via.isEmpty ? nil : arrow.via.map { [$0.x, $0.y] }
        case .text(let text):
            x = text.origin.x
            y = text.origin.y
            self.text = text.text
            wrap = text.wrap
            size = text.size
        }
        type = mark.kind
        agent = mark.agent ? true : nil
        agentName = mark.agentName
    }
}

private struct DrawingRecord: Encodable {
    let version: Int
    let key: String
    let pixels: [Int]
    let pointScale: CGFloat
    let marks: [MarkRecord]
}

private struct CopiedMarksRecord: Encodable {
    let version: Int
    let pointScale: CGFloat
    let marks: [MarkRecord]
}

/// Reading and writing the JSON that drawings and copied marks travel in.
enum DrawingJSON {
    static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    /// The decoded object. JSONSerialization refuses a whole document over one number past a Double's
    /// range, such as `1e999`; such a number is read as null, so the validator drops only its mark.
    static func object(from data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: nullingOverflow(data))
    }

    /// A finite number JSONSerialization decoded, or nil for anything else. It hands `true` over as
    /// an NSNumber, which `as? Double` would read as 1.
    static func number(_ raw: Any?) -> CGFloat? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    /// A whole number JSONSerialization decoded, or nil for anything else.
    static func wholeNumber(_ raw: Any?) -> Int? {
        guard let number = number(raw), number == number.rounded(), abs(number) < 1e15 else { return nil }
        return Int(number)
    }

    /// `data` with every number outside strings that a Double cannot hold replaced by `null`.
    static func nullingOverflow(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        var out = Data(capacity: bytes.count)
        var inString = false, escaped = false
        var i = 0
        while i < bytes.count {
            let byte = bytes[i]
            if inString {
                if escaped { escaped = false } else if byte == UInt8(ascii: "\\") { escaped = true } else if byte == UInt8(ascii: "\"") { inString = false }
            } else if byte == UInt8(ascii: "\"") {
                inString = true
            } else if byte == UInt8(ascii: "-") || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) {
                var end = i + 1
                while end < bytes.count, "0123456789+-.eE".utf8.contains(bytes[end]) { end += 1 }
                let token = bytes[i..<end]
                if let value = Double(String(decoding: token, as: UTF8.self)), value.isInfinite {
                    out.append(contentsOf: "null".utf8)
                } else {
                    out.append(contentsOf: token)
                }
                i = end
                continue
            }
            out.append(byte)
            i += 1
        }
        return out
    }
}

// MARK: - Copied marks

/// Marks on the clipboard, in a pasteboard type of Vignette's own: the marks as a drawing file holds
/// them, and the point scale of the drawing they came from, so a paste keeps their sizes in pt. Any
/// app can write the type, so the marks go through the same validator as a file's.
struct CopiedMarks: Equatable {
    static let pasteboardType = NSPasteboard.PasteboardType(Identity.bundleID + ".marks")

    let pointScale: CGFloat
    let marks: [Mark]

    init(pointScale: CGFloat, marks: [Mark]) {
        self.pointScale = pointScale
        self.marks = marks
    }

    func encoded() throws -> Data {
        try DrawingJSON.encode(CopiedMarksRecord(version: Drawing.version, pointScale: pointScale, marks: marks.map(MarkRecord.init)))
    }

    /// Nil when `data` is not copied marks this build can read, or none of its marks passes the
    /// validator. A mark that fails is dropped, with a log line.
    init?(data: Data) {
        guard let object = (try? DrawingJSON.object(from: data)) as? [String: Any],
              let version = DrawingJSON.wholeNumber(object["version"]), (1...Drawing.version).contains(version),
              let scale = DrawingJSON.number(object["pointScale"]), Drawing.pointScales.contains(scale),
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
        self.init(pointScale: scale, marks: marks)
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
