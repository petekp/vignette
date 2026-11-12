import AppKit

// MARK: Esc

extension LiveInk {
    /// How far from the ink a click, scroll or key reads the screen behind it again (`InkBackdrop.isNearInk`).
    static let backdropReach: CGFloat = 160

    /// Whether Esc is down now, read from the keyboard itself.
    static var escapeIsDown: Bool { CGEventSource.keyState(.hidSystemState, key: CGKeyCode(LiveEscape.keyCode)) }

    var escapeSnapshot: LiveEscape.Snapshot {
        /// Whether a mark that shows on the active Space and is not leaving passes `test`.
        func shows(_ test: (Mark.ID) -> Bool) -> Bool {
            func staying(_ id: Mark.ID) -> Bool { !asks.isFinishing(id) && test(id) }
            return windows.containsShown(where: staying) || surfacesInSight.contains { $0.marks.contains { staying($0.id) } }
        }
        let cancellable = asks.cancellable(sendsWait: sendsWait)
        var snapshot = LiveEscape.Snapshot(
            isOn: isOn,
            screenIsFree: mayInk(),
            menuOpen: note?.menuOpen == true,
            inking: isInking,
            justLetGo: escapeAfterRelease != nil,
            note: note.map { $0.hasKeys ? .hasKeys : .withoutKeys } ?? LiveEscape.Note.none,
            replyFieldOpen: actionsPanels.values.contains(where: \.isTyping),
            askCanBeCancelled: cancellable != nil,
            askSentOnRelease: cancellable.flatMap(asks.ask)?.sentOnRelease == true,
            tourRunning: tourRunning,
            answerShown: shows(asks.isSettledAnswer),
            marksShown: shows { _ in true })
        snapshot.pointerOnInk = LiveEscape.needsPointer(snapshot) && pointerIsOnInk()
        return snapshot
    }

    /// Whether the pointer is within `reach` of a mark, or on a reply, that shows on the active Space.
    func pointerIsOnInk(reach: CGFloat = LiveInk.eraseReach) -> Bool {
        let mouse = NSEvent.mouseLocation
        let point = CGPoint(x: mouse.x, y: StateReport.primaryHeight - mouse.y)
        let onMark = shownMarks.contains { mark in
            let box = mark.shapeExtent ?? Self.drawnExtent(of: mark, sizes: answerSizes)
            return box?.insetBy(dx: -reach, dy: -reach).contains(point) == true
        }
        return onMark || shownReplies().values.contains { $0.note.contains(point) }
    }

    /// Holds Esc exactly while `LiveEscape` has a step for it, so with nothing to back out of it is the
    /// frontmost app's. While the chord is held the key is Esc with the chord's modifiers, the only Esc
    /// that can come then. The main run loop asks before each wait, so the key follows every change to
    /// what the snapshot reads, whatever made it.
    func holdEscape() {
        endEscapeAfterReleaseWhenDone()
        let step = LiveEscape.next(escapeSnapshot)
        let modifiers = step == .cancelHold && chord?.isHeld == true
            ? HotKeySpec.carbonModifiers(Settings.shared.data.liveInkChordChoice.flags) : 0
        let wanted = step.map { _ in modifiers }
        guard wanted != escapeKey?.modifiers else { return }
        escapeKey = wanted.map { modifiers in
            (HotKey(keyCode: LiveEscape.keyCode, modifiers: modifiers, action: { [weak self] in self?.escape() }), modifiers)
        }
    }

    /// Esc: the first step that applies, one per press. The hotkey takes the press while it is held;
    /// the note and the Reply field come here for a press before it is.
    func escape() {
        guard let step = LiveEscape.next(escapeSnapshot) else { return }
        Log.write("[live-ink] esc \(step.rawValue)")
        switch step {
        case .cancelHold:
            cancelHold()
        case .discardNote:
            discardNote()
        case .closeReplyField:
            actionsPanels.values.first(where: \.isTyping)?.closeField()
        case .cancelAsk, .discardAsk:
            cancelAsk()
        case .endTour:
            letGoOfTour(because: "escape")
        case .closeAnswer:
            closeAnswer(by: .answerClosed)
        case .clearInk:
            clear()
        }
    }

    /// Whether a note to a session waits out a grace before it goes, which is what lets Esc stop it.
    var sendsWait: Bool { Settings.shared.data.ui.sendGraceSeconds > 0 }

    /// Stops the newest ask under way: its sent note and any reply leave, the follow-up from a button
    /// puts its answer back, and its ink can be asked about again, or goes when the ask was sent on
    /// release. The responder's turn is stopped when it was this ask's, and the next ask waiting goes.
    /// A session's note is withdrawn if its send is stored before the answer to this comes.
    func cancelAsk() {
        guard let id = asks.cancellable(sendsWait: sendsWait) else { return }
        Log.write("[live-ink] stopping id=\(id)")
        run(asks.reduce(.cancelled(id, shown: shownIDs)))
        showMarks()
        closeEmpty(fade: LiveMarksLayer.removalFade)
    }

    /// Esc while the chord is held, or while a stroke outlives it: inking stops and nothing is sent.
    /// The ink drawn or picked in this hold fades, listening stops, with the microphone, and drops what
    /// it heard, and a note opened in this hold closes. Ink from before the hold stays, and a note up
    /// before it stays with the words it had.
    func cancelHold() {
        let ink = holdInk.intersection(asks.noteInk)
        holdInk = []
        stopListening()
        stopInking(because: "esc")
        if let note, let before = noteBeforeHold, note === before.note {
            if note.content.field.stringValue != before.words { note.put(before.words) }
            // A stroke in the hold moved it to the new ink, which is about to go.
            if notePlace != before.place {
                notePlace = before.place
                hangNote(takingKeys: false)
            }
        } else {
            closeNote()
        }
        noteBeforeHold = nil
        remove(ink)
        showMarks()
        closeEmpty(fade: LiveMarksLayer.removalFade)
        if note?.hasKeys != true { FocusReturn.shared.restore(reason: "live ink hold cancelled") }
        Log.write("[live-ink] hold cancelled marks=\(ink.count)")
    }

    // MARK: Right after the release

    /// The chord was let go and the note opened or stayed for this hold: while the note or an ask sent
    /// from it is there, Esc is live ink's wherever the pointer is, until the person presses off the
    /// ink, another app becomes active, or nothing is left for Esc to stop.
    func keepEscapeAfterRelease() {
        guard note != nil else { return }
        escapeAfterRelease = LiveEscapeAfterRelease(
            returningTo: FocusReturn.shared.previousApp, asksBefore: asks.lastID,
            isOnInk: { [weak self] in self?.pointerIsOnInk() ?? false },
            ended: { [weak self] reason in self?.endEscapeAfterRelease(because: reason) })
    }

    func endEscapeAfterRelease(because reason: String) {
        guard escapeAfterRelease != nil else { return }
        escapeAfterRelease = nil
        Log.write("[live-ink] esc after release ended: \(reason)")
    }

    /// The answer came, the note was sent to a session and stored, or the note and its ask are gone.
    /// An ask from before the release does not keep Esc.
    private func endEscapeAfterReleaseWhenDone() {
        guard let window = escapeAfterRelease, note == nil,
              asks.cancellable(sendsWait: sendsWait, after: window.asksBefore) == nil else { return }
        endEscapeAfterRelease(because: "nothing left to stop")
    }
}
