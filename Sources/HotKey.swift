import Carbon
import Foundation

/// Global hotkey via Carbon. Works without Accessibility permission. `hold` fires as well when
/// the key is kept down for `holdSeconds`.
@MainActor
final class HotKey {
    private var ref: EventHotKeyRef?
    private let action: () -> Void
    private let hold: (() -> Void)?
    private let holdSeconds: TimeInterval
    /// Tells this key's events from another `HotKey`'s.
    private let id: UInt32
    private static var lastID: UInt32 = 0
    /// Every key there is, by its id, for the one handler that hears every hotkey's events.
    private static var keys: [UInt32: WeakKey] = [:]
    private static var handler: EventHandlerRef?
    private var holdTimer: Timer?
    private var isDown = false
    /// `RegisterEventHotKey`'s answer. It is noErr for a combination macOS or another app already
    /// uses (measured on macOS 15 with ⌘⇧3, ⌃Space and Raycast's ⌥Space), so it proves nothing
    /// about the keys reaching this app; only an invalid key or modifier fails it.
    private(set) var status: OSStatus = noErr

    init(keyCode: UInt32, modifiers: UInt32, holdSeconds: TimeInterval = 0.4, action: @escaping () -> Void, hold: (() -> Void)? = nil) {
        self.action = action
        self.hold = hold
        self.holdSeconds = holdSeconds
        Self.lastID += 1
        id = Self.lastID
        Self.installHandler()
        Self.keys[id] = WeakKey(key: self)
        let hotKeyID = EventHotKeyID(signature: Identity.hotKeySignature, id: id)
        status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
    }

    /// The one handler for every `HotKey`, installed with the first and kept for the app's life.
    private static func installHandler() {
        guard handler == nil else { return }
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        // Carbon delivers these on the main run loop, like the rest of AppKit's event handling.
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var fired = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &fired)
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            return MainActor.assumeIsolated {
                guard fired.signature == Identity.hotKeySignature, let key = HotKey.keys[fired.id]?.key else { return OSStatus(eventNotHandledErr) }
                if pressed { key.pressed() } else { key.released() }
                return noErr
            }
        }, 2, &specs, nil, &handler)
    }

    private struct WeakKey { weak var key: HotKey? }

    private func pressed() {
        // A held key can deliver the press again (auto-repeat); only the first counts until the release.
        guard !isDown else { return }
        isDown = true
        action()
        guard let hold else { return }
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: holdSeconds, repeats: false) { _ in
            MainActor.assumeIsolated { hold() }
        }
    }

    private func released() {
        isDown = false
        holdTimer?.invalidate()
    }

    // Isolated so `ref` (a non-Sendable Carbon pointer) can be read without hopping actors.
    isolated deinit {
        holdTimer?.invalidate()
        if let ref { UnregisterEventHotKey(ref) }
        Self.keys[id] = nil
    }
}
