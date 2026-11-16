import AppKit

/// Whether a chord of modifiers held on their own, Control and Option for live ink, is down. The
/// chord counts only while exactly its modifiers are held. Any key pressed during it, or another
/// modifier joining, ends it as the start of a keyboard shortcut, such as a window manager's
/// Control-Option-arrow, and it begins again only once its modifiers are let go. A larger chord held
/// first, such as ⌘⌃⌥, counts as one: letting go of ⌘ does not begin it.
struct HeldChord {
    private let flags: NSEvent.ModifierFlags
    private(set) var isHeld = false
    private var waitingForRelease = false

    init(_ flags: NSEvent.ModifierFlags) {
        self.flags = flags.intersection(Self.modifiers)
    }

    enum Change: Equatable {
        case began
        /// One of its modifiers was let go.
        case ended
        /// A key went down, or another modifier joined: the chord was the start of a shortcut.
        case interrupted
    }

    /// The modifiers a chord is made of.
    static let modifiers: NSEvent.ModifierFlags = [.shift, .control, .option, .command]

    mutating func flagsChanged(_ held: NSEvent.ModifierFlags) -> Change? {
        let held = held.intersection(Self.modifiers)
        if isHeld {
            guard held != flags else { return nil }
            isHeld = false
            guard held.isSuperset(of: flags) else { return .ended }
            waitingForRelease = true
            return .interrupted
        }
        if held.isStrictSuperset(of: flags) { waitingForRelease = true }
        if waitingForRelease {
            if held.isDisjoint(with: flags) { waitingForRelease = false }
            return nil
        }
        guard held == flags else { return nil }
        isHeld = true
        return .began
    }

    mutating func keyDown() -> Change? {
        guard isHeld else { return nil }
        isHeld = false
        waitingForRelease = true
        return .interrupted
    }

    /// Whether `held` is the chord's modifiers and no others.
    func isExactly(_ held: NSEvent.ModifierFlags) -> Bool { held.intersection(Self.modifiers) == flags }
}

/// Watches the keyboard for a `HeldChord` and says when it begins and ends.
///
/// It hears the modifiers through a listen-only event tap (`FlagsTap`), and through NSEvent monitors
/// when the tap cannot be had. A monitor hears nothing while one of Vignette's own menus is open: a
/// global monitor hears only events sent to other apps, and a local monitor is not called for events
/// that menu tracking consumes (`NSEvent.addLocalMonitorForEvents`'s documentation). Measured
/// 2026-11-16: with Vignette's status menu open, ⌃⌥ began no chord, while another process's monitor
/// and tap both heard it.
///
/// A key another app takes as a shortcut, as a window manager takes Control-Option-arrow, reaches no
/// event monitor (measured on macOS 15 with a Carbon hotkey). The HID state still counts it, and
/// counts no modifier, so while the chord is held it is asked every 50 ms whether a key has gone down
/// since the chord began, and whether the chord's modifiers are still down: a release no monitor
/// heard, with Accessibility taken away or Secure Event Input on, would leave inking taking every click.
/// The poll cannot tell which key went down, so a key it reads ends the chord one poll later: by then
/// a hotkey held on the chord's own modifiers, as live ink holds Esc, has had its press. A key read as
/// the chord's modifiers change was a shortcut's, so the chord ends then, as cut short.
@MainActor
final class ModifierChord {
    private var chord: HeldChord
    private var monitors: KeyMonitors?
    private var flagsTap: FlagsTap?
    private let tag: String
    private let name: String
    private var keyWatch: Timer?
    /// The event that began the chord, in seconds since the Mac started.
    private var beganAt: TimeInterval = 0
    /// A key went down since the chord began, read at the last poll, which ends the chord at the next,
    /// or at a change of modifiers before it, as cut short.
    private var keyRead = false
    private let changed: (HeldChord.Change) -> Void

    var isHeld: Bool { chord.isHeld }

    /// `tag` and `name` are for the `KeyMonitors` lines.
    init(_ flags: NSEvent.ModifierFlags, tag: String, name: String, changed: @escaping (HeldChord.Change) -> Void) {
        chord = HeldChord(flags)
        self.changed = changed
        self.tag = tag
        self.name = name
        monitors = KeyMonitors(tag: tag, name: name) { [weak self] in self?.install() ?? [] }
    }

    isolated deinit {
        keyWatch?.invalidate()
    }

