import AppKit

/// Whether a chord of modifiers held on their own, Control and Option for live ink, is down. The
/// chord counts only while exactly its modifiers are held. Any key pressed during it, or another
/// modifier joining, ends it as the start of a keyboard shortcut, such as a window manager's
/// Control-Option-arrow, and it begins again only once its modifiers are let go. A larger chord held
/// first, such as ⌘⌃⌥, counts as one: letting go of ⌘ does not begin it.
struct HeldChord: Equatable {
    let flags: NSEvent.ModifierFlags
    private(set) var isHeld = false
    private var waitingForRelease = false

    init(_ flags: NSEvent.ModifierFlags) {
        self.flags = flags.intersection(Self.modifiers)
    }

    enum Change: Equatable { case began, ended }

    /// The modifiers a chord is made of.
    static let modifiers: NSEvent.ModifierFlags = [.shift, .control, .option, .command]

    mutating func flagsChanged(_ held: NSEvent.ModifierFlags) -> Change? {
        let held = held.intersection(Self.modifiers)
        if isHeld {
            guard held != flags else { return nil }
            isHeld = false
            if held.isSuperset(of: flags) { waitingForRelease = true }
            return .ended
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
        return .ended
    }
}

/// Watches the keyboard for a `HeldChord` and says when it begins and ends.
///
/// A key another app takes as a shortcut, as a window manager takes Control-Option-arrow, reaches no
/// event monitor (measured on macOS 15 with a Carbon hotkey). The HID state still counts it, and
/// counts no modifier, so while the chord is held it is asked every 50 ms whether a key has gone down
/// since the chord began.
@MainActor
final class ModifierChord {
    private var chord: HeldChord
    private var monitors: KeyMonitors?
    private var keyWatch: Timer?
    /// The event that began the chord, in seconds since the Mac started.
    private var beganAt: TimeInterval = 0
    private var lastEvent: TimeInterval = 0
    private let changed: (HeldChord.Change) -> Void

    var isHeld: Bool { chord.isHeld }

    /// `tag` and `name` are for the `KeyMonitors` lines.
    init(_ flags: NSEvent.ModifierFlags, tag: String, name: String, changed: @escaping (HeldChord.Change) -> Void) {
        chord = HeldChord(flags)
        self.changed = changed
        monitors = KeyMonitors(tag: tag, name: name) { [weak self] in self?.install() ?? [] }
    }

    isolated deinit {
        keyWatch?.invalidate()
    }

    private func install() -> [Any?] {
        let flags: (NSEvent) -> Void = { [weak self] event in self?.flagsChanged(event) }
        return [
            NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flags),
            NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { flags($0); return $0 },
        ]
    }

    /// The global and the local monitor can both report one event while Vignette is active, and the
    /// second can arrive after a later event: only an event newer than the last is read.
    private func flagsChanged(_ event: NSEvent) {
        guard event.timestamp > lastEvent else { return }
        lastEvent = event.timestamp
        guard let change = chord.flagsChanged(event.modifierFlags) else { return }
        if change == .began { beganAt = event.timestamp }
        apply(change)
    }

    private func apply(_ change: HeldChord.Change) {
        keyWatch?.invalidate()
        keyWatch = nil
        if change == .began {
            keyWatch = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkKeys() }
            }
        }
        changed(change)
    }

    private func checkKeys() {
        let sinceKey = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
        guard sinceKey < ProcessInfo.processInfo.systemUptime - beganAt, let change = chord.keyDown() else { return }
        apply(change)
    }
}
