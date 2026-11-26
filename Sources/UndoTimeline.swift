import AppKit

/// The undo timeline: Cmd+Z undoes the last thing Vignette did to a screenshot, in the stack or in
/// the annotator, and Shift+Cmd+Z redoes it, as Finder's Undo does. Delete's files come back from
/// the Trash with their drawings, and their cards come back where they were. Stitch's file goes to
/// the Trash, and the cards it took out of the column come back. Opening a screenshot in the
/// annotator and closing it are steps too: undoing a close opens it again, with its history, and
/// undoing an opening closes it. While a screenshot is in the editor, Cmd+Z undoes the editor's own
/// steps back to where this opening began (`EditorHistory`), and the next one goes on through the
/// timeline. The steps last while the app runs, through the stack closing and opening again. A step
/// whose file has moved since is used up with a beep and a log line, as Finder uses one up with an
/// alert.
@MainActor
final class UndoTimeline {
    var files = Files()
    var cards = Cards()
    var editor = Editor()
    private let beep: () -> Void
    /// Tells VoiceOver what an Undo or a Redo just did, in the Edit menu's words.
    var announce: (String) -> Void = { _ in }
    /// Oldest first: Cmd+Z runs the last.
    private var undoSteps: [Step] = []
    /// Oldest first: Shift+Cmd+Z runs the last.
    private var redoSteps: [Step] = []
    /// The step an Undo or a Redo is running.
    private var running: (step: Step, redoing: Bool)?
    /// How many steps each screenshot's history held to undo when it last left the editor. A file
    /// keeps at most `EditorHistory.maxSteps`, dropping the oldest, so one that opens with fewer
    /// moves every depth recorded for it down by as many.
    var leftAt: [ScreenshotKey: Int] = [:]
    /// The step that just ran could not, so there is nothing to announce.
    private var refused = false
    /// The name each file had when a step recorded it, to its name now, for the files Finder or
    /// another app renamed in the folder since.
    private var renamed: [ScreenshotKey: ScreenshotKey] = [:]
    /// The screenshot the run took out of the editor, until it opens the next one, which makes the
    /// two one step, or ends, which makes it a close.
    private var leaving: Shown?
    /// The editor's steps when the timeline last looked. A change since is a new step of the
    /// editor's, which ends what the timeline could redo.
    var seen: EditorPlace?
    /// What an Undo or a Redo asked the annotator for, until the run has done it: that is the step
    /// running, not a new one.
    private var asked: Asked?
    private enum Asked: Equatable { case open(ScreenshotKey), close }
    /// The screenshot the timeline saw open in the editor, until the run takes it out.
    private var inEditor: ScreenshotKey?
    /// The annotator is still carrying out an opening or a close, as behind a zoom springing back to
    /// the fit, and the timeline's next step is not known yet.
    private var busy: Bool { asked != nil || leaving != nil }

    init(beep: @escaping () -> Void = { NSSound.beep() }) {
        self.beep = beep
    }

    // MARK: Steps

    /// Delete: the files go to the Trash, and undoing it puts them back.
    func trash(_ shots: [Screenshot]) {
        let column = cards.column()
        let trashed = moveToTrash(shots)
        guard !trashed.isEmpty else {
            if redoing { refuse(.moveToTrash, "none of \(names(shots)) is in the folder") }
            return
        }
        if redoing { Log.write("[undo] redid \(Name.moveToTrash.rawValue): \(names(trashed.map(\.file.shot)))") }
        record(.moveToTrash, .putBack(trashed: trashed, column: column))
    }

    /// A stitch was written. `takenOut` are the pieces whose cards it took out of the column, and
    /// `column` the stack as it was before.
    func stitched(_ stitch: Screenshot, takenOut: [Screenshot], column: [ScreenshotKey]) {
        record(.stitch, .unstitch(stitch: stitch, pieces: takenOut, column: column))
    }

    /// Files renamed in the folder: the steps that name them follow.
    func rename(_ pairs: [(from: ScreenshotKey, to: ScreenshotKey)]) {
        guard !undoSteps.isEmpty || !redoSteps.isEmpty else {
            renamed = [:]
            return
        }
        for (old, new) in pairs where old != new {
            for (recorded, now) in renamed where now == old { renamed[recorded] = new }
            if renamed[old] == nil { renamed[old] = new }
        }
    }

    // MARK: The annotator

