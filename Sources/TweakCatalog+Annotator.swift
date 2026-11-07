import Foundation

extension TweakCatalog {
    static let annotatorSections: [TweakSection] = [
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
    ]
}
