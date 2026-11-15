import AppKit

extension LiveNotePopover {
    /// How long the words and the ↩ take to dim or come back as the note loses or takes the keys.
    static let focusFade: TimeInterval = 0.18
    /// How long a note waits for macOS's prompts to be answered before it stops waiting to take the keys back.
    static let promptWait: Duration = .seconds(600)

    /// The keys went to a prompt of macOS's own, which comes up over the person's app. Once no prompt
    /// is on the screen, the note takes them back, unless the person went to another app meanwhile.
    func takeKeysAfterPrompts() {
        let app = FocusReturn.shared.previousApp
        Task { @MainActor [weak self] in
            let deadline = ContinuousClock.now + Self.promptWait
            repeat {
                try? await Task.sleep(for: .milliseconds(250))
                guard self != nil, ContinuousClock.now < deadline else { return }
            } while !SystemPrompts.windowIDs().isEmpty
            let front = NSWorkspace.shared.frontmostApplication
            guard let self, front == app || front == NSRunningApplication.current else { return }
            Log.write("[live-ink] note takes back the keys after macOS's prompt")
            self.takeKeys()
        }
    }
}
