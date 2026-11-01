import AppKit

/// Blurs and darkens the screen behind the annotator. Sits above other apps' windows and below
/// the annotator, the stack, and its backdrop. Mouse-transparent, so a click on it reaches the
/// app behind and counts as a click outside.
@MainActor
final class DimPanel: NSPanel {
    private var generation = 0
    private var fadeCount = 0
    private let blur = TunedEffectView()
    private let tint = NSView()
    /// The fade's spring as Core Animation runs it, so a new target starts from where the fade is
    /// and how fast it is moving.
    private var spring: (from: CGFloat, to: CGFloat, velocity: CGFloat, omega: Double, start: CFTimeInterval)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
        // Just short of opaque: a fully opaque screen-sized window occludes the windows under it,
        // and the window server drops their shadows and controls out of the blur when that happens.
        alphaValue = 0.995

        let root = NSView()
        root.wantsLayer = true
        root.alphaValue = 0
        contentView = root
        blur.autoresizingMask = [.width, .height]
        root.addSubview(blur)
        tint.wantsLayer = true
        tint.autoresizingMask = [.width, .height]
        root.addSubview(tint)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    var stateJSON: [String: Any] { ["visible": isVisible, "alpha": alphaOnScreen] }

    /// How opaque the scrim is on screen now.
    private var alphaOnScreen: CGFloat {
        guard isVisible, let layer = contentView?.layer else { return 0 }
        return alphaValue * CGFloat(layer.presentation()?.opacity ?? layer.opacity)
    }

    func show(on screen: NSScreen) {
        let ui = Settings.shared.motionUI
        generation += 1
        setFrame(screen.frame, display: false)
        let bounds = contentView!.bounds
        blur.frame = bounds
        blur.radius = ui.dimBlurRadius
        blur.isHidden = ui.dimBlurRadius <= 0
        tint.frame = bounds
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(ui.dimOpacity).cgColor
        let wasHidden = !isVisible
        orderFront(nil)
        // The blur and the tint arrive together.
        fade(to: 1, duration: ui.dimFade, fromNothing: wasHidden)
    }

    func hide() {
        generation += 1
        let gen = generation
        fade(to: 0, duration: Settings.shared.motionUI.dimFade) { [weak self] in
            guard let self, self.generation == gen else { return }
            self.spring = nil
            self.orderOut(nil)
        }
    }

    /// Springs the content's opacity to `target` on `Tween`'s curve, run by the render server:
    /// ticks from the main thread setting the window's alpha reached the screen late and in jumps
    /// during exits.
    ///
    /// The layer's own opacity stays where the fade started until the spring ends. Set to the
    /// target in the same transaction as the spring, it showed for one or two frames before the
    /// spring in recordings of exits in a VM, and the whole scrim vanished
    /// (`docs/scrim-fade-2026-10-31.md`).
    private func fade(to target: CGFloat, duration: Double, fromNothing: Bool = false, completion: (() -> Void)? = nil) {
        guard let root = contentView, let layer = root.layer else { return }
        let now = CACurrentMediaTime()
        // A panel that was off screen starts from nothing: its presentation layer can still hold
        // the opacity it had before it first went up.
        let (value, velocity) = fromNothing ? (0, 0)
            : spring.map { Tween.spring(value: $0.from, velocity: $0.velocity, target: $0.to, omega: $0.omega, dt: now - $0.start) }
            ?? (CGFloat(layer.presentation()?.opacity ?? layer.opacity), 0)
        let animates = duration > 0 && abs(target - value) > 0.001
        fadeCount += 1
        let thisFade = fadeCount
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAnimation(forKey: "fade")
        root.alphaValue = animates ? value : target
        if animates {
            let omega = Tween.omega(settling: duration)
            let animation = CASpringAnimation(keyPath: "opacity")
            animation.mass = 1
            animation.stiffness = omega * omega
            animation.damping = 2 * omega
            animation.initialVelocity = velocity / (target - value)
            animation.fromValue = Float(value)
            animation.toValue = Float(target)
            animation.duration = animation.settlingDuration
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            CATransaction.setCompletionBlock { [weak self] in
                if let self, self.fadeCount == thisFade {
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    root.alphaValue = target
                    layer.removeAnimation(forKey: "fade")
                    CATransaction.commit()
                }
                completion?()
            }
            layer.add(animation, forKey: "fade")
            spring = (value, target, velocity, omega, now)
        } else {
            spring = nil
        }
        CATransaction.commit()
        if !animates { completion?() }
    }
}
