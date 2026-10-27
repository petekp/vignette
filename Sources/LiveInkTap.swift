import AppKit

/// Takes the pointer's presses, drags, releases and moves from the window server while live ink is
/// inking, before any app hears them, and hands them to the inking: an active event tap at the
/// session level, which drops each event it takes.
///
/// An open menu holds an event capture, so it hears every press on the screen, whatever window is
/// under the pointer. With the overlay taking the presses, the first press of a stroke closed a menu
/// being drawn on. With this tap the menu stays open and highlights nothing as the pen passes over its
/// items, and the pointer still moves (measured 2026-10-26 in a VM, on Finder's File menu). The same
/// holds for anything else that closes when a press lands elsewhere.
///
/// It exists only while inking: made as inking starts and stopped as it ends, since while it is on no
/// app on the Mac hears a click. A process that exits takes its taps with it. macOS makes one only for
/// an app trusted for Accessibility, which the chord needs already; without it `start` answers nil and
/// the overlay takes the presses itself.
@MainActor
final class LiveInkTap {
    private let link: Link
    private var source: CFRunLoopSource?
    private let take: (LiveInkOverlay.Input) -> Void

    private init(take: @escaping (LiveInkOverlay.Input) -> Void) {
        self.take = take
        link = Link()
    }

    /// The events taken. Right and other buttons are taken and dropped too, as the overlay takes them
    /// while inking, so their presses do not close a menu either.
    private static let types: [CGEventType] = [
        .leftMouseDown, .leftMouseDragged, .leftMouseUp, .mouseMoved,
        .rightMouseDown, .rightMouseDragged, .rightMouseUp, .otherMouseDown, .otherMouseDragged, .otherMouseUp,
    ]

    /// Starts taking events and handing each to `take`, on the main thread, in global top-left points.
    static func start(taking take: @escaping (LiveInkOverlay.Input) -> Void) -> LiveInkTap? {
        let tap = LiveInkTap(take: take)
        tap.link.tap = tap
        let mask = types.reduce(CGEventMask(0)) { $0 | CGEventMask(1) << $1.rawValue }
        // Retained for the callback until `stop` lets go of it on the tap's thread.
        let info = Unmanaged.passRetained(tap.link)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: callback, userInfo: info.toOpaque()) else {
            info.release()
            return nil
        }
        tap.link.port = port
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(TapThread.shared.loop, source, .commonModes)
        CFRunLoopWakeUp(TapThread.shared.loop)
        CGEvent.tapEnable(tap: port, enable: true)
        tap.source = source
        return tap
    }

    func stop() {
        guard let port = link.takePort() else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        let loop = TapThread.shared.loop
        if let source { CFRunLoopRemoveSource(loop, source, .commonModes) }
        CFMachPortInvalidate(port)
        source = nil
        // A callback under way finishes before a block queued on its thread runs.
        let info = Unmanaged.passUnretained(link)
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { info.release() }
        CFRunLoopWakeUp(loop)
    }

    isolated deinit {
        stop()
    }

    /// What the callback reaches from the tap's thread: the port, to turn the tap on again, and the tap,
    /// which it hands events to on the main thread.
    private final class Link: @unchecked Sendable {
        private let lock = NSLock()
        private var _port: CFMachPort?
        weak var tap: LiveInkTap?

        var port: CFMachPort? {
            get { lock.withLock { _port } }
            set { lock.withLock { _port = newValue } }
        }

        func takePort() -> CFMachPort? {
            lock.withLock {
                defer { _port = nil }
                return _port
            }
        }
    }

    /// The thread the callback runs on. macOS turns a tap off when its callback is slow to answer, and
    /// the main thread can be busy for longer than it waits: in a VM, starting to ink held it for
    /// 4.8 s, the tap went off, and the menu under the ink highlighted an item.
    private final class TapThread: Thread, @unchecked Sendable {
        static let shared = TapThread()
        private let started = DispatchSemaphore(value: 0)
        private var runLoop: CFRunLoop?

        /// The thread's run loop, once it runs.
        var loop: CFRunLoop {
            if runLoop == nil {
                start()
                started.wait()
            }
            return runLoop!
        }

        private override init() {
            super.init()
            name = "live ink tap"
            qualityOfService = .userInteractive
        }

        override func main() {
            runLoop = CFRunLoopGetCurrent()
            // A port keeps the run loop waiting while no tap's source is on it.
            RunLoop.current.add(Port(), forMode: .common)
            started.signal()
            while true { RunLoop.current.run() }
        }
    }

    /// Runs on the tap's thread, and only hands the event on: whatever it leads to happens on the main
    /// thread, after the window server has the answer to drop it.
    private static let callback: CGEventTapCallBack = { _, type, event, info in
        guard let info else { return Unmanaged.passUnretained(event) }
        let link = Unmanaged<Link>.fromOpaque(info).takeUnretainedValue()
        let point = event.location
        let input: LiveInkOverlay.Input
        switch type {
        case .leftMouseDown: input = .pressed(point)
        case .leftMouseDragged: input = .dragged(point)
        case .leftMouseUp: input = .released(point)
        case .mouseMoved: input = .moved(point)
        case .tapDisabledByTimeout:
            // The tap exists only while inking, so it goes back on.
            if let port = link.port { CGEvent.tapEnable(tap: port, enable: true) }
            Log.write("[live-ink] tap turned off by macOS: too slow; on again")
            return Unmanaged.passUnretained(event)
        case .tapDisabledByUserInput:
            Log.write("[live-ink] tap turned off by macOS: user input; the overlay takes the presses")
            return Unmanaged.passUnretained(event)
        default: return nil
        }
        DispatchQueue.main.async { MainActor.assumeIsolated { link.tap?.handOn(input) } }
        return nil
    }

    private func handOn(_ input: LiveInkOverlay.Input) {
        guard source != nil else { return }
        take(input)
    }
}
