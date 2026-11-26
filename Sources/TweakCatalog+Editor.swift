import Foundation

extension TweakCatalog {
    static let editorSections: [TweakSection] = [
        TweakSection("Editor", [
            TweakGroup(nil, [
                .number("dragDistance", "Drag starts after", \.dragDistance, 0...20, step: 0.5, unit: "pt", safe: 0...1000),
                .number("hitMargin", "Stroke hit margin", \.hitMargin, 0...20, step: 0.5, unit: "pt", safe: 0...1000),
                .number("cornerHitSize", "Corner hit area", \.cornerHitSize, 0...40, step: 0.5, unit: "pt", safe: 0...1000),
                .number("edgeHitSize", "Edge hit area", \.edgeHitSize, 0...40, step: 0.5, unit: "pt", safe: 0...1000),
                .number("smallSide", "Small mark", \.smallSide, 0...60, unit: "pt", safe: 0...10_000),
            ], caption: { _ in "A mark shorter than this along a side keeps its handles' hit areas outside it." }),
            TweakGroup(nil, [
                .number("handleSize", "Handle size", \.handleSize, 2...24, step: 0.5, unit: "pt", safe: 0...1000),
                .number("dotRadius", "Arrow dot radius", \.dotRadius, 1...16, step: 0.5, unit: "pt", safe: 0...1000),
                .number("dotHitRadius", "Arrow dot hit radius", \.dotHitRadius, 2...40, step: 0.5, unit: "pt", safe: 0...1000),
                .number("selectionOutlineWidth", "Selection outline", \.selectionOutlineWidth, 0...12, step: 0.5, unit: "pt", safe: 0...1000),
                .number("smallestRectangle", "Smallest rectangle", \.smallestRectangle, 0...40, unit: "pt", safe: 0...10_000),
                .number("shortestArrow", "Shortest arrow", \.shortestArrow, 0...40, unit: "pt", safe: 0...10_000),
                .number("textDragDelay", "Text drag wait", \.textDragDelay, 0...1, step: 0.05, unit: "s", safe: 0...60),
                .number("textDragDistance", "Text drag distance", \.textDragDistance, 0...80, unit: "pt", safe: 0...10_000),
                .number("noteSettleDuration", "Note settles", \.noteSettleDuration, 0...1, step: 0.05, unit: "s", safe: 0...60),
            ], caption: { _ in "Sizes are screen points, the same at any zoom. A press with the Text tool sets how wide the text wraps if it is held this long and then dragged this far sideways. When typing ends, a note's lines are evened out over the settle time." }),
        ]),
        TweakSection("Comments", [
            TweakGroup(nil, [
                .number("pinSize", "Pin size", \.pinSize, 8...64, step: 0.5, unit: "pt", safe: 1...1000),
                .number("pinNumberSize", "Number size", \.pinNumberSize, 0.2...1, step: 0.01, safe: 0.01...10),
                .number("pinNumberWidth", "Widest number", \.pinNumberWidth, 0.2...1, step: 0.01, safe: 0.01...10),
                .number("clusterOverlap", "Pins cluster past", \.clusterOverlap, 0...1, step: 0.05, safe: 0...1),
                .number("clusterPadding", "Cluster padding", \.clusterPadding, 0...2, step: 0.05, safe: 0...10),
            ], caption: { _ in "A pin's size is in the drawing's points, and its number's size and widest setting are shares of it. Two pins are drawn as one cluster when their bodies overlap by more than the cluster share of their width, and a cluster's label has its padding, a share of the pin's size, beside it." }),
            TweakGroup("On screen", [
                .number("pinGradient", "Lighter top", \.pinGradient, 0...0.6, step: 0.01, safe: 0...1),
                .number("pinBottomShade", "Darker bottom", \.pinBottomShade, 0...0.6, step: 0.01, safe: 0...1),
                .number("pinRimWidth", "Hairline", \.pinRimWidth, 0...3, step: 0.25, unit: "pt", safe: 0...100),
                .number("pinShadowRadius", "Shadow radius", \.pinShadowRadius, 0...10, step: 0.25, unit: "pt", safe: 0...100),
                .number("pinShadowOffset", "Shadow offset", \.pinShadowOffset, 0...8, step: 0.25, unit: "pt", safe: 0...100),
                .number("pinShadowOpacity", "Shadow darkness", \.pinShadowOpacity, 0...1, step: 0.05, safe: 0...1),
            ], caption: { _ in "How a pin looks in the editor, on a card and in flight. Its top is lightened toward white and its bottom darkened toward black by those shares. The hairline and the shadow are in the drawing's points, and the marks' shadow strength multiplies the darkness. Copy, Send and Stitch keep the marks' white edge." }),
            TweakGroup("Popover and lists", [
                .number("pinPopoverWidth", "Popover width", \.pinPopoverWidth, 200...480, step: 4, unit: "pt", safe: 100...2000),
                .number("pinPopoverInset", "Popover inset", \.pinPopoverInset, 0...32, step: 1, unit: "pt", safe: 0...200),
                .number("pinPopoverSpacing", "Popover spacing", \.pinPopoverSpacing, 0...32, step: 1, unit: "pt", safe: 0...200),
                .number("pinListImageSize", "List pin size", \.pinListImageSize, 10...32, step: 1, unit: "pt", safe: 4...200),
                .number("pinListTitleWidth", "List text width", \.pinListTitleWidth, 120...600, step: 10, unit: "pt", safe: 40...2000),
                .number("pinPostSize", "Post button", \.pinPostSize, 12...32, step: 1, unit: "pt", safe: 6...200),
            ], caption: { _ in "In screen points. The popover by a pin has its width, its inset from the edge, the spacing between comments, and its post button's size. The menus a cluster and the toolbar's Pins button open show each pin at the list's pin size, and cut its first comment at the text width." }),
            TweakGroup("Area outline", [
                .number("pinAreaWidth", "Line width", \.pinAreaWidth, 0.5...4, step: 0.25, unit: "pt", safe: 0.1...100),
                .number("pinAreaDash", "Dash", \.pinAreaDash, 1...16, step: 0.5, unit: "pt", safe: 0.5...200),
                .number("pinAreaGap", "Gap", \.pinAreaGap, 1...16, step: 0.5, unit: "pt", safe: 0.5...200),
                .number("pinAreaSpeed", "March speed", \.pinAreaSpeed, 0...60, step: 1, unit: "pt/s", safe: 0...1000),
            ], caption: { _ in "In screen points at every zoom. In the editor an area's outline is dashed, and its dashes march at this speed while the pin is being placed or is open. The motion setting slows them, and Reduce Motion stops them." }),
            TweakGroup("Renderings", [
                .number("pinFarthestMove", "Farthest move", \.pinFarthestMove, 0...12, step: 0.5, safe: 0...24),
                .number("commentListNarrowest", "Narrowest list", \.commentListNarrowest, 4...40, step: 0.5, safe: 1...1000),
                .number("commentListWidestBelow", "Widest list below", \.commentListWidestBelow, 12...80, step: 0.5, safe: 1...1000),
                .number("commentListWidthBeside", "List width beside", \.commentListWidthBeside, 8...60, step: 0.5, safe: 1...1000),
                .number("commentListRowPadding", "Row padding", \.commentListRowPadding, 0...2, step: 0.05, safe: 0...10),
                .number("commentListWordsGap", "Gap before words", \.commentListWordsGap, 0...3, step: 0.05, safe: 0...10),
                .number("commentListParagraphSpacing", "Space after a comment", \.commentListParagraphSpacing, 0...2, step: 0.05, safe: 0...10),
            ], caption: { _ in "Copy, Send and Stitch move a teardrop that would cover another up to the farthest move, in pin sizes, from its place. The list of comments below or beside the picture is measured in multiples of its text size: the comments' width below the picture, between the narrowest and the widest, and beside it, the room above and below each row, the gap between a row's teardrop and its words, and the space after each comment." }),
        ]),
        TweakSection("Marks", [
            TweakGroup(nil, [
                .colour("personColor", "Person colour", \.personColor),
                .colour("agentColor", "Agent colour", \.agentColor),
                .colour("edgeColor", "Edge colour", \.edgeColor),
                .colour("noteTextColor", "Note text colour", \.noteTextColor),
                .number("strokeWidth", "Stroke width", \.strokeWidth, 0.5...12, step: 0.25, unit: "pt", safe: 0.1...100),
                .number("edgeWidth", "Edge width", \.edgeWidth, 0...6, step: 0.25, unit: "pt", safe: 0...100),
                .number("shadowOpacity", "Shadow opacity", \.shadowOpacity, 0...3, step: 0.05, safe: 0...10),
                .number("arrowheadLength", "Arrowhead length", \.arrowheadLength, 1...10, step: 0.25, safe: 0...100),
                .number("arrowheadWidth", "Arrowhead width", \.arrowheadWidth, 1...10, step: 0.25, safe: 0...100),
                .number("markScalePower", "Shrink on small screenshots", \.markScalePower, 0...1, step: 0.05, safe: 0...10),
                .number("smallestNoteText", "Smallest note text", \.smallestNoteText, 4...40, step: 0.5, unit: "px", safe: 0...1000),
            ], caption: { _ in "Widths are in the drawing's points. Shadow opacity multiplies the shadows' darkness. The arrowhead's length and width are multiples of the stroke width. Marks shrink on a screenshot smaller than the screen. At 0 they never shrink, and at 1 they shrink in step with its size. A new note's text never falls below the smallest size, measured after a model resizes the image." }),
        ]),
        TweakSection("Notes", [
            TweakGroup(nil, [
                .font("textFont", "Person font", \.textFont),
                .number("textWeight", "Person weight", \.textWeight, 100...900, step: 100, safe: 100...900),
                // A drawing file refuses a text larger than `Mark.Text.maxSize`, so a new one past it would be
                // dropped when the drawing is read again.
                .number("newTextSize", "New text size", \.newTextSize, 8...96, unit: "pt", safe: 1...Double(Mark.Text.maxSize)),
                .font("agentTextFont", "Agent font", \.agentTextFont),
                .number("agentTextWeight", "Agent weight", \.agentTextWeight, 100...900, step: 100, safe: 100...900),
                // A text past `Mark.Text.maxSize` is capped there, so a larger share of the width is the same.
                .number("agentTextSize", "Agent text size", \.agentTextSize, 0.5...4, step: 0.01, unit: "%", safe: 0.01...100),
                .number("textLineHeight", "Line height", \.textLineHeight, 1...2, step: 0.05, safe: 0.1...10),
                .number("notePaddingTop", "Padding top", \.notePaddingTop, 0...2, step: 0.01, safe: 0...10),
                .number("notePaddingBottom", "Padding bottom", \.notePaddingBottom, 0...2, step: 0.01, safe: 0...10),
                .number("notePaddingSide", "Padding sides", \.notePaddingSide, 0...2, step: 0.01, safe: 0...10),
                .number("noteMaxWidth", "Widest note", \.noteMaxWidth, 4...60, step: 0.5, safe: 1...1000),
                .number("badgeInset", "Badge inset", \.badgeInset, 0...3, step: 0.01, safe: 0...100),
                // `NoteTag.reach` leaves room above a tag for the badge's whole height, and no more.
                .number("badgeOverlap", "Badge overlap", \.badgeOverlap, 0...Double(NoteBadge.height), step: 0.01, safe: 0...Double(NoteBadge.height)),
            ], caption: { _ in "A font is rounded, monospaced, serif, default, or the name of an installed font family. Weights run from 100, Ultralight, to 900, Black. New text size is in the drawing's points. An agent's text size is a percentage of the image's width. The rest are multiples of the text's size." }),
        ]),
        TweakSection("Stitch", [
            TweakGroup(nil, [
                // The floor is the slider's, because below it a stitch is not a smaller picture but a
                // useless one: four wide captures at 64 come out a 64 x 1 PNG the app still reports as ok.
                .number("stitchLongSide", "Long side", \.stitchLongSide, 512...8192, step: 128, unit: "px", safe: 512...20_000),
            ]),
        ]),
    ]
}