    /// The run took `key` out of the editor, by a park or an abandon. The editor keeps the history
    /// it parked, with a text being typed ended, until it opens the next screenshot.
    func editorLeft(_ key: ScreenshotKey) {
        guard let inEditor, current(inEditor) == key else { return }
        self.inEditor = nil
        let depth = editor.depth()
        leftAt[key] = depth
        guard asked == nil else { return }
        leaving = Shown(key: key, depth: depth, file: files.identity(Screenshot(key: key)))
    }

    /// The run opened `key` in the editor. After another screenshot left it, the two are one step.
    func editorOpened(_ key: ScreenshotKey) {
        guard let open = editor.open(), open.key == key else { return }
        inEditor = key
        // Agents' marks join a closed screenshot's history on top, which leaves the depths below.
        if let (recorded, depth) = leftAt.first(where: { current($0.key) == key }) {
            leftAt[recorded] = nil
            if open.undo < depth { rebase(key, by: open.undo - depth) }
        }
        // An image whose file left the folder as it closed went with the step that took the file.
        let before = leaving.flatMap { files.exists(Screenshot(key: current($0.key))) ? $0 : nil }
        leaving = nil
        seen = open
        if let asked {
            self.asked = nil
            if asked == .open(key) { return }
        }
        push(Step(name: .openDrawing, action: .draw, editor: shown(open), then: before))
    }

    /// The annotation run is over. A screenshot it took out of the editor was closed, unless its file
    /// has left the folder, since the step that took the file away closed it.
    func editorEnded() {
        defer {
            leaving = nil
            seen = nil
            asked = nil
            inEditor = nil
        }
        guard asked == nil, let left = leaving, files.exists(Screenshot(key: current(left.key))) else { return }
        push(Step(name: .closeDrawing, action: .draw, editor: nil, then: left))
    }

    // MARK: Keys and menu

    /// Cmd+Z. With nothing to undo, it beeps, as a disabled menu item's shortcut does.
    func undo() { walk(redo: false) }

    /// Shift+Cmd+Z.
    func redo() { walk(redo: true) }

    /// Cmd+Z, or with `redo` Shift+Cmd+Z. A key held down repeats only the editor's own steps, so
    /// one press never runs past an opening, a close or a step of the stack's.
    func walk(redo: Bool, repeated: Bool = false) {
        guard !busy else { return repeated ? () : beep() }
        look()
        switch next(redo: redo) {
        case .editor:
            editor.step(redo)
            seen = editor.open()
        case .step(let step):
            guard !repeated else { return }
            let open = editor.open()
            if redo { take(&redoSteps, open) } else { take(&undoSteps, open) }
            refused = false
            running = (step, redo)
            run(step)
            running = nil
            if !refused { announce(Self.title(step.name, redo: redo)) }
        case .nothing:
            if !repeated { beep() }
        }
    }

    /// What Undo, or with `redo` Redo, would do now, in the Edit menu's words, and whether it can.
    func title(redo: Bool) -> (title: String, enabled: Bool) {
        guard !busy else { return (redo ? "Redo" : "Undo", false) }
        switch next(redo: redo) {
        case .editor: return (editor.title(redo), true)
        case .step(let step): return (Self.title(step.name, redo: redo), true)
        case .nothing: return (redo ? "Redo" : "Undo", false)
        }
    }

    private static func title(_ name: Name, redo: Bool) -> String { "\(redo ? "Redo" : "Undo") \(name.rawValue)" }

    // MARK: Walking the timeline

    /// One step, as it waits to be undone or redone. `editor` is what the editor shows while this
    /// is the next step, and `then` what it shows once the step has run. A step of the stack's
    /// leaves the editor as it was, so the two are the same.
    struct Step {
        let name: Name
        let action: Action
        let editor: Shown?
        let then: Shown?
    }

    /// What a step does when it runs.
    enum Action {
        case putBack(trashed: [Gone], column: [ScreenshotKey])
        case trashAgain([Screenshot])
        case unstitch(stitch: Screenshot, pieces: [Screenshot], column: [ScreenshotKey])
        case restitch(trashed: Gone, pieces: [Screenshot], column: [ScreenshotKey])
        /// Opens, closes or swaps the screenshot in the annotator, to what `then` says.
        case draw
    }

    /// A file a step moved to the Trash, with its drawing, message and history as they were then.
    struct Gone {
        let file: FolderWrites.Trashed
        let saved: Drawings.Saved?
    }

    private enum Next {
        case editor
        case step(Step)
        case nothing
    }

