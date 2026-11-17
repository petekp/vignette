import CoreGraphics

extension LiveNoteCards {
    /// Whether `window` is the frontmost window of the frontmost app, `frontApp`, in `windows`, the
    /// on-screen window list front to back. A minimized window, or one on another Space, is not listed.
    nonisolated static func isInFront(_ window: CGWindowID, frontApp: pid_t?, windows: [[String: Any]]) -> Bool {
        guard let frontApp else { return false }
        return WindowList.front(of: frontApp, in: windows) == window
    }

    /// Which of the notes of one window changed under their ink, from the window as `after` and
    /// `again`, a moment later, captured it; `again` rules out what moves on its own. A note whose
    /// window has changed size since is `uncompared`, as is one whose part the capture lacks.
    nonisolated static func compare(_ members: [(request: String, before: Before)], after: (image: CGImage, frame: CGRect),
                                    again: (image: CGImage, frame: CGRect)) -> (changed: Set<String>, uncompared: Set<String>) {
        var changed = Set<String>(), uncompared = Set<String>()
        for (request, before) in members {
            guard abs(after.frame.width - before.windowSize.width) < 1, abs(after.frame.height - before.windowSize.height) < 1 else {
                Log.write("[live-ink] can't tell whether it landed: the window changed size")
                uncompared.insert(request)
                continue
            }
            let region = before.region.offsetBy(dx: after.frame.minX, dy: after.frame.minY)
            let regionAgain = before.region.offsetBy(dx: again.frame.minX, dy: again.frame.minY)
            let ink = before.ink.offsetBy(dx: -before.region.minX, dy: -before.region.minY)
            guard let now = LiveChange.crop(after.image, frame: after.frame, to: region) else {
                uncompared.insert(request)
                continue
            }
            let later = LiveChange.crop(again.image, frame: again.frame, to: regionAgain)
            switch LiveChange.compare(before: before.picture, after: now, again: later, size: region.size, ink: ink) {
            case .changed(let share, _):
                Log.write("[live-ink] landed changed=\(String(format: "%.3f", share))")
                changed.insert(request)
            case .unchanged(let share):
                Log.write("[live-ink] nothing changed under the ink changed=\(String(format: "%.3f", share))")
            }
        }
        return (changed, uncompared)
    }
}
