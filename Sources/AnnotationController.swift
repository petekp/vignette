import AppKit

/// Hosts the drawing editor in a borderless window. Lifecycle: `prepare` opens the image in the
/// window, ordered in invisible, and gives it the keys; `show` reveals it once the card's flight
/// covers its frame; `hide` parks the drawing at once and removes the window. The editor never
/// hides itself: Esc, a click outside, Cmd+W and Done ask through `onClosed` and `onFinished`, and
/// the transition reducer decides.
@MainActor
final class AnnotationController {
    /// Done: the drawing to render, copy and finish with.
    var onFinished: ((Screenshot, Drawing) -> Void)?
    /// Esc, a click outside, or Cmd+W. The owner decides what happens next and calls `hide` when
    /// it is time; nothing here hides on its own.
    var onClosed: ((RunEnding) -> Void)?
    /// The editor has this opening's screenshot, decoded at the screen's size.
    var onLoaded: ((Opening) -> Void)?
    /// The window server gives this window the presses on its frame now. Once per `show`.
    var onTakesEvents: ((Opening) -> Void)?
    /// A drawing to store: the editor handed it over after a change, or it was parked. `reason`
    /// names which in the log.
    var onDrawing: ((Drawing, _ reason: String) -> Void)?
    /// The stored drawing for a screenshot whose size as displayed is the given one, if any.
    var storedDrawing: ((ScreenshotKey, PixelSize) -> Drawing?)?
    /// The frame moved: it was placed, a zoom stepped it, or it came home on the way out. The
    /// stack follows it, so it narrows as the frame grows towards it.
    var onFrame: ((NSRect) -> Void)?
    /// Send or Reply handed the drawing to this agent session, with what the sent card calls it and the
    /// message typed in the bar, if any.
    var onSend: ((Screenshot, Drawing, AgentDestination, _ title: String, _ message: String?) -> Void)?
    /// Cmd+C with nothing selected: this drawing's rendering goes on the clipboard.
    var onCopyDrawing: ((Screenshot, Drawing) -> Void)?
    /// Left or Right asked for the screenshot beside this one.
    var onPage: ((EditorCore.Page, _ isRepeat: Bool) -> Void)?

    /// The editor, the whole content of the frame. The state report reads its core.
    let editor = EditorView()
    private let toolbar = AnnotatorToolbar()
    private let titleView = AgentTitleView()
    private var window: AnnotationWindow?
    /// The window spans the screen's visible frame and stays put. The visible frame is `frameView`
    /// inside it (shadow) with `container` (clip, corner, ring, editor), so a zoom step moves the
    /// frame and the picture inside it in one layer commit: a window resize and a layer change do
    /// not land on the same display frame, and the picture would drift from the frame between them.
    private var frameView: NSView?
    private var container: NSView?
    private var zoomScreen: NSScreen?
    /// The shot in the editor, from `prepare` until `hide` parks it. Not the session: see AnnotatorTransition.
    private var current: Screenshot?
    private let outsideClick = OutsideClick()
    /// Asks the window server, from `show` until it answers, whether a press on the frame reaches this window.
    private var eventProbe: Timer?
    /// Takes the frame and then the window down behind the flight home (`hideWindows`).
    private let removal = WindowRemoval()
    /// The opening `prepare` was given, so a decode or a send's rendering only lands on the open
    /// that asked for it: the same file can be closed and opened again while the first is on its way.
    private var opened: Opening?
    /// Where the toolbar's Send or Reply goes once the editor hands over the drawing. A key that
    /// sends goes where the bar's filled button would.
    private var sendingTo: AgentDestination?
    /// No key and no press has reached the editor since `prepare`, and the message field has not
    /// taken the keys on its own yet (`offerTyping`).
    private var editorUntouched = false
    /// `show` has put this image's window up.
    private var windowUp = false
    /// The text style of the tweaks.
    private var textStyle = TextStyle.standard
    /// The rule the open drawing's mark scale was last set by, so a change of the rule in the tweaks
    /// rescales it and any other tweak leaves it as it was made.
    private var markScaleRule = UITweaks().markScaleRule

    /// Room the annotator needs below its window: the toolbar and its gap.
    var spaceBelow: CGFloat { AnnotatorToolbar.height + Settings.shared.data.ui.annotationToolbarGap }

    /// Room the annotator needs above its window for `shot` when its title wraps at `wrap`
    /// (`StackLayout.titleWrapWidth`): its agent's title and the gap under it, or nothing for a
    /// screenshot without one.
    func spaceAbove(for shot: Screenshot, wrap: CGFloat) -> CGFloat {
        guard let title = Agent.title(of: shot.url) else { return 0 }
        return AgentTitleView.spaceAbove(title, wrap: wrap, ui: Settings.shared.data.ui)
    }

