import Foundation

extension TweakCatalog {
    static let labSections: [TweakSection] = [
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
            TweakGroup("Send badge", [
                .number("sendBadgeStartScale", "Start size", \.sendBadgeStartScale, 0...1, step: 0.05, safe: 0...1),
                .number("sendBadgeDelay", "Delay", \.sendBadgeDelay, 0...1, step: 0.01, unit: "s", safe: 0...10),
            ], caption: { _ in "The badge at the corner of a send's logo shows nothing until the send has answered, then grows in whole, from Start size, a fraction of its own, never sooner than Delay after the logo appears." }),
        ]),
    ]
}
