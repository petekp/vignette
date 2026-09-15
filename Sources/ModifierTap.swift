import AppKit
import ApplicationServices

/// Fires when one modifier key (right Shift, say) is tapped twice in quick succession with nothing
/// else pressed in between. Modifier taps are invisible to Carbon hotkeys, so this watches key
/// events with NSEvent monitors, which macOS only delivers to apps trusted for Accessibility.
final class ModifierTap {
    private let keyCode: UInt16
    private let flag: NSEvent.ModifierFlags
    private let taps: Int
    private let window: TimeInterval
    private let action: () -> Void
    private var monitors: [Any] = []
    private var count = 0
    private var last: TimeInterval = 0
    private var retry: Timer?

    /// Key codes: 56 left shift, 60 right shift, 55 left cmd, 54 right cmd, 58 left opt,
    /// 61 right opt, 59 left ctrl, 62 right ctrl.
    init(keyCode: UInt16, taps: Int = 2, window: TimeInterval = 0.4, action: @escaping () -> Void) {
        self.keyCode = keyCode
        self.taps = taps
        self.window = window
        self.action = action
        switch keyCode {
        case 56, 60: flag = .shift
        case 55, 54: flag = .command
        case 58, 61: flag = .option
        default: flag = .control
        }
        if ModifierTap.trusted(prompt: true) { install() } else {
            Log.write("[hotkey] modifier tap needs Accessibility permission; waiting for it")
            retry = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                guard let self, ModifierTap.trusted(prompt: false) else { return }
                self.retry?.invalidate()
                self.install()
                Log.write("[hotkey] Accessibility granted; modifier tap active")
            }
        }
    }

    deinit {
        retry?.invalidate()
        monitors.forEach { NSEvent.removeMonitor($0) }
    }

    static func trusted(prompt: Bool) -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): prompt] as CFDictionary)
    }

    private func install() {
        let flags: (NSEvent) -> Void = { [weak self] e in self?.flagsChanged(e) }
        let reset: (NSEvent) -> Void = { [weak self] _ in self?.count = 0 }
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flags),
            NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { flags($0); return $0 },
            NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown], handler: reset),
            NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { reset($0); return $0 },
        ].compactMap { $0 }
    }

    private func flagsChanged(_ event: NSEvent) {
        guard event.keyCode == keyCode else { count = 0; return }
        let mods = event.modifierFlags.intersection([.shift, .command, .option, .control])
        guard mods == flag else { return }   // a release, or another modifier is held
        let now = event.timestamp
        count = now - last < window ? count + 1 : 1
        last = now
        if count >= taps {
            count = 0
            action()
        }
    }
}
