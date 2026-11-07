import AppKit
import SwiftUI

extension UITweaks {
    /// The line a card's, a flight's and the annotator's ring is stroked along, `cardBorderWidth` wide:
    /// the frame's own edge, or half that width outside it, so the whole ring lies outside the image.
    func ring(cornerRadius: CGFloat) -> some InsettableShape {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).inset(by: ringOutsideImage ? -cardBorderWidth / 2 : 0)
    }
}

/// The annotator's ring: the thin white line round the frame that a card's border becomes in flight.
/// It is the clip's own border, drawn over the image's edge pixels, or with `ui.ringOutsideImage` a
/// line just outside the clip, in the frame view's layer, with only the backdrop under it. With
/// `ui.ringFadesWhileZooming` it springs down while a zoom changes the frame's size, and back up once
/// the size has held for `restDelay`.
@MainActor
final class FrameRing {
    /// The ring outside the clip, in the frame view's layer and its coordinates.
    let outside = CAShapeLayer()
    private let clip: CALayer
    private var ui = UITweaks()
    /// The fade's share of the ring's opacity: 1 at rest, 0 while a zoom resizes the frame.
    private lazy var fade = Tween(initial: 1) { [weak self] _ in self?.applyColour() }
    private var fadingDown = false
    private var restTimer: Timer?
    /// The frame's size at the last zoom tick.
    private var lastSize: CGSize?

    /// How long the ring takes to go once the frame starts resizing, before the motion scale.
    static let fadeOutSeconds = 0.1
    /// How long it takes to come back, before the motion scale.
    static let fadeInSeconds = 0.25
    /// How long the frame's size holds before the ring comes back: the same pause after which the
    /// editor draws its texts again for a zoom (`EditorView.restDelay`).
    static let restDelay = EditorView.restDelay

    init(clip: CALayer, in frameLayer: CALayer) {
        self.clip = clip
        outside.fillColor = nil
        outside.anchorPoint = .zero
        outside.position = .zero
        // A layer of its own animates every change by default; this one moves only with the frame.
        outside.actions = ["path": NSNull(), "strokeColor": NSNull(), "lineWidth": NSNull(), "hidden": NSNull(),
                           "contentsScale": NSNull()]
        frameLayer.addSublayer(outside)
    }

    /// Where the ring is drawn, how wide and how bright: `ui`'s, on a screen of `scale` device pixels
    /// per point. A fade the tweaks turned off springs back up.
    func apply(_ ui: UITweaks, scale: CGFloat) {
        self.ui = ui
        clip.borderWidth = ui.ringOutsideImage ? 0 : ui.cardBorderWidth
        outside.isHidden = !ui.ringOutsideImage
        outside.lineWidth = ui.cardBorderWidth
        outside.contentsScale = scale
        if !ui.ringFadesWhileZooming { comeBack() }
        applyColour()
    }

    /// The ring outside the clip, for a frame of `size`, in the frame view's coordinates.
    func path(for size: CGSize) -> CGPath {
        ui.ring(cornerRadius: ui.annotationCornerRadius).path(in: CGRect(origin: .zero, size: size)).cgPath
    }

    /// The frame is `size` now.
    func place(size: CGSize) {
        outside.path = path(for: size)
    }

    /// An image opened in a frame of `size`: the ring is at full, with no fade on its way.
    func reset(size: CGSize) {
        restTimer?.invalidate()
        restTimer = nil
        fadingDown = false
        fade.set(1)
        lastSize = size
    }

    /// A zoom tick put the frame at `size`. A size that changed sends the ring down, and the ring comes
    /// back once the size has held for `restDelay`. With motion at 0 a zoom lands at once and the ring
    /// stays up.
    func zoomTicked(size: CGSize) {
        defer { lastSize = size }
        let motion = Settings.shared.motionScale
        guard ui.ringFadesWhileZooming, motion > 0, let lastSize, lastSize != size else { return }
        if !fadingDown {
            fadingDown = true
            fade.animate(to: 0, duration: Self.fadeOutSeconds * motion)
        }
        restTimer?.invalidate()
        let timer = Timer(timeInterval: Self.restDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.comeBack() }
        }
        RunLoop.main.add(timer, forMode: .common)
        restTimer = timer
    }

    /// At full and staying there.
    var isFull: Bool { fade.flight == nil && fade.value >= 0.999 }

    /// The card is about to fly home from this frame, and the flight draws the ring at full: the ring
    /// springs back up over `seconds` and `done` runs once it is there. Ticks from here on are the fit
    /// before the flight, which leave it up.
    func restore(over seconds: Double, then done: @escaping () -> Void) {
        restTimer?.invalidate()
        restTimer = nil
        fadingDown = false
        fade.animate(to: 1, duration: seconds, completion: done)
    }

    private func comeBack() {
        restTimer?.invalidate()
        restTimer = nil
        fadingDown = false
        fade.animate(to: 1, duration: Self.fadeInSeconds * Settings.shared.motionScale)
    }

    private func applyColour() {
        let colour = NSColor.white.withAlphaComponent(ui.cardBorderOpacity * fade.value).cgColor
        clip.borderColor = colour
        outside.strokeColor = colour
    }
}
