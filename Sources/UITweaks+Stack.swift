import Foundation

extension UITweaks {
    /// The corner's tweaks: the cards, the column, its timings, the flights, the backdrop and the dim
    /// behind the annotator (`TweakCatalog+Stack.swift`).
    struct Stack: Decodable, Equatable {
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
        var shownDim = 0.45             // darkening of the corner's other cards while cards an agent showed are up
        var shownDimFade = 0.35         // that darkening's spring, in and out
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
        var unreadableFolderSeconds = 5.0 // how long the screenshots folder fails to read before the menu says so
        var slideInDuration = 0.3
        var slideInCurve = "spring"      // spring, easeOut, easeInOut, linear
        var slideOutDuration = 0.15
        var staggerDelay = 0.07
        var staggerTotalMax = 0.3        // the last card never starts later than this
        var relayoutDuration = 0.25
        var shiftUpDuration = 0.3        // one card joining a visible stack: how long the others take to shift up
        var expandDuration = 0.35
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
    }
}
