import AppKit
import ScreenCaptureKit
import SwiftUI

/// The first run's introduction to the menu bar icon, played when setup closes. The setup window
/// flies into the icon and becomes a highlight behind it, a light crosses the highlight, the icon
/// pops, and a popover under it says what the icon is. Without it the icon appears in a busy menu
/// bar with nothing pointing at it.
@MainActor
final class MenuBarIntro {
    /// How long the popover stays. It also goes when the shortcut fires or the icon is clicked.
    static let popoverSeconds: TimeInterval = 5

    /// What the popover under the icon says after its title: how to use the shortcut, drawn as a
    /// key, or a sentence.
    enum Note {
        case shortcut(HotKeySpec)
        case text(String)
        /// A lead line and the things it introduces, one per line.
        case list(String, [String])
    }

    /// The menu bar's highlight behind a status item, which the glow copies: the item's whole
    /// frame, with corners measured at about 5 pt on macOS 15.
    private static let highlightRadius: CGFloat = 5

    private var flight: NSPanel?
    private var popover: NSPopover?
    private var monitors: [Any] = []
    private var timeout: Timer?
    private var shortcutFired: NSObjectProtocol?
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
    /// and flies the picture into `button` over `duration`. `finished` runs when the popover has
    /// gone. With `duration` 0, or a window that cannot be drawn into a picture, the window just
    /// closes and the popover opens.
    func play(from window: NSWindow, into button: NSStatusBarButton, note: Note, duration: Double,
              close: @escaping () -> Void, finished: @escaping () -> Void) {
        // A second intro (the Intro Lab's Play on Screen) ends the first, its popover included: a
        // popover left open lost its timer and its monitors, and nothing closed it.
        if popover != nil || finished != nil { dismiss() }
        flight?.orderOut(nil)
        flight = nil
        self.finished = finished
        guard duration > 0 else {
            DispatchQueue.main.async {
                close()
                self.showPopover(note, on: button)
            }
            return
        }
        Self.picture(of: window) { [weak self] picture in
            guard let self else { return }
            guard let picture, let iconWindow = button.window, let screen = iconWindow.screen else {
                close()
                return self.showPopover(note, on: button)
            }
            self.fly(picture, of: window, into: button, iconWindow: iconWindow, screen: screen, note: note,
                     duration: duration, close: close)
        }
    }

