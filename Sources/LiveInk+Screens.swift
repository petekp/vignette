import AppKit

// MARK: Spaces and screens

extension LiveInk {
    /// Inking stops, since its surfaces are on the Space just left.
    func spaceChanged() {
        guard isInking else { return }
        cutInkingShort(because: "the Space changed")
    }

    /// Inking ends with no release to come, so listening, which a release would end, ends too.
    func cutInkingShort(because reason: String) {
        // A note by the pointer waits for the release; with none coming, it has no ink to stay with.
        if noteHangsAtPointer { closeNote() }
        stopListening()
        stopInking(because: reason)
    }

    /// Each surface covers its screen again; one whose screen is gone closes with its marks.
    func screensChanged() {
        let screens = Dictionary(NSScreen.screens.compactMap { screen in Self.display(of: screen).map { ($0, screen) } },
                                 uniquingKeysWith: { first, _ in first })
        // The Dock changing size posts this too, and leaves every screen where it was: inking goes on.
        if isInking, inking.contains(where: { screens[$0.overlay.display]?.frame != $0.overlay.frame }) {
            cutInkingShort(because: "the screens changed")
        }
        var dropped = Set<Mark.ID>()
        for surface in surfaces {
            if let screen = screens[surface.overlay.display] {
                surface.overlay.fit(to: screen)
            } else {
                if surface.overlay.marks.holdsNote, noteHangsAtPointer { closeNote() }
                dropped.formUnion(surface.marks.map(\.id))
                surface.marks = []
            }
        }
        // A mark that reaches onto a screen still here stays, with its part in the asks.
        let gone = dropped.subtracting(marks.map(\.id))
        if !gone.isEmpty { run(asks.reduce(.removed(gone))) }
        bringOntoScreens()
        closeEmpty(fade: 0)
        showMarks()
    }

    /// A mark on no window that a smaller screen left with no part on any screen moves the least way
    /// back onto the screen of the first surface it is on, as macOS moves a window.
    func bringOntoScreens() {
        let frames = StateReport.screenFrames
        var moves: [Mark.ID: CGVector] = [:]
        for surface in surfaces {
            for mark in surface.marks where moves[mark.id] == nil {
                guard let extent = Self.drawnExtent(of: mark, sizes: answerSizes), !frames.contains(where: { $0.intersects(extent) }) else { continue }
                moves[mark.id] = Self.offset(moving: extent, into: surface.overlay.globalFrame)
            }
        }
        guard !moves.isEmpty else { return }
        for surface in surfaces {
            surface.marks = surface.marks.map { mark in moves[mark.id].map { LiveWindows.translated(mark, by: $0) } ?? mark }
        }
        Log.write("[live-ink] moved \(moves.count) onto the screen")
    }
}
