import AppKit

// MARK: Showing and hiding

extension AnnotationController {
    /// Puts the window up behind the flight image, which is past this frame on every side and so
    /// covers it — except for a shadow, which falls outside the frame it is cast from. The flight
    /// carries the shadow until it lands; `landed` hands it over. The keys came with `prepare`; the
    /// pointer comes here, so a drag lands on the editor as soon as the card looks still.
    func show() {
        guard let win = window, current != nil else { return }
        win.alphaValue = 1
        frameView?.layer?.shadowOpacity = 0
        win.makeKeyAndOrderFront(nil)
        toolbar.show()
        NSApp.activate(ignoringOtherApps: true)
        // A click outside this app's windows ends the session. The window was ordered in a line ago
        // and the window server does not report it under the cursor yet, so a press inside this
        // frame in the first few milliseconds would be read as outside and throw the session away
        // (measured: 3 of 4 presses landing 14 to 19 ms after this call). Nothing is ignored for
        // long enough to swallow a press that answers the window: it is not on screen until the
        // flight lands on it, and a hand cannot react inside `outsideClickSettling`.
        outsideClick.start(settling: Self.outsideClickSettling) { [weak self] in self?.cancel(.clickedAway) }
        probeEvents()
        windowUp = true
        // A turn later, once the app is active and the bar is up.
        DispatchQueue.main.async { [weak self] in self?.offerTyping() }
    }

    /// Typing goes to the agent: once the window is up, the bar's message field takes the keys, when
    /// the bar has one, no key or press has reached the editor and no session was picked in the
    /// target's menu. Once per image, so a field the keys left is not given them again when the
    /// session list answers.
    func offerTyping() {
        guard windowUp, editorUntouched, current != nil, toolbar.typeOnOpen() else { return }
        editorUntouched = false
    }

