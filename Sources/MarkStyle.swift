import CoreGraphics

/// How marks are painted, from settings.json's `ui` (`UITweaks.markStyle`): the stroke and the edge
/// around every mark, the colour that says who drew a mark, the words' colour, the shadows' strength,
/// the arrowhead's proportions, and how pins are drawn. Widths are in pt of the drawing.
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
    var pin: PinStyle

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

/// How pins are drawn and laid out, from settings.json's `ui` (`UITweaks.markStyle`), in the editor, on
/// the cards and in the renderings alike.
struct PinStyle: Equatable, Sendable {
    /// The side of the square a teardrop fits in, in pt of the drawing.
    var side: CGFloat
    /// The number's size, and the widest it is set, as shares of `side`. A longer number is set smaller.
    var numberSize: CGFloat
    var numberWidth: CGFloat
    /// Two teardrops cluster when their bodies overlap by more than this share of their width.
    var clusterOverlap: CGFloat
    /// The room beside a cluster's label, as a share of `side`.
    var clusterPadding: CGFloat
    /// The farthest a rendering moves a teardrop's tip from its place, in teardrop sides.
    var farthestMove: CGFloat
    /// A rendering's list of comments (`CommentList`), in multiples of its text size: the comments'
    /// width below a screenshot, at least `listNarrowest` and at most `listWidestBelow`, and beside
    /// one; the room above and below a row, the gap between a row's teardrop and its words, and the
    /// space after each comment.
    var listNarrowest: CGFloat
    var listWidestBelow: CGFloat
    var listWidthBeside: CGFloat
    var listRowPadding: CGFloat
    var listWordsGap: CGFloat
    var listParagraphSpacing: CGFloat
    /// The look on screen (`PinShading`): how far the top is lightened toward white and the bottom
    /// darkened toward black, as shares; the white hairline's width; and the shadow's radius, its
    /// offset down and its darkness, which `MarkStyle.shadowOpacity` multiplies too. Widths in pt of
    /// the drawing.
    var gradient: CGFloat
    var bottomShade: CGFloat
    var rimWidth: CGFloat
    var shadowRadius: CGFloat
    var shadowOffset: CGFloat
    var shadowOpacity: CGFloat
    /// What a pin wears on screen (`PinFace`), as shares of `side`: an agent's logo's size, and the
    /// size of the dot carrying the logo of an agent that answered a person's pin.
    var logoSize: CGFloat
    var answerSize: CGFloat
    /// The gel of a pin in the editor (`PinGel`), in screen pt at every zoom: the bevel round its top,
    /// the dome on its top as a share of half its side, and the share of its colour its deep edge keeps
    /// over light content; the rod of its area's outline, the gel square on each corner of a selected
    /// area pin's area and the white square in its middle, the ring round a selected pin and its gap from
    /// the pin, the rim of its hover card and popover, and
    /// the darkness of the shadow under its number or logo.
    var gelBevel: CGFloat
    var gelDome: CGFloat
    var gelDeep: CGFloat
    var gelRod: CGFloat
    var gelHandle: CGFloat
    var gelHandleCore: CGFloat
    var gelRing: CGFloat
    var gelRingGap: CGFloat
    var gelRim: CGFloat
    var gelFaceShadow: CGFloat
}

/// A colour in sRGB, from settings.json's `#rrggbb`.
struct SRGB: Equatable, Sendable {
    var red: CGFloat, green: CGFloat, blue: CGFloat

    init(red: CGFloat, green: CGFloat, blue: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
    }

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
