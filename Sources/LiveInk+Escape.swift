import AppKit

// MARK: Esc

extension LiveInk {
    /// How far from the ink a click, scroll or key reads the screen behind it again (`InkBackdrop.isNearInk`).
    static let backdropReach: CGFloat = 160

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
    /// frontmost app's. The main run loop asks before each wait, so the key follows every change to
    /// what the snapshot reads, whatever made it.
    func holdEscape() {
        let wanted = LiveEscape.next(escapeSnapshot) != nil
        guard wanted != (escapeKey != nil) else { return }
        escapeKey = wanted ? HotKey(keyCode: LiveEscape.keyCode, modifiers: 0, action: { [weak self] in self?.escape() }) : nil
    }

    /// Esc: the first step that applies, one per press. The hotkey takes the press while it is held;
    /// the note and the Reply field come here for a press before it is.
    func escape() {
        guard let step = LiveEscape.next(escapeSnapshot) else { return }
        Log.write("[live-ink] esc \(step.rawValue)")
        switch step {
        case .discardNote:
            discardNote()
        case .closeReplyField:
            actionsPanels.values.first(where: \.isTyping)?.closeField()
        case .cancelAsk:
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
    /// puts its answer back, and its ink can be asked about again. The responder's turn is stopped when
    /// it was this ask's, and the next ask waiting goes. A session's note is withdrawn if its send is
    /// stored before the answer to this comes.
    func cancelAsk() {
        guard let id = asks.cancellable(sendsWait: sendsWait) else { return }
        Log.write("[live-ink] stopping id=\(id)")
        run(asks.reduce(.cancelled(id, shown: shownIDs)))
        showMarks()
    }
}
