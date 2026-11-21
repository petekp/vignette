import AppKit

/// What asked the editor to close, as `[annotate] closed` names it.
enum CloseVia: String {
    /// Esc, pressed with nothing under way in the editor.
    case esc
    /// Cmd+W, or an Esc that reached the window because no view took it.
    case window
    /// The bar's close: Esc typed in its message field.
    case bar
    case clickOutside = "click-outside"
    /// `vignette://cancel`.
    case url
    case unreadableImage = "unreadable-image"
}

/// Hosts the drawing editor in a borderless window. Lifecycle: `prepare` opens the image in the
/// window, ordered in invisible, and gives it the keys; `show` reveals it once the card's flight
/// covers its frame; `hide` parks the drawing at once and removes the window. The editor never
/// hides itself: Esc, a click outside, Cmd+W and Done ask through `onClosed` and `onFinished`, and
/// the transition reducer decides.
@MainActor
final class AnnotationController {
    /// Done: the drawing to render, copy and finish with.
    var onFinished: ((Screenshot, Drawing) -> Void)?
    /// Esc, a click outside, or Cmd+W, and what asked (`CloseVia`). The owner decides what happens
    /// next and calls `hide` when it is time; nothing here hides on its own.
    var onClosed: ((RunEnding, CloseVia) -> Void)?
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
    /// The image fits in this frame now: a re-fit took the new room. The card flies home from here.
    var onRefit: ((NSRect) -> Void)?
    /// Send or Reply handed the drawing to this agent session, with what the sent card calls it and the
    /// message typed in the bar, if any.
    var onSend: ((Screenshot, Drawing, AgentDestination, _ title: String, _ message: String?) -> Void)?
    /// Cmd+C with nothing selected: this drawing's rendering goes on the clipboard.
    var onCopyDrawing: ((Screenshot, Drawing) -> Void)?
    /// Left or Right asked for the screenshot beside this one.
    var onPage: ((EditorCore.Page, _ isRepeat: Bool) -> Void)?

    /// The editor, the whole content of the frame. The state report reads its core.
    let editor = EditorView()
    let toolbar = AnnotatorToolbar()
    /// The session Send keeps after a send to a hand pick, kept in memory only.
    var keptPick: DestinationChoice.KeptPick?
    /// The apps whose windows the open image's capture showed, when it opened from one.
    var captured: [CaptureRect.Owner]?
    let titleView = AgentTitleView()
    var window: AnnotationWindow?
    /// The window spans the screen's visible frame and stays put, until a re-fit grows it to cover
    /// a new visible frame as well (`refitted`). The visible frame is `frameView`
    /// inside it (shadow) with `container` (clip, corner, ring, editor), so a zoom step moves the
    /// frame and the picture inside it in one layer commit: a window resize and a layer change do
    /// not land on the same display frame, and the picture would drift from the frame between them.
    var frameView: NSView?
    var container: NSView?
    /// The display the zoom last fitted the editor to, kept as its number: AppKit makes new `NSScreen`
    /// objects when the screens change, and an old one keeps its old visible frame.
    var zoomDisplay: NSNumber?
    /// The current screen of `zoomDisplay`, nil once that display is gone.
    var zoomScreen: NSScreen? { zoomDisplay.flatMap { shown in NSScreen.screens.first { $0.displayNumber == shown } } }
    /// The shot in the editor, from `prepare` until `hide` parks it. Not the session: see AnnotatorTransition.
    var current: Screenshot?
    let outsideClick = OutsideClick()
    /// Asks the window server, from `show` until it answers, whether a press on the frame reaches this window.
    var eventProbe: Timer?
    /// Takes the frame and then the window down behind the flight home (`hideWindows`).
    let removal = WindowRemoval()
    /// The opening `prepare` was given, so a decode or a send's rendering only lands on the open
    /// that asked for it: the same file can be closed and opened again while the first is on its way.
    var opened: Opening?
    /// No key or press has reached the editor since `prepare`, no session was picked in the target's
    /// menu, and the message field has not taken the keys on its own yet (`offerTyping`).
    var editorUntouched = false
    /// `show` has put this image's window up.
    var windowUp = false
    /// The text style of the tweaks.
    var textStyle = TextStyle.standard
    /// The rule the open drawing's mark scale was last set by, so a change of the rule in the tweaks
    /// rescales it and any other tweak leaves it as it was made.
    var markScaleRule = UITweaks().markScaleRule

