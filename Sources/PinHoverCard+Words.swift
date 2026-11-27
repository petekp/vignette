import Foundation

extension PinHoverCard {
    /// What the card says.
    struct Words: Equatable {
        /// "You", or the agent's name, as "Claude".
        let name: String
        /// "1 min. ago", or nil for a comment from a file that kept no time.
        let time: String?
        let firstLine: String
        /// "1 reply from Claude", "2 replies from you", or "3 replies" from more than one writer. Nil
        /// for a pin with one comment.
        let replies: String?
        /// "Resolved by Claude", or nil for an open pin.
        let resolved: String?

        /// The card's muted last line: the replies, then who resolved the pin.
        var footnote: String? {
            let parts = [replies, resolved].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }

        init(_ pin: Pin, now: Date) {
            let first = pin.comments.first
            name = Self.writer(first, capitalized: true)
            time = first.flatMap { Self.ago($0, now: now) }
            firstLine = first?.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            resolved = pin.resolved.map { "Resolved by \(Self.resolver($0))" }
            let later = pin.comments.dropFirst()
            guard !later.isEmpty else { replies = nil; return }
            let count = later.count == 1 ? "1 reply" : "\(later.count) replies"
            let writers = Set(later.map { Self.writer($0, capitalized: false) })
            replies = writers.count == 1 ? "\(count) from \(writers.first ?? "")" : count
        }

        /// Who wrote `comment`: "You", or the agent's name, as "Claude".
        static func writer(_ comment: Pin.Comment?, capitalized: Bool) -> String {
            guard let comment, comment.agent else { return capitalized ? "You" : "you" }
            let name = (comment.agentName ?? "").trimmingCharacters(in: .whitespaces)
            guard let letter = name.first else { return capitalized ? "An agent" : "an agent" }
            return letter.uppercased() + name.dropFirst()
        }

        /// Who resolved a pin, as the middle of a sentence names them: "you", or the agent's name, as "Claude".
        static func resolver(_ resolution: Pin.Resolution) -> String {
            writer(Pin.Comment(text: "", agent: resolution.agent, agentName: resolution.agentName), capitalized: false)
        }

        /// How long before `now` `comment` was written, as "1 min. ago". Nil for a comment from a file that
        /// kept no time.
        static func ago(_ comment: Pin.Comment, now: Date) -> String? {
            ago(comment.at, now: now)
        }

        /// How long before `now` `date` was, as "1 min. ago". Nil for no date.
        static func ago(_ date: Date?, now: Date) -> String? {
            date.map { formatter.localizedString(for: min($0, now), relativeTo: now) }
        }

        private static let formatter: RelativeDateTimeFormatter = {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            formatter.dateTimeStyle = .named
            return formatter
        }()
    }
}
