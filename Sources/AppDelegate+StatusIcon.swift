import AppKit

extension AppDelegate {
    /// A template disc `size` across with a hole `hole` across. The hole is half a point smaller
    /// than the dot it frames, so the two overlap and no background shows between them.
    static func ring(size: CGFloat, hole: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSBezierPath(ovalIn: rect).fill()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            let inner = (size - hole) / 2 + 0.25
            NSBezierPath(ovalIn: rect.insetBy(dx: inner, dy: inner)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The icon with a clear circle filling `dot`, which is in the button's coordinates.
    /// The button draws the icon at its own size, centred.
    static func icon(_ icon: NSImage, clearedAround dot: NSRect, in button: NSStatusBarButton) -> NSImage {
        let size = icon.size
        let origin = NSPoint(x: (button.bounds.width - size.width) / 2, y: (button.bounds.height - size.height) / 2)
        var center = NSPoint(x: dot.midX - origin.x, y: dot.midY - origin.y)
        if button.isFlipped { center.y = size.height - center.y }
        let radius = dot.width / 2
        let image = NSImage(size: size, flipped: false) { rect in
            icon.draw(in: rect)
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// A dot at the icon's top right while an update waits, in the accent colour so it reads as
    /// news rather than as part of the icon. An outline in the icon's own colour keeps it visible on
    /// any menu bar, and a clear gap cut into the icon keeps it off the glyph's stroke. They appear
    /// and leave together.
    func showUpdateDot() {
        let wanted = updater?.waiting != nil
        guard let button = statusItem?.button, let icon = NSImage(named: "MenuBarIcon") else { updateDot = nil; dotExit = nil; return }
        let duration = 0.3 * settings.motionScale
        let dotSize: CGFloat = 4, outline: CGFloat = 1, gap: CGFloat = 1
        let size = dotSize + outline * 2
        let bounds = button.bounds
        let frame = NSRect(x: bounds.maxX - 1 - size, y: button.isFlipped ? 0 : bounds.height - size, width: size, height: size)
        if wanted, updateDot == nil, let leaving = dotExit?.badge {
            dotExit = nil
            updateDot = leaving
            setIcon(Self.icon(icon, clearedAround: frame.insetBy(dx: -gap, dy: -gap), in: button), on: button, fading: duration)
            springDot(leaving, appearing: true, duration: duration)
        } else if wanted, updateDot == nil {
            let badge = NSView(frame: frame)
            badge.autoresizingMask = [.minXMargin, button.isFlipped ? .maxYMargin : .minYMargin]
            badge.wantsLayer = true
            // A template image, so the menu bar draws the outline in the icon's colour: white on a
            // dark bar, black on a light one.
            let ring = NSImageView(frame: badge.bounds)
            ring.imageScaling = .scaleNone
            ring.image = Self.ring(size: size, hole: dotSize)
            badge.addSubview(ring)
            let dot = NSView(frame: badge.bounds.insetBy(dx: outline, dy: outline))
            dot.wantsLayer = true
            dot.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            dot.layer?.cornerRadius = dotSize / 2
            badge.addSubview(dot)
            setIcon(Self.icon(icon, clearedAround: frame.insetBy(dx: -gap, dy: -gap), in: button), on: button, fading: duration)
            button.addSubview(badge)
            updateDot = badge
            guard duration > 0, let layer = badge.layer else { return }
            layer.opacity = 0
            layer.transform = CATransform3D.scale(0.3, about: CGPoint(x: size / 2, y: size / 2))
            springDot(badge, appearing: true, duration: duration)
        } else if !wanted, let badge = updateDot {
            updateDot = nil
            let exit = DotExit(badge)
            dotExit = exit
            icon.isTemplate = true
            setIcon(icon, on: button, fading: duration)
            springDot(badge, appearing: false, duration: duration, exit: exit)
        }
    }

    /// Springs the dot in or out from wherever it is drawn now, so a dot wanted again mid-exit
    /// reverses with its motion kept. A dot that left is removed once its exit finishes, unless
    /// the dot was not wanted again in the meantime, which replaces `dotExit`.
    private func springDot(_ badge: NSView, appearing: Bool, duration: Double, exit: DotExit? = nil) {
        guard let layer = badge.layer else { return }
        let shown = layer.presentation() ?? layer
        let fromOpacity = shown.opacity
        let fromTransform = shown.transform
        let size = badge.bounds.width
        let small = CATransform3D.scale(0.3, about: CGPoint(x: size / 2, y: size / 2))
        let toOpacity: Float = appearing ? 1 : 0
        let toTransform = appearing ? CATransform3DIdentity : small
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let exit {
            CATransaction.setCompletionBlock { [weak self] in
                guard let self, self.dotExit === exit else { return }
                self.dotExit = nil
                exit.badge.removeFromSuperview()
            }
        }
        layer.removeAnimation(forKey: "scale")
        layer.removeAnimation(forKey: "fade")
        layer.opacity = toOpacity
        layer.transform = toTransform
        if duration > 0 {
            let scale = CASpringAnimation(perceptualDuration: duration, bounce: appearing ? 0.3 : 0)
            scale.keyPath = "transform"
            scale.fromValue = fromTransform
            scale.toValue = toTransform
            scale.duration = scale.settlingDuration
            let fade = CASpringAnimation(perceptualDuration: appearing ? duration / 2 : duration, bounce: 0)
            fade.keyPath = "opacity"
            fade.fromValue = fromOpacity
            fade.toValue = toOpacity
            fade.duration = fade.settlingDuration
            layer.add(scale, forKey: "scale")
            layer.add(fade, forKey: "fade")
        }
        CATransaction.commit()
    }

    /// Swaps the icon with a crossfade on springs: a picture of the old icon fades out while a picture
    /// of the new one fades in, added together so each pixel is a true blend and nothing dims. The
    /// button draws no image of its own until they finish. The pictures are taken with the update
    /// dot hidden, since the dot moves on its own. A swap that starts mid-fade begins from the blend
    /// on screen at that moment.
    private func setIcon(_ image: NSImage, on button: NSStatusBarButton, fading duration: Double) {
        image.accessibilityDescription = Identity.name
        button.setAccessibilityLabel(Identity.name)
        let layer = button.layer
        let running = layer?.sublayers?.compactMap { $0 as? IconFade }.first
        let onScreen = running?.currentPicture()
        if let running {
            running.removeFromSuperlayer()
        }
        let dots = [updateDot, dotExit?.badge].compactMap { $0 }
        guard duration > 0, let layer, let before = onScreen ?? Self.picture(of: button, hiding: dots) else {
            button.image = image
            return
        }
        button.image = image
        guard let after = Self.picture(of: button, hiding: dots) else { return }
        button.image = nil
        let fade = IconFade(target: image, before: before, after: after)
        fade.frame = button.bounds
        layer.insertSublayer(fade, at: 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak fade] in
            guard let fade, fade.superlayer != nil else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            button.image = fade.target
            fade.removeFromSuperlayer()
            CATransaction.commit()
        }
        for (picture, from, to) in [(before, Float(1), Float(0)), (after, Float(0), Float(1))] {
            let spring = CASpringAnimation(perceptualDuration: duration, bounce: 0)
            spring.keyPath = "opacity"
            spring.fromValue = from
            spring.toValue = to
            spring.duration = spring.settlingDuration
            picture.opacity = to
            picture.add(spring, forKey: "fade")
        }
        CATransaction.commit()
    }

    private static func picture(of button: NSStatusBarButton, hiding dots: [NSView]) -> CALayer? {
        guard let rep = button.bitmapImageRepForCachingDisplay(in: button.bounds) else { return nil }
        let shown = dots.filter { !$0.isHidden }
        shown.forEach { $0.isHidden = true }
        button.cacheDisplay(in: button.bounds, to: rep)
        shown.forEach { $0.isHidden = false }
        return IconFade.layer(showing: rep.cgImage, frame: button.bounds)
    }
}

/// A dot on its way out. Replacing or clearing `AppDelegate.dotExit` cancels the removal.
final class DotExit {
    let badge: NSView
    init(_ badge: NSView) { self.badge = badge }
}

/// An icon crossfade in flight: two pictures of the button, added together, and the icon the
/// button takes when it ends.
final class IconFade: CALayer {
    private(set) var target: NSImage?
    private var before: CALayer?
    private var after: CALayer?

    convenience init(target: NSImage, before: CALayer, after: CALayer) {
        self.init()
        self.target = target
        self.before = before
        self.after = after
        addSublayer(before)
        addSublayer(after)
    }

    static func layer(showing image: CGImage?, frame: CGRect) -> CALayer {
        let picture = CALayer()
        picture.frame = frame
        picture.contents = image
        picture.compositingFilter = "plusL"
        return picture
    }

    /// What the two pictures add up to now, as one picture.
    func currentPicture() -> CALayer? {
        let pictures = [before, after].compactMap { $0 }
        let images = pictures.compactMap { $0.contents.map { $0 as! CGImage } }
        guard let first = images.first, images.count == pictures.count,
              let context = CGContext(data: nil, width: first.width, height: first.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setBlendMode(.plusLighter)
        let rect = CGRect(x: 0, y: 0, width: first.width, height: first.height)
        for (picture, image) in zip(pictures, images) {
            context.setAlpha(CGFloat(picture.presentation()?.opacity ?? picture.opacity))
            context.draw(image, in: rect)
        }
        return IconFade.layer(showing: context.makeImage(), frame: frame)
    }
}
