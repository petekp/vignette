import AppKit
import QuartzCore

/// A display link on the main screen. A display's link stops with the display, so it moves to the
/// main screen of the moment whenever the screens change.
@MainActor
final class ScreenLink {
    private var link: CADisplayLink?
    private var screensChanged: Any?
    private weak var target: AnyObject?
    private let selector: Selector

    var isPaused = false {
        didSet { link?.isPaused = isPaused }
    }

    /// Calls `selector` on `target` with the `CADisplayLink` at each refresh, until `invalidate`.
    init(_ target: AnyObject, _ selector: Selector) {
        self.target = target
        self.selector = selector
        attach()
        screensChanged = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.attach() }
        }
    }

    isolated deinit {
        invalidate()
    }

    func invalidate() {
        link?.invalidate()
        link = nil
        if let screensChanged { NotificationCenter.default.removeObserver(screensChanged) }
        screensChanged = nil
    }

    private func attach() {
        link?.invalidate()
        link = (NSScreen.main ?? NSScreen.screens.first).flatMap { screen in target.map { screen.displayLink(target: $0, selector: selector) } }
        link?.isPaused = isPaused
        link?.add(to: .main, forMode: .common)
    }
}