    /// The zoom's rules and where they put the frame and the picture. The spring is `zoomTween`.
    private var zoom = AnnotatorZoom()
    private lazy var zoomTween = Tween(initial: 1) { [weak self] level in self?.run(.tick(level)) }
    /// Counts the title's ink measurements, so an answer for a block that has moved since is dropped.
    private var inkMeasurement = 0
    /// Where the title's ink came from, for `[state]`.
    private var inkSource: String?
    /// When the title shows: after the landing, once its ink is known.
    private var titleReveal = TitleReveal()

    init() {
        toolbar.onTool = { [weak self] tool in self?.editor.setTool(tool) }
        toolbar.onDone = { [weak self] in self?.editor.done() }
        toolbar.onMessageEnd = { [weak self] in self?.window?.makeKey() }
        toolbar.model.onOfferChanged = { [weak self] offer in self?.offerChanged(offer) }
        toolbar.onSend = { [weak self] destination in
            guard let self else { return }
            sendingTo = destination
            editor.send()
        }
        editor.onTool = { [weak self] tool in self?.toolbar.model.tool = tool }
        editor.onHandOver = { [weak self] drawing in self?.onDrawing?(drawing, "saved") }
        editor.onClose = { [weak self] in self?.cancel() }
        // One Tab order: the marks, then the toolbar's controls, then the marks again.
        editor.onLeaveCanvas = { [weak self] backward in self?.toolbar.enter(backward: backward) }
        toolbar.onLeave = { [weak self] backward in self?.editor.enterCanvas(backward: backward) ?? false }
        editor.onFocusMessage = { [weak self] in self?.toolbar.focusMessage() }
        // While a control on the bar has the focus ring, the keys are about that control.
        editor.onPage = { [weak self] page, isRepeat in
            guard let self, toolbar.model.focus == nil else { return }
            onPage?(page, isRepeat)
        }
        toolbar.onPage = { [weak self] page, isRepeat in self?.onPage?(page, isRepeat) }
        editor.onPress = { [weak self] in
            self?.editorUntouched = false
            self?.toolbar.clearFocus()
            // AppKit leaves the keys with the bar's panel when the image is pressed (observed
            // 2026-10-11), so the press takes them back; the panel's resign ends the field's focus.
            if let window = self?.window, !window.isKeyWindow { window.makeKey() }
        }
        editor.onKey = { [weak self] in self?.editorUntouched = false }
        toolbar.onClose = { [weak self] in self?.cancel() }
        editor.takesKey = { [weak self] key, modifiers in
            guard let toolbar = self?.toolbar, toolbar.model.focus != nil, modifiers.isSubset(of: .shift) else { return false }
            switch key {
            case .tab: toolbar.move(backward: modifiers.contains(.shift))
            case .character(" ") where modifiers.isEmpty: toolbar.activate()
            default: return false
            }
            return true
        }
        editor.onDone = { [weak self] drawing in
            guard let self, let shot = current else { return }
            onFinished?(shot, drawing)
        }
        editor.onSend = { [weak self] drawing in
            guard let self, let shot = current, let destination = sendingTo ?? toolbar.model.offer.destination else { return }
            sendingTo = nil
            let title = SessionMenu.cardTitle(of: toolbar.model.targetRow(for: destination))
            onSend?(shot, drawing, destination, title, toolbar.model.sentMessage)
        }
        editor.onCopyDrawing = { [weak self] drawing in
            guard let self, let shot = current else { return }
            onCopyDrawing?(shot, drawing)
        }
        editor.onZoom = { [weak self] request in self?.zoomRequested(request) }
        editor.onZoomGesture = { [weak self] event in self?.zoomGesture(event) }
        editor.onReveal = { [weak self] rect in
            guard let self else { return }
            let pixels = editor.core.drawing.pixels
            run(.reveal(rect, image: CGSize(width: pixels.width, height: pixels.height)))
        }
    }

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
        // The window and the editor are this image's now, so the last image's removal must not take them.
        removal.cancel()
        let win = window ?? makeWindow()
        frameView?.isHidden = false
        let ui = Settings.shared.data.ui
        let title = Agent.title(of: shot.url)
        titleView.show(false, duration: 0)
        titleView.set(title, ui: ui)
        revealTitle(title == nil ? .closed : .opened)
        // The frame grows no higher than leaves the title on screen, with its margin above it. Its
        // height at the fitted frame is the most it takes, since a wider frame wraps it onto fewer lines.
        var room = room
        if let title {
            let wrap = StackLayout.titleWrapWidth(frame: frame, room: room, minimum: ui.agentTitleMinWidth,
                                                  indent: ui.annotationCornerRadius)
            let above = AgentTitleView.spaceAbove(title, wrap: wrap, ui: ui) + AgentTitleView.marginAbove(ui)
            let top = max(frame.maxY, room.maxY - above)
            room.size.height = top - room.minY
        }
        zoom.edge = Self.edgePull(ui)
        run(.prepare(fitted: frame, room: room))
        zoomTween.set(1)
        place(win, frame: frame)
        measureTitleInk()
        applyCornerRadius()
        toolbar.place(below: frame, gap: Settings.shared.data.ui.annotationToolbarGap)
        editorUntouched = true
        windowUp = false
        win.alphaValue = 0
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        open(shot, opening: opening, started: started)
    }

    /// Opens the drawing with the screenshot's decode at the screen's size: the one a hovered card's
    /// flight already asked for when there is one, else decoded off the main thread and handed to
    /// the editor when it is ready. The drawing opens at once either way, so the keys work from here.
    private func open(_ shot: Screenshot, opening: Opening, started: CFTimeInterval) {
        let key = shot.key.path, name = shot.url.lastPathComponent
        guard let pixels = PixelSize(imageAt: shot.url) else {
            Log.write("[annotate] error \(CommandError.unreadableImage.rawValue) \(name)")
            cancel()
            return
        }
        let screen = zoomScreen ?? NSScreen.main ?? NSScreen.screens[0]
        let ui = Settings.shared.data.ui
        // A new drawing is sized for the screen the annotator opens on: Decision 8 in docs/editor.md.
        markScaleRule = ui.markScaleRule
        let drawing = storedDrawing?(shot.key, pixels) ?? Drawing(key: key, pixels: pixels, sizedFor: DrawingScreen(screen), rule: markScaleRule)
        let maxPixel = Thumbnailer.screenPixels(on: screen), space = screen.colorSpace?.cgColorSpace
        let decoded = Thumbnailer.cached(at: shot.url, maxPixel: maxPixel, space: space).flatMap(Self.cgImage)
        textStyle = ui.textStyle
        editor.open(drawing, image: decoded, picture: container?.bounds ?? .zero, style: textStyle, metrics: ui.editorMetrics,
                    markStyle: ui.markStyle, selectsNewest: !opening.paged)
        editor.noteSettleDuration = Settings.shared.motionUI.noteSettleDuration
        if decoded != nil { loaded(opening, started: started) }
        else {
            Thumbnailer.load(at: shot.url, maxPixel: maxPixel, space: space) { [weak self] image in
                guard let self, self.opening == opening else { return }
                guard let cg = image.flatMap(Self.cgImage) else {
                    Log.write("[annotate] error \(CommandError.unreadableImage.rawValue) \(name)")
                    cancel()
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

    private func place(_ win: NSWindow, frame: NSRect) {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main ?? NSScreen.screens[0]
        zoomScreen = screen
        if win.frame != screen.visibleFrame { win.setFrame(screen.visibleFrame, display: false) }
        moveFrame(to: frame, picture: zoom.picture)
    }

    /// The one place the frame's rect is set: the frame view, the clip, the shadow's path and the
    /// editor inside it all take it from here, in the same tick, so nothing can be a frame behind.
    /// `frameOnScreen` reads the result back for anyone who needs the rect. `picture` is where the
    /// whole picture sits in the editor, in its coordinates, which run down from the top.
    private func moveFrame(to frame: NSRect, picture: CGRect) {
        guard let win = window, let frameView, let container else { return }
        frameView.frame = NSRect(x: frame.minX - win.frame.minX, y: frame.minY - win.frame.minY, width: frame.width, height: frame.height)
        container.frame = frameView.bounds
        let r = Settings.shared.data.ui.annotationCornerRadius
        frameView.layer?.shadowPath = CGPath(roundedRect: frameView.bounds, cornerWidth: r, cornerHeight: r, transform: nil)
        editor.setSize(container.bounds.size, picture: picture)
        placeTitle(frame: frame)
        onFrame?(frame)
    }

    /// The agent's title above the frame in screen coordinates, while it is shown.
    var titleFrameOnScreen: NSRect? {
        guard let win = window, let frame = titleView.shownFrame else { return nil }
        return win.convertToScreen(frame)
    }

    /// Puts the title above `frame`, in screen coordinates, wrapping where `StackLayout` says.
    private func placeTitle(frame: NSRect) {
        guard let win = window else { return }
        let ui = Settings.shared.data.ui
        let wrap = StackLayout.titleWrapWidth(frame: frame, room: zoom.room, minimum: ui.agentTitleMinWidth,
                                              indent: ui.annotationCornerRadius)
        titleView.place(above: frame.offsetBy(dx: -win.frame.minX, dy: -win.frame.minY), wrap: wrap, ui: ui)
    }

    /// Picks the title's ink for where the block is now. With Screen Recording, from the screen
    /// behind the block, read off the main thread, under the dim. Without it, from the system
    /// appearance: Vignette cannot see other apps' windows then, and a light appearance mostly
    /// means light windows. An answer for a block that has moved since, or an image that has gone,
    /// is dropped.
    private func measureTitleInk() {
        guard titleView.title != nil, current != nil, let win = window else { inkSource = nil; return }
        inkMeasurement += 1
        let measurement = inkMeasurement
        guard CGPreflightScreenCaptureAccess() else {
            applyInk(appearanceInk, source: "appearance", detail: "no screen recording")
            return
        }
        let screen = win.convertToScreen(titleView.frame)
        let primary = StateReport.primaryHeight
        let rect = CGRect(x: screen.minX, y: primary - screen.maxY, width: screen.width, height: screen.height)
        let ui = Settings.shared.data.ui
        Task { [weak self] in
            let cells = await TitleBackdrop.brightness(in: rect, cell: max(ui.dimBlurRadius, 8))
            guard let self, inkMeasurement == measurement, current != nil else { return }
            let luminances = (cells ?? []).map { TitleInk.luminance(encoded: $0, dim: ui.dimOpacity) }
            guard let ink = TitleInk.choose(behind: luminances), let low = luminances.min(), let high = luminances.max() else {
                applyInk(appearanceInk, source: "appearance", detail: "the screen could not be read")
                return
            }
            applyInk(ink, source: "backdrop", detail: String(format: "luminance=%.3f...%.3f", low, high))
        }
    }

    private var appearanceInk: TitleInk {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .black
    }

    private func applyInk(_ ink: TitleInk, source: String, detail: String) {
        titleView.set(ink: ink)
        inkSource = source
        Log.write("[annotate] title ink=\(ink.rawValue) source=\(source) \(detail)")
        revealTitle(.inkKnown(at: CACurrentMediaTime()))
    }

    private func revealTitle(_ input: TitleReveal.Input) {
        switch titleReveal.reduce(input) {
        case .waitForInk?:
            guard let opening = opened else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + TitleReveal.inkWait) { [weak self] in
                guard let self, opened == opening, current != nil else { return }
                revealTitle(.waitEnded(at: CACurrentMediaTime()))
            }
        case .show(let waited)?:
            showTitle(waited: waited)
        case .showInAppearanceInk(let waited)?:
            applyInk(appearanceInk, source: "appearance", detail: "no answer from the screen after \(Self.milliseconds(waited))ms")
            showTitle(waited: waited)
        case nil:
            break
        }
    }

    private func showTitle(waited: TimeInterval) {
        titleView.show(true, duration: Settings.shared.motionUI.agentTitleFade)
        Log.write("[annotate] title shown ink=\(titleView.ink.rawValue) source=\(inkSource ?? "none") waited=\(Self.milliseconds(waited))ms")
    }

    private static func milliseconds(_ seconds: TimeInterval) -> Int { Int((seconds * 1000).rounded()) }

    /// The visible frame in screen coordinates.
    var frameOnScreen: NSRect? {
        guard let win = window, let frameView else { return nil }
        return win.convertToScreen(frameView.frame)
    }

    // MARK: Zoom

    /// Hands `input` to the zoom and does what it answers. A spring that lands at once, at motion 0,
    /// ticks and arrives inside `animate`, after the zoom has answered.
    private func run(_ input: AnnotatorZoom.Input) {
        switch zoom.reduce(input) {
        case .spring(let level, let seconds)?:
            // The title sits over another part of the screen once a step has moved the frame.
            zoomTween.animate(to: level, duration: motionScaled(seconds)) { [weak self] in
                self?.run(.arrived)
                self?.measureTitleInk()
            }
        case .place(let frame, let picture)?:
            guard window != nil else { return }
            moveFrame(to: frame, picture: picture)
        case .movePicture(let picture)?:
            editor.pictureRect = picture
        case nil:
            break
        }
    }

    /// The editor's zoom keys and its double-click on empty space.
    private func zoomRequested(_ request: EditorCore.ZoomRequest) {
        switch request {
        case .zoomIn: run(.zoomIn)
        case .zoomOut: run(.zoomOut)
        case .fit: run(.fit)
        case .smart(let point):
            run(.smart(at: cursorFraction(editor.convert(editor.viewPoint(forImagePoint: point), to: nil))))
        }
    }

    /// A pinch, a scroll or a two-finger double tap over the editor. Cmd or ctrl on a scroll zooms,
    /// as the pinch does; a plain scroll moves the part of a magnified picture in view. A trackpad's
    /// scroll is a gesture, and lifting the fingers lets go of a pull below the fit; momentum after
    /// the lift is ignored, as a pinch's end is, so the zoom stops where the hand did. A mouse wheel
    /// has no phases, and each notch is a step.
    private func zoomGesture(_ event: NSEvent) {
        switch event.type {
        case .magnify:
            if event.phase == .ended || event.phase == .cancelled { run(.lift); return }
            run(.pinch(by: event.magnification, at: cursorFraction(event.locationInWindow)))
        case .smartMagnify:
            run(.smart(at: cursorFraction(event.locationInWindow)))
        case .scrollWheel:
            let line: CGFloat = event.hasPreciseScrollingDeltas ? 1 : Self.wheelLinePoints
            if event.modifierFlags.intersection([.command, .control]).isEmpty {
                run(.pan(by: CGVector(dx: event.scrollingDeltaX * line, dy: event.scrollingDeltaY * line)))
                return
            }
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) { run(.lift); return }
            guard event.momentumPhase.isEmpty else { return }
            run(.wheel(points: event.scrollingDeltaY * line, at: cursorFraction(event.locationInWindow),
                       fingers: !event.phase.isEmpty))
        default:
            break
        }
    }

    /// Zoom's springs are in code rather than in the tweaks, but the motion scale still shortens
    /// them, so `ui.motion: 0` and Reduce Motion land a zoom step at once.
    private func motionScaled(_ seconds: Double) -> Double { seconds * Settings.shared.motionScale }

    private static func edgePull(_ ui: UITweaks) -> AnnotatorZoom.EdgePull {
        AnnotatorZoom.EdgePull(band: ui.zoomEdgeBandPoints, pull: ui.zoomEdgePull)
    }

    /// A line of a mouse wheel's notch in points, for wheels that report lines rather than points.
    private static let wheelLinePoints: CGFloat = 10

    /// A point in the window's coordinates as a fraction of the visible frame, x from the left and
    /// y from the top.
    private func cursorFraction(_ locationInWindow: NSPoint) -> CGPoint? {
        guard let frameView, frameView.bounds.width > 0, frameView.bounds.height > 0 else { return nil }
        let p = frameView.convert(locationInWindow, from: nil)
        return Zoom.clamped(CGPoint(x: p.x / frameView.bounds.width, y: 1 - p.y / frameView.bounds.height))
    }

    // MARK: Showing and hiding

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
    /// the bar has one and no key or press has reached the editor. Once per image, so a field the
    /// keys left is not given them again when the session list answers.
    private func offerTyping() {
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

    /// The agent's title as it is drawn now, for the flight taking `key` home, which carries it from
    /// here. The block stops drawing with the frame (`hideWindows`).
    func takeTitle(of key: ScreenshotKey) -> TransitionLayer.Caption? {
        guard opened?.key == key, let frameView, let image = titleView.picture() else { return nil }
        let offset = CGPoint(x: titleView.frame.minX - frameView.frame.minX, y: frameView.frame.maxY - titleView.frame.maxY)
        return TransitionLayer.Caption(image: image, offset: offset, frameWidth: frameView.frame.width,
                                       opacity: titleView.alphaValue)
    }

    private func stopProbe() {
        eventProbe?.invalidate()
        eventProbe = nil
    }

    private func park() {
        sendingTo = nil
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

    private func makeWindow() -> AnnotationWindow {
        let win = AnnotationWindow(contentRect: .zero, styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false   // the frame view carries the shadow; the window itself is invisible
        win.level = AnnotationWindow.level
        win.isMovableByWindowBackground = false
        win.isReleasedWhenClosed = false
        win.animationBehavior = .none
        win.onCloseRequest = { [weak self] in self?.cancel() }
        let root = NSView()
        root.wantsLayer = true
        let frameView = NSView()
        frameView.wantsLayer = true
        // The same shadow the flight carries into this frame, so the handover shows nothing.
        // AppKit's y points up, so a shadow below the frame is a negative offset.
        let look = TransitionLayer.Look.annotator(Settings.shared.data.ui)
        frameView.layer?.shadowColor = NSColor.black.cgColor
        frameView.layer?.shadowOpacity = Float(look.shadowOpacity)
        frameView.layer?.shadowRadius = look.shadowRadius
        frameView.layer?.shadowOffset = CGSize(width: 0, height: -look.shadowY)
        let container = NSView()
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        // The window server gives a press to the window whose pixel under it is not clear, so this
        // opaque frame takes every press on it, over a screenshot's transparent pixels too, and the
        // clear rest of the window passes presses to the app behind, where `OutsideClick` sees them.
        // That holds only while `ignoresMouseEvents` is never set: once set either way, the window
        // takes or passes every press, whatever its pixels.
        container.layer?.backgroundColor = Config.matte.cgColor
        // Sized by hand, with its picture, in `moveFrame`: a size set without the picture would lay
        // the editor out at a size its picture does not fill.
        editor.autoresizingMask = []
        container.addSubview(editor)
        frameView.addSubview(container)
        root.addSubview(frameView)
        root.addSubview(titleView)
        win.contentView = root
        self.frameView = frameView
        self.container = container
        window = win
        return win
    }

    /// The window's corner and ring match a card's, so the flight from the stack ends on a shape that looks the same.
    private func applyCornerRadius() {
        let ui = Settings.shared.data.ui
        container?.layer?.cornerRadius = ui.annotationCornerRadius
        container?.layer?.cornerCurve = .continuous
        container?.layer?.borderWidth = ui.cardBorderWidth
        container?.layer?.borderColor = NSColor.white.withAlphaComponent(ui.cardBorderOpacity).cgColor
    }

    /// The image in the editor, by path, or nil between sessions.
    var currentKey: ScreenshotKey? { current?.key }

    /// The opening the editor is in, or nil between them. A send compares its rendering's answer
    /// with this rather than the path: after Esc and a reopen of the same image, the path matches
    /// and the opening does not.
    var opening: Opening? { current == nil ? nil : opened }

    /// The tweaks changed: the open editor takes their text style, sizes and arrowhead at once.
    func applyTweaks() {
        let ui = Settings.shared.data.ui
        zoom.edge = Self.edgePull(ui)
        textStyle = ui.textStyle
        var scale: (mark: CGFloat, point: CGFloat)?
        if ui.markScaleRule != markScaleRule, editor.core.isOpen {
            let screen = zoomScreen ?? NSScreen.main ?? NSScreen.screens[0]
            scale = ui.markScaleRule.scale(for: editor.core.drawing.pixels, on: DrawingScreen(screen))
        }
        markScaleRule = ui.markScaleRule
        editor.applyTweaks(style: textStyle, metrics: ui.editorMetrics, markStyle: ui.markStyle, scale: scale)
        titleView.set(titleView.title, ui: ui)
        if let frame = frameOnScreen { placeTitle(frame: frame) }
        measureTitleInk()
        editor.noteSettleDuration = Settings.shared.motionUI.noteSettleDuration
    }

    /// A new image opened: `replyTo` is the session it came from, when it names one, and the list
    /// of sessions is on its way. Read once per image: the list comes from subprocesses, and a menu
    /// that re-read it on every click would stall the bar.
    func beginDestinations(replyTo: AgentDestination?) {
        toolbar.model.begin(replyTo: replyTo, carryingTarget: toolbar.model.shown)
        offered = nil
        logOffer(was: nil)
    }

    /// Another client answered with its sessions, and the pick made from them.
    func destinationsAnswered(_ answer: DestinationChoice.Answer) {
        let before = toolbar.model.offer.destination?.id
        toolbar.model.answered(answer)
        logOffer(was: before)
    }

    /// Where the bar's filled button sent before the person picked another target, and whether it
    /// was a Reply, for `SendContext`. A pick never comes through `logOffer`.
    private(set) var offered: (id: String, reply: Bool)?

    /// Logs where the bar's filled button sends, whenever that changes: the card's own session for a
    /// Reply, else the target. `reply` marks the first, since the target is then not on the bar.
    private func logOffer(was before: String?) {
        let offer = toolbar.model.offer
        guard let to = offer.destination, to.id != before else { return }
        offered = (to.id, !offer.isSend)
        Log.write("[send] target \(to.address.description) project=\(to.detail) focus=\(to.focus?.rawValue ?? "none")\(offer.isSend ? "" : " reply")")
    }

    /// Return and Cmd+Return do what the bar offers, and a message field that arrived with the
    /// session list may take the keys.
    private func offerChanged(_ offer: ToolbarOffer) {
        editor.finishes = offer.finishes
        offerTyping()
    }

    /// True from Send's press until the bar leaves; the button shows the send and takes no second
    /// click. `prepare` resets it.
    var sending: Bool {
        get { toolbar.model.sending }
        set { toolbar.model.sending = newValue }
    }

    /// The send failed before its request was stored, so the drawing is still here: the button says
    /// so, with `reason` beside it, until the person moves on.
    func sendFailed(_ reason: String) { toolbar.model.sendFailed(reason) }

    /// Ends the session as Esc would. `open vignette://cancel`. False when nothing was open.
    @discardableResult
    func cancelForDebug() -> Bool {
        guard current != nil else { return false }
        cancel()
        return true
    }

    private func cancel(_ how: RunEnding = .back) {
        guard current != nil else { return }
        Log.write("[annotate] cancelled")
        onClosed?(how)
    }

    /// The drawing in the editor, stored before the app quits. The editor parks for it.
    func storeForQuit() {
        guard current != nil else { return }
        park()
    }

    var stateJSON: [String: Any] {
        [
            "current": current?.url.path as Any,
            "windowVisible": window?.isVisible ?? false,
            "key": window?.isKeyWindow ?? false,
            "zoom": [zoom.window.width, zoom.window.height],
            "zoomLevel": zoom.level,
            "zoomPhase": zoom.phase.description,
            "canvasZoom": [zoom.camera.width, zoom.camera.height],
            "zoomAnchor": [zoom.anchor.x, zoom.anchor.y],
            "zoomCenter": [zoom.center.x, zoom.center.y],
            "room": StateReport.topLeft(zoom.room, primaryHeight: StateReport.primaryHeight),
            "frame": frameOnScreen.map { StateReport.topLeft($0, primaryHeight: StateReport.primaryHeight) } as Any,
            "toolbar": (toolbar.panel.isVisible ? StateReport.topLeft(toolbar.barFrame, primaryHeight: StateReport.primaryHeight) : nil) as Any,
            "title": titleFrameOnScreen.map { StateReport.topLeft($0, primaryHeight: StateReport.primaryHeight) } as Any,
            "titleInk": (titleFrameOnScreen == nil ? nil : ["ink": titleView.ink.rawValue, "source": inkSource as Any]) as Any,
            "toolbarFocus": toolbar.model.focus?.name as Any,
            "toolbarKey": toolbar.panel.isKeyWindow,
            "tool": toolbar.model.tool?.rawValue as Any,
            "offer": (current == nil ? nil : offerJSON) as Any,
        ]
    }

    /// What the bar offers, and where its filled button sends: the session's id, client, project
    /// and why it is the session you came from, never its title.
    private var offerJSON: [String: Any] {
        let offer = toolbar.model.offer
        var json: [String: Any] = ["listed": toolbar.model.listed]
        switch offer {
        case .copy: json["kind"] = "copy"
        case .choose: json["kind"] = "choose"
        case .send: json["kind"] = "send"
        case .reply: json["kind"] = "reply"
        }
        if let destination = offer.destination {
            json["session"] = destination.id
            json["client"] = destination.client.rawValue
            json["project"] = destination.detail
            json["focus"] = destination.focus?.rawValue as Any
        }
        return json
    }
}

/// An agent's title above the image in the editor: the title in semibold, the description under it
/// in the same colour, fainter, drawn straight on the editor's backdrop, the blur and its dim. Its
/// ink is white or black, whichever stands out more from that backdrop (`TitleInk`). Its left edge
/// is where the frame's top edge comes out of its rounded corner, and it wraps at
/// `StackLayout.titleWrapWidth`. Its text keeps its size at any zoom. It lives in the annotator's
/// window beside the frame, and `AnnotationController.moveFrame` places it, so it moves with the
/// frame in the same commit. It is fileprivate, so nothing outside the editor can draw it: not a
/// card, a rendering, a stitch or a send. The flight home carries a picture of it (`picture`).
@MainActor
fileprivate final class AgentTitleView: NSView {
    private let titleField = AgentTitleView.label()
    private let descriptionField = AgentTitleView.label()
    private(set) var title: AgentTitle?
    private(set) var ink = TitleInk.white
    private var ui = UITweaks()
    private var visible = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        alphaValue = 0
        addSubview(titleField)
        addSubview(descriptionField)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// The image's title, or nil for an image without one, which hides the block at once.
    func set(_ title: AgentTitle?, ui: UITweaks) {
        self.title = title
        self.ui = ui
        if title == nil { show(false, duration: 0) }
        applyText()
    }

    /// Draws the text in `ink`.
    func set(ink: TitleInk) {
        self.ink = ink
        applyText()
    }

    private func applyText() {
        let colour = ink == .white ? NSColor.white : NSColor.black
        titleField.attributedStringValue = Self.text(title?.title, Self.titleFont(ui), colour)
        descriptionField.attributedStringValue = Self.text(title?.description, Self.descriptionFont(ui),
                                                           colour.withAlphaComponent(Self.descriptionOpacity))
    }

    /// How much fainter the description is than the title.
    private static let descriptionOpacity: CGFloat = 0.72

    /// Puts the block above `frame`, in this view's superview's coordinates: its left edge where the
    /// frame's top edge comes out of its rounded corner, its bottom `ui.agentTitleGap` above the
    /// frame's top, and its text wrapping at `wrap`.
    func place(above frame: NSRect, wrap: CGFloat, ui: UITweaks) {
        guard let title else { return }
        let parts = Self.parts(of: title, wrap: wrap, ui: ui)
        let size = Self.size(of: parts, ui: ui)
        self.frame = NSRect(x: frame.minX + ui.annotationCornerRadius, y: frame.maxY + ui.agentTitleGap,
                            width: size.width, height: size.height)
        titleField.isHidden = parts.title == .zero
        descriptionField.isHidden = parts.description == .zero
        var top = bounds.height
        if parts.title != .zero {
            top -= parts.title.height
            titleField.frame = NSRect(x: 0, y: top, width: parts.title.width, height: parts.title.height)
            top -= ui.agentTitleLineGap
        }
        if parts.description != .zero {
            descriptionField.frame = NSRect(x: 0, y: top - parts.description.height,
                                            width: parts.description.width, height: parts.description.height)
        }
    }

    /// Fades the block in or out over `duration`. A later call takes over the fade.
    func show(_ shown: Bool, duration: Double) {
        let target: CGFloat = shown && title != nil ? 1 : 0
        visible = target == 1
        guard alphaValue != target, duration > 0 else { return fade.set(target) }
        fade.animate(to: target, duration: duration)
    }

    private lazy var fade = Tween(initial: 0) { [weak self] alpha in self?.alphaValue = alpha }

    /// The block as drawn, at full opacity, or nil while none of it shows.
    func picture() -> NSImage? {
        guard title != nil, alphaValue > 0, let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    /// The block's frame for `[state]`, in the window's coordinates, or nil while it is not shown.
    var shownFrame: NSRect? { visible ? frame : nil }

    // MARK: Measuring

    /// How much room the block takes above the frame when it wraps at `wrap`: its own height and the
    /// gap under it. What the editor's room keeps for it (`StackLayout.annotationFrame`,
    /// `AnnotationController.prepare`).
    static func spaceAbove(_ title: AgentTitle, wrap: CGFloat, ui: UITweaks) -> CGFloat {
        size(of: parts(of: title, wrap: wrap, ui: ui), ui: ui).height + ui.agentTitleGap
    }

    /// The least room between the block and the top of the zoom's room: twice the gap under it.
    static func marginAbove(_ ui: UITweaks) -> CGFloat { 2 * ui.agentTitleGap }

    /// The block's size: as wide as its longest line, and as tall as its lines.
    private static func size(of parts: (title: NSSize, description: NSSize), ui: UITweaks) -> NSSize {
        let both = parts.title != .zero && parts.description != .zero
        return NSSize(width: ceil(max(parts.title.width, parts.description.width)),
                      height: ceil(parts.title.height + parts.description.height + (both ? ui.agentTitleLineGap : 0)))
    }

    /// Each part's size as its label draws it, wrapping at `wrap`. `.zero` for a part the title lacks.
    private static func parts(of title: AgentTitle, wrap: CGFloat, ui: UITweaks) -> (title: NSSize, description: NSSize) {
        let wrap = max(1, wrap)
        func measure(_ string: String?, _ font: NSFont) -> NSSize {
            guard let string else { return .zero }
            measuring.attributedStringValue = text(string, font, .labelColor)
            let size = measuring.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: wrap, height: .greatestFiniteMagnitude))
            return NSSize(width: min(wrap, ceil(size.width)), height: ceil(size.height))
        }
        return (measure(title.title, titleFont(ui)), measure(title.description, descriptionFont(ui)))
    }

    private static let measuring = label()

    private static func label() -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: "")
        field.isSelectable = false
        field.lineBreakMode = .byWordWrapping
        field.cell?.truncatesLastVisibleLine = false
        return field
    }

    private static func titleFont(_ ui: UITweaks) -> NSFont { .systemFont(ofSize: ui.agentTitleSize, weight: .semibold) }
    private static func descriptionFont(_ ui: UITweaks) -> NSFont { .systemFont(ofSize: ui.agentDescriptionSize) }

    private static func text(_ string: String?, _ font: NSFont, _ colour: NSColor) -> NSAttributedString {
        NSAttributedString(string: string ?? "", attributes: [.font: font, .foregroundColor: colour])
    }
}
