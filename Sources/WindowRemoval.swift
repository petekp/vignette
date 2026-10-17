import AppKit

/// Takes a window off the screen once what replaces it is shown: the window server takes a window
/// down at once, so ordered out in the turn its replacement came up, the window left the place empty
/// for 4 to 9 frames (docs/e2e-2026-09-26.md). `hide` runs on the next turn of the main queue, the one
/// the annotator's flight home starts moving in, so the two land in one commit. `remove` runs a few
/// display refreshes later, once the display has shown that commit.
@MainActor
final class WindowRemoval: NSObject {
    /// The first refresh can come before the commit, and the render server draws a commit on the
    /// refresh after it arrives.
    private static let refreshes = 3
    private var generation = 0
    private var link: CADisplayLink?
    private var left = 0
    private var remove: (() -> Void)?

    func start(on screen: NSScreen?, hide: @escaping () -> Void = {}, remove: @escaping () -> Void) {
        cancel()
        let started = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, generation == started else { return }
            hide()
            guard let screen = screen ?? NSScreen.main else { remove(); return }
            self.remove = remove
            left = Self.refreshes
            let link = screen.displayLink(target: self, selector: #selector(refreshed))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
    }

    func cancel() {
        generation += 1
        link?.invalidate()
        link = nil
        remove = nil
    }

    @objc private func refreshed(_ link: CADisplayLink) {
        left -= 1
        guard left <= 0 else { return }
        let remove = remove
        cancel()
        remove?()
    }
}
