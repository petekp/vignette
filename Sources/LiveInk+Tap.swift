import AppKit

// MARK: The tap

extension LiveInk {
    /// Takes the pointer's events while inking lasts, or leaves them to the overlays when macOS refuses.
    func startTap(since began: Date) {
        guard tap == nil else { return }
        tap = LiveInkTap.start { [weak self] input in self?.tapped(input) }
        tap?.onTurnedOff = { [weak self] in self?.inking.forEach { $0.overlay.tapTakesPresses = false } }
        inking.forEach { $0.overlay.tapTakesPresses = tap != nil }
        let ms = Int(Date().timeIntervalSince(began) * 1000)
        Log.write(tap == nil ? "[live-ink] error tap refused by macOS; the overlay takes the presses" : "[live-ink] tap on ms=\(ms)")
    }

    func stopTap() {
        pressedSurface = nil
        inking.forEach { $0.overlay.tapTakesPresses = false }
        guard let tap else { return }
        tap.stop()
        self.tap = nil
        Log.write("[live-ink] tap off")
    }

    /// An event the tap took: a press goes to the surface under it, and that surface takes the rest of
    /// the stroke, wherever the pointer goes; a move goes to the surface under the pointer.
    private func tapped(_ input: LiveInkOverlay.Input) {
        // The gel is lit from the pointer, and its own watch hears no move the tap takes.
        if InkClock.shared.showsInk { InkClock.shared.wake() }
        let under = { (point: CGPoint) in self.inking.first { $0.overlay.globalFrame.contains(point) } }
        switch input {
        case .pressed(let point):
            pressedSurface = under(point)
            pressedSurface?.overlay.take(input)
        case .dragged:
            pressedSurface?.overlay.take(input)
        case .released:
            let surface = pressedSurface
            pressedSurface = nil
            surface?.overlay.take(input)
        case .moved(let point):
            under(point)?.overlay.take(input)
        }
    }
}
