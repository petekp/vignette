import Foundation

/// Every setting the tweak panel and the labs show, each defined once: its control, the range its
/// slider covers, and for a number the range outside which a value breaks the app, which
/// `UITweaks.bounds` is made from (docs/tweak-panel-redesign-2026-10-12.md).
struct TweakSpec: @unchecked Sendable, Identifiable {
    enum Control {
        /// A number on a slider over `range`, rounded to `step`. A typed value may go past the slider
        /// but not past `safe`.
        case number(WritableKeyPath<UITweaks, Double>, range: ClosedRange<Double>, step: Double, unit: String, safe: ClosedRange<Double>)
        case integer(WritableKeyPath<UITweaks, Int>, range: ClosedRange<Int>)
        /// `#rrggbb`.
        case colour(WritableKeyPath<UITweaks, String>)
        /// A system design's name or an installed family's.
        case font(WritableKeyPath<UITweaks, String>)
        case choice(WritableKeyPath<UITweaks, String>, [String])
    }

    /// The setting's name in settings.json.
    let key: String
    let label: String
    let control: Control
    /// Whether the setting does anything with the others as they are; a row that does not is hidden.
    let applies: @Sendable (UITweaks) -> Bool

    var id: String { key }

    static func number(_ key: String, _ label: String, _ path: WritableKeyPath<UITweaks, Double>, _ range: ClosedRange<Double>,
                       step: Double = 1, unit: String = "", safe: ClosedRange<Double>,
                       when applies: @escaping @Sendable (UITweaks) -> Bool = { _ in true }) -> TweakSpec {
        TweakSpec(key: key, label: label, control: .number(path, range: range, step: step, unit: unit, safe: safe), applies: applies)
    }

    static func integer(_ key: String, _ label: String, _ path: WritableKeyPath<UITweaks, Int>, _ range: ClosedRange<Int>) -> TweakSpec {
        TweakSpec(key: key, label: label, control: .integer(path, range: range), applies: { _ in true })
    }

    static func colour(_ key: String, _ label: String, _ path: WritableKeyPath<UITweaks, String>) -> TweakSpec {
        TweakSpec(key: key, label: label, control: .colour(path), applies: { _ in true })
    }

    static func font(_ key: String, _ label: String, _ path: WritableKeyPath<UITweaks, String>) -> TweakSpec {
        TweakSpec(key: key, label: label, control: .font(path), applies: { _ in true })
    }

    static func choice(_ key: String, _ label: String, _ path: WritableKeyPath<UITweaks, String>, _ options: [String]) -> TweakSpec {
        TweakSpec(key: key, label: label, control: .choice(path, options), applies: { _ in true })
    }

    /// Whether `ui` holds this setting's default, counting floating-point noise as equal.
    func isDefault(in ui: UITweaks) -> Bool {
        let defaults = UITweaks()
        switch control {
        case .number(let path, _, _, _, _): return UITweaks.same(ui[keyPath: path], defaults[keyPath: path])
        case .integer(let path, _): return ui[keyPath: path] == defaults[keyPath: path]
        case .colour(let path), .font(let path), .choice(let path, _): return ui[keyPath: path] == defaults[keyPath: path]
        }
    }

    /// `ui` with this setting put back to its default.
    func reset(_ ui: inout UITweaks) {
        let defaults = UITweaks()
        switch control {
        case .number(let path, _, _, _, _): ui[keyPath: path] = defaults[keyPath: path]
        case .integer(let path, _): ui[keyPath: path] = defaults[keyPath: path]
        case .colour(let path), .font(let path), .choice(let path, _): ui[keyPath: path] = defaults[keyPath: path]
        }
    }
}

/// Rows under one heading, with a caption under them that may follow the settings.
struct TweakGroup: @unchecked Sendable {
    let title: String?
    let tweaks: [TweakSpec]
    let caption: (@Sendable (UITweaks) -> String)?

    init(_ title: String?, _ tweaks: [TweakSpec], caption: (@Sendable (UITweaks) -> String)? = nil) {
        self.title = title; self.tweaks = tweaks; self.caption = caption
    }
}

