import Foundation

extension TweakCatalog {
    static let stackSections: [TweakSection] = [
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
            TweakGroup(nil, [
                .number("dropDuration", "Drop", \.dropDuration, 0...1.5, step: 0.05, unit: "s", safe: 0...60),
            ], caption: { _ in "How long a card dragged out of the stack takes to pour into the point it was dropped on. A drop that fails slides home as macOS draws it." }),
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
    ]
}
