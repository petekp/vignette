import AppKit

// MARK: The pointer field

extension LiveInk {
    /// The pointer field's delay passed, or a press came first: the field shows, and listening starts.
    func showFieldForChord() {
        fieldTimer?.invalidate()
        guard !chordShowsField else { return }
        chordShowsField = true
        holdField()
        // Not before the field, so a chord on its way to a shortcut ends no tour, captures nothing and
        // says nothing. Screen Recording is what a note reads the window with, so say so before any ink.
        letGoOfFocus(because: "ink")
        InkBackdrop.shared.refresh()
        if !ScreenRecording.granted {
            let mouse = NSEvent.mouseLocation
            let pointer = CGPoint(x: mouse.x, y: StateReport.primaryHeight - mouse.y)
            (inking.first { $0.overlay.globalFrame.contains(pointer) } ?? inking.first)?.overlay.showNotice(Self.screenRecordingNotice, at: pointer)
        }
        // The field goes to the screen first, so making the recognizer on this thread never holds it back.
        CATransaction.flush()
        listen()
    }

    /// Holds the pointer field up, in the current settings, on the surfaces taking ink while the chord
    /// shows it, and lets it go on every other surface.
    func holdField() {
        let ui = Settings.shared.motionUI
        let held = chordShowsField ? inking : []
        for surface in surfaces {
            surface.overlay.holdField(held.contains { $0 === surface }, ui: ui)
        }
    }
}
