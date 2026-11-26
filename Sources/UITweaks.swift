import Foundation

/// Layout, styling, timing, and backdrop parameters. All in points and seconds.
struct UITweaks: Codable, Equatable {
    // Cards
    var cardMaxWidth = 188.0
    var cardMaxHeight = 153.0
    var cardMinSide = 120.0
    var cardSpacing = 10.0
    var panelInset = 19.0            // room for shadows inside the panel
    var screenMargin = 17.0          // distance from the screen corner
    var stackMinScale = 0.5          // how narrow the stack goes to make room for the annotator
    var cardCornerRadius = 16.0
    var cardBorderWidth = 0.5
    var cardBorderOpacity = 0.4
    var cardShadowRadius = 4.0
    var cardShadowOpacity = 0.85
    var cardShadowY = 4.0
    var hoverScale = 1.06
    var pressScale = 0.97
    var hoverDim = 0.35             // darkening of a hovered card behind its buttons
    // Hover buttons and selection
    var buttonSize = 27.0
    var buttonIconSize = 11.0
    var buttonSpacing = 4.0
    var selectionCircleSize = 19.0
    var selectionStripGap = 16.0     // the widest selected card to the control strip beside it
    var autoScrollZone = 44.0        // band at each end of the column where a drag-select scrolls it
    var autoScrollSpeed = 600.0      // points a second at the very edge of that band
    // A two-finger swipe toward the screen's edge closes the corner (StackSwipe)
    var swipeDistance = 70.0         // points toward the edge past which a release closes it
    var swipeSpeed = 500.0           // points a second toward the edge at which a release closes it wherever it is
    var swipeStretch = 10.0          // the farthest a pull away from the edge moves the column, within the panel's room
    // Timings
    var thumbnailSeconds = 5.0       // how long a fresh thumbnail stays
    var markSeconds = 1.7            // how long a card's notice stays; the stored key keeps its older name
    var sendGraceSeconds = 3.0       // how long a Send waits before its session gets it; 0 sends at once
    // The success check on a copied or sent card (CheckCoin; docs/check-lab-2026-10-11.md): a coin
    // of tinted polymer with a glowing check mark inside it, which spins as it appears and settles
    // face on. Lengths are fractions of its diameter.
    var checkColor = "#00d2b2"       // the polymer's tint
    var checkGlowColor = "#8dffc4"   // the mark's glow
    var checkRoughness = 1.0         // 0 a mirror, 1 frosted: how soft every reflection is
    var checkThickness = 0.05
    var checkEdge = 0.2              // the rounding of the coin's rim
    var checkDome = 0.07             // how far each face rises at its centre
    var checkMarkSize = 0.43         // the mark's width
    var checkMarkWeight = 0.25       // its stroke's width
    var checkGlow = 0.54             // 0 to 3: how bright the mark glows
    var checkGlowSpread = 0.02       // how far its glow lights the polymer around it
    var checkClarity = 0.18          // 0 to 1: how much of what is behind the coin shows through it
    var checkLightAngle = -19.0      // where the key light is, degrees clockwise from the top
    var checkLightHeight = 50.0      // its height above the coin's face, in degrees
    var checkLight = 3.0             // 0 to 3: its strength
    var checkStudio = 0.8            // 0 to 1: how much brighter the studio's ceiling is than its floor
    var checkGlint = 2.4             // 0 to 3: the strip light the spin sweeps the coin past
    var checkGlintAngle = -63.0      // where the strip stands, degrees to the right of the viewer
    var checkSpinTurns = 1.0         // how many times the coin turns; 0 for no spin
    var checkSpinDuration = 0.65     // the spring's duration
    var checkSpinBounce = 0.22       // 0 to 1: how far it rocks past face on before it settles
    var checkSpinDelay = 0.05        // after the check appears
    var checkBloom = 0.73            // 0 to 2: the bloom; 0 turns it off
    var checkBloomRadius = 0.49
    var checkBloomThreshold = 0.24   // 0 to 1: how bright a reflection must be to bloom
    var slideInDuration = 0.3
    var slideInCurve = "spring"      // spring, easeOut, easeInOut, linear
    var slideOutDuration = 0.15
    var staggerDelay = 0.07
    var staggerTotalMax = 0.3        // the last card never starts later than this
    var relayoutDuration = 0.25
    var shiftUpDuration = 0.3        // one card joining a visible stack: how long the others take to shift up
    var expandDuration = 0.35
    var introDuration = 0.95         // setup's window flying into the menu bar icon, once per Mac
    var introFunnel = 1.0            // 0 flies that window as one piece, up to 1 pours it into the icon (docs/intro-funnel-2026-09-30.md)
    var introFunnelSmoothing = 1.0   // 0 starts and stops each row of the pour abruptly, 1 eases both, so its sides curve without corners
    var introFunnelCorner = 32.0     // the pour's corners, in points, grown from the window's own as its rows leave
    var introFunnelSmear = 1.0       // 0 to 1: how far a squeezed row is averaged, so squeezed text softens instead of breaking up
    var introFunnelRim = 0.9         // 0 to 1: the light along the pour's bent edges
    var introFunnelFade = 0.1        // the share of each row's travel over which it fades into the icon
    var hoverRevealDuration = 0.15
    var dropDuration = 0.42          // a card dragged out and dropped pouring into the point it was dropped on
    // A flight between a stack slot and the annotator, bowed and swelled by FlightCurve
    var flightArc = 0.15             // how far the path bows, as a fraction of its length
    var flightArcMax = 240.0         // the bow never exceeds this many points
    var flightDepth = 0.07           // how much larger the card is in the middle of the path
    var flightTiming = "quickSpring" // quickSpring or spring: how a flight moves and comes to rest (FlightTiming.Choice)
    var motion = 1.0                 // multiplier on every animation, 0 to 1; Reduce Motion forces 0
    // Backdrop
    var backdropWidth = 160.0
    var backdropTint = 0.65          // darkness at the right edge, 0 to 1
    var backdropTintStart = 0.0      // where the tint begins, 0 = left edge, 1 = right edge
    var backdropBlurRadius = 20.0    // the rightmost band's radius; with one band, the whole strip's
    var backdropBands = 1            // effect views in the blur ramp; one is a single blur that fades in from the strip's left edge
    var backdropRampPower = 0.5      // how the bands' radii grow to the right: 1 = linear, higher keeps the left sharper; no effect with one band
    var backdropFadeIn = 0.25
    var backdropFadeOut = 0.3
    var backdropSlideIn = 0.3           // the strip slides in from the screen edge while it fades
    var backdropSlideOut = 0.2
    var backdropTopFadeHeight = 0.0  // the strip fades in over this many points below the menu bar; 0 leaves it unmasked, with a crisp top edge
    var dimOpacity = 0.3             // screen darkening behind the annotator
    var dimBlurRadius = 17.0
    var dimFade = 0.4                // the spring settles within this
    // Annotator window
    var annotationMinWidth = 770.0
    var annotationMinHeight = 320.0
    var annotationCornerRadius = 16.0
    var annotationToolbarGap = 9.0   // the frame to the toolbar, the toolbar to the screen's bottom, and the frame to the stack
    var annotationScreenInset = 60.0
    // An agent's title above the image (`AgentTitleView`): screen pt, the same size at any zoom
    var agentTitleSize = 17.0
    var agentDescriptionSize = 13.0
    var agentTitleLineGap = 2.0      // between the title and the description under it
    var agentTitleGap = 10.0         // between the block and the image's frame
    var agentTitleMinWidth = 300.0   // the narrowest it wraps at: about 45 characters of the description
    var agentTitleFade = 0.15        // in after the flight lands, out as it flies home
    var zoomEdgeBandPoints = 250.0   // how far from each edge of the picture a zoom holds that edge
    var zoomEdgePull = 0.6           // the part of that band in which the edge is held exactly
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
    var pinPopoverWidth = 280.0      // screen pt
    var pinPopoverInset = 12.0
    var pinPopoverSpacing = 10.0
    var pinListImageSize = 18.0
    var pinListTitleWidth = 320.0
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
