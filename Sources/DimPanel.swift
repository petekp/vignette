import AppKit

/// Blurs and darkens the screen behind the annotator. Sits above other apps' windows and below
/// the annotator, the stack, and its backdrop. Mouse-transparent, so a click on it reaches the
/// app behind and counts as a click outside.
@MainActor
final class DimPanel: NSPanel {
    private lazy var alpha = Tween(initial: 0) { [weak self] v in self?.alphaValue = v }
    private var generation = 0
    private let blur = TunedEffectView()
    private let tint = NSView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
        alphaValue = 0

        let root = NSView()
        root.wantsLayer = true
        contentView = root
        blur.autoresizingMask = [.width, .height]
        root.addSubview(blur)
        tint.wantsLayer = true
        tint.autoresizingMask = [.width, .height]
        root.addSubview(tint)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

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
        orderFront(nil)
        // The whole panel fades: the blur and the tint arrive together.
        alpha.animate(to: 1, duration: ui.dimFade, curve: "spring")
    }

    func hide() {
        generation += 1
        let gen = generation
        alpha.animate(to: 0, duration: Settings.shared.motionUI.dimFade, curve: "spring") { [weak self] in
            guard let self, self.generation == gen else { return }
            self.orderOut(nil)
        }
    }
}