    /// Finds the moment the window server starts giving this window the presses on its frame. The
    /// window is ordered in at alpha 0 in `prepare`, which passes every press through, and alpha 1
    /// reaches the window server 6 to 25 ms after `show` sets it (measured 2026-09-23). Nothing
    /// announces it: no occlusion change arrives with the alpha. So this asks, every millisecond,
    /// which window a press at the frame's centre would reach.
    private func probeEvents() {
        eventProbe?.invalidate()
        guard let win = window, let opening else { return }
        let started = CACurrentMediaTime()
        let timer = Timer(timeInterval: 0.001, repeats: true) { [weak self] timer in
            let answered = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.opening == opening else { return true }
                let elapsed = CACurrentMediaTime() - started
                let reached = self.pressReaches(win)
                guard reached || elapsed > Self.eventProbeDeadline else { return false }
                self.eventProbe = nil
                Log.write("[annotate] takes events after=\(Int((elapsed * 1000).rounded()))ms reached=\(reached)")
                self.onTakesEvents?(opening)
                return true
            }
            if answered { timer.invalidate() }
        }
        RunLoop.main.add(timer, forMode: .common)
        eventProbe = timer
    }

    /// How long `probeEvents` asks before it hands over anyway: presses handed over reach the editor
    /// whatever the window server says, and a flight kept over the frame for want of an answer
    /// would hide what the editor draws.
    private static let eventProbeDeadline: TimeInterval = 0.5

    /// Whether a press at the frame's centre reaches `win`. This app's windows above it are looked
    /// through: the flight layer covers the frame until the flight has settled.
    private func pressReaches(_ win: NSWindow) -> Bool {
        guard let frameView else { return false }
        let point = win.convertPoint(toScreen: NSPoint(x: frameView.frame.midX, y: frameView.frame.midY))
        var below = 0
        for _ in 0..<8 {
            let number = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: below)
            if number == win.windowNumber { return true }
            guard let above = NSApp.window(withWindowNumber: number), above.level > win.level else { return false }
            below = number
        }
        return false
    }

    /// A press begun on the card flying into this editor, which the flight layer took. Only for the
    /// image open now: a press held for another has nowhere to go.
    func take(_ event: FlightPress.Event, for key: ScreenshotKey) {
        guard current?.key == key else { return }
        editor.take(event)
    }

    /// How long the annotator ignores clicks after its window is ordered in. A race with the window
    /// server, not an animation: fixed, in code, and the motion scale does not touch it.
    private static let outsideClickSettling: TimeInterval = 0.15

    /// The flight is exactly on this frame and is going. The window draws the shadow from here on,
    /// in the same run loop turn the flight drops its own, so it is never drawn twice or missing.
    func landed() {
        run(.landed)
        frameView?.layer?.shadowOpacity = Float(TransitionLayer.Look.annotator(Settings.shared.data.ui).shadowOpacity)
        revealTitle(.landed(at: CACurrentMediaTime()))
    }

    /// The file in the editor was renamed. The editor's drawing follows through `Drawings.rename`.
    func renamed(to shot: Screenshot, opening: Opening) {
        guard current != nil, self.opened == opening else { return }
        current = shot
        opened = opening
    }

    /// Lets the prepared image go without a fit: the session ends before the window came up, so
    /// there is no zoom to undo. Its drawing is parked and stored like any other, since a key
    /// pressed during the flight may have changed it.
    func abandon() {
        guard current != nil else { return }
        // Nothing zooms before the landing, so there is no fit to wait for.
        _ = zoom.reduce(.close)
        revealTitle(.closed)
        outsideClick.stop()
        stopProbe()
        current = nil
        park()
        hideWindows()
    }

    /// Parks the drawing at once and stores it, then removes the window. While zoomed, the window
    /// springs back to the fitted frame first, so the card flies home from where it left. `then`
    /// runs at the fitted frame, in the turn that starts the removal, so the flight home it starts
    /// covers the frame before it goes (`hideWindows`). Called once per `prepare`, by the reducer.
    func hide(then completion: (() -> Void)? = nil) {
        revealTitle(.closed)
        outsideClick.stop()
        stopProbe()
        current = nil
        park()
        fitBeforeHide { [weak self] in
            self?.hideWindows()
            completion?()
        }
    }

    private func stopProbe() {
        eventProbe?.invalidate()
        eventProbe = nil
    }

    private func park() {
        if let drawing = editor.park() { onDrawing?(drawing, "parked") }
    }

    /// Springs the level back to the fitted size and answers once it is there, so the window the
    /// flight takes over from is the frame the flight starts at. The deadline brings the window down
    /// even if the spring never reports arriving.
    private func fitBeforeHide(_ done: @escaping () -> Void) {
        guard case .spring(let level, let seconds)? = zoom.reduce(.close), window != nil else { done(); return }
        var answered = false
        let once = { if !answered { answered = true; done() } }
        zoomTween.animate(to: level, duration: motionScaled(seconds), completion: once)
        DispatchQueue.main.asyncAfter(deadline: .now() + motionScaled(seconds) + 0.3) { once() }
    }

    private func hideWindows() {
        // Nothing here is on screen any more: a spring still ticking would move a hidden frame.
        zoomTween.stop()
        // `hideSoon` takes the bar down only if no other image has asked for it by the next turn
        // of the run loop.
        toolbar.hideSoon()
        // The flight home is added at this frame in this turn, above this window, and starts moving
        // on the next. The window server takes a window down at once, and ordered out here the
        // window left the frame empty for 4 to 9 frames before the flight showed (measured). So the
        // frame is hidden in the commit that starts the flight moving, and the window goes once the
        // display has shown it. The flight casts the shadow from this turn, so it is never doubled.
        // The title goes in that commit too, the one the flight shows its copy in (`leavingAnnotator`).
        frameView?.layer?.shadowOpacity = 0
        removal.start(on: window?.screen, hide: { [weak self] in
            self?.frameView?.isHidden = true
            self?.titleView.show(false, duration: 0)
        }) { [weak self] in
            guard let self else { return }
            window?.orderOut(nil)
            // The window is out of sight, so the screenshot and the marks' layers are let go.
            editor.clear()
        }
    }

    /// Ends the session as Esc would. `open vignette://cancel`. False when nothing was open.
    @discardableResult
    func cancelForDebug() -> Bool {
        guard current != nil else { return false }
        cancel()
        return true
    }

    func cancel(_ how: RunEnding = .back) {
        guard current != nil else { return }
        Log.write("[annotate] cancelled")
        onClosed?(how)
    }

    /// The drawing in the editor, stored before the app quits. The editor parks for it.
    func storeForQuit() {
        guard current != nil else { return }
        park()
    }
}
