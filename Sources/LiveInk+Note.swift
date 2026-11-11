import AppKit

// MARK: The note

extension LiveInk {
    /// Where a note hangs from `mark` before the window's text is known.
    func firstPlace(beside mark: Mark) -> PopoverPlace? {
        guard let extent = mark.shapeExtent else { return nil }
        return LiveAnswerLayout.noteHang(LiveNotePopover.placementSize, for: mark, scene: scene(frame: extent, page: nil, text: []))
    }

    /// The note hangs by the pointer: it opened on the voice before any ink, and no ink has been
    /// drawn for it since.
    var noteHangsAtPointer: Bool { note != nil && notePlace != nil && notePlace?.anchor == nil }

    /// Gives the new ink its note, with the keys unless `takingKeys` is false, or, with no new ink,
    /// opens it by the pointer. A note up already keeps its words, its target and its caret, and moves
    /// to hang from the newest ink. Answers whether the note took the keys.
    @discardableResult
    func showNote(takingKeys: Bool = true) -> Bool {
        let mark = newInk.last(where: { $0.shapeExtent != nil })
        guard let first = mark.map(firstPlace(beside:)) ?? pointerNotePlace() else { return false }
        if let note {
            if notePlace?.anchor != mark?.id {
                hang(note, from: mark, at: first, takingKeys: takingKeys)
                if let mark { prepare(beside: mark, panel: note) }
                Log.write("[live-ink] note moved to the newest ink")
            }
            guard takingKeys else { return false }
            // Taking the keys back lists the targets again (`onKeysBack`).
            note.takeKeys()
            return true
        }
        let offered = lastTarget ?? .responder(noteAgent)
        let panel = LiveNotePopover(at: first, target: offered)
        panel.offer(responders.offers, conversing: responders.conversing)
        // It opens with the sessions this hold listed, and gets their later answers, or lists them itself.
        let held = listing?.hold == inkings ? listing : nil
        held?.note = panel
        if let listed = held?.candidates { panel.setSessions(listed) }
        panel.speechProblem = speechProblem
        if !responders.unable.isEmpty { checkResponder(responders.unable) }
        // An ask is about ink, so words by the pointer wait in the note until the person draws.
        panel.mayAsk = { [weak self] in self.map { !$0.asks.noteInk.isEmpty } ?? false }
        panel.onAsk = { [weak self, weak panel] words, target, title in
            guard let self else { return }
            self.stopListening()
            self.letGoOfNotePanel()
            self.lastTarget = target
            let session = target.session.map { (destination: $0, title: title) }
            let note = panel.flatMap { panel in panel.shownPlace.map { (panel: panel, place: $0, tag: panel.tagFrame) } }
            if case .failure = self.ask(words, to: target.agent, sendingTo: session, from: note) { panel?.fadeAway() }
        }
        panel.onKeysBack = { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.refreshTargets(of: panel)
        }
        panel.onEscape = { [weak self] in self?.escape() }
        panel.onTyped = { [weak self] in self?.typedInNote() }
        note = panel
        hang(panel, from: mark, at: first, takingKeys: takingKeys)
        if let mark { prepare(beside: mark, panel: panel) } else { panel.reveal() }
        if held == nil { refreshTargets(of: panel) }
        listen(into: panel)
        let why = isInking ? (mark == nil ? "the first word was heard" : "the chord is held") : "a menu is still open"
        Log.write("[live-ink] note open\(mark == nil ? " by the pointer" : "")\(takingKeys ? "" : " without the keys: " + why)")
        return panel.hasKeys
    }

    /// Lists the sessions for the note's target again, so one started since shows up. A target the
    /// person picked by hand stays (`DestinationChoice`).
    func refreshTargets(of panel: LiveNotePopover) {
        listSessions? { [weak panel] candidates in panel?.setSessions(candidates) }
    }

    /// Hangs the note from `mark`, or by the pointer with none, at `place`. A note hung the first time
    /// opens with the keys when `takingKeys`.
    func hang(_ panel: LiveNotePopover, from mark: Mark?, at place: PopoverPlace, takingKeys: Bool = true) {
        var place = place
        place.anchor = mark?.id
        notePlace = place
        hangNote(takingKeys: takingKeys)
    }

    /// Hands the note to the overlays: the one that draws the mark it hangs from, its window's or its
    /// home screen's, hangs it, and every other lets go of it. A note by the pointer hangs from the
    /// screen's surface under its place, which stays up while it holds the note.
    func hangNote(takingKeys: Bool = true) {
        let anchor = notePlace?.anchor
        let holder: Surface?
        if let place = notePlace, anchor == nil, note != nil {
            let spot = CGPoint(x: place.at.midX, y: place.at.midY)
            let onScreen = { (surface: Surface) in surface.overlay.isOnActiveSpace && surface.overlay.globalFrame.contains(spot) }
            holder = surfaces.first(where: onScreen) ?? activeSurfaces().first(where: onScreen)
        } else {
            let drawing = surfaces.filter { $0.marks.contains { $0.id == anchor } }
            let mark = drawing.first?.marks.first { $0.id == anchor }
            holder = mark.flatMap { home(of: $0, among: drawing) }
        }
        for surface in surfaces {
            surface.overlay.marks.hang(surface === holder ? note : nil, place: notePlace, takingKeys: takingKeys)
        }
        windows.hang(anchor == nil ? nil : note, place: notePlace, takingKeys: takingKeys)
    }