    /// Room the annotator needs below its window: the toolbar and its gap.
    var spaceBelow: CGFloat { bar.height + bar.margin }

    /// The toolbar under the frame, with the gap it keeps from the frame, and from the bottom of the
    /// room once a zoomed frame has carried it there.
    var bar: ZoomBar { ZoomBar(height: AnnotatorToolbar.height, margin: Settings.shared.data.ui.annotationToolbarGap) }

    /// Room the annotator needs above its window for `shot` when its title wraps at `wrap`
    /// (`StackLayout.titleWrapWidth`): its agent's title and the gap under it, or nothing for a
    /// screenshot without one.
    func spaceAbove(for shot: Screenshot, wrap: CGFloat) -> CGFloat {
        guard let title = Agent.title(of: shot.url) else { return 0 }
        return AgentTitleView.spaceAbove(title, wrap: wrap, ui: Settings.shared.data.ui)
    }

    /// The zoom's rules and where they put the frame and the picture. The spring is `zoomTween`.
    var zoom = AnnotatorZoom()
    lazy var zoomTween = Tween(initial: 1) { [weak self] level in self?.run(.tick(level)) }
    /// The re-fit's spring, from 0 where the room changed to 1 in the new room.
    lazy var refitTween = Tween(initial: 1) { [weak self] progress in self?.run(.refitTick(progress)) }
    /// Counts the title's ink measurements, so an answer for a block that has moved since is dropped.
    var inkMeasurement = 0
    /// Where the title's ink came from, for `[state]`.
    var inkSource: String?
    /// When the title shows: after the landing, once its ink is known.
    var titleReveal = TitleReveal()

    init() {
        toolbar.onTool = { [weak self] tool in self?.editor.setTool(tool) }
        toolbar.onDone = { [weak self] in self?.editor.done() }
        toolbar.onMessageEnd = { [weak self] in self?.window?.makeKey() }
        toolbar.model.onOfferChanged = { [weak self] offer in self?.offerChanged(offer) }
        toolbar.onSend = { [weak self] destination in self?.editor.send(to: destination) }
        editor.onTool = { [weak self] tool in self?.toolbar.model.tool = tool }
        editor.onChange = { [weak self] drawing in self?.drawingChanged(drawing) }
        editor.onHandOver = { [weak self] drawing in self?.onDrawing?(drawing, "saved") }
        editor.onClose = { [weak self] in self?.cancel(via: .esc) }
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
        toolbar.onPick = { [weak self] in self?.editorUntouched = false }
        toolbar.onClose = { [weak self] in self?.cancel(via: .bar) }
        toolbar.panel.onCommandKey = { [weak self] event in self?.fieldCommand(event) ?? false }
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
        editor.onSend = { [weak self] drawing, chosen in
            guard let self, let shot = current, let destination = chosen ?? toolbar.model.offer.destination else { return }
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
        applyRing()
        measureTitleInk()
        editor.noteSettleDuration = Settings.shared.motionUI.noteSettleDuration
    }

    /// A Command key in the message field that the field has no use for does what it does on the
    /// image. Cmd+W goes through the window's close, as the main menu's Close sends it from the image.
    private func fieldCommand(_ event: NSEvent) -> Bool {
        let key = EditorCore.Key(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers)
        let composing = (toolbar.panel.firstResponder as? NSTextView)?.hasMarkedText() == true
        let fieldEmpty = toolbar.model.fieldEmpty && !composing
        guard let shot = current,
              let command = FieldCommand(key, EditorCore.Modifiers(eventFlags: event.modifierFlags.rawValue),
                                         fieldEmpty: fieldEmpty) else { return false }
        switch command {
        case .close: window?.performClose(nil)
        case .zoom(let request): zoomRequested(request)
        case .copyDrawing: onCopyDrawing?(shot, editor.core.drawingForHost)
        }
        return true
    }
}
