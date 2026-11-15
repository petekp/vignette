import AppKit

extension LiveNotePopover {
    /// How long the words and the ↩ take to dim or come back as the note loses or takes the keys.
    static let focusFade: TimeInterval = 0.18
    /// How long a note waits for macOS's prompts to be answered before it stops waiting to take the keys back.
    static let promptWait: Duration = .seconds(600)
    /// How long a prompt's window may stay listed after the keys left its process, as it closes.
    static let promptClosing: Duration = .seconds(1)

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            send()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onEscape?()
            return true
        case #selector(NSResponder.moveDown(_:)):
            showTargets()
            return true
        case #selector(NSResponder.insertTab(_:)):
            step(backward: false)
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            step(backward: true)
            return true
        default:
            return false
        }
    }

    /// The keys went to a prompt of macOS's own, which comes up over the person's app. Once the
    /// prompt has left and the keys are back with that app, the note takes them. The keys reaching
    /// any other app, or that app while the prompt stays up, is the person moving on, so it stops.
    func takeKeysAfterPrompts() {
        guard promptWaiting == nil else { return }
        let app = FocusReturn.shared.previousApp
        promptWaiting = Task { @MainActor [weak self] in
            defer { self?.promptWaiting = nil }
            let deadline = ContinuousClock.now + Self.promptWait
            var keysBack: ContinuousClock.Instant?
            while ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled else { return }
                let front = NSWorkspace.shared.frontmostApplication
                guard !SystemPrompts.isPromptApp(front) else { keysBack = nil; continue }
                let isPersonsApp = front == NSRunningApplication.current || (app != nil && front == app)
                guard isPersonsApp else { return }
                if !SystemPrompts.windowIDs().isEmpty {
                    let since = keysBack ?? .now
                    keysBack = since
                    if ContinuousClock.now - since < Self.promptClosing { continue }
                    return
                }
                Log.write("[live-ink] note takes back the keys after macOS's prompt")
                takeKeys()
                return
            }
        }
    }
}
