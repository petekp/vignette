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
        guard let button = statusItem?.button, let icon = NSImage(named: "MenuBarIcon") else { updateDot = nil; return }
        let duration = 0.3 * settings.motionScale
        let dotSize: CGFloat = 4, outline: CGFloat = 1, gap: CGFloat = 1
        let size = dotSize + outline * 2
        let bounds = button.bounds
        let frame = NSRect(x: bounds.maxX - 1 - size, y: button.isFlipped ? 0 : bounds.height - size, width: size, height: size)
        if wanted, updateDot == nil, let leaving = leavingDot {
            leavingDot = nil
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
            guard duration > 0 else { return }
            springDot(badge, appearing: true, duration: duration)
        } else if !wanted, let badge = updateDot {
            updateDot = nil
            leavingDot = badge
            icon.isTemplate = true
            setIcon(icon, on: button, fading: duration)
            springDot(badge, appearing: false, duration: duration)
        }
    }

    /// Springs the dot in or out from wherever it is drawn now, so a dot wanted again mid-exit
    /// reverses with its motion kept. A dot that left is removed once its exit finishes, unless
    /// `updateDot` has become that same dot again by then.
    private func springDot(_ badge: NSView, appearing: Bool, duration: Double) {
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
        if !appearing {
            CATransaction.setCompletionBlock { [weak self, weak badge] in
                guard let self, let badge, self.leavingDot === badge else { return }
                self.leavingDot = nil
                badge.removeFromSuperview()
            }
        }
        CATransaction.commit()
    }

    /// Swaps the icon, with the old picture fading out on a spring over the new one. The picture
    /// is taken with the button's subviews (the update dot) hidden, since the dot moves on its own.
    private func setIcon(_ image: NSImage, on button: NSStatusBarButton, fading duration: Double) {
        image.accessibilityDescription = Identity.name
        var old: CALayer?
        if duration > 0, let layer = button.layer, let rep = button.bitmapImageRepForCachingDisplay(in: button.bounds) {
            let hidden = button.subviews.filter { !$0.isHidden }
            hidden.forEach { $0.isHidden = true }
            button.cacheDisplay(in: button.bounds, to: rep)
            hidden.forEach { $0.isHidden = false }
            let snapshot = CALayer()
            snapshot.frame = button.bounds
            snapshot.contents = rep.cgImage
            snapshot.contentsScale = button.window?.backingScaleFactor ?? 2
            layer.addSublayer(snapshot)
            old = snapshot
        }
        button.image = image
        guard let old else { return }
        let fade = CASpringAnimation(perceptualDuration: duration, bounce: 0)
        fade.keyPath = "opacity"
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = fade.settlingDuration
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        old.opacity = 0
        CATransaction.setCompletionBlock { old.removeFromSuperlayer() }
        old.add(fade, forKey: "fade")
        CATransaction.commit()
    }
}
