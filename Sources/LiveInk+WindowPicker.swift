import AppKit

// MARK: macOS's window picker

extension LiveInk {
    /// ⌘⇧ went down, so a capture may be starting. macOS's window picker, Space during ⌘⇧4 or ⌘⇧5's
    /// window capture, takes the window whose pixels are under the pointer, so over a mark it took the
    /// overlay, which captures leave out ("Unable to capture window image"). It passes over a window
    /// whose alpha is 0, and it reads the windows when Space is pressed (measured on macOS 15), before
    /// its own window is up. So while there are marks this looks 10 times a second, for
    /// `CaptureOrigin.pollSeconds` and as long as a capture lasts, for a `screencapture` process,
    /// which ⌘⇧4 runs, or a window of `screencaptureui`, which ⌘⇧5 puts up, and clears the
    /// overlays while there is one. The marks are out of the capture either way.
    func watchForWindowPicker() {
        guard !surfaces.isEmpty || !windows.isEmpty else { return }
        pickerWatchUntil = Date().addingTimeInterval(CaptureOrigin.pollSeconds)
        guard pickerWatch == nil else { return }
        checkWindowPicker()
        pickerWatch = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkWindowPicker() }
        }
    }

    func checkWindowPicker() {
        let up = Self.isCapturing()
        if up != pickerUp {
            pickerUp = up
            surfaces.forEach { $0.overlay.alphaValue = up ? 0 : 1 }
            windows.pickerClear = up
            Log.write("[live-ink] \(up ? "clear for" : "back after") a capture")
        }
        if !up, Date() > pickerWatchUntil { stopWatchingForWindowPicker() }
    }

    func stopWatchingForWindowPicker() {
        pickerWatch?.invalidate()
        pickerWatch = nil
        if pickerUp {
            surfaces.forEach { $0.overlay.alphaValue = 1 }
            windows.pickerClear = false
        }
        pickerUp = false
    }
}
