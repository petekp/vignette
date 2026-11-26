import AppKit

/// Who made a pin, the writer of its first comment: the person, or an agent by its name in lower case,
/// "" for an agent that gave none. It decides the pin's colour everywhere and what it wears on screen.
enum PinMaker: Hashable, Sendable {
    case person
    case agent(String)

    var isAgent: Bool { self != .person }

    /// Who made a cluster of pins made by `makers`: their one maker, an agent with no name when every
    /// pin is an agent's but not one agent's, and the person otherwise.
    init(cluster makers: [PinMaker]) {
        if let first = makers.first, makers.allSatisfy({ $0 == first }) {
            self = first
        } else {
            self = makers.allSatisfy(\.isAgent) ? .agent("") : .person
        }
    }
}

/// What a teardrop wears on screen, in the editor, on a card, in flight and in the pins' menus. Copy,
/// Send and Stitch draw a number on every pin, so a picture's pins match the "Pin 3:" in the words
/// beside it.
enum PinFace: Equatable {
    case number
    /// The agent's logo, `Resources/agents/<name>.svg`, or `Agent.fallbackSymbol`, in the words' colour.
    case logo(String)
    /// The first letter of the agent's name, in capitals.
    case letter(String)

    /// The person's pins wear their number, and an agent's its logo, or the first letter of its name
    /// when the app has no logo for it. An agent that gave no name wears `Agent.fallbackSymbol`.
    init(_ maker: PinMaker) {
        guard case .agent(let name) = maker else { self = .number; return }
        if !Agent.hasLogo(name), let first = name.first {
            self = .letter(first.uppercased())
        } else {
            self = .logo(name)
        }
    }
}

extension Pin.Comment {
    var writer: PinMaker { agent ? .agent((agentName ?? "").lowercased()) : .person }
}

extension Pin {
    var maker: PinMaker { comments.first?.writer ?? .person }

    /// The agent whose dot a person's pin wears on screen: the writer of its newest agent's comment.
    /// Nil for an agent's pin and for a pin no agent answered.
    var answeringAgent: PinMaker? {
        guard maker == .person, let answer = comments.dropFirst().last(where: \.agent) else { return nil }
        return .agent((answer.agentName ?? "").lowercased())
    }
}

extension MarkStyle {
    /// This style with the agents' colour taken by `maker`'s brand when it has one (`Agent.brandColors`),
    /// so a pin, its area and its line are drawn in it.
    func painting(_ maker: PinMaker) -> MarkStyle {
        guard case .agent(let name) = maker, let brand = Agent.brandColors[name] else { return self }
        var style = self
        style.agentColor = brand
        return style
    }
}
