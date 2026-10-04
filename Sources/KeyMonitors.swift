import AppKit

/// NSEvent monitors that watch keys pressed in other apps, which macOS reports only to an app trusted
/// for Accessibility. They are installed once the app is trusted, checked every 2 s, and this never
/// prompts: macOS's dialog arriving unasked during a launch is the one people dismiss, so only a
/// button the person pressed raises it (`Accessibility.request()`).
@MainActor
final class KeyMonitors {
    private var monitors: [Any] = []
    private var retry: Timer?
    private let install: () -> [Any?]

    /// `tag` and `name` say what is waiting, in the `[<tag>] <name> needs Accessibility permission` line.
    init(tag: String, name: String, install: @escaping () -> [Any?]) {
        self.install = install
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
                self.monitors = self.install().compactMap { $0 }
                Log.write("[\(tag)] Accessibility granted; \(name) active")
            }
        }
    }

    isolated deinit {
        retry?.invalidate()
        monitors.forEach { NSEvent.removeMonitor($0) }
    }
}
