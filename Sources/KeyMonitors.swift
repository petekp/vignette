import AppKit

/// NSEvent monitors that watch keys pressed in other apps, which macOS reports only to an app trusted
/// for Accessibility. They are installed once the app is trusted, checked every 2 s, and this never
/// prompts: macOS's dialog arriving unasked during a launch is the one people dismiss, so only a
/// button the person pressed raises it (`Accessibility.request()`).
@MainActor
final class KeyMonitors {
    private var monitors: [Any] = []
    private var retry: Timer?

    /// `tag` and `name` say what is waiting, in the `[<tag>] <name> needs Accessibility permission` line.
    init(tag: String, name: String, install: @escaping () -> [Any?]) {
        if ModifierTap.trusted(prompt: false) {
            monitors = install().compactMap { $0 }
            return
        }
        Log.write("[\(tag)] \(name) needs Accessibility permission; waiting for it")
        // Timer.scheduledTimer runs its block on the run loop it is scheduled on: the main one, here.
        retry = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, ModifierTap.trusted(prompt: false) else { return }
                self.retry?.invalidate()
                self.monitors = install().compactMap { $0 }
                Log.write("[\(tag)] Accessibility granted; \(name) active")
            }
        }
    }

    /// The global and the local `flagsChanged` monitor, for `install`. While Vignette is active both
    /// report one event, and the second can arrive after a later event, so only an event newer than
    /// the last reaches `handler`.
    static func flagsChanged(_ handler: @escaping (NSEvent) -> Void) -> [Any?] {
        var last: TimeInterval = -1
        let newer: (NSEvent) -> Void = { event in
            guard event.timestamp > last else { return }
            last = event.timestamp
            handler(event)
        }
        return [
            NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: newer),
            NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { newer($0); return $0 },
        ]
    }

    isolated deinit {
        retry?.invalidate()
        monitors.forEach { NSEvent.removeMonitor($0) }
    }
}
