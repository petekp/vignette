import AppKit

// MARK: Where the panel goes

extension AnnotatorToolbar {
    /// Centers the toolbar under `frame`, `gap` points below it. A bar that is already up — one
    /// image following another with no gap between them — slides to the new place instead of being
    /// taken down and raised again, so the controls stay where the hand left them and only move
    /// with the image's height. It also cancels a `hideSoon` waiting its turn: this bar is wanted.
    func place(below frame: NSRect, gap: CGFloat) {
        placedBelow = (frame, gap)
        carried = nil
        hideGeneration += 1
        position(slide: true)
    }

    /// Puts the middle of the bar's top edge at `center` and `top` at once: a zoomed frame carries
    /// the bar down as it grows towards it, and back up as it comes home, and a re-fit carries it
    /// from under the frame's last place to under its new one. At once, with no spring of its own,
    /// since the frame it follows is already on one. The bar's place under the frame `place` was
    /// given is nil, and a bar already there is left alone, slide and all. `fitted` is the fitted
    /// frame the zoom is growing from: a bar placed under another frame, the last image's before a
    /// swap's `place`, is not the one this point belongs to, and is left to slide.
    func follow(top: CGFloat, center: CGFloat, fitted: NSRect) {
        guard let (frame, gap) = placedBelow, frame == fitted else { return }
        let place = NSPoint(x: frame.midX, y: frame.minY - gap)
        let point = NSPoint(x: center, y: top)
        let next = point == place ? nil : point
        guard next != carried else { return }
        carried = next
        sliding = false
        slideX.stop(); slideY.stop()
        let at = next ?? place
        panel.setFrameOrigin(Self.rect(center: at.x, top: at.y + Self.padding + Self.messageRoom,
                                       size: panel.frame.size).origin)
        noteRoomBelow(barTop: at.y, x: at.x)
    }

    func position(slide: Bool) {
        guard let (frame, gap) = placedBelow else { return }
        let fit = fittingSize
        // While the bar is up the panel never narrows, so a bar springing narrower keeps the room it
        // is animating in. The bar is centred in the panel and the rest is clear, which passes
        // presses through. A new session starts at the bar's own width.
        let up = model.shown && panel.isVisible
        let size = NSSize(width: up ? max(fit.width, panel.frame.width) : fit.width, height: fit.height)
        let barTop = carried?.y ?? frame.minY - gap
        let center = carried?.x ?? frame.midX, top = barTop + Self.padding + Self.messageRoom
        noteRoomBelow(barTop: barTop, x: center)
        guard slide, up else {
            sliding = false
            slideX.stop(); slideY.stop()
            panel.setFrame(Self.rect(center: center, top: top, size: size), display: true)
            return
        }
        if !sliding {
            // The springs start from where the bar really is, not from the last value they carried.
            slideX.set(panel.frame.midX)
            slideY.set(panel.frame.maxY)
            sliding = true
        }
        // The window server may give the panel a frame a fraction off the size asked for, so the
        // size is compared with a point of tolerance. A new size keeps the slide's centre and top.
        if abs(panel.frame.width - size.width) >= 1 || abs(panel.frame.height - size.height) >= 1 {
            panel.setFrame(Self.rect(center: slideX.value, top: slideY.value, size: size), display: true)
        }
        // As long as the incoming card's flight takes to cover `frame`, when that window comes up.
        let seconds = FlightTiming.covers(frame)
        slideX.animate(to: center, duration: seconds)
        slideY.animate(to: top, duration: seconds)
    }

    /// The room under a bar whose top edge is at `barTop`, down to the bottom of the visible screen
    /// it is on, which the message field grows into.
    private func noteRoomBelow(barTop: CGFloat, x: CGFloat) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: x, y: barTop)) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let room = barTop - Self.height - visible.minY
        if model.roomBelow != room { model.roomBelow = room }
    }

    /// The panel's frame from its centre and top edge, which is what the springs move, so a change of
    /// size never moves the bar.
    private static func rect(center: CGFloat, top: CGFloat, size: NSSize) -> NSRect {
        NSRect(x: (center - size.width / 2).rounded(), y: top - size.height, width: size.width, height: size.height)
    }

    func applySlide() {
        guard sliding else { return }
        let origin = Self.rect(center: slideX.value, top: slideY.value, size: panel.frame.size).origin
        guard origin != panel.frame.origin else { return }
        panel.setFrameOrigin(origin)
    }
}
