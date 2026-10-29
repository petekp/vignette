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
