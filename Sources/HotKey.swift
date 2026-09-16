import Carbon
import Foundation

/// Global hotkey via Carbon. Works without Accessibility permission. `hold` fires as well when
/// the key is kept down for `holdSeconds`.
@MainActor
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private let hold: (() -> Void)?
    private let holdSeconds: TimeInterval
    private var holdTimer: Timer?

    init(keyCode: UInt32, modifiers: UInt32, holdSeconds: TimeInterval = 0.4, action: @escaping () -> Void, hold: (() -> Void)? = nil) {
        self.action = action
        self.hold = hold
        self.holdSeconds = holdSeconds
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        // Carbon delivers these on the main run loop, like the rest of AppKit's event handling.
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData else { return noErr }
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            MainActor.assumeIsolated {
                let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                if pressed { hotKey.pressed() } else { hotKey.holdTimer?.invalidate() }
            }
            return noErr
        }, 2, &specs, selfPtr, &handler)
        let id = EventHotKeyID(signature: Identity.hotKeySignature, id: 1)
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }

    private func pressed() {
        action()
        guard let hold else { return }
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: holdSeconds, repeats: false) { _ in
            MainActor.assumeIsolated { hold() }
        }
    }

    // Isolated so `ref`/`handler` (non-Sendable Carbon pointers) can be read without hopping actors.
    isolated deinit {
        holdTimer?.invalidate()
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
