import AppKit

/// Darkens the screen behind the annotator. Sits above other apps' windows and below the
/// annotator, the stack, and its backdrop. Mouse-transparent, so a click on it reaches the app
/// behind and counts as a click outside.
@MainActor
final class DimPanel: NSPanel {
    private lazy var alpha = Tween(initial: 0) { [weak self] v in self?.alphaValue = v }
    private var generation = 0

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .black
        hasShadow = false
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
        alphaValue = 0
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(on screen: NSScreen) {
        let ui = Settings.shared.motionUI
        generation += 1
        setFrame(screen.frame, display: false)
        orderFront(nil)
        alpha.animate(to: ui.dimOpacity, duration: ui.dimFade)
    }

    func hide() {
        generation += 1
        let gen = generation
        alpha.animate(to: 0, duration: Settings.shared.motionUI.dimFade, curve: "easeInOut") { [weak self] in
            guard let self, self.generation == gen else { return }
            self.orderOut(nil)
        }
    }
}
