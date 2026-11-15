import AppKit
import QuartzCore

/// A progressively blurred strip along the right edge of the screen behind the recent stack.
/// It runs from the screen's bottom edge to the menu bar's bottom edge, the top the stack's column
/// uses, so nothing behind the menu bar is blurred. A `backdropTopFadeHeight` above 0 fades it in over
/// that many points below its top; the default, 0, leaves a crisp top edge. Mouse-transparent.
///
/// macOS has no public variable blur, and the private variableBlur filter ignores its mask when the
/// backdrop renders in the window server (tried; it blurs uniformly). So the ramp is built from
/// `backdropBands` NSVisualEffectViews, each masked to a feathered vertical band and tuned to a larger
/// blur radius than the one to its left. The default is one band, whose mask fades a single blur in
/// from the strip's left edge. Masks are public API; the radius is set through the backdrop
/// layer's existing gaussianBlur filter by key path.
@MainActor
final class BackdropPanel: NSPanel {
    private let tint = NSView()
    private let tintLayer = CAGradientLayer()
    /// Masks the bands and the tint together, so the strip fades in below the menu bar. Set on the
    /// content layer only while the fade height is above 0, so a fade of 0 leaves the strip unmasked.
    private let topFade = CAGradientLayer()
    private var bands: [TunedEffectView] = []
    private lazy var alpha = Tween(initial: 0) { [weak self] v in self?.alphaValue = v }
    /// 0 is parked past the screen edge, 1 is in place. Separate from the fade so each has its own timing.
    private lazy var slide = Tween(initial: 1) { [weak self] v in self?.applySlide(v) }
    /// Where the strip sits when fully in.
    private var strip: NSRect = .zero

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        // Just under the Dock (20) so the Dock paints over the strip, and so does a hidden menu bar
        // (24) that slides down over a strip reaching the top of the screen.
        level = NSWindow.Level(rawValue: 19)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
        alphaValue = 0

        let root = NSView()
        root.wantsLayer = true
        contentView = root
        // Layer space has its origin at the bottom left here, so y 1 is the strip's top.
        topFade.startPoint = CGPoint(x: 0.5, y: 1)
        topFade.endPoint = CGPoint(x: 0.5, y: 0)
        topFade.colors = [NSColor.black.withAlphaComponent(0).cgColor, NSColor.black.cgColor]
        tint.wantsLayer = true
        tint.layer = tintLayer
        tint.autoresizingMask = [.width, .height]
        tintLayer.startPoint = CGPoint(x: 0, y: 0.5)
        tintLayer.endPoint = CGPoint(x: 1, y: 0.5)
        root.addSubview(tint)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    var stateJSON: [String: Any] {
        ["visible": isVisible, "alpha": alphaValue, "frame": StateReport.topLeft(frame, primaryHeight: StateReport.primaryHeight), "bands": bands.map { $0.radius }]
    }

    func show(on screen: NSScreen, below panel: NSPanel) {
        let ui = Settings.shared.motionUI
        refresh(on: screen)
        if !isVisible { slide.set(0) }
        orderFront(nil)
        alpha.animate(to: 1, duration: ui.backdropFadeIn)
        slide.animate(to: 1, duration: ui.backdropSlideIn)
    }

    private func applySlide(_ v: CGFloat) {
        guard strip.width > 0 else { return }
        setFrameOrigin(NSPoint(x: strip.minX + strip.width * (1 - v), y: strip.minY))
    }

    /// Rebuilds bands, masks, radii, and tint from the current settings without animating.
    func refresh(on screen: NSScreen) {
        let ui = Settings.shared.data.ui
        let full = screen.frame
        let width = CGFloat(ui.backdropWidth)
        // The visible frame's top is the menu bar's bottom edge, notch row included, or the
        // screen's top when the menu bar hides.
        let top = min(full.maxY, screen.visibleFrame.maxY)
        strip = NSRect(x: full.maxX - width, y: full.minY, width: width, height: top - full.minY)
        let fade = min(CGFloat(max(0, ui.backdropTopFadeHeight)), strip.height)
        setFrame(strip, display: false)
        applySlide(slide.value)
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
            let key = "\(width)/\(i)/\(n)"
            if band.maskKey != key {
                band.maskKey = key
                band.maskImage = BackdropPanel.bandMask(width: width, band: i, of: n)
            }
        }
        tint.frame = bounds
        tintLayer.colors = [NSColor.black.withAlphaComponent(0).cgColor,
                            NSColor.black.withAlphaComponent(0).cgColor,
                            NSColor.black.withAlphaComponent(CGFloat(ui.backdropTint)).cgColor]
        tintLayer.locations = [0, NSNumber(value: min(0.999, ui.backdropTintStart)), 1]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        topFade.frame = bounds
        topFade.locations = [0, NSNumber(value: Double(fade / max(1, bounds.height)))]
        contentView!.layer?.mask = fade > 0 ? topFade : nil
        CATransaction.commit()
    }

    func hide() {
        let ui = Settings.shared.motionUI
        slide.animate(to: 0, duration: ui.backdropSlideOut)
        alpha.animate(to: 0, duration: ui.backdropFadeOut) { [weak self] in
            if self?.alphaValue == 0 { self?.orderOut(nil) }
        }
    }

    /// Alpha mask for one band: fades in over the previous band and out over the next, so adjacent
    /// bands cross-fade. The first band fades in from nothing at the strip's left edge; the last
    /// stays opaque to the screen edge.
    /// One pixel tall and stretched: a drawing-handler image is shaded at the strip's full height on
    /// every show (measured: 12 ms per open); a bitmap is a blit. The top fade is the panel's own mask,
    /// not cap insets here: NSVisualEffectView measures a mask's `capInsets.top` from the bottom and
    /// stretches the wrong row. Cached for the current width and band count only, since they rarely
    /// change, and a slider dragged across them would keep every step's.
    private static func bandMask(width: CGFloat, band i: Int, of n: Int) -> NSImage {
        let size = "\(width)/\(n)"
        if size != maskSize { masks = [:]; maskSize = size }
        if let hit = masks[i] { return hit }
        let step = width / CGFloat(n)
        let start = step * CGFloat(i)
        let end = step * CGFloat(i + 1)
        let pixels = max(1, Int((width * 2).rounded()))
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: width, height: 1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        do {
            let rect = NSRect(x: 0, y: 0, width: width, height: 1)
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
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        image.resizingMode = .stretch
        masks[i] = image
        return image
    }

    private static var masks: [Int: NSImage] = [:]
    private static var maskSize = ""
}

/// NSVisualEffectView with a chosen blur radius and no material tint. The radius lives on the
/// private backdrop layer's gaussianBlur filter; AppKit rebuilds those layers on some updates, so
/// the tweak is reapplied in every hook where that happens.
@MainActor
final class TunedEffectView: NSVisualEffectView {
    var radius: CGFloat = 20 { didSet { retune() } }
    var maskKey = ""   // which band mask is set, so `refresh` skips an unchanged one

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
