import AppKit

/// A numbered place on a screenshot, a point or an area, that holds one or more comments. It belongs
/// to a drawing beside its marks and is not a mark: it keeps its `id` in the drawing file, is drawn
/// above every mark, and is named in the undo history by its `id` (ADR 0030).
struct Pin: Equatable, Identifiable {
    /// Random, and never changes. A request's `pins.json` and an agent's answer name a pin by it.
    let id: UUID
    /// The number the pin shows, from 1. A deleted pin's number is never given to another pin while
    /// the drawing's file exists.
    var number: Int
    var place: Place
    /// Oldest first. A pin read from a file holds at least one.
    var comments: [Comment]

    enum Place: Equatable {
        /// In px of the screenshot, the space marks use.
        case point(CGPoint)
        /// Its width and height are more than 0. The teardrop's tip sits on corner `tip`, where the
        /// drag that made it ended.
        case area(CGRect, tip: Corner)
    }

    /// A corner of an area, in the screenshot's px, whose y runs down.
    enum Corner: String, CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight

        init(right: Bool, bottom: Bool) {
            switch (right, bottom) {
            case (true, true): self = .bottomRight
            case (true, false): self = .topRight
            case (false, true): self = .bottomLeft
            case (false, false): self = .topLeft
            }
        }

        /// The corner a drag from `start` to `end` ends at.
        init(from start: CGPoint, to end: CGPoint) {
            self.init(right: end.x >= start.x, bottom: end.y >= start.y)
        }

        var isRight: Bool { self == .topRight || self == .bottomRight }
        var isBottom: Bool { self == .bottomLeft || self == .bottomRight }

        /// The corner across the area on each axis that is true.
        func mirrored(x: Bool, y: Bool) -> Corner {
            Corner(right: isRight != x, bottom: isBottom != y)
        }

