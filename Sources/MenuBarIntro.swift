import AppKit
import SwiftUI

/// The first run's introduction to the menu bar icon, played when setup closes. The setup window
/// flies into the icon, the icon pops, and a popover under it says what the icon is. Without it the
/// icon appears in a busy menu bar with nothing pointing at it.
@MainActor
final class MenuBarIntro {
    /// How long the popover stays when nobody clicks. It says one thing, so a first click anywhere
    /// also closes it.
    static let popoverSeconds: TimeInterval = 8

    private var flight: NSPanel?
    private var popover: NSPopover?
    private var monitors: [Any] = []
    private var timeout: Timer?
    private var finished: (() -> Void)?

    /// Whether a person can see `button`. macOS still gives a status item a window when the bar
    /// has no room for it, under the notch or past the end of a crowded bar, and nothing is drawn.
    static func canSee(_ button: NSStatusBarButton) -> Bool {
        guard let window = button.window, window.isVisible, window.occlusionState.contains(.visible),
              let screen = window.screen, screen.frame.contains(window.frame) else { return false }
        // On a Mac with a notch, the bar's two usable parts are either side of it.
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return true }
        return [left, right].contains { $0.intersection(window.frame).width >= window.frame.width - 1 }
    }

    /// Covers `window` with a picture of itself and, once the picture is on screen, calls `close`
    /// and flies the picture into `button` on a spring that settles in about `duration`. The icon
    /// then pops and the popover says `message`. `finished` runs when the popover has gone. With
    /// `duration` 0, or a window that cannot be drawn into a picture, the window just closes.
    func play(from window: NSWindow, into button: NSStatusBarButton, message: String, duration: Double,
              close: @escaping () -> Void, finished: @escaping () -> Void) {
        self.finished = finished
        guard duration > 0, let picture = Self.picture(of: window), let iconWindow = button.window, let screen = iconWindow.screen else {
            DispatchQueue.main.async {
                close()
                self.showPopover(message, on: button)
            }
            return
        }
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        // Above the menu bar, which the flight ends in.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let host = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        host.wantsLayer = true
        panel.contentView = host

        let start = window.frame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        let end = iconWindow.convertToScreen(button.convert(button.bounds, to: nil)).offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        let layer = Self.cardLayer(picture, frame: start, scale: window.backingScaleFactor, appearance: window.effectiveAppearance)
        host.layer?.addSublayer(layer)
        panel.orderFrontRegardless()
        flight = panel

        // The window closes once its picture has been drawn over it: closed first, the window
        // server takes it down at once and the frames before the picture shows are empty.
        CATransaction.flush()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            close()
            self?.fly(layer, from: start, to: end, duration: duration) { [weak self] in
                self?.flight?.orderOut(nil)
                self?.flight = nil
                Self.pop(button)
                self?.showPopover(message, on: button)
            }
        }
    }

    /// Closes the popover, stops listening for the click that would have, and ends the intro.
    func dismiss() {
        timeout?.invalidate()
        timeout = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        popover?.close()
        popover = nil
        let done = finished
        finished = nil
        done?()
    }

    // MARK: The flight

    /// The window's frame view drawn into a bitmap: its content and title bar, without the shadow
    /// and rounded corners the window server adds.
    private static func picture(of window: NSWindow) -> NSImage? {
        guard let view = window.contentView?.superview,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        return image
    }

    /// The picture on the window's own background, with its corners and shadow. The outer layer
    /// casts the shadow and the inner one clips, since a layer that clips its contents clips its
    /// shadow too.
    private static func cardLayer(_ picture: NSImage, frame: NSRect, scale: CGFloat, appearance: NSAppearance) -> CALayer {
        let radius = windowCornerRadius
        let card = CALayer()
        card.frame = frame
        card.shadowColor = NSColor.black.cgColor
        card.shadowOpacity = 0.35
        card.shadowRadius = 20
        card.shadowOffset = CGSize(width: 0, height: -8)
        card.shadowPath = CGPath(roundedRect: CGRect(origin: .zero, size: frame.size), cornerWidth: radius, cornerHeight: radius, transform: nil)
        let face = CALayer()
        face.frame = card.bounds
        face.cornerRadius = radius
        face.masksToBounds = true
        appearance.performAsCurrentDrawingAppearance { face.backgroundColor = NSColor.windowBackgroundColor.cgColor }
        face.contents = picture
        face.contentsScale = scale
        face.contentsGravity = .resize
        card.addSublayer(face)
        return card
    }

    /// A titled window's corner radius, which AppKit does not publish: 10 pt through macOS 15, and
    /// larger from macOS 26. Only the first frames show it, over the window it matches.
    private static var windowCornerRadius: CGFloat {
        if #available(macOS 26, *) { return 16 }
        return 10
    }

    /// Down a bowed path, as every card flight goes (`FlightCurve`), shrinking at an even rate to
    /// the icon's height and fading over the last stretch, so the icon is what is left. The keyframes
    /// sample a spring with no bounce: one that overshot would carry the picture past the icon.
    private func fly(_ layer: CALayer, from start: NSRect, to end: NSRect, duration: Double, arrived: @escaping () -> Void) {
        let spring = Spring(duration: duration, bounce: 0)
        let total = spring.settlingDuration
        let curve = FlightCurve(ui: Settings.shared.motionUI)
        let targetScale = end.height * 0.8 / max(start.width, start.height)
        // FlightCurve works with y down; layer coordinates have it up.
        let from = CGPoint(x: start.midX, y: -start.midY), to = CGPoint(x: end.midX, y: -end.midY)
        let steps = 90
        var positions: [NSValue] = [], scales: [CGFloat] = [], opacities: [CGFloat] = [], times: [NSNumber] = []
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let s = i == steps ? 1 : CGFloat(spring.value(target: 1.0, time: t * total))
            let point = CGPoint(x: from.x + (to.x - from.x) * s, y: from.y + (to.y - from.y) * s)
            let place = curve.placement(at: point, from: from, to: to)
            positions.append(NSValue(point: CGPoint(x: point.x + place.offset.width, y: -(point.y + place.offset.height))))
            scales.append(pow(targetScale, s) * place.scale)
            opacities.append(1 - min(1, max(0, (s - 0.8) / 0.2)))
            times.append(NSNumber(value: t))
        }
        func track(_ keyPath: String, _ values: [Any]) -> CAKeyframeAnimation {
            let animation = CAKeyframeAnimation(keyPath: keyPath)
            animation.values = values
            animation.keyTimes = times
            return animation
        }
        let group = CAAnimationGroup()
        group.animations = [track("position", positions), track("transform.scale", scales), track("opacity", opacities)]
        group.duration = total
        CATransaction.begin()
        CATransaction.setCompletionBlock(arrived)
        layer.position = positions.last!.pointValue
        layer.setValue(scales.last!, forKeyPath: "transform.scale")
        layer.opacity = 0
        layer.add(group, forKey: "flight")
        CATransaction.commit()
    }

    /// The icon grows and springs back, where the picture has just gone.
    private static func pop(_ button: NSStatusBarButton) {
        button.wantsLayer = true
        guard let layer = button.layer else { return }
        let bounds = button.bounds
        let pop = CASpringAnimation(perceptualDuration: 0.4, bounce: 0.5)
        pop.keyPath = "transform"
        pop.fromValue = CATransform3D.scale(1.35, about: CGPoint(x: bounds.midX, y: bounds.midY))
        pop.toValue = CATransform3DIdentity
        pop.duration = pop.settlingDuration
        layer.add(pop, forKey: "pop")
    }

    // MARK: The popover

    private func showPopover(_ message: String, on button: NSStatusBarButton) {
        let popover = NSPopover()
        // Closed here rather than by AppKit: setup hands the focus back to the person's app as it
        // closes, and a transient popover in an app that is not active would not stay.
        popover.behavior = .applicationDefined
        popover.animates = Settings.shared.motionScale > 0
        popover.contentViewController = NSHostingController(rootView: MenuBarIntroNote(message: message))
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        self.popover = popover
        let close: () -> Void = { [weak self] in MainActor.assumeIsolated { self?.dismiss() } }
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        monitors = [NSEvent.addGlobalMonitorForEvents(matching: clicks) { _ in close() },
                    NSEvent.addLocalMonitorForEvents(matching: clicks) { event in close(); return event }].compactMap { $0 }
        timeout = Timer.scheduledTimer(withTimeInterval: Self.popoverSeconds, repeats: false) { _ in close() }
    }
}

private struct MenuBarIntroNote: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(Identity.name) is in your menu bar").font(.headline)
            Text(message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 250, alignment: .leading)
    }
}

extension CATransform3D {
    /// A scale about `point`. AppKit anchors a view's layer at its corner, so a scale about the
    /// centre has to be written as one.
    static func scale(_ factor: CGFloat, about point: CGPoint) -> CATransform3D {
        let center = CATransform3DMakeTranslation(point.x, point.y, 0)
        return CATransform3DConcat(CATransform3DConcat(CATransform3DInvert(center), CATransform3DMakeScale(factor, factor, 1)), center)
    }
}
