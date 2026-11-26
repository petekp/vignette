import Foundation

/// Keep and Clear on an agent's marks on top of a screenshot (`PendingMarks`), as steps of the timeline.
extension UndoTimeline {
    /// The person kept the agent's marks `entry` on `key`: they joined its drawing as one step of its
    /// history. Kept in the editor, that step sits just below this one, so the editor's steps made
    /// after it come first and the editor's history ends one step shorter once this is undone.
    func kept(_ entry: PendingMarks.Entry, on key: ScreenshotKey) {
        let action = Action.unkeep(key: key, entry: entry, drawn: marks.drawn(key))
        guard let open = editor.open(), open.key == key else { return record(.keepMarks, action) }
        let joined = shown(open)
        var before = joined
        before.depth = max(0, joined.depth - 1)
        push(Step(name: .keepMarks, action: action, editor: joined, then: before))
        seen = open
    }

    /// The person cleared the agent's marks `entry` off `key`.
    func cleared(_ entry: PendingMarks.Entry, on key: ScreenshotKey) {
        record(.clearMarks, .unclear(key: key, entry: entry))
    }

    /// Runs a Keep or Clear step. None of them opens or closes the annotator.
    func runMarks(_ action: Action) {
        switch action {
        case .unkeep(let key, let entry, let drawn): unkeep(entry, on: current(key), drawn: drawn)
        case .rekeep(let key, let entry, let taken): rekeep(entry, on: current(key), taken: taken)
        case .unclear(let key, let entry): unclear(entry, on: current(key))
        case .reclear(let key, let entry): reclear(entry, on: current(key))
        default: break
        }
    }

    private func unkeep(_ entry: PendingMarks.Entry, on key: ScreenshotKey, drawn: String?) {
        guard marks.onTop(key) == nil else { return refuse(.keepMarks, "\(key.name) has other marks on top") }
        guard drawn == nil || marks.drawn(key) == drawn else { return refuse(.keepMarks, "\(key.name)'s drawing has changed since") }
        guard let taken = marks.takeBack(key) else { return refuse(.keepMarks, "\(key.name)'s drawing no longer ends with the marks") }
        moveLeftAt(key, by: -1)
        marks.setOnTop(entry, key)
        seen = editor.open()
        log(.keepMarks, "put marks=\(taken.step.changes.count) back on top of \(key.name)", [])
        record(.keepMarks, .rekeep(key: key, entry: entry, taken: taken))
    }

    private func rekeep(_ entry: PendingMarks.Entry, on key: ScreenshotKey, taken: TakenBackMarks) {
        guard marks.onTop(key)?.id == entry.id else { return refuse(.keepMarks, "\(key.name) has other marks on top") }
        guard marks.putBack(taken, key) else { return refuse(.keepMarks, "\(key.name)'s drawing could not be written") }
        moveLeftAt(key, by: 1)
        marks.setOnTop(nil, key)
        seen = editor.open()
        log(.keepMarks, "kept marks=\(taken.step.changes.count) on \(key.name)", [])
        record(.keepMarks, .unkeep(key: key, entry: entry, drawn: marks.drawn(key)))
    }

    /// A Keep's step taken off or put back on a screenshot the editor does not hold moves the top of
    /// its stored history, so its next opening does not read the change as steps lost from the bottom.
    private func moveLeftAt(_ key: ScreenshotKey, by steps: Int) {
        guard editor.open()?.key != key, let recorded = leftAt.keys.first(where: { current($0) == key }) else { return }
        leftAt[recorded, default: 0] += steps
    }

    private func unclear(_ entry: PendingMarks.Entry, on key: ScreenshotKey) {
        guard marks.onTop(key) == nil else { return refuse(.clearMarks, "\(key.name) has other marks on top") }
        marks.setOnTop(entry, key)
        log(.clearMarks, "put marks=\(entry.drawing.marks.count) back on top of \(key.name)", [])
        record(.clearMarks, .reclear(key: key, entry: entry))
    }

    private func reclear(_ entry: PendingMarks.Entry, on key: ScreenshotKey) {
        guard marks.onTop(key)?.id == entry.id else { return refuse(.clearMarks, "\(key.name) has other marks on top") }
        marks.setOnTop(nil, key)
        log(.clearMarks, "took marks=\(entry.drawing.marks.count) off \(key.name)", [])
        record(.clearMarks, .unclear(key: key, entry: entry))
    }
}
