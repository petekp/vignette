import AppKit
@preconcurrency import ApplicationServices

/// Fires when one modifier key (right Shift, say) is tapped twice in quick succession with nothing
/// else pressed in between. Modifier taps are invisible to Carbon hotkeys, so this watches key
/// events with NSEvent monitors, which macOS only delivers to apps trusted for Accessibility.
/// `hold` fires as well when the last tap is kept down for `holdSeconds`.
@MainActor
final class ModifierTap {
    private let keyCode: UInt16
    private let flag: NSEvent.ModifierFlags
    private let taps: Int
    private let window: TimeInterval
    private let action: () -> Void
    private let hold: (() -> Void)?
    private let holdSeconds: TimeInterval
    private var monitors: KeyMonitors?
    private var count = 0
    private var last: TimeInterval = 0
    /// The timestamp of the last flags change counted. While Vignette is active, the global and the
    /// local monitor can both report the same event, and counted twice a double tap fired twice.
    private var lastEvent: TimeInterval = -1
    private var holdTimer: Timer?

    /// Key codes: 56 left shift, 60 right shift, 55 left cmd, 54 right cmd, 58 left opt,
    /// 61 right opt, 59 left ctrl, 62 right ctrl.
    init(keyCode: UInt16, taps: Int = 2, window: TimeInterval = 0.4, holdSeconds: TimeInterval = 0.4,
         action: @escaping () -> Void, hold: (() -> Void)? = nil) {
        self.keyCode = keyCode
        self.taps = taps
        self.window = window
        self.holdSeconds = holdSeconds
        self.action = action
        self.hold = hold
        flag = Self.flag(forKeyCode: keyCode)
        // The double tap is the default shortcut, so this runs during every launch, and never
        // prompts: the setup window raises macOS's dialog, as the answer to a choice just made.
        monitors = KeyMonitors(tag: "hotkey", name: "modifier tap") { [weak self] in self?.install() ?? [] }
    }

    isolated deinit {
        holdTimer?.invalidate()
    }

    /// The modifier a modifier key's code sets, either side of the keyboard.
    nonisolated static func flag(forKeyCode keyCode: UInt16) -> NSEvent.ModifierFlags {
        switch keyCode {
        case 56, 60: .shift
        case 55, 54: .command
        case 58, 61: .option
        default: .control
        }
    }

    nonisolated static func trusted(prompt: Bool) -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): prompt] as CFDictionary)
    }

    private func install() -> [Any?] {
        let flags: (NSEvent) -> Void = { [weak self] e in self?.flagsChanged(e) }
        let reset: (NSEvent) -> Void = { [weak self] _ in self?.count = 0; self?.holdTimer?.invalidate() }
        return [
            NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flags),
            NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { flags($0); return $0 },
            NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown], handler: reset),
            NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { reset($0); return $0 },
        ]
    }

    private func flagsChanged(_ event: NSEvent) {
        guard event.timestamp != lastEvent else { return }
        lastEvent = event.timestamp
        guard event.keyCode == keyCode else { count = 0; return }
        let mods = event.modifierFlags.intersection([.shift, .command, .option, .control])
        if !mods.contains(flag) { holdTimer?.invalidate(); return }   // released before the hold
        guard mods == flag else { return }   // another modifier is held
        let now = event.timestamp
        count = now - last < window ? count + 1 : 1
        last = now
        if count >= taps {
            count = 0
            action()
            guard let hold else { return }
            holdTimer?.invalidate()
            holdTimer = Timer.scheduledTimer(withTimeInterval: holdSeconds, repeats: false) { _ in
                MainActor.assumeIsolated { hold() }
            }
        }
    }
}