    private func fly(_ picture: NSImage, of window: NSWindow, into button: NSStatusBarButton, iconWindow: NSWindow,
                     screen: NSScreen, note: Note, duration: Double, close: @escaping () -> Void) {
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        // Closing setup hands the focus back to the app before Vignette, and a panel that hid then
        // would take the picture with it.
        panel.hidesOnDeactivate = false
        // Above the menu bar, which the flight ends in.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let host = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        host.wantsLayer = true
        panel.contentView = host

        let start = window.frame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        let end = iconWindow.convertToScreen(button.convert(button.bounds, to: nil)).offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        let layer = Self.cardLayer(picture, frame: start, scale: window.backingScaleFactor, appearance: window.effectiveAppearance)
        // Above 0 the picture pours into the icon (`FunnelFlight`), drawn by SwiftUI from one
        // bitmap of the card; at 0 the card's layers fly as one piece.
        let strength = Settings.shared.motionUI.introFunnel
        let clock = FunnelClock()
        let flat = strength > 0 ? Self.flattened(layer, scale: window.backingScaleFactor, space: screen.colorSpace?.cgColorSpace) : nil
        if let flat {
            // SwiftUI's y runs down from the panel's top edge.
            let down = { (rect: NSRect) in NSRect(x: rect.minX, y: screen.frame.height - rect.maxY, width: rect.width, height: rect.height) }
            let view = NSHostingView(rootView: FunnelFlight(image: flat.image,
                                                            card: down(start.insetBy(dx: -flat.margin, dy: -flat.margin)),
                                                            icon: down(end), cardRadius: Self.windowCornerRadius + flat.margin,
                                                            progress: { clock.begin.map { min(1, max(0, (CACurrentMediaTime() - $0) / duration)) } ?? 0 }))
            view.frame = host.bounds
            host.addSubview(view)
        } else {
            host.layer?.addSublayer(layer)
        }
        panel.orderFrontRegardless()
        flight = panel

        // The window closes once its picture has been drawn over it: closed first, the window
        // server takes it down at once and the frames before the picture shows are empty. While
        // both are up, only the picture casts a shadow: the two together drew one twice as dark
        // for three frames.
        CATransaction.flush()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { window.hasShadow = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            close()
            let path = FlightPath(from: start, to: end, duration: duration, curve: FlightCurve(ui: Settings.shared.motionUI))
            let begin = CACurrentMediaTime()
            let motion = Settings.shared.motionScale
            let arrived: () -> Void = {
                self?.flight?.orderOut(nil)
                self?.flight = nil
                // The popover opens once the pop is under way, so the eye reaches the icon first.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12 * motion) { self?.showPopover(note, on: button) }
            }
            if flat != nil {
                clock.begin = begin
                // The last row is gone as it arrives. The panel goes three frames later, so a frame
                // drawn late still draws nothing rather than ending the pour a frame early.
                DispatchQueue.main.asyncAfter(deadline: .now() + path.arrival) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12 * motion) { self?.showPopover(note, on: button) }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + path.arrival + 0.05) {
                    self?.flight?.orderOut(nil)
                    self?.flight = nil
                }
            } else {
                self?.fly(layer, along: path, from: begin, arrived: arrived)
            }
            // In the pour the glow comes up as the first row reaches the icon, already the icon's
            // width, since that is the width the pour's mouth has narrowed to.
            let firstRow = path.arrival * (1 - 0.6 * strength)
            Self.glow(behind: button, from: flat != nil ? end.width : path.width(at: path.handover),
                      at: begin + (flat != nil ? firstRow : path.handover), arrival: begin + path.arrival, motion: motion)
            Self.pop(button, at: begin + path.arrival, motion: motion)
        }
    }

    /// Closes the popover and stops listening for what would have closed it.
    private func closePopover() {
        timeout?.invalidate()
        timeout = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        shortcutFired.map(NotificationCenter.default.removeObserver)
        shortcutFired = nil
        popover?.close()
        popover = nil
    }

    /// Closes the popover and ends the intro.
    func dismiss() {
        closePopover()
        let done = finished
        finished = nil
        done?()
    }

    // MARK: The flight

    /// Where the picture is over time. It goes into the icon, so it accelerates the whole way and
    /// arrives at speed, as a thing pulled in does, and the icon's pop is the impact. A spring
    /// settles softly instead: its last tenth took as long as the rest, a speck creeping into the
    /// icon. The path bows as every card flight does (`FlightCurve`). The picture keeps most of its
    /// size while it crosses the screen, so the eye can follow it, and collapses to the
    /// highlight's height over the last stretch.
    private struct FlightPath {
        let start: NSRect, end: NSRect
        let duration: Double
        let curve: FlightCurve
        let endScale: CGFloat
        /// When the picture starts handing over to the glow behind the icon: the last fifth of
        /// the way.
        let handover: Double
        /// When it hits the icon.
        var arrival: Double { duration }

        /// The timing curve's control points: it starts at rest and ends at one and a half times
        /// its mean speed. Faster, the picture was gone a frame after it reached the bar.
        private static let lift = CGPoint(x: 0.45, y: 0), pull = CGPoint(x: 0.7, y: 0.55)

        init(from start: NSRect, to end: NSRect, duration: Double, curve: FlightCurve) {
            self.start = start
            self.end = end
            self.duration = duration
            self.curve = curve
            endScale = end.height / start.height
            // The progress curve rises the whole way, so halving finds when it passes 0.8.
            var low = 0.0, high = 1.0
            for _ in 0..<30 {
                let mid = (low + high) / 2
                if Self.ease(mid) < 0.8 { low = mid } else { high = mid }
            }
            handover = high * duration
        }

        func progress(at time: Double) -> CGFloat {
            CGFloat(Self.ease(min(1, max(0, time / duration))))
        }

        /// The cubic Bézier through `lift` and `pull`: the fraction of the way at fraction `x` of
        /// the time. Its x rises with its parameter, so halving finds the parameter.
        private static func ease(_ x: Double) -> Double {
            func cubic(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> Double {
                let a = Double(a), b = Double(b)
                return 3 * a * t * (1 - t) * (1 - t) + 3 * b * t * t * (1 - t) + t * t * t
            }
            var low = 0.0, high = 1.0
            for _ in 0..<30 {
                let mid = (low + high) / 2
                if cubic(lift.x, pull.x, mid) < x { low = mid } else { high = mid }
            }
            return cubic(lift.y, pull.y, (low + high) / 2)
        }

        /// The picture's centre, in layer coordinates (y up), and its scale, at `progress`.
        func placement(at progress: CGFloat) -> (center: CGPoint, scale: CGFloat) {
            // FlightCurve works with y down.
            let from = CGPoint(x: start.midX, y: -start.midY), to = CGPoint(x: end.midX, y: -end.midY)
            let point = CGPoint(x: from.x + (to.x - from.x) * progress, y: from.y + (to.y - from.y) * progress)
            let place = curve.placement(at: point, from: from, to: to)
            return (CGPoint(x: point.x + place.offset.width, y: -(point.y + place.offset.height)),
                    pow(endScale, progress * progress) * place.scale)
        }

        func width(at time: Double) -> CGFloat {
            start.width * placement(at: progress(at: time)).scale
        }
    }

    /// The window as the window server draws it. In dark mode that has what the window's own views
    /// lack: the wallpaper's tint in the background and a light rim inside the edge, and a picture
    /// of the views alone looked flat beside the window it replaced. From macOS 14.4 ScreenCaptureKit
    /// captures an app's own windows without Screen Recording permission. Earlier, or when the
    /// capture fails or takes longer than a quarter second, the views are drawn instead.
    private static func picture(of window: NSWindow, _ done: @escaping (NSImage?) -> Void) {
        guard #available(macOS 14.4, *) else { return done(viewsPicture(of: window)) }
        let id = CGWindowID(window.windowNumber), size = window.frame.size, scale = window.backingScaleFactor
        // The capture holds the screen's own pixel values but is labelled sRGB, so on a Display P3
        // screen every saturated colour shifted at the handover (measured on macOS 15). Labelled
        // with the screen's space, the values are shown as they were.
        let space = window.screen?.colorSpace?.cgColorSpace
        Task { @MainActor in
            let image = await WindowCapture.image(of: id, size: size, scale: scale, within: .milliseconds(250))
                .map { image in space.flatMap { image.copy(colorSpace: $0) } ?? image }
            done(image.map { NSImage(cgImage: $0, size: size) } ?? viewsPicture(of: window))
        }
    }

    /// The window's frame view drawn into a bitmap: its content and title bar, without what the
    /// window server adds.
    private static func viewsPicture(of window: NSWindow) -> NSImage? {
        guard let view = window.contentView?.superview,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        return image
    }

    /// The picture on the window's own background, with what the window server adds to a window and
    /// a capture of it leaves out: its shadow, a hairline outline, and in dark mode a light rim
    /// inside the edge. Without those the picture read as a flat panel taking the window's place. The outer layer casts the shadow and the inner one clips,
    /// since a layer that clips its contents clips its shadow too.
    private static func cardLayer(_ picture: NSImage, frame: NSRect, scale: CGFloat, appearance: NSAppearance) -> CALayer {
        let radius = windowCornerRadius
        let card = CALayer()
        card.frame = frame
        // Matched to an active window's on macOS 15 by how much each darkens what is behind it,
        // beside and below the window: dark and long below it, short at its sides, almost none above.
        card.shadowColor = NSColor.black.cgColor
        card.shadowOpacity = 0.75
        card.shadowRadius = 22
        card.shadowOffset = CGSize(width: 0, height: -15)
        card.shadowPath = CGPath(roundedRect: CGRect(origin: .zero, size: frame.size), cornerWidth: radius, cornerHeight: radius, transform: nil)
        let face = CALayer()
        face.name = "face"
        face.frame = card.bounds
        face.cornerRadius = radius
        face.masksToBounds = true
        appearance.performAsCurrentDrawingAppearance { face.backgroundColor = NSColor.windowBackgroundColor.cgColor }
        // A bitmap rather than the NSImage, so `render(in:)` draws it too (`flattened`).
        face.contents = picture.cgImage(forProposedRect: nil, context: nil, hints: nil) ?? picture
        face.contentsScale = scale
        face.contentsGravity = .resize
        card.addSublayer(face)
        // Measured on macOS 15 in dark mode: a black device pixel just outside the edge, and a
        // point of white at about a fifth inside it. The light-mode outline is not measured.
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let pixel = 1 / scale
        let outline = CALayer()
        outline.name = "outline"
        outline.frame = card.bounds.insetBy(dx: -pixel, dy: -pixel)
        outline.cornerRadius = radius + pixel
        outline.borderWidth = pixel
        outline.borderColor = NSColor.black.withAlphaComponent(dark ? 1 : 0.2).cgColor
        card.addSublayer(outline)
        if dark {
            let rim = CALayer()
            rim.name = "rim"
            rim.frame = card.bounds
            rim.cornerRadius = radius
            rim.borderWidth = 1
            rim.borderColor = NSColor.white.withAlphaComponent(0.19).cgColor
            card.addSublayer(rim)
        }
        return card
    }

    /// The picture the intro would fly for `window`, as the funnel draws it: the card without its
    /// shadow, with `margin` points around it. For the Intro Lab's preview.
    static func funnelPicture(of window: NSWindow, _ done: @escaping ((image: CGImage, margin: CGFloat)?) -> Void) {
        picture(of: window) { picture in
            guard let picture else { return done(nil) }
            let layer = cardLayer(picture, frame: NSRect(origin: .zero, size: window.frame.size),
                                  scale: window.backingScaleFactor, appearance: window.effectiveAppearance)
            done(flattened(layer, scale: window.backingScaleFactor, space: window.screen?.colorSpace?.cgColorSpace))
        }
    }

    /// The card without its shadow drawn into one bitmap, with `margin` points around it for the
    /// outline, which sits outside the card's edge.
    private static func flattened(_ card: CALayer, scale: CGFloat, space: CGColorSpace?) -> (image: CGImage, margin: CGFloat)? {
        let margin: CGFloat = 1
        let size = card.bounds.insetBy(dx: -margin, dy: -margin).size
        guard let space = space ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int((size.width * scale).rounded(.up)), height: Int((size.height * scale).rounded(.up)),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: margin, y: margin)
        let shadow = card.shadowOpacity
        card.shadowOpacity = 0
        card.render(in: context)
        card.shadowOpacity = shadow
        return context.makeImage().map { ($0, margin) }
    }

    /// A titled window's corner radius, which AppKit does not publish: 10 pt through macOS 15, and
    /// larger from macOS 26. Only the first frames show it, over the window it matches.
    static var windowCornerRadius: CGFloat {
        if #available(macOS 26, *) { return 16 }
        return 10
    }

    /// Flies the picture along `path`. On the way in it stops reading as a window: its shadow,
    /// outline and rim go as it nears the bar, and its corners round to the highlight's. It fades
    /// out over the last stretch, into the icon, while the glow comes up behind the icon in its place.
    private func fly(_ card: CALayer, along path: FlightPath, from begin: CFTimeInterval, arrived: @escaping () -> Void) {
        guard let face = card.sublayers?.first(where: { $0.name == "face" }) else { return arrived() }
        let edges = card.sublayers?.filter { $0.name == "outline" || $0.name == "rim" } ?? []
        let steps = 90
        var positions: [NSValue] = [], scales: [CGFloat] = [], opacities: [CGFloat] = []
        var shadows: [CGFloat] = [], radii: [CGFloat] = [], windowLook: [CGFloat] = [], times: [Double] = []
        for i in 0...steps {
            let time = path.arrival * Double(i) / Double(steps)
            let progress = path.progress(at: time)
            let (center, scale) = path.placement(at: progress)
            positions.append(NSValue(point: center))
            scales.append(scale)
            opacities.append(1 - Self.ramp(progress, 0.8, 1))
            // The window's shadow, outline and rim go as it nears the bar, where the highlight takes over.
            let window = 1 - Self.ramp(progress, 0.5, 0.85)
            shadows.append(CGFloat(card.shadowOpacity) * window)
            windowLook.append(window)
            // On screen the corner goes from the window's to the highlight's; the face is drawn
            // at the window's size and scaled, so its own radius is that divided by the scale.
            let onScreen = Self.windowCornerRadius * scale + (Self.highlightRadius - Self.windowCornerRadius * scale) * Self.ramp(progress, 0.6, 1)
            radii.append(onScreen / scale)
            times.append(time)
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock(arrived)
        // Set without Core Animation's implicit animations, which would run beside the keyframes:
        // the implicit scale shrank the picture in place before the flight showed.
        CATransaction.setDisableActions(true)
        card.position = positions.last!.pointValue
        card.setValue(scales.last!, forKeyPath: "transform.scale")
        card.opacity = 0
        card.shadowOpacity = 0
        face.cornerRadius = radii.last!
        card.add(Self.keyframes("position", positions, at: times, from: begin, on: card), forKey: "position")
        card.add(Self.keyframes("transform.scale", scales, at: times, from: begin, on: card), forKey: "scale")
        card.add(Self.keyframes("opacity", opacities, at: times, from: begin, on: card), forKey: "opacity")
        card.add(Self.keyframes("shadowOpacity", shadows, at: times, from: begin, on: card), forKey: "shadow")
        face.add(Self.keyframes("cornerRadius", radii, at: times, from: begin, on: face), forKey: "corner")
        for edge in edges {
            // The outline sits outside the face, so its corners are wider by as much.
            let outset = (edge.bounds.width - card.bounds.width) / 2
            edge.cornerRadius = radii.last! + outset
            edge.opacity = 0
            edge.add(Self.keyframes("cornerRadius", radii.map { $0 + outset }, at: times, from: begin, on: edge), forKey: "corner")
            edge.add(Self.keyframes("opacity", windowLook, at: times, from: begin, on: edge), forKey: "opacity")
        }
        CATransaction.commit()
    }

    /// The menu bar's highlight shape behind the icon, the picture's last place. It comes up as
    /// the picture fades, from the picture's width out to the item's, then a light crosses it in
    /// the direction the picture travelled, and it fades. It is a view under the button, since a
    /// layer added to the button draws over the icon.
    private static func glow(behind button: NSStatusBarButton, from width: CGFloat, at handover: CFTimeInterval,
                             arrival: CFTimeInterval, motion: Double) {
        guard let host = button.superview else { return }
        let view = NSView(frame: button.frame)
        view.wantsLayer = true
        host.addSubview(view, positioned: .below, relativeTo: button)
        guard let base = view.layer else { return view.removeFromSuperview() }
        let bounds = base.bounds

        let pill = CALayer()
        pill.frame = bounds
        pill.cornerRadius = highlightRadius
        pill.masksToBounds = true
        // The bar's own appearance: a light bar gets a dark highlight and a dark bar a light one.
        button.effectiveAppearance.performAsCurrentDrawingAppearance {
            pill.backgroundColor = NSColor.labelColor.withAlphaComponent(0.16).cgColor
        }
        pill.opacity = 0
        base.addSublayer(pill)

        let band = bounds.width * 0.8
        let sheen = CAGradientLayer()
        sheen.frame = CGRect(x: 0, y: 0, width: band, height: bounds.height)
        sheen.colors = [NSColor.white.withAlphaComponent(0).cgColor, NSColor.white.withAlphaComponent(0.55).cgColor,
                        NSColor.white.withAlphaComponent(0).cgColor]
        // Tilted a little, as light catching a surface is.
        sheen.startPoint = CGPoint(x: 0, y: 0.35)
        sheen.endPoint = CGPoint(x: 1, y: 0.65)
        sheen.position = CGPoint(x: bounds.width + band / 2, y: bounds.midY)
        pill.addSublayer(sheen)

        let hold = arrival + 0.3 * motion, gone = arrival + 1.0 * motion
        let easeOut = CAMediaTimingFunction(name: .easeOut), easeInOut = CAMediaTimingFunction(name: .easeInEaseOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock { view.removeFromSuperview() }
        pill.add(keyframes("opacity", [0, 1, 1, 0], at: [handover, arrival, hold, gone], from: 0, on: pill,
                           timing: [easeOut, CAMediaTimingFunction(name: .linear), easeInOut]), forKey: "opacity")
        pill.add(keyframes("bounds.size.width", [min(width, bounds.width), bounds.width], at: [handover, arrival + 0.12 * motion],
                           from: 0, on: pill, timing: [easeOut]), forKey: "width")
        sheen.add(keyframes("position.x", [-band / 2, bounds.width + band / 2], at: [arrival, arrival + 0.55 * motion],
                            from: 0, on: sheen, timing: [easeInOut]), forKey: "sweep")
        CATransaction.commit()
    }

    /// The icon is hit: it starts growing at once, peaks about a third larger and settles with a
    /// small bounce. The motion is a spring's answer to a push rather than to a jump in size.
    private static func pop(_ button: NSStatusBarButton, at time: CFTimeInterval, motion: Double) {
        button.wantsLayer = true
        guard let layer = button.layer else { return }
        let spring = Spring(duration: 0.45 * motion, bounce: 0.45)
        let total = spring.settlingDuration, steps = 60
        let samples = (0...steps).map { spring.value(target: 0.0, initialVelocity: 1.0, time: total * Double($0) / Double(steps)) }
        let peak = samples.max() ?? 1
        let center = CGPoint(x: button.bounds.midX, y: button.bounds.midY)
        let values = samples.map { NSValue(caTransform3D: CATransform3D.scale(1 + 0.3 * $0 / peak, about: center)) }
        let times = (0...steps).map { time + total * Double($0) / Double(steps) }
        layer.add(keyframes("transform", values, at: times, from: 0, on: layer), forKey: "pop")
    }

    /// 0 below `low`, 1 above `high`, and smooth in between.
    private static func ramp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        let t = min(1, max(0, (value - low) / (high - low)))
        return t * t * (3 - 2 * t)
    }

    /// A keyframe animation at `times`, which are seconds on the media clock after `begin`. Every
    /// part of the intro is timed from one moment, so the hand-overs between them stay exact. It
    /// holds its first value until it starts; the layer's own value is its last.
    private static func keyframes(_ keyPath: String, _ values: [Any], at times: [Double], from begin: CFTimeInterval,
                                  on layer: CALayer, timing: [CAMediaTimingFunction]? = nil) -> CAKeyframeAnimation {
        let first = times.first ?? 0, total = max((times.last ?? 0) - first, 0.001)
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = times.map { NSNumber(value: ($0 - first) / total) }
        animation.timingFunctions = timing
        animation.beginTime = layer.convertTime(begin + first, from: nil)
        animation.duration = total
        animation.fillMode = .backwards
        return animation
    }

    // MARK: The popover

    private func showPopover(_ note: Note, on button: NSStatusBarButton) {
        closePopover()
        let popover = NSPopover()
        // Closed here rather than by AppKit: setup hands the focus back to the person's app as it
        // closes, and a transient popover in an app that is not active would not stay.
        popover.behavior = .applicationDefined
        popover.animates = Settings.shared.motionScale > 0
        popover.contentViewController = NSHostingController(rootView: MenuBarIntroNote(note: note))
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        self.popover = popover
        let close: () -> Void = { [weak self] in MainActor.assumeIsolated { self?.dismiss() } }
        // A click on the icon opens its menu, which the popover would cover.
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        monitors = [NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak button] event in
            if event.window != nil, event.window === button?.window { close() }
            return event
        }].compactMap { $0 }
        // The shortcut doing what the popover describes is the person having read it.
        shortcutFired = NotificationCenter.default.addObserver(forName: .hotKeyFired, object: nil, queue: .main) { _ in close() }
        timeout = Timer.scheduledTimer(withTimeInterval: Self.popoverSeconds, repeats: false) { _ in close() }
    }
}

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

