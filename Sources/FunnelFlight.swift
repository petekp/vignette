import SwiftUI

/// When the funnel's flight began on the media clock, set once the window has closed. The view
/// reads it every frame, so it needs no publishing.
@MainActor
final class FunnelClock {
    var begin: CFTimeInterval?
}

/// The picture pouring into the menu bar icon (docs/intro-funnel-2026-09-30.md). The bitmap stays
/// where the window was, and `funnel` in IntroFunnel.metal bends it, row by row, into `icon`. The
/// shadow is SwiftUI's, cast by the bent shape, and goes as the rows near the bar. The funnel's
/// numbers are read from the settings on every frame, so the Intro Lab's sliders show at once.
struct FunnelFlight: View {
    let image: CGImage
    /// The bitmap's place and the icon's, in the view's points with y down.
    let card: CGRect, icon: CGRect
    /// The picture's own corner radius in the view's points, which the pour's corners grow from.
    let cardRadius: CGFloat
    /// Points in this view per point on screen: 1 on screen, less in the Intro Lab's preview.
    var zoom: CGFloat = 1
    /// How far through the flight, 0 to 1, asked on every frame.
    let progress: @MainActor () -> Double
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        TimelineView(.animation) { _ in
            let t = progress()
            let ui = Settings.shared.data.ui
            let shadow = 1 - Self.ramp(t, 0.3, 0.7)
            GeometryReader { space in
                Image(decorative: image, scale: 1)
                    .resizable()
                    .frame(width: card.width, height: card.height)
                    .offset(x: card.minX, y: card.minY)
                    .frame(width: space.size.width, height: space.size.height, alignment: .topLeading)
                    .layerEffect(ShaderLibrary.funnel(.float4(card.minX, card.minY, card.width, card.height),
                                                      .float4(icon.minX, icon.minY, icon.width, icon.height),
                                                      .float(t), .float(ui.introFunnel), .float(ui.introFunnelSmoothing),
                                                      .float(ui.introFunnelCorner * zoom), .float(cardRadius),
                                                      .float(ui.introFunnelSmear), .float(ui.introFunnelRim),
                                                      .float(ui.introFunnelFade),
                                                      // The window's shadow as measured on macOS 15: how much it
                                                      // darkens what is behind it at 2, 10 and 22 pt beside the
                                                      // window (0.31, 0.20, 0.09) and just below it (0.54).
                                                      .float3(0.67 * shadow, 20 * zoom, 15 * zoom),
                                                      .float(1 / displayScale)),
                                 maxSampleOffset: space.size)
            }
        }
        .ignoresSafeArea()
    }

    private static func ramp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        let t = min(1, max(0, (value - low) / (high - low)))
        return t * t * (3 - 2 * t)
    }
}