    /// What Cmd+Z, or with `redo` Shift+Cmd+Z, runs now. With a screenshot in the editor, its own
    /// steps come first, as far as the timeline's next step left its history. Over lone thumbnails a
    /// step that closes the annotator is out of reach, since nothing would have the keys after it.
    private func next(redo: Bool) -> Next {
        let open = editor.open()
        let steps = redo ? (editorStepped ? [] : redoSteps) : undoSteps
        let index = steps.lastIndex { !shows($0, open) }
        let step = index.map { steps[$0] }
        if let open {
            var mark = step?.editor.flatMap { current($0.key) == open.key ? $0.depth : nil }
            // With nothing older left in the timeline, as after a relaunch, the screenshot's stored
            // steps are the oldest, so they come before its opening.
            if !redo, let index, case .draw = steps[index].action, !steps[..<index].contains(where: { !shows($0, open) }) { mark = 0 }
            if redo, open.redo > 0, open.undo < mark ?? .max { return .editor }
            if !redo, open.undo > mark ?? 0 { return .editor }
            if let step, case .draw = step.action, step.then == nil, !cards.isStack() { return .nothing }
        }
        return step.map(Next.step) ?? .nothing
    }

    /// An opening or a close whose result the editor already shows, as after the step above it was
    /// used up, has nothing left to do: Cmd+Z passes over it.
    private func shows(_ step: Step, _ open: EditorPlace?) -> Bool {
        guard case .draw = step.action else { return false }
        return open?.key == step.then.map { current($0.key) }
    }

    /// Takes off the step `next` chose, with the steps above it it passed over.
    private func take(_ steps: inout [Step], _ open: EditorPlace?) {
        while let last = steps.last, shows(last, open) { steps.removeLast() }
        steps.removeLast()
    }

    /// The editor made a step since the timeline last looked, which ends what the timeline could redo.
    private var editorStepped: Bool {
        guard let open = editor.open(), let seen, current(seen.key) == open.key else { return false }
        return (seen.undo, seen.redo) != (open.undo, open.redo)
    }

    private func look() {
        if editorStepped { redoSteps = [] }
        seen = editor.open()
    }

    /// Inside an Undo or a Redo, files the step that takes it back, on the other side. Outside one,
    /// a new step, which ends what could be redone and leaves the editor as it is.
    func record(_ name: Name, _ action: Action) {
        guard let running else {
            let shown = editor.open().map(shown)
            return push(Step(name: name, action: action, editor: shown, then: shown))
        }
        let back = Step(name: name, action: action, editor: running.step.then, then: running.step.editor)
        if running.redoing { undoSteps.append(back) } else { redoSteps.append(back) }
    }

    func push(_ step: Step) {
        undoSteps.append(step)
        redoSteps = []
    }

    private func run(_ step: Step) {
        switch step.action {
        case .putBack(let trashed, let column): putBack(trashed, column: column)
        case .trashAgain(let shots): trash(shots.map(current))
        case .unstitch(let stitch, let pieces, let column): unstitch(stitch, pieces: pieces, column: column)
        case .restitch(let trashed, let pieces, let column): restitch(trashed, pieces: pieces, column: column)
        case .draw: return draw(step)
        }
        // A Delete that took the screenshot in the editor away brings it back there when undone.
        guard !refused, let then = step.then, editor.open()?.key != current(then.key) else { return }
        if let why = reopen(then) { log(step.name, "the editor", ["open \(current(then.key).name): \(why)"]) }
    }

    /// Opens the screenshot `step` leaves in the editor, or closes the one there.
    private func draw(_ step: Step) {
        let open = editor.open()
        if let then = step.then {
            let key = current(then.key)
            if let why = reopen(then) { return refuse(step.name, why) }
            log(step.name, "opened \(key.name)", [])
        } else {
            guard let open else { return refuse(step.name, "no screenshot is in the editor") }
            asked = .close
            guard cards.draw(nil) else {
                asked = nil
                return refuse(step.name, "\(open.key.name) can't close")
            }
            log(step.name, "closed \(open.key.name)", [])
        }
        record(step.name, .draw)
    }

    /// Asks the annotator to open `shown`'s screenshot. Answers why not when its file has moved or
    /// changed since, or it can't open.
    private func reopen(_ shown: Shown) -> String? {
        let shot = Screenshot(key: current(shown.key))
        guard files.exists(shot) else { return "\(shot.key.name) is not in the folder" }
        guard shown.file == nil || files.identity(shot) == shown.file else { return "\(shot.key.name) has changed since" }
        asked = .open(shot.key)
        guard cards.draw(shot.key) else {
            asked = nil
            return "\(shot.key.name) can't open"
        }
        return nil
    }

