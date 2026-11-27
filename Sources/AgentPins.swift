import Foundation

/// One comment an agent supplied with `pins=` on `add` or `show`: a new pin at a point or over an
/// area, or an answer on a pin the screenshot already holds. A new pin's numbers are fractions of the
/// image, as an `AgentMark`'s are, so it does not depend on the screenshot's pixel size. `parse`
/// checks them.
struct AgentPin: Equatable {
    enum Target: Equatable {
        /// `x` and `y` alone.
        case point(x: Double, y: Double)
        /// `x` and `y` the area's top-left corner, `w` and `h` its size, and the corner its teardrop's
        /// tip sits on, `bottomRight` unless `corner` names another, as a drag from top left to bottom
        /// right with the Comment tool leaves it.
        case area(x: Double, y: Double, w: Double, h: Double, tip: Pin.Corner)
        /// `pin` as a number: the pin Send's line calls "Pin 3".
        case number(Int)
        /// `pin` as the `id` a request's `pins.json` gives the pin.
        case id(UUID)
    }

    let target: Target
    let text: String

    var isAnswer: Bool {
        switch target {
        case .number, .id: return true
        case .point, .area: return false
        }
    }

    /// How many comments one call may carry: a screenshot holds no more pins.
    static let maxCount = Pin.maxCount

    /// The comments for `pins=<value>`: the JSON itself when the value starts with a bracket, else the
    /// path to a file holding it, at most `AgentMark.maxBytes`. Throws the one thing wrong with it,
    /// worded for the error line: the index and the field, never what the file said.
    static func parse(_ value: String) throws -> [AgentPin] {
        guard let list = try AgentMark.json(value, of: "pins") as? [[String: Any]] else {
            throw MarkProblem("expected a JSON array of pins")
        }
        guard !list.isEmpty else { throw MarkProblem("no pins in it") }
        guard list.count <= maxCount else { throw MarkProblem("\(list.count) pins; at most \(maxCount)") }
        return try list.enumerated().map { index, item in
            do { return try AgentPin(validating: item) }
            catch { throw MarkProblem("pin \(index + 1): \(error)") }
        }
    }

