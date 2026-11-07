import Foundation

extension UITweaks {
    /// The same tweaks with every animation scaled: the durations, and how far a flight bows and
    /// swells. Dwell times (`thumbnailSeconds`, `markSeconds`, `sendGraceSeconds`) are not motion and
    /// stay as they are, and `flightArcMax` is a limit on the bow rather than an amount of it.
    func scaledForMotion(_ scale: Double) -> UITweaks {
        var u = self
        u.slideInDuration *= scale; u.slideOutDuration *= scale
        u.staggerDelay *= scale; u.staggerTotalMax *= scale
        u.relayoutDuration *= scale; u.shiftUpDuration *= scale; u.expandDuration *= scale; u.hoverRevealDuration *= scale
        u.dropDuration *= scale
        u.introDuration *= scale
        u.checkSpinDuration *= scale; u.checkSpinDelay *= scale
        u.noteSettleDuration *= scale
        u.agentTitleFade *= scale
        u.liveInkFieldFade *= scale; u.liveInkDrawOn *= scale
        u.liveInkFieldFollow *= scale
        u.liveInkHideFade *= scale; u.liveInkShowFade *= scale
        u.inkSettle *= scale; u.inkSettleStagger *= scale; u.lightGlintFade *= scale
        // The lamp's breath and drift are motion, so they go with it.
        u.liveInkLampBreath *= scale; u.liveInkLampDrift *= scale
        u.backdropFadeIn *= scale; u.backdropFadeOut *= scale; u.dimFade *= scale
        u.backdropSlideIn *= scale; u.backdropSlideOut *= scale
        u.flightArc *= scale; u.flightDepth *= scale
        return u
    }
}
