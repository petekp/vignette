import AppKit

/// Runs `StackSwipe` for the corner: reads each scroll event over the panel, ticks the swipe's
/// springs on the display link, and puts its offset on the model, where `StackView` draws it.
@MainActor
final class StackSwipeDriver: NSObject {
    private var swipe = StackSwipe()
    private let model: StackModel
    /// The screen the corner is on, whose display link ticks the springs.
    private let screen: () -> NSScreen
    /// Closes the corner by the swipe; the slide-out answers with `leave()`.
    private let close: () -> Void
    private var link: CADisplayLink?

    init(model: StackModel, screen: @escaping () -> NSScreen, close: @escaping () -> Void) {
        self.model = model
        self.screen = screen
        self.close = close
    }

    /// The fingers move the column as they are, whatever the motion setting; the springs after
    /// the release are motion, so they are scaled. A pull away from the edge stays inside the panel.
    private var rules: StackSwipe.Rules {
        let ui = Settings.shared.data.ui, scaled = Settings.shared.motionUI
        let room = StackLayout.current.at(widthScale: model.widthScale).pullRoom
        return StackSwipe.Rules(distance: ui.swipeDistance, speed: ui.swipeSpeed, stretch: min(ui.swipeStretch, room),
                                returnDuration: scaled.relayoutDuration, exitDuration: scaled.slideOutDuration)
    }

    func scroll(_ event: NSEvent) -> StackSwipe.Answer {
        // The image in the annotator came from the column, and a drag out of it is still going.
        let swipes = !model.annotating && model.draggedCard == nil
        let answer = swipe.scroll(Self.read(event), swipes: swipes, rules: rules, now: CACurrentMediaTime())
        if answer == .close {
            close()
            // The slide-out has called `leave` by now; when it did not, the column comes back.
            swipe.cancelClose(rules: rules, now: CACurrentMediaTime())
        }
        draw()
        return answer
    }

    /// The corner is closing by the swipe: the column leaves as one piece, past the screen's edge,
    /// with the selection strip when it is out.
    func leave() {
        let layout = StackLayout.current.at(widthScale: model.widthScale)
        let strip = model.isStack && model.inSelectionMode && !model.annotating
        swipe.leave(distance: strip ? layout.stripExitDistance : layout.columnExitDistance, rules: rules, now: CACurrentMediaTime())
        draw()
    }

    /// The corner came up again: a column leaving by the swipe turns around.
    func presented() {
        swipe.presented(rules: rules, now: CACurrentMediaTime())
        draw()
    }

    /// The corner has gone.
    func reset() {
        swipe.reset()
        draw()
    }

    private func draw() {
        if model.swipe != swipe.offset { model.swipe = swipe.offset }
        if model.swipeExit != swipe.carriesColumn { model.swipeExit = swipe.carriesColumn }
        if swipe.isSpringing { startTicking() } else { stopTicking() }
    }

    private func startTicking() {
        guard link == nil else { return }
        let link = screen().displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func stopTicking() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        swipe.tick(at: CACurrentMediaTime())
        draw()
    }

    static func read(_ event: NSEvent) -> StackSwipe.Scroll {
        let phase: StackSwipe.Scroll.Phase
        if event.phase.contains(.began) { phase = .began }
        else if event.phase.contains(.changed) { phase = .changed }
        else if event.phase.contains(.ended) { phase = .ended }
        else if event.phase.contains(.cancelled) { phase = .cancelled }
        else if event.phase.contains(.mayBegin) { phase = .mayBegin }
        else { phase = .none }
        // The fingers' own direction, whichever way the person's scrolling runs.
        let dx = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 10
        return StackSwipe.Scroll(phase: phase, momentum: !event.momentumPhase.isEmpty, dx: dx, dy: dy, time: event.timestamp)
    }
}
