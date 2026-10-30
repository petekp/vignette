import AppKit

/// A popover hung from a view of a live ink overlay, at a rect that moves with one of the overlay's
/// marks: an answer's reply, or the person's note. It keeps where it hangs, and slides on a spring to
/// hang from another mark or another rect on the same one, since AppKit moves a popover whose
/// positioning rect changes in one frame. It fades as its mark fades, and shows again where it hung
/// when its host's window comes back, since AppKit closes a popover whose host window went.
@MainActor
final class HangingPopover {
    /// What it does to hang from another host view, or another edge, which AppKit takes only by
    /// showing the popover again, in one frame.
    enum Reshow {
        case atOnce
        /// Fades out, shows again there, and fades back in.
        case fadingThrough
    }

    /// What `hang` did.
    enum Hung {
        /// The popover came up, for the first time or after AppKit closed it.
        case shown
        case moved
        /// Its host's window is not on the screen; it shows once it is (`fade`).
        case waiting
    }

    let popover = NSPopover()
    private(set) weak var host: NSView?
    private(set) var edge: PopoverPlace.Edge?
    /// The mark it hangs from, and the rect in the marks' coordinates.
    private var from: (anchor: Mark.ID?, at: CGRect)?
    /// Where it hangs, in the host's coordinates.
    private var rect: CGRect = .zero
    /// The alpha its window shows at, once it is up.
    private(set) var alpha: CGFloat
    private let reshow: Reshow
    private var stopped = false
    /// Where it is sliding to, in the host's coordinates.
    private var target: CGRect?
    private lazy var x = Tween(initial: 0) { [weak self] _ in self?.applySlide() }
    private lazy var y = Tween(initial: 0) { [weak self] _ in self?.applySlide() }

    init(reshow: Reshow, alpha: CGFloat = 1) {
        self.reshow = reshow
        self.alpha = alpha
        popover.behavior = .applicationDefined
    }

    /// The popover's window, once it has been shown.
    var window: NSWindow? { popover.contentViewController?.view.window }

    var isSliding: Bool { target != nil }

    /// The rect it hangs from now, in global top-left points: it moves with its mark's window.
    var hungFrom: CGRect? {
        guard let host, let hostWindow = host.window else { return nil }
        return StateReport.flipped(hostWindow.convertToScreen(host.convert(popover.positioningRect, to: nil)))
    }

    /// Hangs it from `rect` in `host`, which is `place` in the marks' coordinates. Up already, it
    /// slides there when `animated` and its mark or the rect on it changed, and else goes there at
    /// once, as when the layer moved in its window.
    @discardableResult
    func hang(from host: NSView, at rect: CGRect, place: PopoverPlace, animated: Bool) -> Hung {
        guard !stopped else { return .waiting }
        let moved = from.map { $0.anchor != place.anchor || $0.at != place.at } ?? false
        let shownHost = self.host
        from = (place.anchor, place.at)
        self.rect = rect
        let reshown = shownHost !== host || place.edge != edge
        self.host = host
        edge = place.edge
        guard popover.isShown, shownHost != nil else { return show() ? .shown : .waiting }
        let motion = animated ? Settings.shared.motionScale : 0
        if reshown {
            stopSlide()
            switch reshow {
            case .atOnce: showAgain()
            case .fadingThrough: fadeThrough(motion: motion)
            }
        } else if motion > 0, moved || isSliding {
            slide(to: rect, duration: Self.slideDuration * motion)
        } else if !isSliding, popover.positioningRect != rect {
            popover.positioningRect = rect
        }
        return .moved
    }

    /// Fades it to `target` over `duration`, as its mark fades. Answers true when it came back, shown
    /// again where it hung after AppKit closed it.
    @discardableResult
    func fade(to target: CGFloat, duration: CFTimeInterval) -> Bool {
        guard !stopped else { return false }
        let changed = target != alpha
        alpha = target
        let back = target > 0 && !popover.isShown && show(from: 0)
        guard changed || back, let window else { return back }
        guard duration > 0 else { window.alphaValue = target; return back }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: target > window.alphaValue ? .easeOut : .easeIn)
            window.animator().alphaValue = target
        }
        return back
    }

    /// It is closing: it moves and shows again no more.
    func stop() {
        stopped = true
        stopSlide()
    }

    /// Shows it where it hangs, at `start`, or at its alpha, when its host's window is on the screen.
    private func show(from start: CGFloat? = nil) -> Bool {
        guard let host, let edge, host.window?.isVisible == true else { return false }
        popover.show(relativeTo: rect, of: host, preferredEdge: edge.rectEdge(flipped: host.isFlipped))
        window?.alphaValue = start ?? alpha
        return true
    }

    /// Shows it again where it hangs now, keeping its window's alpha and the keys.
    private func showAgain() {
        guard let host, let edge else { return }
        popover.show(relativeTo: rect, of: host, preferredEdge: edge.rectEdge(flipped: host.isFlipped))
    }

    private func fadeThrough(motion: CGFloat) {
        guard motion > 0, let window, window.alphaValue > 0 else { return showAgain() }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeOut * motion
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.stopped else { return }
                self.showAgain()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Self.fadeIn * motion
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    window.animator().alphaValue = self.alpha
                }
            }
        }
    }

    private func slide(to rect: CGRect, duration: CFTimeInterval) {
        guard rect != target else { return }
        if target == nil {
            x.set(popover.positioningRect.minX)
            y.set(popover.positioningRect.minY)
        }
        target = rect
        let settled = { [weak self] in
            guard let self, let target = self.target, self.x.value == target.minX, self.y.value == target.minY else { return }
            self.target = nil
        }
        x.animate(to: rect.minX, duration: duration, completion: settled)
        y.animate(to: rect.minY, duration: duration, completion: settled)
    }

    private func stopSlide() {
        x.stop()
        y.stop()
        target = nil
    }

    private func applySlide() {
        guard let target else { return }
        popover.positioningRect = CGRect(origin: CGPoint(x: x.value, y: y.value), size: target.size)
    }

    /// How long it takes to move to another mark, at full motion: as long as a focus takes to come
    /// in, so a tour's reply arrives as its next target sharpens.
    static let slideDuration: CFTimeInterval = Focus.fade
    static let fadeIn: TimeInterval = 0.18
    static let fadeOut: TimeInterval = 0.16
}
