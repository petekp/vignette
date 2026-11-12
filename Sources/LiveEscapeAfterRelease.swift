import AppKit

/// Right after the chord is let go, the person has not gone anywhere else, so Esc is meant for live
/// ink wherever the pointer is (`LiveEscape.Snapshot.justLetGo`). This watches for them going
/// somewhere: a mouse press off the ink, in any app, or another app becoming active. The activation
/// Vignette causes itself, handing the keys back to the app the person was in (`FocusReturn.restore`),
/// does not count when it comes within `handBackLeeway` of the hand-back. The person switching back
/// to that app later does. It holds a global monitor of mouse presses, which needs no permission,
/// from the release until it ends, and lets go of it then.
@MainActor
final class LiveEscapeAfterRelease {
    private var pressWatch: Any?
    private var activationWatch: NSObjectProtocol?
    private let ended: (String) -> Void
    static let handBackLeeway: TimeInterval = 0.5
    /// The last ask id given when the chord was let go. Esc stops only asks after it.
    let asksBefore: LiveAsks.Ask.ID

    /// `returningTo` is the app the keys go back to; `isOnInk` says whether the pointer is on live ink.
    init(returningTo app: NSRunningApplication?, asksBefore: LiveAsks.Ask.ID, isOnInk: @escaping () -> Bool,
         ended: @escaping (String) -> Void) {
        self.ended = ended
        self.asksBefore = asksBefore
        pressWatch = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard !isOnInk() else { return }
                self?.end(because: "a press off the ink")
            }
        }
        activationWatch = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let activated = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let activated, activated != NSRunningApplication.current else { return }
                let handedBack = FocusReturn.shared.handedBackAt.map { ProcessInfo.processInfo.systemUptime - $0 < Self.handBackLeeway }
                if activated == app, handedBack == true { return }
                self?.end(because: "\(activated.localizedName ?? "another app") became active")
            }
        }
    }

    isolated deinit {
        stopWatching()
    }

    private func end(because reason: String) {
        stopWatching()
        ended(reason)
    }

    private func stopWatching() {
        if let pressWatch { NSEvent.removeMonitor(pressWatch) }
        pressWatch = nil
        if let activationWatch { NSWorkspace.shared.notificationCenter.removeObserver(activationWatch) }
        activationWatch = nil
    }
}