    private func rebase(_ key: ScreenshotKey, by offset: Int) {
        func moved(_ shown: Shown?) -> Shown? {
            guard var shown, current(shown.key) == key else { return shown }
            shown.depth = max(0, shown.depth + offset)
            return shown
        }
        func moved(_ step: Step) -> Step { Step(name: step.name, action: step.action, editor: moved(step.editor), then: moved(step.then)) }
        undoSteps = undoSteps.map(moved)
        redoSteps = redoSteps.map(moved)
        if let running { self.running = (moved(running.step), running.redoing) }
    }

    func shown(_ place: EditorPlace) -> Shown {
        Shown(key: place.key, depth: place.undo, file: files.identity(Screenshot(key: place.key)))
    }

    private func putBack(_ trashed: [Gone], column: [ScreenshotKey]) {
        let (back, failed) = moveBack(trashed)
        guard !back.isEmpty else { return refuse(.moveToTrash, failed.joined(separator: "; ")) }
        log(.moveToTrash, "put back \(names(back))", failed)
        cards.putBack(back, column.map(current))
        record(.moveToTrash, .trashAgain(back))
    }

    /// The pieces' cards come back first, so the column never empties and closes between the two.
    private func unstitch(_ recorded: Screenshot, pieces recordedPieces: [Screenshot], column recordedColumn: [ScreenshotKey]) {
        let column = cards.column()
        let stitch = current(recorded)
        let pieces = recordedPieces.map(current).filter(files.exists)
        if !pieces.isEmpty { cards.putBack(pieces, recordedColumn.map(current)) }
        let trashed = files.exists(stitch) ? moveToTrash([stitch]) : []
        guard let inTrash = trashed.first else {
            guard !pieces.isEmpty else { return refuse(.stitch, "\(stitch.url.lastPathComponent) is not in the folder") }
            log(.stitch, "put back the cards of \(names(pieces))", ["\(stitch.url.lastPathComponent) is not in the folder"])
            return
        }
        log(.stitch, "moved \(stitch.url.lastPathComponent) to the Trash" + (pieces.isEmpty ? "" : ", put back the cards of \(names(pieces))"), [])
        record(.stitch, .restitch(trashed: inTrash, pieces: pieces, column: column))
    }

    private func restitch(_ trashed: Gone, pieces recordedPieces: [Screenshot], column recordedColumn: [ScreenshotKey]) {
        let column = cards.column()
        let (back, failed) = moveBack([trashed])
        guard let stitch = back.first else { return refuse(.stitch, failed.joined(separator: "; ")) }
        cards.putBack(back, recordedColumn.map(current))
        let shown = Set(cards.column())
        let pieces = recordedPieces.map(current).filter { shown.contains($0.key) }
        if !pieces.isEmpty { cards.takeOut(pieces) }
        log(.stitch, "put back \(stitch.url.lastPathComponent)", [])
        record(.stitch, .unstitch(stitch: stitch, pieces: pieces, column: column))
    }

    /// Each drawing is read before its file goes, since the drawing is forgotten once the file has left.
    private func moveToTrash(_ shots: [Screenshot]) -> [Gone] {
        var saved: [ScreenshotKey: Drawings.Saved] = [:]
        for shot in shots { saved[shot.key] = files.saved(shot) }
        return files.trash(shots).map { Gone(file: $0, saved: saved[$0.shot.key]) }
    }

    private func moveBack(_ gone: [Gone]) -> (back: [Screenshot], failed: [String]) {
        let result = files.putBack(gone.map(\.file))
        let back = Set(result.back.map(\.key))
        for item in gone where back.contains(item.file.shot.key) {
            if let saved = item.saved { files.restore(saved) }
        }
        return result
    }

    private func current(_ shot: Screenshot) -> Screenshot { renamed[shot.key].map(Screenshot.init(key:)) ?? shot }
    func current(_ key: ScreenshotKey) -> ScreenshotKey { renamed[key] ?? key }

    private var redoing: Bool { running?.redoing == true }

    func log(_ name: Name, _ what: String, _ failed: [String]) {
        Log.write("[undo] \(redoing ? "redid" : "undid") \(name.rawValue): \(what)" + (failed.isEmpty ? "" : "; can't \(failed.joined(separator: "; "))"))
    }

    /// A step that can no longer run is used up: the next Cmd+Z goes to the one before it.
    func refuse(_ name: Name, _ why: String) {
        Log.write("[undo] can't \(redoing ? "redo" : "undo") \(name.rawValue): \(why)")
        refused = true
        beep()
    }

    private func names(_ shots: [Screenshot]) -> String { shots.map(\.url.lastPathComponent).joined(separator: ", ") }
}
