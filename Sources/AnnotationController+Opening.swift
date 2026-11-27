import AppKit

// MARK: Opening an image

extension AnnotationController {
    /// Sizes the window to `frame`, opens the image in the editor, and takes the keys, so a key
    /// pressed during the flight already reaches the editor and Esc turns the card around. The
    /// window is ordered in invisible until `show`, and the window server passes every press through
    /// a window it draws nothing of. `room` is the rect the frame may grow within: the visible
    /// screen, less any strip its owner keeps for itself.
    func prepare(_ shot: Screenshot, opening: Opening, in frame: NSRect, room: NSRect) {
        let started = CACurrentMediaTime()
        current = shot
        opened = opening
        // A send still rendering belongs to the session before this one, which its answer will find gone.
        toolbar.model.resetSend()
        editor.closePinList()
        // The window and the editor are this image's now, so the last image's removal must not take them.
        removal.cancel()
        let win = window ?? makeWindow()
        frameView?.isHidden = false
        let ui = Settings.shared.data.ui
        let title = AgentTitleView.Content.of(shot.url)
        titleView.show(false, duration: 0)
        titleView.set(title, ui: ui)
        revealTitle(title == nil ? .closed : .opened)
        zoom.edge = Self.edgePull(ui)
        let bar = self.bar
        toolbar.place(below: frame, gap: bar.margin)
        run(.prepare(fitted: frame, room: Self.room(room, below: title, over: frame, ui: ui), bar: bar))
        zoomTween.set(1)
        place(win, frame: frame)
        measureTitleInk()
        applyCornerRadius()
        editorUntouched = true
        windowUp = false
        win.alphaValue = 0
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        open(shot, opening: opening, started: started)
    }

    /// The room changed under the open image: a Dock appeared, hid or moved, or a screen changed.
    /// `frame` is where it fits now and `room` the rect it may grow within, as `prepare` takes them.
    /// The zoom moves the frame there once the flight has landed (`AnnotatorZoom.refit`).
    func refit(in frame: NSRect, room: NSRect) {
        guard let shot = current else { return }
        let title = AgentTitleView.Content.of(shot.url)
        run(.refit(fitted: frame, room: Self.room(room, below: title, over: frame, ui: Settings.shared.data.ui), bar: bar))
    }

    /// `room` less the block above `frame`, the sender's line and the agent's title, and its margin:
    /// the frame grows no higher than leaves the block on screen. Its height at the fitted frame is the most it takes, since a
    /// wider frame wraps it onto fewer lines.
    private static func room(_ room: NSRect, below title: AgentTitleView.Content?, over frame: NSRect, ui: UITweaks) -> NSRect {
        guard let title else { return room }
        let wrap = StackLayout.titleWrapWidth(frame: frame, room: room, minimum: ui.agentTitleMinWidth,
                                              indent: ui.annotationCornerRadius)
        let above = AgentTitleView.spaceAbove(title, wrap: wrap, ui: ui) + AgentTitleView.marginAbove(ui)
        var room = room
        room.size.height = max(frame.maxY, room.maxY - above) - room.minY
        return room
    }

    /// Opens the drawing with the screenshot's decode at the screen's size: the one a hovered card's
    /// flight already asked for when there is one, else decoded off the main thread and handed to
    /// the editor when it is ready. The drawing opens at once either way, so the keys work from here.
    private func open(_ shot: Screenshot, opening: Opening, started: CFTimeInterval) {
        let key = shot.key.path, name = shot.url.lastPathComponent
        guard let pixels = PixelSize(imageAt: shot.url) else {
            Log.write("[annotate] error \(CommandError.unreadableImage.rawValue) \(name)")
            restoreMessage("")
            cancel(via: .unreadableImage)
            return
        }
        let screen = zoomScreen ?? NSScreen.main ?? NSScreen.screens[0]
        let ui = Settings.shared.data.ui
        // A new drawing is sized for the screen the annotator opens on: Decision 8 in docs/editor.md.
        markScaleRule = ui.markScaleRule
        let drawing = storedDrawing?(shot.key, pixels)
            ?? Drawing(key: key, pixels: pixels, sizedFor: DrawingScreen(screen), rule: markScaleRule).numbered(storedNumbering?(shot.key, pixels))
        let words = storedMessage?(shot.key, pixels) ?? ""
        restoreMessage(words)
        let history = storedHistory?(shot.key, pixels, drawing) ?? EditorHistory()
        let maxPixel = Thumbnailer.screenPixels(on: screen), space = screen.colorSpace?.cgColorSpace
        let decoded = Thumbnailer.cached(at: shot.url, maxPixel: maxPixel, space: space).flatMap(Self.cgImage)
        textStyle = ui.textStyle
        editor.open(drawing, image: decoded, picture: container?.bounds ?? .zero, style: textStyle, metrics: ui.editorMetrics,
                    markStyle: ui.markStyle, selectsNewest: !opening.paged, message: words, history: history)
        pinsBefore = nil
        drawingChanged(drawing)
        editor.noteSettleDuration = Settings.shared.motionUI.noteSettleDuration
        if decoded != nil { loaded(opening, started: started) }
        else {
            Thumbnailer.load(at: shot.url, maxPixel: maxPixel, space: space) { [weak self] image in
                guard let self, self.opening == opening else { return }
                guard let cg = image.flatMap(Self.cgImage) else {
                    Log.write("[annotate] error \(CommandError.unreadableImage.rawValue) \(name)")
                    cancel(via: .unreadableImage)
                    return
                }
                editor.setImage(cg)
                loaded(opening, started: started)
            }
        }
    }

    private func loaded(_ opening: Opening, started: CFTimeInterval) {
        Log.write("[annotate] loaded \(Int((CACurrentMediaTime() - started) * 1000))ms \(opening.key.name)")
        onLoaded?(opening)
    }

    private static func cgImage(_ image: NSImage) -> CGImage? {
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
