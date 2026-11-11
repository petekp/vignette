import Foundation

extension TweakCatalog {
    static let liveInkSections: [TweakSection] = [
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
                .number("inkLengthDiagonals", "Longest line", \.inkLengthDiagonals, 0.5...5, step: 0.1, unit: "diagonals", safe: 0.1...50),
                .number("inkSettle", "Settle onto shape", \.inkSettle, 0...1.5, step: 0.05, unit: "s", safe: 0...10),
                .number("inkSettleBounce", "Settle bounce", \.inkSettleBounce, 0...0.8, step: 0.01, safe: 0...0.9),
                .number("inkSettleStagger", "Settle stagger", \.inkSettleStagger, 0...0.4, step: 0.01, unit: "s", safe: 0...2),
            ], caption: { _ in "The line narrows over its first Start taper points to Start width of its width, and a loop over its last End taper points. Longest line is measured in diagonals of the screen the line began on. Past it, the line's start recedes as the pen goes on, and the loop or arrow is made from what is left. When the pen lifts, a loop or an arrow springs from where the hand drew it onto its shape. Settle onto shape is the spring's length and Settle bounce how far it swings past the shape. The line's end lets go first, and its start Settle stagger later." }),
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
            ], caption: { _ in "A window's marks fade out as it minimises or shrinks past them, and fade back in when they can show again." }),
        ]),
        TweakSection("Pointer", [
            TweakGroup("Ring", [
                .number("liveInkFieldSize", "Size", \.liveInkFieldSize, 0...120, unit: "pt", safe: 0...200),
                .number("liveInkFieldClear", "Clear middle", \.liveInkFieldClear, 0...1, step: 0.05, safe: 0...1),
                .number("liveInkFieldSpread", "Spread", \.liveInkFieldSpread, 0.8...3, step: 0.05, safe: 0.8...3),
                .number("liveInkFieldGlow", "Glow", \.liveInkFieldGlow, 0...1, step: 0.05, safe: 0...1),
                .number("liveInkFieldFollow", "Follow", \.liveInkFieldFollow, 0...0.5, step: 0.01, unit: "s", safe: 0...1),
                .number("liveInkFieldStretch", "Stretch", \.liveInkFieldStretch, 0...1, step: 0.05, safe: 0...1),
            ], caption: { _ in "The lamp shows while Control and Option are held, tightens while the button is down, and Size 0 turns it off. Follow 0 holds it on the pointer." }),
            TweakGroup("Lamp's life", [
                .number("liveInkLampBreath", "Breath", \.liveInkLampBreath, 0...0.5, step: 0.01, safe: 0...1),
                .number("liveInkLampBreathSeconds", "Breath length", \.liveInkLampBreathSeconds, 1...8, step: 0.1, unit: "s", safe: 0.5...30),
                .number("liveInkLampEnergy", "Energy from speed", \.liveInkLampEnergy, 0...1.5, step: 0.05, safe: 0...3),
                .number("liveInkLampDrift", "Drift", \.liveInkLampDrift, 0...1, step: 0.05, safe: 0...1),
                .number("liveInkLampVoice", "Energy from voice", \.liveInkLampVoice, 0...1.5, step: 0.05, safe: 0...3),
            ], caption: { _ in "The lamp takes your ink's colours: the ice over dark content and deep blue over light, which darkens what is under it. Breath makes its pool rise and fall over the breath length. Energy brightens and widens it while the pointer moves fast, and while you speak with speech on. Drift moves light slowly round inside it. Breath and drift stop with Reduce Motion." }),
            TweakGroup("Showing", [
                .number("liveInkFieldDelay", "Delay", \.liveInkFieldDelay, 0...1, step: 0.05, unit: "s", safe: 0...60),
                .number("liveInkFieldFade", "Fade", \.liveInkFieldFade, 0...1, step: 0.05, unit: "s", safe: 0...60),
                .number("liveInkFieldOpacity", "Opacity", \.liveInkFieldOpacity, 0...1, step: 0.05, safe: 0...1),
            ], caption: { _ in "The field waits for the delay, or for a press, so the chord on its way to a shortcut does not flash it. It fades in and out, and the ring grows in, over the fade." }),
            TweakGroup("Note before ink", [
                .number("liveInkNoteClearance", "Distance", \.liveInkNoteClearance, 0...160, unit: "pt", safe: 0...1000),
            ], caption: { _ in "With speech on, the note opens on the first word you say, before you draw, this far from the pointer. It moves away when the pointer comes near, and moves to your ink once you draw." }),
        ]),
    ]
}
