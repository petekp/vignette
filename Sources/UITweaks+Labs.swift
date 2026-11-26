import Foundation

extension UITweaks {
    /// The success check's and the menu bar intro's tweaks (`TweakCatalog+Labs.swift`).
    struct Labs: Decodable, Equatable {
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
        // The badge at the corner of a send's logo (SendOverlay), which grows in once the send has answered
        var sendBadgeStartScale = 0.25   // the size it grows from, a fraction of its own
        var sendBadgeDelay = 0.12        // seconds after the logo appears before it may grow in
        var introDuration = 0.95         // setup's window flying into the menu bar icon, once per Mac
        var introFunnel = 1.0            // 0 flies that window as one piece, up to 1 pours it into the icon (docs/intro-funnel-2026-09-30.md)
        var introFunnelSmoothing = 1.0   // 0 starts and stops each row of the pour abruptly, 1 eases both, so its sides curve without corners
        var introFunnelCorner = 32.0     // the pour's corners, in points, grown from the window's own as its rows leave
        var introFunnelSmear = 1.0       // 0 to 1: how far a squeezed row is averaged, so squeezed text softens instead of breaking up
        var introFunnelRim = 0.9         // 0 to 1: the light along the pour's bent edges
        var introFunnelFade = 0.1        // the share of each row's travel over which it fades into the icon
    }
}
