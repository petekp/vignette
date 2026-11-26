import Foundation

extension UITweaks {
    /// The editor's tweaks: its handles and hit areas, the pins and the comment list, the marks and the
    /// stitch (`TweakCatalog+Editor.swift`).
    struct Editor: Decodable, Equatable {
        // The editor (`EditorMetrics`): screen pt, the same size at any zoom, unless it says otherwise
        var dragDistance = 4.0           // how far a press travels before it is a drag
        var hitMargin = 4.0              // added to a stroke's half-width to make its hit band
        var cornerHitSize = 13.5         // a corner handle's hit area, a square centred on the corner
        var edgeHitSize = 9.0            // an edge handle's hit area, a strip along the whole side
        var smallSide = 16.0             // a mark shorter than this keeps its handles' hit areas outside it
        var handleSize = 8.0             // the corner square drawn
        var dotRadius = 4.0              // an arrow dot's drawn radius
        var dotHitRadius = 12.0          // an arrow dot's hit radius, and its halo's
        var smallestRectangle = 4.0      // a new rectangle's shortest side
        var shortestArrow = 8.0          // a new arrow's shortest length
        var textDragDelay = 0.15         // seconds a Text tool press waits before a sideways drag sets a wrap width; a threshold, not motion
        var textDragDistance = 24.0      // and the sideways travel it needs
        var newTextSize = 17.0           // pt of the drawing, not of the screen
        var selectionOutlineWidth = 3.5  // the whole outline, light edge included; it runs this far outside a mark
        var noteSettleDuration = 0.25    // seconds a note takes to move to its balanced lines when typing ends
        // Comments (`PinStyle`): drawing pt, or shares of a pin's size, or multiples of the list's text size
        var pinSize = 24.0               // the square a teardrop fits in
        var pinNumberSize = 0.5
        var pinNumberWidth = 0.64        // the widest a number is set
        var clusterOverlap = 0.34        // pins cluster when their bodies overlap by more than this share of their width
        var clusterPadding = 0.7         // beside a cluster's label
        var pinFarthestMove = 6.0        // pin sizes a rendering may move a teardrop from its place
        var commentListNarrowest = 12.0  // a rendering's list of comments
        var commentListWidestBelow = 36.0
        var commentListWidthBeside = 24.0
        var commentListRowPadding = 0.6
        var commentListWordsGap = 0.75
        var commentListParagraphSpacing = 0.4
        var pinGradient = 0.2
        var pinBottomShade = 0.1
        var pinRimWidth = 1.0
        var pinShadowRadius = 2.5
        var pinShadowOffset = 1.5
        var pinShadowOpacity = 0.35
        var pinLogoSize = 0.56           // an agent's logo on its pin, a share of the pin's size
        var pinAnswerSize = 0.5          // the dot on a pin an agent answered
        var pinPopoverWidth = 280.0      // screen pt
        var pinPopoverInset = 12.0
        var pinPopoverSpacing = 10.0
        var pinListImageSize = 18.0
        var pinListTitleWidth = 320.0
        var pinPostSize = 20.0
        var pinComposerLines = 6.0       // the lines a comment's field grows to before it scrolls
        var pinDeleteSize = 16.0         // a comment's trash button in the popover
        var pinAvatarSize = 20.0         // the writer's avatar beside a comment in the popover
        var pinHoverWidth = 240.0        // the card a pin grows into under the pointer
        var pinHoverDuration = 0.25      // seconds it takes to grow
        var pinAreaWidth = 1.5           // an area's dashed outline in the editor, screen pt
        var pinAreaDash = 4.0
        var pinAreaGap = 3.0
        var pinAreaSpeed = 14.0          // screen pt a second the dashes march
        // Marks (`MarkStyle`, `TextStyle`, `docs/mark-style-settings-2026-09-29.md`)
        var personColor = "#e03131"      // a person's marks, as #rrggbb
        var agentColor = "#364fc7"       // every agent's marks
        var edgeColor = "#ffffff"        // the edge around every mark
        var noteTextColor = "#ffffff"    // the words on a note's tag
        var strokeWidth = 3.5            // pt of the drawing
        var edgeWidth = 1.5              // pt, outside a stroke on both sides and around a note's tag
        var shadowOpacity = 1.0          // multiplies the marks' shadows' darkness; 0 turns them off
        var textFont = "rounded"         // a person's notes: rounded, monospaced, serif, default, or an installed font family
        var agentTextFont = "monospaced" // an agent's notes
        var textWeight = 600.0           // 100 Ultralight to 900 Black, as the nearest of the font's weights
        var agentTextWeight = 600.0
        var agentTextSize = 1.33         // an agent's note, as a percentage of the image's width
        var textLineHeight = 1.32        // a multiple of the text's size
        var notePaddingTop = 0.42        // the tag around a note's words, in multiples of the text's size
        var notePaddingBottom = 0.47
        var notePaddingSide = 0.8
        var noteMaxWidth = 18.0          // a note without a wrap width wraps at this many times its size
        var badgeInset = 0.35            // an agent's badge from its tag's left edge, in multiples of the text's size
        var badgeOverlap = 0.2           // and how far it overlaps the tag's top edge
        var arrowheadLength = 4.5        // multiples of the stroke width
        var arrowheadWidth = 4.0
        var markScalePower = 0.5         // how marks shrink on a screenshot smaller than the screen: 0 never, 1 in step with its size
        var smallestNoteText = 16.0      // px a new note's text never falls below, as a reader that resizes the image sees it
        // Stitch
        var stitchLongSide = 4096.0      // a composition longer than this is scaled down to it
    }
}
