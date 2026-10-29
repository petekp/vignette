import Foundation

/// What an agent says its screenshot shows: a title, and a muted line of description under it. The
/// editor shows it above the image (`AgentTitleView`), so an agent can say what the picture is
/// without drawing on it. It is the agent's claim about the file, recorded beside its name
/// (`Agent.record(title:on:)`), and never part of the drawing.
///
/// Every value comes through `validated`, which makes each part one line and cuts it to its limit,
/// so `add`, a reply and a read of the file's attributes cannot disagree about either.
struct AgentTitle: Equatable {
    /// At the default size, one line on a frame 520 pt wide or wider, and two on a frame 300 pt
    /// wide, about the narrowest a tall screenshot opens at on a laptop's screen.
    static let maxTitle = 60
    /// Two lines on a frame 770 pt wide, the editor's smallest for a wide image, and four at 300 pt.
    static let maxDescription = 140

    let title: String?
    let description: String?

    enum Part: String {
        case title, description

        var limit: Int { self == .title ? AgentTitle.maxTitle : AgentTitle.maxDescription }
    }

    private init(title: String?, description: String?) {
        self.title = title
        self.description = description
    }

    /// The title an agent gave, as it may be stored and shown: each part on one line, trimmed, and
    /// cut at a word to its limit, with an ellipsis. Nil when neither part has any text. `cut` names
    /// the parts that were longer than their limit.
    static func validated(title: String?, description: String?) -> (value: AgentTitle?, cut: [Part]) {
        let heading = clipped(oneLine(title), to: Part.title.limit)
        let line = clipped(oneLine(description), to: Part.description.limit)
        let cut = [heading.cut ? Part.title : nil, line.cut ? Part.description : nil].compactMap { $0 }
        guard heading.text != nil || line.text != nil else { return (nil, cut) }
        return (AgentTitle(title: heading.text, description: line.text), cut)
    }

    /// Control characters and line breaks become spaces, and runs of spaces become one, so a title
    /// is one paragraph. Nil when nothing is left.
    private static func oneLine(_ value: String?) -> String? {
        guard let value else { return nil }
        let words = value.components(separatedBy: .controlCharacters).joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    /// `text` cut to `limit` characters, the ellipsis counted: at the last space that leaves a word
    /// whole, or mid-word when the text has no space to cut at.
    private static func clipped(_ text: String?, to limit: Int) -> (text: String?, cut: Bool) {
        guard let text, text.count > limit else { return (text, false) }
        let room = text.prefix(limit - 1)
        let breaksAfter = text.dropFirst(limit - 1).first?.isWhitespace ?? true
        var kept = room
        if !breaksAfter, let space = room.lastIndex(where: \.isWhitespace) { kept = room[..<space] }
        var trimmed = kept.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ",;:")))
        if trimmed.isEmpty { trimmed = String(room) }
        return (trimmed + "…", true)
    }
}

extension AgentTitle: Codable {
    private enum CodingKeys: String, CodingKey { case title, description }

    /// A stored title is read through `validated` too, so a record edited by hand cannot carry a
    /// longer one.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let title = try container.decodeIfPresent(String.self, forKey: .title)
        let description = try container.decodeIfPresent(String.self, forKey: .description)
        guard let value = Self.validated(title: title, description: description).value else {
            throw DecodingError.dataCorruptedError(forKey: .title, in: container, debugDescription: "an agent title with no text")
        }
        self = value
    }
}

/// The colour of an agent's title in the editor: white or black, whichever stands out more from the
/// backdrop behind it.
enum TitleInk: String {
    case white, black

    /// The ink for a backdrop whose parts have these relative luminances, 0 to 1: the one whose
    /// contrast ratio (WCAG 2) with its worst part is higher. White's worst part is the lightest and
    /// black's the darkest, so over a backdrop with light and dark parts no word is lost on the part
    /// least like it. Nil with no parts.
    static func choose(behind luminances: [Double]) -> TitleInk? {
        guard let darkest = luminances.min(), let lightest = luminances.max() else { return nil }
        return InkContrast.ratio(1, lightest) >= InkContrast.ratio(0, darkest) ? .white : .black
    }

    /// The relative luminance of a part of the screen under the editor's dim: `encoded` is its
    /// brightness as captured, sRGB encoded from 0 to 1, and the dim lays black over it at `dim`.
    static func luminance(encoded: Double, dim: Double) -> Double {
        InkContrast.linear(encoded * (1 - dim))
    }
}

/// When an agent's title shows in the editor: once the flight has landed and the opening's ink is
/// known, whichever comes second, so the title never shows in an ink it is about to lose. An ink
/// still unknown `inkWait` after the landing shows the title in the appearance's ink, and the
/// measured ink replaces it when it answers.
struct TitleReveal {
    /// How long a landed title waits for its ink. A wait for data, not motion, so the motion scale
    /// does not touch it.
    static let inkWait: TimeInterval = 0.5

    enum Input {
        /// A titled image opened. Its ink is unknown, whatever the last image's was.
        case opened
        case inkKnown(at: TimeInterval)
        case landed(at: TimeInterval)
        case waitEnded(at: TimeInterval)
        /// The image has no title, or is closing.
        case closed
    }

    enum Effect: Equatable {
        case waitForInk
        /// `waited` is the time from the landing.
        case show(waited: TimeInterval)
        case showInAppearanceInk(waited: TimeInterval)
    }

    private enum Phase {
        case flying(inkKnown: Bool)
        case waiting(since: TimeInterval)
        case shown, closed
    }

    private var phase = Phase.closed

    mutating func reduce(_ input: Input) -> Effect? {
        switch (input, phase) {
        case (.opened, _):
            phase = .flying(inkKnown: false)
        case (.closed, _):
            phase = .closed
        case (.inkKnown, .flying):
            phase = .flying(inkKnown: true)
        case (.inkKnown(let now), .waiting(let since)):
            phase = .shown
            return .show(waited: now - since)
        case (.landed, .flying(inkKnown: true)):
            phase = .shown
            return .show(waited: 0)
        case (.landed(let now), .flying(inkKnown: false)):
            phase = .waiting(since: now)
            return .waitForInk
        case (.waitEnded(let now), .waiting(let since)):
            phase = .shown
            return .showInAppearanceInk(waited: now - since)
        default:
            break
        }
        return nil
    }
}
