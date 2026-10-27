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
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private let take: (LiveInkOverlay.Input) -> Void

    private init(take: @escaping (LiveInkOverlay.Input) -> Void) {
        self.take = take
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
        let mask = types.reduce(CGEventMask(0)) { $0 | CGEventMask(1) << $1.rawValue }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: callback,
                                           userInfo: Unmanaged.passUnretained(tap).toOpaque()) else { return nil }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap.port = port
        tap.source = source
        return tap
    }

    func stop() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(port)
        self.port = nil
        source = nil
    }

    isolated deinit {
        stop()
    }

    /// Runs on the main run loop. It only hands the event on: whatever the event leads to, inking ending
    /// and this tap stopping included, happens after the window server has the answer to drop it.
    private static let callback: CGEventTapCallBack = { _, type, event, info in
        guard let info else { return Unmanaged.passUnretained(event) }
        let tap = Unmanaged<LiveInkTap>.fromOpaque(info).takeUnretainedValue()
        let point = event.location
        let input: LiveInkOverlay.Input
        switch type {
        case .leftMouseDown: input = .pressed(point)
        case .leftMouseDragged: input = .dragged(point)
        case .leftMouseUp: input = .released(point)
        case .mouseMoved: input = .moved(point)
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            MainActor.assumeIsolated { tap.disabled(by: type) }
            return Unmanaged.passUnretained(event)
        default: return nil
        }
        DispatchQueue.main.async { MainActor.assumeIsolated { tap.handOn(input) } }
        return nil
    }

    private func handOn(_ input: LiveInkOverlay.Input) {
        guard port != nil else { return }
        take(input)
    }

    /// macOS turns a tap off when its callback is slow to answer, and when the person's input asks it
    /// to. Only a slow answer turns it back on, since the tap exists only while inking.
    private func disabled(by type: CGEventType) {
        guard let port else { return }
        if type == .tapDisabledByTimeout {
            CGEvent.tapEnable(tap: port, enable: true)
            Log.write("[live-ink] tap turned off by macOS: too slow; on again")
        } else {
            Log.write("[live-ink] tap turned off by macOS: user input; the overlay takes the presses")
        }
    }
}