        func point(of frame: CGRect) -> CGPoint {
            CGPoint(x: isRight ? frame.maxX : frame.minX, y: isBottom ? frame.maxY : frame.minY)
        }
    }

    /// The words one person or one agent wrote on a pin.
    struct Comment: Equatable {
        /// Plain text, within `MarkFields`' limits, as a note's.
        var text: String
        var agent: Bool
        /// Which agent wrote it, as a mark's `agentName`. Nil for a person's comment.
        var agentName: String?
        /// The agent session that wrote it. The file keeps only its id and names its client by
        /// `agentName`, so it is kept only when `agentName` is its client's name. Nil for a person's
        /// comment, and for an agent's that named no session.
        var session: AgentAddress?
        /// That session's name as the person knows it, a Herdr tab's label or the session's own name,
        /// as `Agent.cleanSender` keeps it. Nil until the session list answers, and for a session with no name.
        var sessionName: String?
        /// When its words were written, to the second, as the file keeps it. Nil for a comment from a
        /// file written before comments kept a time.
        var at: Date?

        init(text: String, agent: Bool = false, agentName: String? = nil, session: AgentAddress? = nil,
             sessionName: String? = nil, at: Date? = nil) {
            self.text = text
            self.agent = agent
            self.agentName = agent ? agentName : nil
            self.session = agent && session?.client == AgentClient(rawValue: (agentName ?? "").lowercased()) ? session : nil
            self.sessionName = agent ? Agent.cleanSender(sessionName).name : nil
            self.at = at.map { Date(timeIntervalSince1970: $0.timeIntervalSince1970.rounded(.down)) }
        }

        /// This comment with `name` as its session's name, when `session` wrote it and it has none yet.
        func naming(_ session: AgentAddress, _ name: String) -> Comment {
            guard self.session == session, sessionName == nil else { return self }
            var named = self
            named.sessionName = Agent.cleanSender(name).name
            return named
        }

        /// How a file writes `at`: ISO 8601 in UTC, to the second, as `2026-11-25T18:04:09Z`.
        static func written(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

        /// A file's `at`, or nil when it is missing or not a time `written` would write.
        static func time(_ raw: Any?) -> Date? {
            (raw as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        }
    }

    /// The most pins one screenshot holds.
    static let maxCount = 99

    /// Where the teardrop's tip sits: a point pin's point, or its area's corner `tip`.
    var tip: CGPoint {
        switch place {
        case .point(let point): return point
        case .area(let frame, let corner): return corner.point(of: frame)
        }
    }

    var area: CGRect? {
        if case .area(let frame, _) = place { return frame }
        return nil
    }

    /// The teardrop's body goes up and to the left of its tip, rather than to the right, so that it
    /// stays outside an area whose tip is its bottom-left corner.
    var leansLeft: Bool {
        if case .area(_, .bottomLeft) = place { return true }
        return false
    }

    /// Who made the pin, the writer of its first comment, which its colour says.
    var color: MarkColor { comments.first?.agent == true ? .agent : .person }

    /// The pin with `name` given to each comment `session` wrote that has no session name yet.
    func naming(_ session: AgentAddress, _ name: String) -> Pin {
        var named = self
        named.comments = comments.map { $0.naming(session, name) }
        return named
    }

    /// The pin with its place moved by `delta`, in px.
    func moved(by delta: CGVector) -> Pin {
        var moved = self
        switch place {
        case .point(let point): moved.place = .point(CGPoint(x: point.x + delta.dx, y: point.y + delta.dy))
        case .area(let frame, let corner): moved.place = .area(frame.offsetBy(dx: delta.dx, dy: delta.dy), tip: corner)
        }
        return moved
    }
}

// MARK: - The pins' words as text

extension Pin {
    /// The pins' words in number order, as Send's line and the clipboard's text carry them:
    /// `Pin 1: remove extra margin. Pin 3: too narrow. / can it glow?`. Each comment is put on one line
    /// (`asOneLine`), a pin's comments are joined by " / ", and a pin's words end in a full stop unless
    /// they end in other closing punctuation. `quoting` is applied to each pin's words after its number.
    static func lineWords(_ pins: [Pin], quoting: (String) -> String = { $0 }) -> String {
        pins.sorted { $0.number < $1.number }
            .map { pin in "Pin \(pin.number): " + quoting(ended(pin.comments.map(\.text.asOneLine).joined(separator: " / "))) }
            .joined(separator: " ")
    }

    /// What a rendering's file carries as text after its path on the clipboard: the pins' words, or nil
    /// for a drawing without pins. A terminal pastes this text, so a pin's words holding a character a
    /// shell would act on are single-quoted (`Clipboard.shellWords`). Send's line is never read by a
    /// shell, so it carries the words as typed.
    static func clipboardWords(of drawing: Drawing) -> String? {
        drawing.pins.isEmpty ? nil : lineWords(drawing.pins, quoting: Clipboard.shellWords)
    }

    /// `words` with a full stop added when they end in a letter or a digit, so words that end in their
    /// own punctuation, a question mark or a smiley, keep it as typed.
    static func ended(_ words: String) -> String {
        guard let last = words.last, last.isLetter || last.isNumber else { return words }
        return words + "."
    }
}

// MARK: - Checking pins from a file

extension Pin {
    /// A pin as a drawing file holds it: one item of its `pins` list. Throws the one thing wrong with
    /// it, in the words of `MarkProblem`.
    init(validating raw: Any) throws {
        guard let item = raw as? [String: Any] else { throw MarkProblem("not an object") }
        let fields = MarkFields(item: item, unit: .px)
        guard let rawID = item["id"] as? String, let id = UUID(uuidString: rawID) else { throw MarkProblem("id must be a UUID") }
        guard let number = DrawingJSON.wholeNumber(item["number"]), number >= 1 else {
            throw MarkProblem("number must be a whole number from 1")
        }
        let origin = CGPoint(x: try fields.number("x"), y: try fields.number("y"))
        let place: Place
        if item["w"] == nil && item["h"] == nil {
            place = .point(origin)
        } else {
            guard let corner = item["corner"] == nil ? .topLeft : (item["corner"] as? String).flatMap(Corner.init(rawValue:)) else {
                throw MarkProblem("corner must be \(Corner.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            place = .area(CGRect(origin: origin, size: CGSize(width: try fields.size("w"), height: try fields.size("h"))), tip: corner)
        }
        guard let list = item["comments"] as? [Any], !list.isEmpty else { throw MarkProblem("comments must be a list of at least one") }
        let comments = try list.enumerated().map { index, raw in
            do { return try Comment(validating: raw) } catch { throw MarkProblem("comment \(index + 1): \(error)") }
        }
        self.init(id: id, number: number, place: place, comments: comments)
    }

    /// This pin inside `image`: a point stopped at the image's edge, and an area moved in where it fits
    /// and cut to the image where it does not, as a rectangle is. Nil when nothing of an area is inside.
    func placed(in image: PixelSize) -> Pin? {
        var placed = self
        switch place {
        case .point(let point):
            placed.place = .point(CGPoint(x: min(max(point.x, 0), CGFloat(image.width)), y: min(max(point.y, 0), CGFloat(image.height))))
        case .area(let frame, let corner):
            guard case .rectangle(let inside)? = Mark(geometry: .rectangle(frame)).placed(in: image, pointScale: 1, style: .standard)?.geometry else {
                return nil
            }
            placed.place = .area(inside, tip: corner)
        }
        return placed
    }

    /// The pins of a file's `pins` list, checked, placed inside `image` and put in number order, and its `nextPin` raised past
    /// every number kept. A pin that fails, repeats the number or the `id` of one kept before it, or
    /// comes after `maxCount` are kept, is dropped; `note` hears what happened to each pin dropped or
    /// moved, and to a `nextPin` that is not a whole number from 1, as "dropped pin=2" and why.
    static func read(_ list: [Any], nextPin raw: Any?, in image: PixelSize,
                     note: (_ what: String, _ why: String) -> Void) -> (pins: [Pin], nextPin: Int) {
        var pins: [Pin] = []
        for (index, item) in list.enumerated() {
            let name = "pin=\(index + 1)"
            do {
                let pin = try Pin(validating: item)
                guard pins.count < maxCount else { throw MarkProblem("a screenshot holds at most \(maxCount) pins") }
                guard !pins.contains(where: { $0.number == pin.number }) else { throw MarkProblem("number \(pin.number) is taken") }
                guard !pins.contains(where: { $0.id == pin.id }) else { throw MarkProblem("its id is taken") }
                guard let placed = pin.placed(in: image) else { throw MarkProblem("nothing of it fits inside the image") }
                if placed != pin { note("moved \(name)", "it did not fit where it was") }
                pins.append(placed)
            } catch {
                note("dropped \(name)", "\(error)")
            }
        }
        let stored = writtenNextPin(raw)
        if raw != nil, stored == nil { note("dropped nextPin", "it must be a whole number from 1") }
        return (pins.sorted { $0.number < $1.number }, max(stored ?? 1, (pins.map(\.number).max() ?? 0) + 1))
    }

    /// The `nextPin` a file holds, as written: nil when it has none, or none that is a whole number from 1.
    static func writtenNextPin(_ raw: Any?) -> Int? {
        DrawingJSON.wholeNumber(raw).flatMap { $0 >= 1 ? $0 : nil }
    }
}

extension Pin.Comment {
    /// One item of a pin's `comments` list. Throws the one thing wrong with it.
    init(validating raw: Any) throws {
        guard let item = raw as? [String: Any] else { throw MarkProblem("not an object") }
        let fields = MarkFields(item: item, unit: .px)
        // A time or a session that does not read is left out rather than costing the comment its words.
        let agentName = try fields.agentName()
        var session: AgentAddress?
        if let client = AgentClient(rawValue: (agentName ?? "").lowercased()), let id = Agent.cleanSession(item["session"] as? String) {
            session = AgentAddress(client: client, id: id)
        }
        self.init(text: try fields.text(), agent: try fields.flag("agent"), agentName: agentName, session: session,
                  sessionName: item["sessionName"] as? String, at: Pin.Comment.time(item["at"]))
    }
}

// MARK: - The file's encoding

/// A pin as a drawing file writes it: `x` and `y` are a point, or an area's top-left corner; `w`, `h`
/// and `corner`, the corner its teardrop's tip sits on, only for an area; and a comment's `agent`,
/// `agentName`, `session` and `sessionName` only for an agent's. A file from before `corner` has the
/// tip at the top-left.
struct PinRecord: Encodable {
    struct CommentRecord: Encodable {
        let text: String
        var agent: Bool?
        var agentName: String?
        /// The session's id. Its client is the one `agentName` names.
        var session: String?
        var sessionName: String?
        var at: String?
    }

    let id: String
    let number: Int
    let x: CGFloat
    let y: CGFloat
    var w: CGFloat?
    var h: CGFloat?
    var corner: String?
    let comments: [CommentRecord]

    init(_ pin: Pin) {
        id = pin.id.uuidString
        number = pin.number
        x = pin.extent.minX
        y = pin.extent.minY
        if case .area(let frame, let tip) = pin.place {
            w = frame.width
            h = frame.height
            corner = tip.rawValue
        }
        comments = pin.comments.map {
            CommentRecord(text: $0.text, agent: $0.agent ? true : nil, agentName: $0.agentName, session: $0.session?.id,
                          sessionName: $0.sessionName, at: $0.at.map(Pin.Comment.written))
        }
    }
}

extension Pin {
    /// Where the pin is, as a rect in px: its area, or a point's empty rect.
    var extent: CGRect {
        switch place {
        case .point(let point): return CGRect(origin: point, size: .zero)
        case .area(let frame, _): return frame
        }
    }

    /// What VoiceOver calls the pin: "Pin 3, area, 2 comments".
    var spokenName: String {
        guard number > 0 else { return "New pin" }
        let kind: String
        switch place {
        case .point: kind = "point"
        case .area: kind = "area"
        }
        return "Pin \(number), \(kind), \(comments.count == 1 ? "1 comment" : "\(comments.count) comments")"
    }
}