    private init(validating item: [String: Any]) throws {
        let fields = MarkFields(item: item, unit: .fraction)
        text = try fields.text()
        if let named = item["pin"] {
            guard ["x", "y", "w", "h", "corner"].allSatisfy({ item[$0] == nil }) else {
                throw MarkProblem("pin names a pin to answer, so it takes no x, y, w, h or corner")
            }
            if let number = DrawingJSON.wholeNumber(named), number >= 1 {
                target = .number(number)
            } else if let id = (named as? String).flatMap(UUID.init(uuidString:)) {
                target = .id(id)
            } else {
                throw MarkProblem("pin must be a pin's number from 1, or its id from pins.json")
            }
            return
        }
        let x = Double(try fields.number("x")), y = Double(try fields.number("y"))
        guard item["w"] != nil || item["h"] != nil else {
            guard item["corner"] == nil else { throw MarkProblem("corner needs w and h") }
            target = .point(x: x, y: y)
            return
        }
        let corner: Pin.Corner
        if let raw = item["corner"] {
            guard let named = (raw as? String).flatMap(Pin.Corner.init(rawValue:)) else {
                throw MarkProblem("corner must be \(Pin.Corner.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            corner = named
        } else {
            corner = .bottomRight
        }
        target = .area(x: x, y: y, w: Double(try fields.size("w")), h: Double(try fields.size("h")), tip: corner)
    }
}

/// What one call of an agent's brings to a screenshot's drawing: its marks and its pins, the agent
/// that `agent=` names, the session that `session=` names and its name, and when it came, which the
/// pins' comments keep.
struct AgentAdditions {
    var marks: [AgentMark]
    var pins: [AgentPin] = []
    var agent: String?
    var session: AgentAddress?
    var sessionName: String?
    var at = Date()

    var isEmpty: Bool { marks.isEmpty && pins.isEmpty }

    var author: AgentAuthor { AgentAuthor(agent: agent, session: session, sessionName: sessionName, at: at) }
}

/// Who wrote an agent's comments, which each of them keeps: the agent `agent=` names, the session
/// that wrote them and that session's name, and when.
struct AgentAuthor {
    var agent: String?
    var session: AgentAddress?
    var sessionName: String?
    var at: Date?

    init(agent: String? = nil, session: AgentAddress? = nil, sessionName: String? = nil, at: Date? = Date()) {
        self.agent = agent
        self.session = session
        self.sessionName = sessionName
        self.at = at
    }

    /// `text` as this author's comment.
    func comment(_ text: String) -> Pin.Comment {
        let name = Agent.clean(agent).flatMap { $0.isEmpty ? nil : $0 }
        return Pin.Comment(text: text, agent: true, agentName: name, session: session, sessionName: sessionName, at: at)
    }
}

extension AgentPin {
    /// What `list` changes on `drawing`, the pins in their state after: each new pin placed in px inside
    /// the image and numbered from `nextPin` in the order given, and each pin an answer names with the
    /// answer added. Every comment is `author`'s. `dropped` numbers from 1, as `pins=`
    /// counts them, the answers whose pin the drawing does not hold and the new pins past `Pin.maxCount`.
    static func join(_ list: [AgentPin], by author: AgentAuthor, onto drawing: Drawing) -> (pins: [Pin], dropped: [Int]) {
        var changed: [Pin] = [], dropped: [Int] = []
        var next = drawing.nextPin, count = drawing.pins.filter { $0.number > 0 }.count
        for (index, item) in list.enumerated() {
            let comment = author.comment(item.text)
            let place: Pin.Place
            switch item.target {
            case .number, .id:
                func named(_ pin: Pin) -> Bool {
                    switch item.target {
                    case .number(let number): return pin.number == number
                    case .id(let id): return pin.id == id
                    case .point, .area: return false
                    }
                }
                guard let held = drawing.pins.first(where: { $0.number > 0 && named($0) }) else {
                    dropped.append(index + 1)
                    continue
                }
                if let i = changed.firstIndex(where: { $0.id == held.id }) {
                    changed[i].comments.append(comment)
                } else {
                    var pin = held
                    pin.comments.append(comment)
                    changed.append(pin)
                }
                continue
            case .point(let x, let y):
                place = .point(CGPoint(x: x * Double(drawing.pixels.width), y: y * Double(drawing.pixels.height)))
            case .area(let x, let y, let w, let h, let tip):
                let width = Double(drawing.pixels.width), height = Double(drawing.pixels.height)
                place = .area(CGRect(x: x * width, y: y * height, width: w * width, height: h * height), tip: tip)
            }
            guard count < Pin.maxCount,
                  let pin = Pin(id: UUID(), number: next, place: place, comments: [comment]).placed(in: drawing.pixels) else {
                dropped.append(index + 1)
                continue
            }
            changed.append(pin)
            next += 1
            count += 1
        }
        return (changed, dropped)
    }

    /// Why `list` cannot join `drawing`, worded for the error line: an answer naming a pin it does not
    /// hold, or more new pins than it has room for. Nil when every one joins.
    static func problem(_ list: [AgentPin], on drawing: Drawing?, name: String) -> String? {
        let empty = Drawing(key: "", pixels: drawing?.pixels ?? PixelSize(width: 1, height: 1), pointScale: 1, marks: [])
        let dropped = join(list, by: AgentAuthor(), onto: drawing ?? empty).dropped
        guard let first = dropped.first else { return nil }
        switch list[first - 1].target {
        case .number(let number): return "pin \(first): \(name) has no pin \(number)"
        case .id(let id): return "pin \(first): \(name) has no pin with id \(id.uuidString)"
        case .point, .area: return "pin \(first): \(name) holds at most \(Pin.maxCount) pins"
        }
    }
}

extension Drawing {
    /// The drawing with `name` given to each comment `session` wrote that has no session name yet.
    func naming(_ session: AgentAddress, _ name: String) -> Drawing {
        var drawing = self
        drawing.pins = pins.map { $0.naming(session, name) }
        return drawing
    }

    /// The drawing with `pins` in place of the pins of the same `id`, and those it lacks added, kept in
    /// number order, with `nextPin` past every number.
    func taking(_ pins: [Pin]) -> Drawing {
        var drawing = self
        let ids = Set(pins.map(\.id))
        drawing.pins = (drawing.pins.filter { !ids.contains($0.id) } + pins).sorted { $0.number < $1.number }
        drawing.nextPin = max(drawing.nextPin, (pins.map(\.number).max() ?? 0) + 1)
        return drawing
    }
}
