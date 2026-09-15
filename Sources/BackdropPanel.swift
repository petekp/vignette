import AppKit
import QuartzCore

/// A progressively blurred strip along the right edge of the screen behind the recent stack.
/// The window sits below the menu bar and the Dock so both draw over it, and covers the full screen
/// height. Mouse-transparent.
///
/// macOS has no public variable blur, and the private variableBlur filter ignores its mask when the
/// backdrop renders in the window server (tried; it blurs uniformly). So the ramp is built from
/// several NSVisualEffectViews, each masked to a feathered vertical band and tuned to a larger blur
/// radius than the one to its left. Masks are public API; the radius is set through the backdrop
/// layer's existing gaussianBlur filter by key path.
final class BackdropPanel: NSPanel {
    private let tint = NSView()
    private let tintLayer = CAGradientLayer()
    private var bands: [TunedEffectView] = []
    private lazy var alpha = Tween(initial: 0) { [weak self] v in self?.alphaValue = v }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        // Just under the Dock (20) so the Dock and menu bar (24) paint over the strip.
        level = NSWindow.Level(rawValue: 19)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
        alphaValue = 0

        let root = NSView()
        root.wantsLayer = true
        contentView = root
        tint.wantsLayer = true
        tint.layer = tintLayer
        tint.autoresizingMask = [.width, .height]
        tintLayer.startPoint = CGPoint(x: 0, y: 0.5)
        tintLayer.endPoint = CGPoint(x: 1, y: 0.5)
        root.addSubview(tint)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    var stateDescription: String {
        "visible=\(isVisible) alpha=\(alphaValue) frame=\(frame) bands=\(bands.map { $0.radius })"
    }

    func show(on screen: NSScreen, below panel: NSPanel) {
        refresh(on: screen)
        orderFront(nil)
        alpha.animate(to: 1, duration: Settings.shared.data.ui.backdropFadeIn)
    }

    /// Rebuilds bands, masks, radii, and tint from the current settings without animating.
    func refresh(on screen: NSScreen) {
        let ui = Settings.shared.data.ui
        let full = screen.frame
        let width = CGFloat(ui.backdropWidth)
        setFrame(NSRect(x: full.maxX - width, y: full.minY, width: width, height: full.height), display: false)
        let bounds = contentView!.bounds
        let n = max(1, ui.backdropBands)
        while bands.count > n { bands.removeLast().removeFromSuperview() }
        while bands.count < n {
            let band = TunedEffectView()
            band.autoresizingMask = [.width, .height]
            contentView!.addSubview(band, positioned: .below, relativeTo: tint)
            bands.append(band)
        }
        for (i, band) in bands.enumerated() {
            band.frame = bounds
            // Radii grow with a power curve; higher power keeps the left edge sharper.
            let t = CGFloat(i + 1) / CGFloat(n)
            band.radius = CGFloat(ui.backdropBlurRadius) * pow(t, CGFloat(ui.backdropRampPower))
            band.maskImage = BackdropPanel.bandMask(width: width, band: i, of: n)
        }
        tint.frame = bounds
        tintLayer.colors = [NSColor.black.withAlphaComponent(0).cgColor,
                            NSColor.black.withAlphaComponent(0).cgColor,
                            NSColor.black.withAlphaComponent(CGFloat(ui.backdropTint)).cgColor]
        tintLayer.locations = [0, NSNumber(value: min(0.999, ui.backdropTintStart)), 1]
    }

    func hide() {
        alpha.animate(to: 0, duration: Settings.shared.data.ui.backdropFadeOut, curve: "easeInOut") { [weak self] in
            if self?.alphaValue == 0 { self?.orderOut(nil) }
        }
    }

    /// Alpha mask for one band: fades in over the previous band and out over the next, so adjacent
    /// bands cross-fade. The first band fades in from nothing at the strip's left edge; the last
    /// stays opaque to the screen edge.
    private static func bandMask(width: CGFloat, band i: Int, of n: Int) -> NSImage {
        let step = width / CGFloat(n)
        let start = step * CGFloat(i)
        let end = step * CGFloat(i + 1)
        let image = NSImage(size: NSSize(width: width, height: 1), flipped: false) { rect in
            var stops: [(NSColor, CGFloat)] = []
            let clear = NSColor.black.withAlphaComponent(0)
            let solid = NSColor.black
            if i == 0 {
                stops.append((clear, 0))            // no hard edge where the strip begins
                stops.append((solid, step / width))
            } else {
                stops.append((clear, (start - step) / width))
                stops.append((solid, start / width))
            }
            if i == n - 1 {
                stops.append((solid, 1))
            } else {
                stops.append((solid, end / width))
                stops.append((clear, min(1, (end + step) / width)))
            }
            let gradient = NSGradient(colors: stops.map(\.0), atLocations: stops.map(\.1), colorSpace: .deviceRGB)!
            gradient.draw(in: rect, angle: 0)
            return true
        }
        image.resizingMode = .stretch
        return image
    }
}

/// NSVisualEffectView with a chosen blur radius and no material tint. The radius lives on the
/// private backdrop layer's gaussianBlur filter; AppKit rebuilds those layers on some updates, so
/// the tweak is reapplied in every hook where that happens.
final class TunedEffectView: NSVisualEffectView {
    var radius: CGFloat = 20 { didSet { retune() } }

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() { super.layout(); retune() }
    override func updateLayer() { super.updateLayer(); retune() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); retune() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); retune() }

    private func retune() {
        guard let root = layer else { return }
        func walk(_ l: CALayer) {
            guard let children = l.sublayers else { return }
            let backdrops = children.filter { String(describing: type(of: $0)).contains("Backdrop") }
            if backdrops.isEmpty { children.forEach(walk); return }
            for child in children {
                if backdrops.contains(where: { $0 === child }) {
                    child.setValue(radius, forKeyPath: "filters.gaussianBlur.inputRadius")
                } else {
                    child.isHidden = true   // material tint layers; the panel draws its own tint
                }
            }
        }
        walk(root)
    }
}