/// One entry of the panel's sidebar. A section a lab also shows names the lab, and one that changes
/// how live ink looks offers its samples (`InkSamples`).
struct TweakSection: @unchecked Sendable, Identifiable {
    enum Lab { case intro, check, setup }

    let name: String
    let lab: Lab?
    let inkSamples: Bool
    let groups: [TweakGroup]

    var id: String { name }
    var tweaks: [TweakSpec] { groups.flatMap(\.tweaks) }

    init(_ name: String, lab: Lab? = nil, inkSamples: Bool = false, _ groups: [TweakGroup]) {
        self.name = name; self.lab = lab; self.inkSamples = inkSamples; self.groups = groups
    }
}

enum TweakCatalog {
    static func section(_ name: String) -> TweakSection? { sections.first { $0.name == name } }

    static let sections: [TweakSection] = [
        TweakSection("Cards", [
            TweakGroup(nil, [
                .number("cardMaxWidth", "Max width", \.cardMaxWidth, 80...600, safe: 1...10_000),
                .number("cardMaxHeight", "Max height", \.cardMaxHeight, 60...400, safe: 1...10_000),
                .number("cardMinSide", "Min side", \.cardMinSide, 20...200, safe: 1...10_000),
                .number("cardSpacing", "Spacing", \.cardSpacing, 0...40, safe: 0...1000),
                .number("panelInset", "Panel inset", \.panelInset, 0...60, safe: 0...1000),
                .number("screenMargin", "Screen margin", \.screenMargin, 0...80, safe: 0...10_000),
                .number("stackMinScale", "Narrows to", \.stackMinScale, 0.3...1, step: 0.05, safe: 0.3...1),
                .number("stackGap", "Gap to annotator", \.stackGap, 0...80, safe: 0...1000),
            ], caption: { _ in "How narrow the stack goes to make room for the annotator's frame, and how far it stays from it. The frame never grows into that narrowest width." }),
            TweakGroup(nil, [
                .number("cardCornerRadius", "Corner radius", \.cardCornerRadius, 0...30, safe: 0...1000),
                .number("cardBorderWidth", "Border width", \.cardBorderWidth, 0...4, step: 0.5, safe: 0...100),
                .number("cardBorderOpacity", "Border opacity", \.cardBorderOpacity, 0...1, step: 0.05, safe: 0...1),
                .number("cardShadowRadius", "Shadow radius", \.cardShadowRadius, 0...40, safe: 0...1000),
                .number("cardShadowOpacity", "Shadow opacity", \.cardShadowOpacity, 0...1, step: 0.05, safe: 0...1),
                .number("cardShadowY", "Shadow y", \.cardShadowY, -20...30, safe: -1000...1000),
                .number("hoverScale", "Hover scale", \.hoverScale, 0.9...1.2, step: 0.01, safe: 0.1...10),
                .number("pressScale", "Press scale", \.pressScale, 0.8...1, step: 0.01, safe: 0.1...10),
                .number("hoverDim", "Hover dim", \.hoverDim, 0...0.8, step: 0.05, safe: 0...1),
            ]),
        ]),
        TweakSection("Hover buttons", [
            TweakGroup(nil, [
                .number("buttonSize", "Size", \.buttonSize, 16...48, safe: 1...1000),
                .number("buttonIconSize", "Icon size", \.buttonIconSize, 8...24, safe: 1...1000),
                .number("buttonSpacing", "Spacing", \.buttonSpacing, 0...24, safe: 0...1000),
                .number("selectionCircleSize", "Selection circle", \.selectionCircleSize, 12...36, safe: 1...1000),
                .number("selectionStripGap", "Selection strip gap", \.selectionStripGap, 0...40, safe: 0...1000),
                .number("autoScrollZone", "Drag-select edge band", \.autoScrollZone, 0...120, unit: "pt", safe: 0...10_000),
                .number("autoScrollSpeed", "Drag-select speed", \.autoScrollSpeed, 0...2000, step: 25, unit: "pt/s", safe: 0...10_000),
            ], caption: { _ in "How deep the band at each end of the column is, and how fast a drag-select scrolls at its very edge." }),
        ]),
        TweakSection("Timings", [
            TweakGroup(nil, [
                .number("motion", "Motion", \.motion, 0...1, step: 0.05, safe: 0...1),
            ], caption: { _ in "Scales every animation; 0 makes them instant. The system's Reduce Motion forces 0." }),
            TweakGroup(nil, [
                .number("thumbnailSeconds", "Thumbnail stays", \.thumbnailSeconds, 1...20, step: 0.5, unit: "s", safe: 0...3600),
                .number("markSeconds", "Card notice stays", \.markSeconds, 0.5...5, step: 0.1, unit: "s", safe: 0...3600),
                .number("sendGraceSeconds", "Wait before sending", \.sendGraceSeconds, 0...10, step: 0.5, unit: "s", safe: 0...10),
                .number("slideInDuration", "Slide in", \.slideInDuration, 0...1.5, step: 0.05, unit: "s", safe: 0...60),
                .choice("slideInCurve", "Slide in curve", \.slideInCurve, ["spring", "easeOut", "easeInOut", "linear"]),
                .number("slideOutDuration", "Slide out", \.slideOutDuration, 0...1.5, step: 0.05, unit: "s", safe: 0...60),
                .number("staggerDelay", "Stagger per card", \.staggerDelay, 0...0.3, step: 0.01, unit: "s", safe: 0...60),
                .number("staggerTotalMax", "Stagger total max", \.staggerTotalMax, 0...1.5, step: 0.05, unit: "s", safe: 0...60),
                .number("relayoutDuration", "Relayout", \.relayoutDuration, 0...1, step: 0.05, unit: "s", safe: 0...60),
                .number("shiftUpDuration", "Shift up for a new card", \.shiftUpDuration, 0...2, step: 0.05, unit: "s", safe: 0...60),
                .number("hoverRevealDuration", "Hover reveal", \.hoverRevealDuration, 0...0.6, step: 0.05, unit: "s", safe: 0...60),
            ]),
        ]),
        TweakSection("Flights", [
            TweakGroup(nil, [
                .number("expandDuration", "Expand to annotator", \.expandDuration, 0...1.5, step: 0.05, unit: "s", safe: 0...60),
                .number("flightArc", "Arc", \.flightArc, 0...0.4, step: 0.01, safe: 0...1),
                .number("flightArcMax", "Arc cap", \.flightArcMax, 0...300, step: 2, unit: "pt", safe: 0...2000),
                .number("flightDepth", "Depth", \.flightDepth, 0...0.3, step: 0.01, safe: 0...1),
            ], caption: { _ in "How far a card bows off the straight line between its slot and the annotator, and how much it swells halfway there." }),
        ]),
        TweakSection("Backdrop", [
            TweakGroup(nil, [
                .number("backdropWidth", "Width", \.backdropWidth, 100...1000, step: 10, safe: 1...10_000),
                .number("backdropBlurRadius", "Blur radius", \.backdropBlurRadius, 0...120, safe: 0...1000),
                .integer("backdropBands", "Bands", \.backdropBands, 1...12),
                .number("backdropRampPower", "Ramp power", \.backdropRampPower, 0.5...4, step: 0.1, safe: 0.01...100),
                .number("backdropTint", "Tint", \.backdropTint, 0...1, step: 0.05, safe: 0...1),
                .number("backdropTintStart", "Tint start", \.backdropTintStart, 0...1, step: 0.05, safe: 0...1),
                .number("backdropFadeIn", "Fade in", \.backdropFadeIn, 0...1.5, step: 0.05, unit: "s", safe: 0...60),
                .number("backdropFadeOut", "Fade out", \.backdropFadeOut, 0...1.5, step: 0.05, unit: "s", safe: 0...60),
                .number("backdropSlideIn", "Slide in", \.backdropSlideIn, 0...1.5, step: 0.05, unit: "s", safe: 0...60),
                .number("backdropSlideOut", "Slide out", \.backdropSlideOut, 0...1.5, step: 0.05, unit: "s", safe: 0...60),
                .number("dimOpacity", "Dim behind annotator", \.dimOpacity, 0...0.9, step: 0.05, safe: 0...1),
                .number("dimBlurRadius", "Dim blur", \.dimBlurRadius, 0...60, step: 1, unit: "pt", safe: 0...1000),
                .number("dimFade", "Dim fade", \.dimFade, 0...1, step: 0.05, unit: "s", safe: 0...60),
            ]),
        ]),
        TweakSection("Annotator", [
            TweakGroup(nil, [
                .number("annotationMinWidth", "Min width", \.annotationMinWidth, 200...1200, step: 10, safe: 1...100_000),
                .number("annotationMinHeight", "Min height", \.annotationMinHeight, 100...900, step: 10, safe: 1...100_000),
                .number("annotationScreenInset", "Screen inset", \.annotationScreenInset, 0...200, step: 5, safe: 0...10_000),
                .number("annotationCornerRadius", "Corner radius", \.annotationCornerRadius, 0...30, safe: 0...1000),
                .number("annotationToolbarGap", "Toolbar gap", \.annotationToolbarGap, 0...40, safe: 0...1000),
                // `Zoom.pulledToEdges` caps the band at half a side, so any value past a frame's own size
                // behaves the same; this is that, not a design limit. 0...400 is the slider's range.
                .number("zoomEdgeBandPoints", "Zoom edge band", \.zoomEdgeBandPoints, 0...400, step: 5, unit: "pt", safe: 0...2000),
                .number("zoomEdgePull", "Zoom edge pull", \.zoomEdgePull, 0...1, step: 0.05, safe: 0...1),
            ]),
            TweakGroup("Agent title", [
                .number("agentTitleSize", "Title size", \.agentTitleSize, 11...32, step: 0.5, unit: "pt", safe: 1...200),
                .number("agentDescriptionSize", "Description size", \.agentDescriptionSize, 9...24, step: 0.5, unit: "pt", safe: 1...200),
                .number("agentTitleLineGap", "Line gap", \.agentTitleLineGap, 0...16, step: 0.5, unit: "pt", safe: 0...200),
                .number("agentTitleGap", "Gap to image", \.agentTitleGap, 0...40, unit: "pt", safe: 0...1000),
                .number("agentTitleMinWidth", "Narrowest wrap", \.agentTitleMinWidth, 0...600, step: 10, unit: "pt", safe: 0...10_000),
                .number("agentTitleFade", "Fade", \.agentTitleFade, 0...1, step: 0.05, unit: "s", safe: 0...60),
            ]),
        ]),
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
    ] + liveInkSections + [
        TweakSection("Menu bar intro", lab: .intro, [
            TweakGroup("Flight", [
                .number("introDuration", "Duration", \.introDuration, 0.1...3, step: 0.05, unit: "s", safe: 0...60),
                .number("introFunnel", "Funnel strength", \.introFunnel, 0...1, step: 0.05, safe: 0...1),
            ], caption: { _ in "At 0 the intro flies the window as one piece, as it shipped; the preview then shows its rows moving together instead." }),
            TweakGroup("Pour", [
                .number("introFunnelSmoothing", "Smoothing", \.introFunnelSmoothing, 0...1, step: 0.05, safe: 0...1),
                .number("introFunnelCorner", "Corner", \.introFunnelCorner, 0...80, unit: "pt", safe: 0...200),
                .number("introFunnelSmear", "Smear", \.introFunnelSmear, 0...1, step: 0.05, safe: 0...1),
                .number("introFunnelRim", "Rim light", \.introFunnelRim, 0...1, step: 0.05, safe: 0...1),
                .number("introFunnelFade", "Fade into icon", \.introFunnelFade, 0.05...1, step: 0.05, safe: 0...1),
            ], caption: { _ in "Smoothing eases each row's start and stop, which curves the sides. Corner is the radius the pour's corners grow to. Smear averages squeezed rows so text softens instead of breaking up. Rim light brightens the bent edges. Fade into icon is how much of each row's travel it fades over as it reaches the icon." }),
        ]),
        // Setup has no settings to tune. Its section opens the lab.
        TweakSection("Setup", lab: .setup, []),
        TweakSection("Check", lab: .check, [
            TweakGroup("Coin", [
                .colour("checkColor", "Colour", \.checkColor),
                .number("checkRoughness", "Roughness", \.checkRoughness, 0...1, step: 0.01, safe: 0...1),
                .number("checkThickness", "Thickness", \.checkThickness, 0.02...0.4, step: 0.01, safe: 0.02...0.5),
                .number("checkEdge", "Edge", \.checkEdge, 0...0.2, step: 0.01, safe: 0...0.25),
                .number("checkDome", "Dome", \.checkDome, 0...0.2, step: 0.01, safe: 0...0.3),
                .number("checkClarity", "Clarity", \.checkClarity, 0...1, step: 0.01, safe: 0...1),
            ], caption: { _ in "Colour tints the polymer, more deeply the farther you look through it. Its glossy surface reflects the lights white, a little face on and nearly all at a grazing angle. Roughness softens every reflection, from a mirror at 0 to frosted at 1. Clarity is how much of what is behind the coin shows through it. Edge rounds the rim, and Dome raises each face's middle. Lengths are fractions of the coin's width." }),
            TweakGroup("Check mark", [
                .colour("checkGlowColor", "Glow colour", \.checkGlowColor),
                .number("checkGlow", "Glow", \.checkGlow, 0...3, step: 0.01, safe: 0...3),
                .number("checkGlowSpread", "Glow spread", \.checkGlowSpread, 0.01...0.3, step: 0.01, safe: 0.01...0.3),
                .number("checkMarkSize", "Size", \.checkMarkSize, 0.2...0.8, step: 0.01, safe: 0.1...0.8),
                .number("checkMarkWeight", "Weight", \.checkMarkWeight, 0.03...0.25, step: 0.01, safe: 0.02...0.3),
            ], caption: { _ in "The mark is a glowing tube in the middle of the coin, seen through both faces. Glow spread is how far its light reaches into the polymer around it. Weight is the tube's width, kept inside the coin's thickness." }),
            TweakGroup("Light", [
                .number("checkLightAngle", "Key angle", \.checkLightAngle, -180...180, unit: "°", safe: -180...180),
                .number("checkLightHeight", "Key height", \.checkLightHeight, 5...90, unit: "°", safe: 5...90),
                .number("checkLight", "Key light", \.checkLight, 0...3, step: 0.01, safe: 0...3),
                .number("checkGlint", "Glint", \.checkGlint, 0...3, step: 0.01, safe: 0...3),
                .number("checkGlintAngle", "Glint angle", \.checkGlintAngle, -90...90, unit: "°", safe: -90...90),
                .number("checkStudio", "Studio contrast", \.checkStudio, 0...1, step: 0.01, safe: 0...1),
            ], caption: { _ in "The coin reflects a studio: a bright ceiling, a soft horizon, a dim floor, a key light shaped like a window at Key angle, clockwise from the top, and Key height above the face, and a tall strip light, Glint, at Glint angle to the viewer's right. Spinning sweeps the coin's reflections across the strip, so its face and rim flash as they pass it." }),
            TweakGroup("Spin", [
                .number("checkSpinTurns", "Turns", \.checkSpinTurns, 0...3, step: 0.25, safe: 0...5),
                .number("checkSpinDuration", "Duration", \.checkSpinDuration, 0.2...3, step: 0.05, unit: "s", safe: 0...10),
                .number("checkSpinBounce", "Bounce", \.checkSpinBounce, 0...0.8, step: 0.01, safe: 0...0.9),
                .number("checkSpinDelay", "Delay", \.checkSpinDelay, 0...1, step: 0.01, unit: "s", safe: 0...10),
            ], caption: { _ in "The coin turns about its upright axis as it appears, a spring winding the turns back to face on. Bounce is how far it rocks past face on before it settles. Turns 0 leaves it still. A half turn shows the back, where the mark inside reads mirrored." }),
            TweakGroup("Bloom", [
                .number("checkBloom", "Strength", \.checkBloom, 0...2, step: 0.01, safe: 0...2),
                .number("checkBloomRadius", "Radius", \.checkBloomRadius, 0...0.8, step: 0.01, safe: 0...1),
                .number("checkBloomThreshold", "Threshold", \.checkBloomThreshold, 0...0.95, step: 0.01, safe: 0...0.95),
            ], caption: { _ in "What is brighter than Threshold, the mark's glow and the glint's flash, blurred over Radius, a fraction of the coin, and added back, so it glows past the coin's edge. Strength 0 turns it off. It shows on the dark veil, not on the white ring of a send's badge." }),
        ]),
    ]
}
