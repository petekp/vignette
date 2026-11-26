import Foundation

extension UITweaks {
    /// Live ink's tweaks: the pointer field, the answers, the thinking light, the person's ink and an
    /// agent's marks on the live screen (`TweakCatalog+LiveInk.swift`).
    struct LiveInk: Decodable, Equatable {
        // The pointer field, which says the screen is taking ink while the chord is held: the ring round
        // the pointer.
        var liveInkFieldDelay = 0.25     // how long the chord is held before it shows, unless a press shows it sooner
        var liveInkFieldFade = 0.5       // how long it fades in and out, and the ring grows in
        var liveInkFieldOpacity = 1.0
        // The ring: a soft pool of light in the ink colour round the pointer, clear in the middle so what
        // the pointer is on still reads.
        var liveInkFieldSize = 23.0      // the ring's radius in points; 0 turns it off
        var liveInkFieldGlow = 1.0       // 0 to 1: the ink-coloured light on and round the ring
        var liveInkFieldFollow = 0.04    // how long the ring takes to catch up with the pointer; 0 holds it on it
        var liveInkFieldStretch = 0.6    // 0 to 1: how far the ring stretches along the way the pointer moves
        var liveInkFieldClear = 0.4      // how much of the lamp's middle is left alone
        var liveInkFieldSpread = 1.7     // Lamp: how far its light reaches, in ring sizes
        // Lamp's life: how its pool of light moves on its own
        var liveInkLampBreath = 0.15     // 0 to 0.5: how far its size and light rise and fall
        var liveInkLampBreathSeconds = 3.5 // how long one breath takes
        var liveInkLampEnergy = 0.6      // 0 to 1.5: how much brighter and wider it grows while the pointer moves fast
        var liveInkLampDrift = 0.3       // 0 to 1: light drifting slowly round inside the pool
        var liveInkLampVoice = 0.8       // 0 to 1.5: how much brighter and wider it grows with the voice while live ink listens
        // The note that opens on the first word heard, before any ink: how far it keeps from the pointer,
        // in points from the middle of the pointer's ring to the note's arrow
        var liveInkNoteClearance = 40.0
        // Live ink's answers
        var liveInkDrawOn = 0.5          // how long an answer's mark takes to draw itself on
        var liveInkHideFade = 0.12       // a mark fading out as its window minimises or shrinks past it, or as it is set aside
        var liveInkShowFade = 0.22       // a mark fading back in once its window is back or has grown over it
        var liveInkTextSize = 15.0       // an answer's note, in points of the screen
        var liveInkTextWidth = 320.0     // the widest an answer's note wraps at, in points
        // The thinking light while an ask waits for its answer (`LiveMarksLayer.think`, `RimLight`)
        var thinkingBrightness = 0.45     // 0 to 1: the band of light that runs along the ink
        var thinkingLength = 110.0        // the band's length along the line, in points
        var thinkingWidth = 1.1           // the band's width at its middle, as a share of the line's
        var thinkingGlow = 12.0           // how far the band's glow reaches round the line, in points
        var thinkingRimBrightness = 0.45  // 0 to 1: the light that runs round a popover's rim
        // The person's live ink as opal gel (InkGel; docs/live-ink-gel-2026-10-12.md): a rod of milky
        // material under a thin film whose pale colours follow the line, with a glow under it.
        var inkGelLight = "#0085ff"      // the ice's hue, over dark content
        var inkGelDeep = "#051a91"       // the deep blue, over light content
        var inkGelWidth = 8.0            // the line's width, in points of the screen
        var inkGelCore = 0.0             // 0 to 1: how white the ice is along its middle
        var inkGelSheen = 2.0            // 0 to 2: the highlight
        var inkGelGlow = 0.0             // 0 to 2: the glow round the line
        var inkGelBloom = 0.2            // 0 to 2: more glow where the line faces the light
        var inkGelGlowRadius = 13.0      // how far the glow reaches, in points
        var inkGelShadow = 0.0           // 0 to 1: the shadow under the line, which shows on light windows
        var inkGelMotion = 2.05          // 0 to 3: how fast the light and the shimmer drift; 0 holds them still
        var inkGelShimmer = 3.0          // 0 to 3: a slow ripple of light along the line
        var inkGelWander = 1.5           // how far the light wanders, in radians
        var inkGelHighlightSharpness = 79.0  // the highlight's specular power: higher is a smaller, harder spot
        var inkGelGlowFalloff = 5.1      // how fast the glow fades past the line's core
        var inkGelDeepEdge = 1.0         // the deep blue at the line's edge, as a share of it at the middle
        var inkGelEdgeOpacity = 0.28     // the ice's opacity at the line's edge; its middle is opaque
        var inkGelSheathDepth = 2.25     // how far the deep blue sheath reaches in over light content
        var inkGelShimmerLength = 400.0  // the shimmer's wavelength along the line, in points
        var inkGelShimmerSpeed = 0.9     // how fast the shimmer runs along the line
        var inkGelLightAngle = 33.0      // where the light comes from, in degrees, 0 to the right
        var inkGelLightHeight = 1.05     // how high the light is over the line: lower lights it from the side
        var inkGelPointerLight = 1.0     // 0 to 1: how much of the light comes from the pointer rather than the light angle
        var inkGelPointerHeight = 120.0  // how high over the screen the pointer's light hangs, in points
        // The person's live ink as the hand draws it (`InkHand.Feel`). Widths are multiples of `inkGelWidth`.
        var inkHandWidth = 0.9           // the width where the hand moves at its average speed
        var inkHandSpeed = 0.42          // how much each multiple of the average speed narrows it
        var inkHandThinnest = 0.72
        var inkHandWidest = 1.4
        var inkHandSpeedMemory = 48.0    // pointer events the average speed is taken over
        var inkHandWidthSmoothing = 6.0  // points either side that a width is averaged with
        var inkHandStartTaper = 14.0     // points the line narrows over where the pen lands
        var inkHandStartWidth = 0.38     // its width where the pen lands, a share of the full width
        var inkHandEndTaper = 26.0       // points a loop narrows over where the pen lifts
        var inkHandEndWidth = 0.3
        var inkLengthDiagonals = 2.0     // diagonals of its screen of line the pen keeps; past it, the line's start recedes
        var inkSettle = 0.3              // seconds of the spring a drawn loop or arrow settles onto its shape on
        var inkSettleBounce = 0.25       // 0 to 0.9: how far it swings past its shape before it is still
        var inkSettleStagger = 0.08      // seconds after the line's end lets go that its start does
        // An agent's marks on the live screen, drawn as light (`LightMarkLayer`)
        var lightGlow = 3.0              // the tight glow's reach, in points, over a dark window
        var lightGlowWide = 9.0          // the wide glow's
        var lightGlowStrength = 1.0      // multiplies the glows once the mark has settled
        var lightGlowDrawing = 1.0       // multiplies the glows while the mark draws itself on
        var lightCoreWhite = 0.75        // how white the core's middle is over a dark window
        var lightGlintLength = 26.0      // points of the glint that runs at the head as a mark draws on
        var lightGlintFade = 0.15        // seconds the glint takes to go once the mark is drawn
        var lightOverLight = 1.0         // multiplies the glows over a light window, where they tint it
    }
}