    /// The note goes when its ink does: asked about, taken back, erased, or gone with its window. When
    /// the ink it hangs from went and other ink of its is left, it moves to hang from the newest of that,
    /// once the chord is let go. A note by the pointer has no ink yet, and stays.
    func keepNoteWithItsInk() {
        guard let note, !noteHangsAtPointer else { return }
        let ink = noteInk
        guard let newest = ink.last(where: { $0.shapeExtent != nil }) else {
            closeNote()
            Log.write("[live-ink] note closed: its ink is gone")
            return
        }
        guard !isInking, !ink.contains(where: { $0.id == notePlace?.anchor }), let place = firstPlace(beside: newest)
        else { return }
        hang(note, from: newest, at: place)
        Log.write("[live-ink] note moved: the ink it hung from went")
    }

    /// The note is no longer this one's to place: it was asked in, and hands over or fades where it is.
    func letGoOfNotePanel() {
        note = nil
        notePlace = nil
        hangNote()
    }

    func closeNote() {
        let closing = note
        let byThePointer = noteHangsAtPointer
        letGoOfNotePanel()
        closing?.dismiss()
        // The surface it hung from may hold nothing else now; it closes once the note has faded.
        if byThePointer { closeEmpty(fade: LiveMarksLayer.removalFade) }
    }

    /// Esc stopped an ask, and its ink is the note's again (`LiveAsks.Effect.reopenNote`): the note
    /// opens on it with the keys and the words the ask carried, or the note up already takes the keys
    /// and keeps its own words.
    func reopenNote(_ words: String) {
        let opening = note == nil
        showNote()
        guard let note else { return }
        if opening || note.isEmpty {
            note.put(words)
            typedOver = true
        }
        Log.write("[live-ink] note reopened words=\(words.split(whereSeparator: \.isWhitespace).count)")
    }

    /// Esc in the note: the note goes, with what was said for it and its ink, all the ink no ask has
    /// been about. Ink an ask was about stays.
    func discardNote() {
        closeNote()
        stopListening()
        let before = marks.count
        run(asks.reduce(.noteDiscarded))
        showMarks()
        closeEmpty(fade: LiveMarksLayer.removalFade)
        Log.write("[live-ink] note discarded marks=\(before - marks.count)")
    }

    // MARK: By the pointer

    /// Where a note by the pointer hangs now, on the screen the pointer is on, keeping `edge` when it
    /// fits there.
    func pointerNotePlace(at pointer: CGPoint? = nil, keeping edge: PopoverPlace.Edge? = nil) -> PopoverPlace? {
        let mouse = NSEvent.mouseLocation
        let pointer = pointer ?? CGPoint(x: mouse.x, y: StateReport.primaryHeight - mouse.y)
        let appKit = NSPoint(x: pointer.x, y: StateReport.primaryHeight - pointer.y)
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(appKit, $0.frame, false) }) ?? NSScreen.main else { return nil }
        return LiveNotePopover.pointerPlace(LiveNotePopover.placementSize, at: pointer, clearance: Settings.shared.data.ui.liveInkNoteClearance,
                                            screen: StateReport.flipped(screen.visibleFrame), keeping: edge)
    }

    /// The first word was heard while the chord is held and no note is up: the note opens by the
    /// pointer, without the keys, so the words show as they are said. A menu still open waits for the
    /// release, which closes it first.
    func showNoteOnTheVoice() {
        guard note == nil, isInking, listening != nil, releaseWatch == nil, LiveMenus.open().isEmpty else { return }
        showNote(takingKeys: false)
    }

    /// The pointer moved to `pointer` while the chord is held, or the pen did. A note by the pointer
    /// that it comes near moves out of its way, on a spring, so it never sits where the person is
    /// about to draw.
    func noteMayMove(from pointer: CGPoint) {
        guard isInking, noteHangsAtPointer, let note, let place = notePlace else { return }
        let clearance = Settings.shared.data.ui.liveInkNoteClearance
        guard LiveNotePopover.pointer(pointer, crowds: note.globalFrame ?? place.body, clearance: clearance),
              let moved = pointerNotePlace(at: pointer, keeping: place.edge) else { return }
        hang(note, from: nil, at: moved, takingKeys: false)
    }
}
