import CoreGraphics

/// How marks are painted, from settings.json's `ui` (`UITweaks.markStyle`): the stroke and the edge
/// around every mark, the colour that says who drew a mark, the words' colour, the shadows' strength,
/// and the arrowhead's proportions. Widths are in pt of the drawing.
struct MarkStyle: Equatable, Sendable {
    var strokeWidth: CGFloat
    /// The edge outside a stroke on both sides, and outside a note's tag. It keeps a mark visible on
    /// a dark or busy screenshot, and on one of its own colour.
    var edgeWidth: CGFloat
    var personColor: SRGB
    var agentColor: SRGB
    var edgeColor: SRGB
    /// The words on every tag.
    var wordColor: SRGB
    /// A multiplier on every shadow's darkness, the badge's included.
    var shadowOpacity: CGFloat
    /// An arrowhead's proportions, in multiples of the stroke width: a filled triangle this long from
    /// its tip to its base, and this wide across the base.
    var arrowheadLength: CGFloat
    var arrowheadWidth: CGFloat

    /// The tweaks' defaults.
    static let standard = UITweaks().markStyle

    /// The most of an arrow's body a head may take: a short arrow gets a smaller head of the same
    /// shape, so it still shows a body and its head never reaches back past its start.
    static let maxShareOfBody: CGFloat = 0.5

    /// The colour of `author`'s marks.
    func color(_ author: MarkColor) -> CGColor {
        switch author {
        case .person: return personColor.cgColor
        case .agent: return agentColor.cgColor
        }
    }
}

/// A colour in sRGB, from settings.json's `#rrggbb`.
struct SRGB: Equatable, Sendable {
    var red: CGFloat, green: CGFloat, blue: CGFloat

    /// `#rrggbb`, or nil for anything else.
    init?(hex: String) {
        guard hex.count == 7, hex.first == "#", hex.dropFirst().allSatisfy(\.isHexDigit),
              let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        red = CGFloat((value >> 16) & 0xff) / 255
        green = CGFloat((value >> 8) & 0xff) / 255
        blue = CGFloat(value & 0xff) / 255
    }

    /// `color` in sRGB, or nil for one that has no sRGB equivalent.
    init?(_ color: CGColor) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let components = color.converted(to: space, intent: .defaultIntent, options: nil)?.components, components.count >= 3 else { return nil }
        red = min(max(components[0], 0), 1)
        green = min(max(components[1], 0), 1)
        blue = min(max(components[2], 0), 1)
    }

    /// Defined in sRGB; Core Graphics converts it into whatever colour space it is drawn into.
    var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: 1) }

    /// As settings.json writes it.
    var hex: String {
        String(format: "#%02x%02x%02x", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
}