    /// Runs once the app is trusted for Accessibility, which the tap needs too.
    private func install() -> [Any?] {
        let heard: (NSEvent) -> Void = { [weak self] in self?.flagsChanged($0) }
        guard CGPreflightListenEventAccess() else {
            Log.write("[\(tag)] \(name): no access to listen to keys; event monitors hear the chord")
            return KeyMonitors.flagsChanged(heard)
        }
        if let tap = FlagsTap.start(tag: tag, heard) {
            flagsTap = tap
            return []
        }
        Log.write("[\(tag)] \(name): macOS refused the modifier tap; event monitors hear the chord")
        return KeyMonitors.flagsChanged(heard)
    }

    /// A key went down since the chord began, by the HID state, which counts keys no monitor sees.
    private var keyWentDown: Bool {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown) < ProcessInfo.processInfo.systemUptime - beganAt
    }

    private func flagsChanged(_ event: NSEvent) {
        if keyRead || chord.isHeld && !chord.isExactly(event.modifierFlags) && keyWentDown, let change = chord.keyDown() {
            _ = chord.flagsChanged(event.modifierFlags)
            return apply(change)
        }
        guard let change = chord.flagsChanged(event.modifierFlags) else { return }
        if change == .began { beganAt = event.timestamp }
        apply(change)
    }

    private func apply(_ change: HeldChord.Change) {
        keyWatch?.invalidate()
        keyWatch = nil
        keyRead = false
        if change == .began {
            let watch = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkKeys() }
            }
            // The common modes, so it runs during a menu's or a drag's tracking too.
            RunLoop.main.add(watch, forMode: .common)
            keyWatch = watch
        }
        changed(change)
    }

    private func checkKeys() {
        let held = NSEvent.ModifierFlags(rawValue: UInt(CGEventSource.flagsState(.hidSystemState).rawValue))
        if keyWentDown {
            if keyRead || !chord.isExactly(held), let change = chord.keyDown() { _ = chord.flagsChanged(held); return apply(change) }
            keyRead = true
        }
        if let change = chord.flagsChanged(held) { apply(change) }
    }
}

/// A listen-only event tap at the head of the session's taps that hears every change of modifiers,
/// whichever app has the keys and whatever menu is open. It drops and delays nothing. macOS gives a
/// listen-only tap on keys only to a process with listen access (`CGPreflightListenEventAccess`), so
/// it is made only once that answers true, which never prompts. Its callback runs on `EventTapThread`
/// and only hands a copy of each event to the main thread.
@MainActor
private final class FlagsTap {
    private let link = Link()
    private var source: CFRunLoopSource?
    private let heard: (NSEvent) -> Void

    private init(heard: @escaping (NSEvent) -> Void) {
        self.heard = heard
    }

    /// Nil when macOS refuses the tap.
    static func start(tag: String, _ heard: @escaping (NSEvent) -> Void) -> FlagsTap? {
        let tap = FlagsTap(heard: heard)
        tap.link.tap = tap
        tap.link.tag = tag
        let info = Unmanaged.passRetained(tap.link)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                           eventsOfInterest: CGEventMask(1) << CGEventType.flagsChanged.rawValue,
                                           callback: callback, userInfo: info.toOpaque()) else {
            info.release()
            return nil
        }
        tap.link.port = port
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(EventTapThread.shared.loop, source, .commonModes)
        CFRunLoopWakeUp(EventTapThread.shared.loop)
        CGEvent.tapEnable(tap: port, enable: true)
        tap.source = source
        return tap
    }

    func stop() {
        guard let port = link.takePort() else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        let loop = EventTapThread.shared.loop
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

    private func hand(_ event: CGEvent) {
        guard source != nil, let event = NSEvent(cgEvent: event) else { return }
        heard(event)
    }

    /// What the callback reaches from the tap's thread.
    private final class Link: @unchecked Sendable {
        private let lock = NSLock()
        private var _port: CFMachPort?
        weak var tap: FlagsTap?
        var tag = ""

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

    /// A copy of a tapped event, which the tap's thread hands to the main thread and no longer touches.
    private struct Copy: @unchecked Sendable {
        let event: CGEvent
    }

    private static let callback: CGEventTapCallBack = { _, type, event, info in
        guard let info else { return Unmanaged.passUnretained(event) }
        let link = Unmanaged<Link>.fromOpaque(info).takeUnretainedValue()
        switch type {
        case .flagsChanged:
            guard let copy = event.copy().map(Copy.init) else { break }
            DispatchQueue.main.async { MainActor.assumeIsolated { link.tap?.hand(copy.event) } }
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // `stop` takes the port before it turns the tap off, which comes here too.
            guard let port = link.port else { break }
            CGEvent.tapEnable(tap: port, enable: true)
            Log.write("[\(link.tag)] modifier tap turned off by macOS (\(type == .tapDisabledByTimeout ? "too slow" : "user input")); on again")
        default: break
        }
        return Unmanaged.passUnretained(event)
    }
}
