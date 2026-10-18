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
        /// One of `names`, which the file keeps as the name's index.
        case style(WritableKeyPath<UITweaks, Double>, names: [String], safe: ClosedRange<Double>)
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

    static func style(_ key: String, _ label: String, _ path: WritableKeyPath<UITweaks, Double>, _ names: [String],
                      safe: ClosedRange<Double>) -> TweakSpec {
        TweakSpec(key: key, label: label, control: .style(path, names: names, safe: safe), applies: { _ in true })
    }

    /// Whether `ui` holds this setting's default, counting floating-point noise as equal.
    func isDefault(in ui: UITweaks) -> Bool {
        let defaults = UITweaks()
        switch control {
        case .number(let path, _, _, _, _), .style(let path, _, _): return UITweaks.same(ui[keyPath: path], defaults[keyPath: path])
        case .integer(let path, _): return ui[keyPath: path] == defaults[keyPath: path]
        case .colour(let path), .font(let path), .choice(let path, _): return ui[keyPath: path] == defaults[keyPath: path]
        }
    }

    /// `ui` with this setting put back to its default.
    func reset(_ ui: inout UITweaks) {
        let defaults = UITweaks()
        switch control {
        case .number(let path, _, _, _, _), .style(let path, _, _): ui[keyPath: path] = defaults[keyPath: path]
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
    enum Lab { case intro, pointer, check }

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
            ], caption: { _ in "Widths are in the drawing's points. Shadow opacity multiplies the shadows' darkness. The arrowhead's length and width are multiples of the stroke width." }),
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
        TweakSection("Live ink gel", inkSamples: true, [
            TweakGroup(nil, [
                .colour("inkGelLight", "Ice", \.inkGelLight),
                .colour("inkGelDeep", "Deep blue", \.inkGelDeep),
                .number("inkGelWidth", "Width", \.inkGelWidth, 1...12, step: 0.25, unit: "pt", safe: 0.5...30),
                .number("inkGelCore", "White middle", \.inkGelCore, 0...1, step: 0.05, safe: 0...1),
                .number("inkGelSheen", "Highlight", \.inkGelSheen, 0...2, step: 0.05, safe: 0...2),
                .number("inkGelGlow", "Glow", \.inkGelGlow, 0...2, step: 0.05, safe: 0...2),
                .number("inkGelBloom", "Bloom toward light", \.inkGelBloom, 0...2, step: 0.05, safe: 0...2),
                .number("inkGelGlowRadius", "Glow reach", \.inkGelGlowRadius, 0...24, step: 0.5, unit: "pt", safe: 0...60),
                .number("inkGelShadow", "Shadow", \.inkGelShadow, 0...1, step: 0.01, safe: 0...1),
                .number("inkGelMotion", "Drift speed", \.inkGelMotion, 0...3, step: 0.05, safe: 0...3),
                .number("inkGelShimmer", "Shimmer", \.inkGelShimmer, 0...3, step: 0.05, safe: 0...3),
                .number("inkGelWander", "Light wander", \.inkGelWander, 0...1.5, step: 0.05, unit: " rad", safe: 0...1.5),
            ], caption: { _ in "Your live ink is luminous ice over dark windows and deep blue over light ones, whichever of the two has more contrast with what is behind it. Each stroke takes one colour for its whole length; one that crosses both kinds of content gets a light middle in a deep blue sheath. Vignette reads what is behind the ink when you start inking and after an answer is drawn. The light drifts slowly round the line, and drift speed 0 holds it still." }),
            TweakGroup("Material", [
                .number("inkGelHighlightSharpness", "Highlight sharpness", \.inkGelHighlightSharpness, 10...300, safe: 1...1000),
                .number("inkGelGlowFalloff", "Glow falloff", \.inkGelGlowFalloff, 0.5...6, step: 0.1, safe: 0.1...20),
                .number("inkGelDeepEdge", "Deep blue edge", \.inkGelDeepEdge, 0...1, step: 0.01, safe: 0...1),
                .number("inkGelEdgeOpacity", "Ice edge opacity", \.inkGelEdgeOpacity, 0...1, step: 0.01, safe: 0...1),
                .number("inkGelSheathDepth", "Deep sheath depth", \.inkGelSheathDepth, 0...2.5, step: 0.05, safe: 0...5),
                .number("inkGelShimmerLength", "Shimmer length", \.inkGelShimmerLength, 10...400, step: 5, unit: "pt", safe: 1...2000),
                .number("inkGelShimmerSpeed", "Shimmer speed", \.inkGelShimmerSpeed, 0...4, step: 0.05, safe: 0...20),
                .number("inkGelLightAngle", "Light angle", \.inkGelLightAngle, -180...180, unit: "°", safe: -360...360),
                .number("inkGelLightHeight", "Light height", \.inkGelLightHeight, 0.2...3, step: 0.05, safe: 0.01...10),
                .number("inkGelPointerLight", "Light from pointer", \.inkGelPointerLight, 0...1, step: 0.05, safe: 0...1),
                .number("inkGelPointerHeight", "Pointer light height", \.inkGelPointerHeight, 10...600, step: 5, unit: "pt", safe: 1...5000),
            ], caption: { _ in "Highlight sharpness makes the highlight a smaller, harder spot. Glow falloff is how fast the glow fades past the line. Deep blue edge is how dark the deep blue gets at the line's edge, and Ice edge opacity how clear the ice is there. Deep sheath depth is how far the deep blue reaches in over light content. The shimmer runs along the line in waves Shimmer length apart. The light hangs over the pointer, Pointer light height above the screen, so the highlights follow it; lower lights the line from its side. Light from pointer at 0 lights it from Light angle instead, 0 to the right, with Light height lower lighting it from the side." }),
        ]),
        TweakSection("Live ink hand", inkSamples: true, [
            TweakGroup("Width from speed", [
                .number("inkHandWidth", "At average speed", \.inkHandWidth, 0.3...1.5, step: 0.01, safe: 0.05...5),
                .number("inkHandSpeed", "Speed effect", \.inkHandSpeed, 0...1, step: 0.01, safe: 0...3),
                .number("inkHandThinnest", "Thinnest", \.inkHandThinnest, 0.2...1, step: 0.01, safe: 0.05...5),
                .number("inkHandWidest", "Widest", \.inkHandWidest, 1...3, step: 0.05, safe: 0.05...5),
                .number("inkHandSpeedMemory", "Speed memory", \.inkHandSpeedMemory, 4...200, unit: "events", safe: 1...1000),
                .number("inkHandWidthSmoothing", "Width smoothing", \.inkHandWidthSmoothing, 0...20, unit: "points", safe: 0...50),
            ], caption: { _ in "A line is wider where the hand slows and thinner where it hurries. At average speed it is the first width; Speed effect is how much each multiple of the average speed narrows it, between Thinnest and Widest. Widths are multiples of the gel's width. The average is over the last Speed memory pointer events, about 120 a second, and each width is averaged with the Width smoothing points either side, 2 pt apart." }),
            TweakGroup("Tapers", [
                .number("inkHandStartTaper", "Start taper", \.inkHandStartTaper, 0...60, unit: "pt", safe: 0...500),
                .number("inkHandStartWidth", "Start width", \.inkHandStartWidth, 0...1, step: 0.01, safe: 0...1),
                .number("inkHandEndTaper", "End taper", \.inkHandEndTaper, 0...80, unit: "pt", safe: 0...500),
                .number("inkHandEndWidth", "End width", \.inkHandEndWidth, 0...1, step: 0.01, safe: 0...1),
                .number("inkLength", "Longest line", \.inkLength, 400...4000, step: 50, unit: "pt", safe: 200...100_000),
                .number("inkSettle", "Settle onto shape", \.inkSettle, 0...1.5, step: 0.05, unit: "s", safe: 0...10),
                .number("inkSettleBounce", "Settle bounce", \.inkSettleBounce, 0...0.8, step: 0.01, safe: 0...0.9),
                .number("inkSettleStagger", "Settle stagger", \.inkSettleStagger, 0...0.4, step: 0.01, unit: "s", safe: 0...2),
            ], caption: { _ in "The line narrows over its first Start taper points to Start width of its width, and a loop over its last End taper points. Past Longest line, the line's start recedes as the pen goes on, and the loop or arrow is made from what is left. When the pen lifts, a loop or an arrow springs from where the hand drew it onto its shape. Settle onto shape is the spring's length and Settle bounce how far it swings past the shape. The line's end lets go first, and its start Settle stagger later." }),
        ]),
        TweakSection("Answer light", inkSamples: true, [
            TweakGroup("Glow", [
                .number("lightGlow", "Tight glow reach", \.lightGlow, 0...20, step: 0.5, unit: "pt", safe: 0...100),
                .number("lightGlowWide", "Wide glow reach", \.lightGlowWide, 0...40, step: 0.5, unit: "pt", safe: 0...200),
                .number("lightGlowStrength", "Glow", \.lightGlowStrength, 0...2, step: 0.05, safe: 0...3),
                .number("lightGlowDrawing", "Glow while drawing", \.lightGlowDrawing, 0...2, step: 0.05, safe: 0...3),
                .number("lightOverLight", "Over light windows", \.lightOverLight, 0...3, step: 0.05, safe: 0...5),
                .number("lightCoreWhite", "White middle", \.lightCoreWhite, 0...1, step: 0.05, safe: 0...1),
            ], caption: { _ in "An agent's marks are light: a core whose middle is White middle of the way to white, in a tight glow and a wide one. Glow while drawing is their strength as the mark draws itself on, and Glow once it settles. Over a light window the glows can only tint it, so Over light windows sets their strength there." }),
            TweakGroup("Glint", [
                .number("lightGlintLength", "Glint length", \.lightGlintLength, 0...120, unit: "pt", safe: 0...500),
                .number("lightGlintFade", "Glint fade", \.lightGlintFade, 0...1, step: 0.05, unit: "s", safe: 0...5),
            ], caption: { _ in "A bright piece of the line runs at the mark's head as it draws itself on, and fades over Glint fade once it is drawn." }),
        ]),
        TweakSection("Live ink", [
            TweakGroup(nil, [
                .number("liveInkDrawOn", "Answer draw-on", \.liveInkDrawOn, 0...2, step: 0.05, unit: "s", safe: 0...60),
                .number("liveInkTextSize", "Answer text size", \.liveInkTextSize, 8...32, unit: "pt", safe: 4...200),
                .number("liveInkTextWidth", "Answer text width", \.liveInkTextWidth, 120...800, step: 10, unit: "pt", safe: 40...2000),
                .number("liveInkHideFade", "Hide fade", \.liveInkHideFade, 0...1, step: 0.01, unit: "s", safe: 0...10),
                .number("liveInkShowFade", "Show fade", \.liveInkShowFade, 0...1, step: 0.01, unit: "s", safe: 0...10),
            ], caption: { _ in "Marks on a window fade out while its content scrolls or the window is resized, and fade back in once it is still." }),
            TweakGroup(nil, [
                .number("liveInkSpeechPause", "Speech pause", \.liveInkSpeechPause, 0.3...4, step: 0.1, unit: "s", safe: 0.1...30),
                .number("liveInkSpeechQuiet", "Speech quiet level", \.liveInkSpeechQuiet, 0...1, step: 0.05, safe: 0...1),
            ], caption: { _ in "Listening until a pause ends once the input stays under the quiet level for the pause, after Control and Option are let go. The level runs from -60 dB at 0 to 0 dB at 1." }),
        ]),
        TweakSection("Pointer", lab: .pointer, [
            TweakGroup("Ring", [
                .style("liveInkFieldStyle", "Style", \.liveInkFieldStyle, ["Glass", "Lens", "Squircle", "Droplet", "Lamp", "Caustic"], safe: 0...5),
                .number("liveInkFieldSize", "Size", \.liveInkFieldSize, 0...120, unit: "pt", safe: 0...200),
                // Bend past 1.8 folds the glass where the ridge is steepest.
                .number("liveInkFieldBend", "Bend", \.liveInkFieldBend, 0...1.8, step: 0.05, safe: 0...1.8, when: { $0.ring != 4 }),
                .number("liveInkFieldSplit", "Colour split", \.liveInkFieldSplit, 0...2, step: 0.05, safe: 0...2, when: { $0.ring != 4 }),
                .number("liveInkFieldDepth", "Depth", \.liveInkFieldDepth, 0.04...0.3, step: 0.01, safe: 0.04...0.3, when: { $0.ring == 5 }),
                .number("liveInkFieldZoom", "Zoom", \.liveInkFieldZoom, 1...1.6, step: 0.02, safe: 1...1.6, when: { $0.ring == 1 }),
                .number("liveInkFieldClear", "Clear middle", \.liveInkFieldClear, 0...1, step: 0.05, safe: 0...1, when: { [1, 4].contains($0.ring) }),
                .number("liveInkFieldShine", "Shine", \.liveInkFieldShine, 0...1, step: 0.05, safe: 0...1, when: { [1, 5].contains($0.ring) }),
                .number("liveInkFieldShade", "Shade", \.liveInkFieldShade, 0...1, step: 0.05, safe: 0...1, when: { [1, 5].contains($0.ring) }),
                .number("liveInkFieldSquareness", "Squareness", \.liveInkFieldSquareness, 2...8, step: 0.1, safe: 2...8, when: { $0.ring == 2 }),
                .number("liveInkFieldBreak", "Break", \.liveInkFieldBreak, 0...1, step: 0.05, safe: 0...1, when: { $0.ring == 2 }),
                .number("liveInkFieldSpread", "Spread", \.liveInkFieldSpread, 0.8...3, step: 0.05, safe: 0.8...3, when: { $0.ring == 4 }),
                .number("liveInkFieldGlow", "Glow", \.liveInkFieldGlow, 0...1, step: 0.05, safe: 0...1),
                .number("liveInkFieldFollow", "Follow", \.liveInkFieldFollow, 0...0.5, step: 0.01, unit: "s", safe: 0...1),
                .number("liveInkFieldStretch", "Stretch", \.liveInkFieldStretch, 0...1, step: 0.05, safe: 0...1),
            ], caption: { TweakCatalog.ringNote($0) }),
            TweakGroup("Lamp's life", [
                .number("liveInkLampBreath", "Breath", \.liveInkLampBreath, 0...0.5, step: 0.01, safe: 0...1, when: { $0.ring == 4 }),
                .number("liveInkLampBreathSeconds", "Breath length", \.liveInkLampBreathSeconds, 1...8, step: 0.1, unit: "s", safe: 0.5...30, when: { $0.ring == 4 }),
                .number("liveInkLampEnergy", "Energy from speed", \.liveInkLampEnergy, 0...1.5, step: 0.05, safe: 0...3, when: { $0.ring == 4 }),
                .number("liveInkLampDrift", "Drift", \.liveInkLampDrift, 0...1, step: 0.05, safe: 0...1, when: { $0.ring == 4 }),
            ], caption: { _ in "The lamp takes your ink's colours: the ice over dark content and deep blue over light, which darkens what is under it. Breath makes its pool rise and fall over the breath length. Energy brightens and widens it while the pointer moves fast. Drift moves light slowly round inside it. Breath and drift stop with Reduce Motion." }),
            TweakGroup("Showing", [
                .number("liveInkFieldDelay", "Delay", \.liveInkFieldDelay, 0...1, step: 0.05, unit: "s", safe: 0...60),
                .number("liveInkFieldFade", "Fade", \.liveInkFieldFade, 0...1, step: 0.05, unit: "s", safe: 0...60),
                .number("liveInkFieldOpacity", "Opacity", \.liveInkFieldOpacity, 0...1, step: 0.05, safe: 0...1),
            ], caption: { _ in "The field waits for the delay, or for a press, so the chord on its way to a shortcut does not flash it. It fades in and out, and the ring grows in, over the fade." }),
        ]),
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

    /// The pointer lab's notes on each style, in the order of the style's names.
    private static let ringNotes = [
        "Glass: a soft ridge of glass round the pointer that bends the screen and glows in the ink colour. What the pointer is on stays still.",
        "Lens: a clear bead. Its rim draws the screen in, Zoom magnifies its middle about the arrow's tip, and a rim light, a highlight and a soft shadow let it read on any page.",
        "Squircle: the glass ridge on a rounded square, the shape of an app icon. Break leaves only its corners.",
        "Droplet: the glass ring at rest. Moving, it pulls into a teardrop, a round head leading and a soft tail behind, as long as Stretch lets it.",
        "Lamp: no edge, only a soft pool of ink-coloured light round the arrow. It never reads the screen.",
        "Caustic: light through a glass on a table. A bright crescent gathers to a point on the side away from the light, fringed by Colour split.",
    ]

    private static func ringNote(_ ui: UITweaks) -> String {
        ringNotes[min(max(ui.ring, 0), ringNotes.count - 1)]
            + " It shows while Control and Option are held, tightens while the button is down, and Size 0 turns it off. Follow 0 holds it on the pointer."
    }
}

extension UITweaks {
    /// The pointer field's ring style, as the index its name is kept as.
    var ring: Int { Int(liveInkFieldStyle.rounded()) }
}