private struct MenuBarIntroNote: View {
    let note: MenuBarIntro.Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(Identity.name) is in your menu bar").font(.headline)
            switch note {
            case let .shortcut(spec):
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        if let key = spec.doubleTapKey {
                            Text("Tap")
                            Keycap(symbol: key.glyph, label: key.label)
                            Text("twice")
                        } else {
                            Text("Press")
                            Keycap(symbol: nil, label: spec.glyphs)
                        }
                    }
                    Text("to see your recent screenshots.")
                }
                .foregroundStyle(.secondary)
            case let .text(text):
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            case let .list(lead, items):
                VStack(alignment: .leading, spacing: 3) {
                    Text(lead)
                    ForEach(items, id: \.self) { item in
                        Text("• \(item)").fixedSize(horizontal: false, vertical: true)
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 250, alignment: .leading)
    }
}

/// A key as it looks on the keyboard, inline in a sentence: its symbol beside its name.
private struct Keycap: View {
    let symbol: String?
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Text(symbol) }
            Text(label)
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.22), lineWidth: 0.5))
        // The key's lower edge, as on a keycap.
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.18)).offset(y: 1))
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

/// One window of this app, captured by ScreenCaptureKit.
@available(macOS 14.4, *)
private enum WindowCapture {
    /// The window with id `id`, at `scale`, or nil when the capture fails or has not answered
    /// within `limit`.
    static func image(of id: CGWindowID, size: CGSize, scale: CGFloat, within limit: Duration) async -> CGImage? {
        await withCheckedContinuation { continuation in
            let gate = Gate(continuation)
            Task { gate.open(with: try? await capture(id, size: size, scale: scale)) }
            Task {
                try? await Task.sleep(for: limit)
                gate.open(with: nil)
            }
        }
    }

    private static func capture(_ id: CGWindowID, size: CGSize, scale: CGFloat) async throws -> CGImage? {
        guard let window = try await SCShareableContent.currentProcess.windows.first(where: { $0.windowID == id }) else { return nil }
        let configuration = SCStreamConfiguration()
        configuration.width = Int(size.width * scale)
        configuration.height = Int(size.height * scale)
        configuration.ignoreShadowsSingleWindow = true
        configuration.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window),
                                                          configuration: configuration)
    }

    /// Resumes the continuation with the first answer, the capture's or the time limit's.
    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<CGImage?, Never>?

        init(_ continuation: CheckedContinuation<CGImage?, Never>) { self.continuation = continuation }

        func open(with image: CGImage?) {
            lock.lock()
            let waiting = continuation
            continuation = nil
            lock.unlock()
            waiting?.resume(returning: image)
        }
    }
}
