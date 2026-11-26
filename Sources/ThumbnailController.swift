import AppKit
import SwiftUI

/// Owns the bottom-right panel: fresh-screenshot thumbnails, the recent stack, the marks on cards,
/// and the transitions into and out of the annotator.
@MainActor
final class ThumbnailController {
    weak var actions: Actions?
    /// Which screenshots have a drawing, and each one read for its card.
    var drawings: Drawings?
    /// The file in the annotator was renamed; the opening keeps its id.
    var onAnnotatorRenamed: ((Screenshot, Opening) -> Void)?
    /// A card starts travelling to `frame`; the annotator loads the image there while hidden.
    /// `room` is the rect its frame may grow within, which a zoom may not leave.
    var onAnnotatorPrepare: ((Screenshot, Opening, NSRect, NSRect) -> Void)?
    /// The Dock or a screen changed under the annotator's image: its new frame and room.
    var onAnnotatorRefit: ((NSRect, NSRect) -> Void)?
    var onAnnotatorLifted: (() -> Void)?
    /// The flight covers the annotator's frame; the window comes up behind it and takes the keys.
    var onAnnotatorShow: ((_ watchesClickOutside: Bool) -> Void)?
    /// The flight is exactly on the frame; the annotator draws the shadow itself from here on.
    var onAnnotatorLanded: (() -> Void)?
    /// A swap, return, or dismissal has started. The annotator parks its drawing, hides, then calls back.
    var onAnnotatorHide: ((_ hidden: @escaping () -> Void) -> Void)?
    /// The session ends before the window came up. The annotator stores the drawing and lets the image go, with no fit-out.
    var onAnnotatorAbandon: (() -> Void)?
    /// Space the annotator needs below its window, for the toolbar.
    var annotatorBelow: () -> CGFloat = { 0 }
    /// Space the annotator needs above its window for this screenshot when its title wraps at a
    /// width: its agent's title, or nothing.
    var annotatorAbove: (Screenshot, _ wrap: CGFloat) -> CGFloat = { _, _ in 0 }
    /// The editor's marks, whose text bitmaps a flight to or from the annotator takes.
    var annotatorMarks: () -> MarkLayers? = { nil }
    /// The agent's title above the editor, for the flight taking that image home, which carries it.
    var annotatorTitle: (ScreenshotKey) -> TransitionLayer.Caption? = { _ in nil }
    /// A press begun on the card flying into the editor, for the image with this key; see `FlightPress`.
    var onAnnotatorPress: ((FlightPress.Event, ScreenshotKey) -> Void)?
    /// What the cards a drag out of the stack drop; see `StackModel.drags`.
    var drags: DragItems? {
        get { model.drags }
        set { model.drags = newValue }
    }

    private let panel = ThumbnailPanel()
    /// Who has the keys, the backdrop, the watch for a click outside and the focus going back: only
    /// through events sent here (`CornerPresentation`).
    lazy var keys = CornerKeys(panel: panel, screen: { [unowned self] in self.screen })
    private let dim = DimPanel()
    private let flights = TransitionLayer()
    let model = StackModel()
    let timeline = UndoTimeline()
    let older = OlderShots()
    let pictures = CardPictures()
    private var hosting: NSHostingView<StackView>!
    /// When a lone thumbnail leaves the corner (`leaveCorner(after:)`).
    private var leaveTimer: Timer?
    /// When the hover follows the pointer again after the wheel (`holdHover()`).
    private var wheelSettling: Timer?
    /// Names the recent screenshots, and the log's detail about them, for the stack the shortcut
    /// opens. Asked only then, after the panel has taken the keys, so a key pressed while a large
    /// folder is listed reaches it.
    var recentListing: () -> (shots: [Screenshot], detail: String) = { ([], "") }
    var visible = false {
        didSet {
            // Flight decodes are screen-sized; they are only worth keeping while the stack is up.
            if !visible { flightImages.removeAll() }
            else { areaReader.presented() }
        }
    }
    private var dismissGeneration = 0
    private var shrinkGeneration = 0
    private var stitchGeneration = 0
    private lazy var sweep = StackSweep(
        model: model, screen: { [unowned self] in self.screen },
        column: { [unowned self] in
            StackSweep.Column(layout: self.layout, cards: self.cardSizes, contentHeight: self.drawnContentHeight, maxScroll: self.maxScroll)
        },
        isVisible: { [unowned self] in self.visible }, selected: { [unowned self] in self.keys.send(.selected) },
        relayout: { [unowned self] in self.relayout() })
    private lazy var swipe = StackSwipeDriver(model: model, screen: { [unowned self] in self.screen }) { [unowned self] in self.dismiss(by: .swipe) }
    /// The one owner of the annotation run, its queue included. Only `handle` writes it; see AnnotationRun.
    private(set) var run = AnnotationRun()
    /// The card the run has open, kept here because a lone thumbnail leaves the model once the annotator shows.
    private var sessionCard: Card?
    private var annotating: Card? { run.isActive ? sessionCard : nil }
    private var annotationFrame: NSRect = .zero
    /// The editor's card and its offscreen slot as the column slides out.
    private var leavingWithColumn: (id: UUID, to: NSRect)?
    /// The editor's marks as its park left them, until the flight home has taken their texts. The
    /// editor lets them go once it is hidden, which is before the card is sent home.
    private var parkedMarks: MarkLayers?
    /// Where a press on a flying card goes.
    var flightPress = FlightPress()
    /// The agent's marks `show` brought, drawn on top until kept or cleared, and the calls waiting for the hand.
    let pendingMarks = PendingMarks()
    var showQueue = ShowQueue<ShowCall>()
    var showWait: Timer?, dimTimer: Timer?
    /// Cards made in this turn whose stored drawings are still to be read. A stack opening makes
    /// every card in one turn, and reading theirs together gives the column one change of `cards`.
    private var drawingReads: [ScreenshotKey] = []
    private lazy var flightImages = FlightImages(model: model, flights: flights, screen: { [unowned self] in self.screen },
                                                 isVisible: { [unowned self] in self.visible })

    init() {
        hosting = NSHostingView(rootView: StackView(model: model))
        panel.contentView = hosting
        panel.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        panel.timeline = timeline
        connectTimeline()
        keys.perform = { [weak self] effect in self?.perform(effect) }
        keys.changed = { [weak self] old, new in self?.presentationChanged(from: old, to: new) }
        flights.onPress = { [weak self] id, event in self?.flightPressed(id, event) }
        panel.onScroll = { [weak self] event in self?.scroll(event) }
        model.scrolled = { [weak self] in self?.scrolled(towardOlder: $0) }
        model.onAction = { [weak self] action, cards in
            guard let self else { return }
            if cards.count == 1, let index = self.model.cards.firstIndex(where: { $0.id == cards[0].id }) { self.scrollToReveal(index) }
            self.run(action, on: cards)
        }
        model.onClickImage = { [weak self] card in
            guard let self else { return }
            // A recording opens in its own app whatever else is going on; it never takes the
            // annotator's place, so a drawing in progress is left where it is.
            if card.shot.kind == .recording, !self.model.inSelectionMode {
                if let open = Config.defaultAction(for: [card.shot]) { self.run(open, on: [card]) }
                return
            }
            // Where the card is now, before opening it narrows the stack or takes it out of the column.
            let slot = self.cardFrame(of: card)
            // A click picks the next image by hand, so it replaces whatever the queue had left.
            if self.run.isActive { self.send(.annotate([card.shot.key])); self.swallowSecondClick(on: slot); return }
            if self.model.inSelectionMode { self.toggle(card) }
            else if let action = Config.defaultAction(for: [card.shot]) {
                self.run(action, on: [card])
                if action.id == "annotate" { self.swallowSecondClick(on: slot) }
            }
        }
        model.onSweep = { [weak self] y in self?.sweep.move(toYFromTop: y) }
        model.onSweepEnd = { [weak self] in
            guard let self else { return }
            self.sweep.end()
            self.revealFocused()
        }
        model.onHover = { [weak self] id in
            guard let self else { return }
            self.flightImages.prefetch(id)
            // Focus follows the pointer: one variable says where a key acts, and moving onto a card
            // moves it there. Leaving a card leaves the focus behind, so keys still act on the card
            // the pointer last named. Only while the stack holds the keys and nothing is in the
            // annotator: the stack keeps them through the flight out, and a key there is about the
            // card that is flying, not the one the cursor happens to be over.
            if let id, self.keys.isKeyed { self.model.focused = id }
        }
        model.onSelectionChanged = { [weak self] added, removed in self?.selectionChanged(added: added, removed: removed) }
    }

    /// The screen a presentation started on. `NSScreen.main` follows the active display, which is
    /// what the user is looking at; pinning it keeps every frame of one presentation on one screen.
    /// The display is pinned rather than its `NSScreen`: AppKit makes new `NSScreen` objects when the
    /// screens change, a Dock that moves or hides included, and an old one keeps its old visible frame.
    private var pinnedDisplay: NSNumber?
    /// Where on screen the file in `annotate`'s request was captured, until its `prepare` uses it.
    private var captureOrigin: (key: ScreenshotKey, rect: NSRect)?
    var screen: NSScreen {
        if let pinnedDisplay, let pinned = NSScreen.screens.first(where: { $0.displayNumber == pinnedDisplay }) { return pinned }
        return NSScreen.main ?? NSScreen.screens[0]
    }
    /// A display was added, removed, or rearranged. Whatever is showing moves to a screen that exists.
    func screensChanged() {
        defer {
            dim.refit(to: screen)
            if let card = annotating { onAnnotatorRefit?(targetFrame(for: currentCard(card)), annotatorRoom) }
        }
        guard visible else { return }
        if pinnedDisplay != nil { pinnedDisplay = screen.displayNumber }
        Log.write("[screen] changed; relayout on \(screen.localizedName)")
        relayout()
        keys.refreshBackdrop(on: screen)
    }

    private lazy var areaReader = StackAreaReader(isVisible: { [unowned self] in self.visible },
                                                  relayout: { [unowned self] in self.relayout() })
    private var area: StackArea { areaReader.area }

    /// The cards as they are drawn now: at the stack's full width, or narrowed for the annotator.
    var cardSizes: [NSSize] { model.cards.map { layout.drawn($0.size) } }
    var ui: UITweaks { Settings.shared.motionUI }
    var layout: StackLayout { StackLayout.current.at(widthScale: model.widthScale) }
    private var showsStrip: Bool { model.isStack && model.inSelectionMode }

    /// The selection strip's screen frame, or nil when nothing is selected or the annotator has an
    /// image. Asked here and in `StackView`, never in `showsStrip`: that one sizes the panel, and
    /// the panel's window must not be resized while a session is running.
    private var stripFrame: NSRect? {
        guard !model.annotating else { return nil }
        guard showsStrip, let strip = layout.stripPlacement(rows: Config.stripRows.count, selection: model.selectedIndices(),
                                                            cards: cardSizes,
                                                            scroll: model.scroll, viewport: model.viewport) else { return nil }
        let reveal = layout.stripReveal(rows: StackLayout.stripRows)
        return layout.stripFrame(strip, panelFrame: panel.frame, scroll: model.scroll, reveal: reveal, safeBottom: area.safeBottom)
    }


    /// The stack, the transition, and the screen, for the `[state]` line. Frames in global top-left points.
    var stateJSON: [String: Any] {
        let h = StateReport.primaryHeight
        let s = screen
        return [
            "stack": [
                "visible": visible, "isStack": model.isStack,
                "cards": model.cards.indices.map { i -> [String: Any] in
                    let card = model.cards[i]
                    let notice = model.notices.notice(on: card.shot.key)
                    var notCopied: String?
                    if case .notCopied(let reason)? = notice { notCopied = reason }
                    return ["file": card.shot.key.path, "frame": StateReport.topLeft(cardFrame(i), primaryHeight: h),
                            "out": model.outCards.contains(card.id), "forming": model.forming.contains(card.id),
                            "drawing": drawings?.keys.contains(card.shot.key) ?? false, "agent": card.agent as Any,
                            "kind": card.shot.kind == .recording ? "recording" : "image",
                            "copied": notice?.kind == .copied,
                            "notCopied": notCopied as Any, "notSaved": notice?.kind == .notSaved,
                             "shown": model.shown[card.id].map(Self.shownJSON) as Any,
                             "agentMarks": pendingMarks[card.shot.key]?.drawing.marks.count ?? 0]
                },
                "selected": model.selectedCards().map(\.shot.key.path),
                "queue": run.queue.map(\.path), "showsWaiting": showQueue.waiting.count, "dimsUnshown": model.dimsUnshown,
                "focused": model.cards.first { $0.id == model.focused }?.shot.key.path as Any,
                "hovered": model.cards.first { $0.id == model.hoveredCard }?.shot.key.path as Any,
                "key": panel.isKeyWindow,
                "scroll": Int(model.scroll), "viewport": Int(model.viewport), "safeBottom": Int(area.safeBottom),
                "widthScale": model.widthScale, "swipe": Int(model.swipe), "older": older.state,
                "panel": StateReport.topLeft(panel.frame, primaryHeight: h), "panelOnScreen": panel.isVisible,
                "strip": stripFrame.map { StateReport.topLeft($0, primaryHeight: h) } as Any,
                "undoTitle": timeline.menuTitle(for: UndoTimeline.undoAction) ?? "Undo",
                "redoTitle": timeline.menuTitle(for: UndoTimeline.redoAction) ?? "Redo",
            ] as [String: Any],
            "transition": ["phase": "\(run.phase)", "annotating": annotating?.shot.key.path as Any, "isActive": run.isActive],
            "screen": ["name": s.localizedName, "frame": StateReport.topLeft(s.frame, primaryHeight: h),
                       "visibleFrame": StateReport.topLeft(s.visibleFrame, primaryHeight: h), "scale": s.backingScaleFactor, "pinned": pinnedDisplay != nil],
            "backdrop": keys.backdropState,
            "dim": dim.stateJSON,
        ]
    }

    // MARK: Public

    /// A fresh screenshot. Joins the bottom of whatever is showing; on its own it leaves after a
    /// few seconds unless hovered. A `drawing` already known, as a live ink note's is, is on the card
    /// from its first frame rather than after the drawings are read.
    func show(_ shot: Screenshot, drawing: Drawing? = nil) {
        guard var card = makeCard(shot) else { return }
        if let drawing { card.marks = marks(drawing, on: card) }
        // A new shot never closes an open annotator: the reducer answers `join` and the card joins the panel.
        send(.newShot(shot.key))
        if visible { insert(card) } else { present(cards: [card]) }
        // An agent's card is something to read, not the echo of a capture the person just made.
        leaveCorner(after: ui.thumbnailSeconds * (card.agent == nil ? 1 : 2))
    }

    enum StackToggle: Equatable { case shown(Int), dismissed, empty }

    var stackShowing: Bool { visible && keys.isStack }

    /// The stack or the annotator is up, or a card lands to make the stack: no live ink.
    var holdsScreen: Bool { visible && (keys.isStack || keys.becomesStack) || run.isActive }
    /// The stack or the annotator is coming up: `holdsScreen` turns true.
    var onTakesScreen: (() -> Void)?
    /// The session a card came from, which a send back to it makes "Replied" (`ScreenshotRequests.origin(of:)`).
    var origin: (URL) -> AgentDestination? = Agent.origin(of:)
    /// Why the session's queue holds the last send of the file at a URL, nil when it holds none
    /// (`ScreenshotRequests.queuedSend(of:)`).
    var queuedSend: (URL) -> Card.Queued? = { _ in nil }

    /// The card with the keyboard focus ring, while the stack is up.
    var focusedShot: Screenshot? { model.cards.first { $0.id == model.focused }?.shot }

    /// The recent stack: toggles. Takes keyboard focus. Stays until Esc, the hotkey, or a click elsewhere.
    @discardableResult
    func toggleRecent(by request: StackRequest) -> StackToggle {
        let wasStack = keys.isStack
        // `CornerKeys` takes a panel off screen for an empty corner, and orders it out again if no
        // stack follows; a lone card on its way home has its panel off screen until it lands.
        orderPanelIn()
        keys.send(.shortcut(request))
        if keys.isStack { return .shown(model.cards.count) }
        return wasStack ? .dismissed : .empty
    }

    /// Lists the recent screenshots for the shortcut and presents them as the stack.
    private func openRecent() {
        let asked = CACurrentMediaTime()
        let (shots, detail) = recentListing()
        let started = CACurrentMediaTime()
        let cards = keptShown() + shots.filter { shownCard(of: $0) == nil }.compactMap { makeCard($0) }
        if !cards.isEmpty {
            present(cards: cards)
            Log.write("[stack] shown cards=\(cards.count) \(detail)listed=\(Int((started - asked) * 1000))ms shown=\(Int((CACurrentMediaTime() - started) * 1000))ms decoding=\(cards.filter { $0.image == nil }.count)")
        }
        keys.send(.listed(found: !cards.isEmpty))
    }

    /// The cards' side of what `CornerPresentation` decided; `CornerKeys` has run the window side.
    private func perform(_ effect: CornerPresentation.Effect) {
        switch effect {
        case .takeKeys(let focus):
            switch focus {
            case .card(let id) where model.cards.contains(where: { $0.id == id }): model.focused = id
            default: if model.focused == nil { model.focused = model.hoveredCard ?? model.cards.first?.id }
            }
        case .releaseKeys:
            model.focused = nil
        case .closeEditor:
            run.logClosing(by: "shortcut")
            send(.cancel(.shortcut))
        case .listRecent:
            openRecent()
        case .slideOut(let reason):
            slideOut(reason)
        case .holdKeys, .restoreFocus:
            break
        }
    }

    /// The model follows the presentation, and a column that does not leave on its own has no
    /// timer. Becoming the stack, by any hand, takes the screen from live ink.
    private func presentationChanged(from old: CornerPresentation, to new: CornerPresentation) {
        model.follow(new)
        if !new.leavesOnItsOwn { leaveTimer?.invalidate() }
        guard new.isStack, !old.isStack else { return }
        onTakesScreen?()
        if new.mode == .stack(recent: false) { Log.write("[stack] corner became the stack cards=\(model.cards.count)") }
    }

    /// Opens the annotator on the first of `shots` and queues the rest: finishing one opens the
    /// next, until the list is done. The selection is untouched by the whole run, so the same cards
    /// can be copied or stitched after the last one. `origin` is where on screen a new capture was
    /// taken; its flight starts there instead of at its card.
    func annotate(_ shots: [Screenshot], from origin: NSRect? = nil) {
        guard let first = shots.first else { return }
        // A flight from the capture starts over the very pixels it shows, so it waits for the
        // picture: the card's own is not decoded yet, and a flight with none shows nothing until it
        // arrives, then appears part way along. Until it starts, the screen shows the same pixels.
        if let origin, let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: origin.midX, y: origin.midY)) }) {
            let maxPixel = Thumbnailer.screenPixels(on: screen), space = screen.colorSpace?.cgColorSpace
            if Thumbnailer.cached(at: first.url, maxPixel: maxPixel, space: space) == nil {
                Thumbnailer.load(at: first.url, maxPixel: maxPixel, space: space) { [weak self] _ in
                    self?.startAnnotating(shots, from: origin)
                }
                return
            }
        }
        startAnnotating(shots, from: origin)
    }

    private func startAnnotating(_ shots: [Screenshot], from origin: NSRect?) {
        guard let first = shots.first else { return }
        captureOrigin = origin.map { (first.key, $0) }
        // A file that cannot be read never reaches the run, so an image already open stays open.
        guard openableCard(for: first) != nil else { captureOrigin = nil; return }
        send(.annotate(shots.map(\.key)))
    }

    /// The card `shot` opens from, made now if the panel does not have it. Nil when its header does
    /// not read, which is logged here.
    private func openableCard(for shot: Screenshot) -> Card? {
        if visible {
            // A shot the panel does not have yet joins it; the flight starts from its offscreen slot.
            if card(for: shot) == nil, let card = makeCard(shot) { insert(card) }
            if let card = card(for: shot) { return card }
        } else if let card = makeCard(shot) {
            // Not on screen: the card flies straight from its offscreen slot, so nothing waits for a slide-in.
            present(cards: [card], entrance: .stayOffscreen)
            return card
        }
        Log.write("[annotate] error \(CommandError.unreadableImage.rawValue) \(shot.url.lastPathComponent)")
        return nil
    }

    /// The editor asked to close (Esc, click outside, Cmd+W). The run decides what returns, and
    /// drops the rest of its list.
    func annotationEnded(_ how: RunEnding, _ via: CloseVia) {
        run.logClosing(by: via.rawValue)
        send(.cancel(how))
    }

    /// Send: the drawing is stored as a request and the card comes home without a Copied notice.
    /// The run carries on, because a queue is a list the person asked for and sending one of its
    /// cards to an agent does not withdraw the rest; only Esc, which is a person stopping, empties
    /// it. Copying is Done's, so the card comes home unmarked.
    func annotationSent() {
        send(.sent)
    }

    /// Done or Return: the result is on the clipboard. The card comes back marked copied; in quick
    /// mode everything closes instead.
    func annotationFinished(quick: Bool) {
        guard quick else { return send(.finish) }
        if visible { dismiss(by: .quickDone) } else { send(.dismiss(.finished)) }
    }

    /// Left or Right in the editor: the screenshot beside the one the editor shows or is opening, in
    /// the corner's order, or a beep at either end. A key's repeat never beeps.
    func page(_ page: EditorCore.Page, isRepeat: Bool) {
        guard run.takesPage(isRepeat: isRepeat), let from = run.heading else { return }
        guard let next = model.neighbor(of: from, page) else { if !isRepeat { NSSound.beep() }; return }
        if let index = model.cards.firstIndex(where: { $0.id == next.id }) { scrollToReveal(index) }
        send(.page(next.shot.key, isRepeat: isRepeat))
    }

    /// The editor has the screenshot for `opening`.
    func editorLoaded(_ opening: Opening) {
        send(.loaded(opening))
    }

    /// The annotator's window for `opening` takes presses now.
    func annotatorTakesEvents(_ opening: Opening) {
        send(.takesPresses(opening))
    }

    /// A press, drag or release on a flying card. See `FlightPress`.
    private func flightPressed(_ id: UUID?, _ event: FlightPress.Event) {
        let key: ScreenshotKey?
        let now: [FlightPress.Event]
        if case .pressed = event.phase {
            key = id.flatMap(keyFlyingIn)
            now = flightPress.press(event, into: key, ready: key != nil && run.takesPresses)
        } else {
            key = flightPress.key
            now = flightPress.move(event)
        }
        guard let key else { return }
        for event in now { onAnnotatorPress?(event, key) }
    }

    /// The image the flight `id` is carrying into the editor, nil for a flight going anywhere else.
    private func keyFlyingIn(_ id: UUID) -> ScreenshotKey? {
        sessionCard?.id == id ? keyInEditor : nil
    }

    /// The image on its way into the editor or in it, nil while none is or while it parks.
    private var keyInEditor: ScreenshotKey? {
        switch run.phase {
        case .flyingOut(let opening), .annotating(let opening): return opening.key
        case .idle, .parking: return nil
        }
    }

    /// The screenshot at `key` has this drawing now, or none: its card draws it at once, and so does
    /// the card in the annotator, which a lone thumbnail keeps out of the column.
    func setDrawing(_ drawing: Drawing?, for key: ScreenshotKey) { setDrawings([key: drawing]) }

    /// Each key's drawing, or none, reaching the column in one change of `cards`.
    private func setDrawings(_ drawings: [ScreenshotKey: Drawing?]) {
        var cards = model.cards, changed = false
        for index in cards.indices {
            guard let drawing = drawings[cards[index].shot.key] else { continue }
            let marks = marks(drawing, on: cards[index])
            if marks !== cards[index].marks { cards[index].marks = marks; changed = true }
        }
        if changed { model.cards = cards }
        guard let card = sessionCard, let drawing = drawings[card.shot.key] else { return }
        sessionCard?.marks = model.cards.first { $0.id == card.id }.map(\.marks) ?? marks(drawing, on: card)
    }

    /// Sets what the tabs of `shot`'s cards say about its last send, the editor's card included.
    func setSent(_ sent: Card.Sent?, of shot: Screenshot) {
        if model.cards.contains(where: { $0.shot.url == shot.url && $0.sent != sent }) {
            model.cards = model.cards.map { card in
                guard card.shot.url == shot.url else { return card }
                var card = card
                card.sent = sent
                return card
            }
        }
        if sessionCard?.shot.url == shot.url { sessionCard?.sent = sent }
    }

    /// Reads the drawings of the cards made since the last read, together.
    private func readDrawings() {
        let keys = drawingReads
        drawingReads = []
        guard let drawings, !keys.isEmpty else { return }
        drawings.load(keys, style: ui.textStyle) { [weak self] loaded in self?.setDrawings(loaded) }
    }

    /// `card`'s marks for `drawing`: the ones it has, shown anew, while they are on the same image.
    private func marks(_ drawing: Drawing?, on card: Card) -> MarkLayers? {
        guard let drawing else {
            card.marks?.clear()
            return nil
        }
        var marks = card.marks
        if marks?.pixels != drawing.pixels || marks?.isParked == true {
            marks?.clear()
            marks = MarkLayers(pixels: drawing.pixels, queue: MarkLayers.cardQueue)
            marks?.setScale(screen.backingScaleFactor)
        }
        // At the card's size at rest: a stack narrowed for the annotator shows the same bitmaps smaller.
        marks?.show(drawing, filling: card.size, backingScale: screen.backingScaleFactor, style: ui.textStyle, markStyle: ui.markStyle)
        return marks
    }

    /// Drops cards whose files no longer exist.
    func remove(_ shots: [Screenshot]) {
        let urls = Set(shots.map(\.url))
        send(.remove(shots.map(\.key).sorted()))
        for card in model.cards where urls.contains(card.shot.url) { flights.end(id: card.id) }
        sweep.end()
        // When no card would be left, they slide out with the panel rather than vanish, and the
        // slide-out's end takes them out. A panel already sliding out is left to that end too.
        if !visible || model.cards.allSatisfy({ urls.contains($0.shot.url) }) { dismiss(by: .removed); return }
        removeCards { urls.contains($0.shot.url) }
        model.setSelection(model.selection.filter { id in model.cards.contains { $0.id == id } })
        relayout()
    }

    /// Files renamed inside the folder. Each card keeps its id, its place, its selection and its focus,
    /// and takes the new file; the run, the notices and the flight state follow it.
    func rename(_ pairs: [(from: ScreenshotKey, to: ScreenshotKey)]) {
        for (old, new) in pairs where old != new {
            guard !model.cards.contains(where: { $0.shot.key == new }) else {
                remove([Screenshot(key: old)])
                continue
            }
            let shot = Screenshot(key: new)
            model.cards = model.cards.map { $0.shot.key == old ? $0.with(shot: shot) : $0 }
            if sessionCard?.shot.key == old { sessionCard = sessionCard?.with(shot: shot) }
            model.notices.rename(from: old, to: new)
            if captureOrigin?.key == old { captureOrigin?.key = new }
            flightImages.rename(from: old, to: new)
            drawingReads = drawingReads.map { $0 == old ? new : $0 }
            flightPress.rename(from: old, to: new)
            pendingMarks.rename(from: old, to: new)
            send(.renamed(from: old, to: new))
            if let opening = run.opening, opening.key == new { onAnnotatorRenamed?(shot, opening) }
        }
        timeline.rename(pairs)
    }

    /// Re-applies layout tweaks to whatever is on screen. Called when settings.ui changes.
    func applyTweaks() {
        let style = ui.textStyle, markStyle = ui.markStyle
        // Marks drawn outside the column: in flight, and a lone thumbnail's while its image is in the annotator.
        flights.restyle(style, markStyle: markStyle)
        sessionCard?.marks?.restyle(style, markStyle: markStyle)
        guard visible else { return }
        model.cards = model.cards.enumerated().map { index, card in
            let size = layout.cardSize(for: card.pointSize)
            // A file not downloaded keeps its picture, since a decode downloads it; a card far from view keeps none.
            let image = card.image == nil || Thumbnailer.isDataless(card.shot.url) ? card.image
                : Thumbnailer.image(at: card.shot.url, maxPixel: thumbnailPixels(size: size, pointSize: card.pointSize),
                                    space: screenSpace, caches: cachesPicture(at: index)) ?? card.image
            if let marks = card.marks, let drawing = marks.drawing {
                marks.show(drawing, filling: size, backingScale: screen.backingScaleFactor, style: style, markStyle: markStyle)
            }
            return card.with(size: size).with(image: image)
        }
        relayout()
        keys.refreshBackdrop(on: screen)
    }

    /// The stitched file is written: the cards it was made from converge into its slot and the new
    /// card takes their place as the newest. The originals leave the stack; their files are
    /// untouched, so the next stack open has them back. False when the stack is not showing all of
    /// them, and the caller shows the stitched card as it would any copy. Copied waits for `copied`.
    ///
    /// The watcher reports the new file a moment later like any capture. The card is already in the
    /// column by then, so `insert` ignores it; with `annotateOnCapture` on, the same report carries
    /// it into the annotator from the slot the stitch just filled.
    @discardableResult
    func stitched(_ pieces: [Screenshot], into key: ScreenshotKey, copied: PendingRendering? = nil) -> Bool {
        guard visible, model.isStack, !run.isActive, pieces.count > 1 else { return false }
        let cards = pieces.compactMap { shot in model.cards.first { $0.shot.key == shot.key } }
        guard cards.count == pieces.count, let result = makeStitchedCard(key), let stitched = result.image else { return false }
        // Where each card is now, while the selection bar is still part of the column, with its marks
        // made before the card lets its own go.
        let flying = cards.map { card in
            let drawing = card.marks?.drawing
            let scale = drawing.map { max(cardTextScale(card.size, $0.pixels), cardTextScale(result.size, $0.pixels)) } ?? 0
            return (id: card.id, image: flightImages.image(for: card), marks: flightMarks(drawing, scale: scale, adopting: [card.marks]),
                    from: cardFrame(of: card))
        }
        let ids = Set(cards.map(\.id))
        model.forming.formUnion(ids)
        model.forming.insert(result.id)
        if let focused = model.focused, ids.contains(focused) { model.focused = nil }
        removeCards { ids.contains($0.id) }
        model.clearSelection()
        sweep.end()
        model.cards.insert(result, at: 0)
        withAnimation(Anim.spring(ui.relayoutDuration)) { model.scroll = 0 }
        relayout()
        stitchGeneration += 1
        let generation = stitchGeneration
        flights.converge(pieces: flying, result: (id: result.id, image: stitched, frame: cardFrame(of: result)),
                         look: .card(ui), on: screen) { [weak self] in
            guard let self else { return }
            self.model.forming.subtract(ids)
            self.model.forming.remove(result.id)
            guard self.stitchGeneration == generation else { return }
            // Copied comes back as the lone thumbnail if the stack has gone, so a stitch never ends in silence.
            self.showCopied([result.shot], after: copied)
        }
        Log.write("[stack] stitched cards=\(cards.count) into=\(key.name)")
        return true
    }

    /// The stitched image decodes here and not on the background queue `makeCard` uses: the card is
    /// the destination of a flight that starts in the same run loop turn, so it cannot arrive later.
    private func makeStitchedCard(_ key: ScreenshotKey) -> Card? {
        let url = key.url
        guard let pointSize = Thumbnailer.pointSize(of: url) else { return nil }
        let size = layout.cardSize(for: pointSize)
        guard let image = Thumbnailer.image(at: url, maxPixel: thumbnailPixels(size: size, pointSize: pointSize), space: screenSpace) else { return nil }
        return Card(id: UUID(), shot: Screenshot(key: key), image: image, pointSize: pointSize, size: size,
                    agent: Agent.of(url), duration: Thumbnailer.duration(of: url), sent: sent(of: url))
    }

    /// The Copied notice over the cards themselves. With nothing on screen, the first of them comes
    /// up as the lone thumbnail wearing the notice, as a failed send's card does, and the notice counts
    /// the rest. `label` is what the notice says, since what was copied is the caller's to name.
    func showCopied(_ shots: [Screenshot], label: String = "Copied") {
        var label = label
        if !shots.contains(where: isSeen), let first = shots.first {
            show(first)
            if shots.count > 1 { label += " \(shots.count)" }
        }
        // A card still on its way back from the annotator shows the notice when it lands.
        for shot in shots where isSeen(shot) { post(.copied(label: label), on: shot) }
    }

    /// A failure on `shot`'s card, which keeps Copied off it if it is parking after Done in `opening`.
    func showFailed(_ notice: CardNotices.Event, on shot: Screenshot, in opening: Opening?) {
        if let opening { send(.failed(opening)) }
        post(notice, on: shot)
    }

    /// The annotator's opening of `shot`, if it holds or is parking that one.
    func opening(of shot: Screenshot) -> Opening? { run.key == shot.key ? run.opening : nil }

    /// The person sees `shot`'s card, or will when it lands: it is on screen, or in the annotator,
    /// whose card comes home wearing whatever was posted meanwhile.
    func isSeen(_ shot: Screenshot) -> Bool {
        (visible && card(for: shot) != nil) || run.key == shot.key
    }

    /// Puts the notice on `shot`'s card, brings the card up when nobody would see it otherwise, and
    /// takes the notice down after its hold. The notice's hold sets the corner's time. With `comesUp`
    /// false a card off screen stays off: the notice is still posted and expires on time, and does not
    /// hold the corner for a card nobody sees.
    func post(_ event: CardNotices.Event, on shot: Screenshot, comesUp: Bool = true) {
        let file = shot.key, seen = isSeen(shot)
        guard let posted = model.notices.post(event, on: file, seen: seen, noticeHold: ui.markSeconds + ui.expandDuration) else { return }
        if !seen && comesUp { show(shot) }
        guard let hold = posted.hold else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) { [weak self] in self?.model.notices.expire(posted.id) }
        if seen || comesUp { leaveCorner(after: hold) }
    }

    /// Closes the corner, whatever it shows.
    func dismiss(by reason: DismissReason) {
        guard visible else { return }
        keys.send(.dismiss(reason))
    }

    /// The column leaves. Quick Done and a click outside close by hand: the focus goes back once the
    /// annotator is gone.
    private func slideOut(_ reason: DismissReason) {
        guard visible else { return }
        Log.write("[stack] dismissed by=\(reason.rawValue) stack=\(model.isStack) cards=\(model.cards.count)")
        visible = false
        dismissGeneration += 1
        let gen = dismissGeneration
        leaveTimer?.invalidate()
        // A stitch still converging ends with the stack: its pieces stop where they are, and the
        // new card, an empty slot while its image was in the layer, slides out with the column.
        if !model.forming.isEmpty {
            for id in model.forming { flights.end(id: id) }
            model.forming = []
        }
        // An image still flying home from the editor leaves too.
        for card in model.cards where card.id != annotating?.id && model.outCards.contains(card.id) && flights.isFlying(card.id) {
            leaveWithColumn(card, to: layout.offscreen(cardFrame(of: card)), marks: flights.marks(of: card.id))
        }
        // The editor's image goes once the editor is down, after any fit-out.
        leavingWithColumn = annotating.flatMap { card in
            model.cards.contains { $0.id == card.id } ? (card.id, layout.offscreen(cardFrame(of: card))) : nil
        }
        model.slidingOut = true
        if run.isActive { send(.dismiss(reason.runEnding)) }
        // Cards leave the way they came, newest first (see CardView). The selection stays in the
        // layout and slides out with them; the block below clears it once gone.
        if reason == .swipe { swipe.leave() }
        model.offscreen = Set(model.cards.map(\.id))
        let total = ui.slideOutDuration + Double(max(0, model.cards.count - 1)) * StackView.staggerStep(count: model.cards.count) + 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + (model.cards.isEmpty ? ui.slideOutDuration : total)) { [weak self] in
            guard let self, self.dismissGeneration == gen, !self.visible else { return }
            self.panel.orderOut(nil)
            self.model.removeCards { _ in true }
            self.model.clearSelection()
            self.model.offscreen = []
            self.model.outCards = []
            self.model.forming = []
            self.model.slidingOut = false
            self.model.scroll = 0
            self.swipe.reset()
            self.pinnedDisplay = nil
            self.keys.send(.slidOut)
        }
    }

    /// Flies `card`'s image to `slot` on the column's spring.
    private func leaveWithColumn(_ card: Card, to slot: NSRect, marks: MarkLayers?) {
        Log.write("[stack] leaves with the column \(card.shot.key.name)")
        flights.fly(id: card.id, image: flightImages.image(for: currentCard(card)), marks: marks, caption: annotatorTitle(card.shot.key),
                    from: annotationFrame, to: slot, leavingAnnotator: true, lookFrom: .annotator(ui), lookTo: .card(ui),
                    spring: ui.slideOutDuration, on: screen, arrived: { [weak self] in
            self?.flights.end(id: card.id)
        })
    }

    // MARK: Annotation run. The run decides; this section only runs its effects.

    private let hold = EventHold<AnnotationRun.Event>()

    /// Every event reaches the run here. One that arrives while another is being handled, as a park
    /// or a flight answering inside the effects that asked for it, runs right after it.
    func send(_ event: AnnotationRun.Event) {
        hold.send(event) { handle($0) }
    }

    private func handle(_ event: AnnotationRun.Event) {
        run.logClosing(byEvent: event)
        // Asked before anything moves: a file the queue opens gets its card made here, and one
        // that has none is passed over.
        let effects = run.reduce(event) { key in openableCard(for: Screenshot(key: key)) != nil }
        Log.write("[transition] \(event) -> \(run) effects=\(effects.map(\.description).joined(separator: " "))")
        // The stack's width is set before this batch's flights are aimed, so a swap's returning
        // card and the card leaving are aimed at one column, and so are a queue's finished card and
        // the next one. The card leaving is still drawn at the width the stack had, so it flies from
        // the slot it has now.
        let leaving = preparedCard(in: effects)
        let slot = leaving.map { cardFrame(of: $0) }
        if leaving != nil || releasesRoom(effects) {
            makeRoom(besides: leaving.map { targetFrame(for: $0) }, animated: true)
        }
        for effect in effects { follow(effect) { perform(effect, leaving: slot) } }
        // A press held for, or handed to, an image that is no longer on its way in or in the editor.
        if let key = flightPress.key, key != keyInEditor {
            flightPress.ended(key)
        }
        // The editor is open exactly while the run is: from its first `prepare`, after the
        // annotator's window has taken the keys, so they pass from one to the other rather than
        // being nobody's, to its `endRun`.
        if model.annotating != run.isActive {
            model.annotating = run.isActive
            flights.staysUp = run.isActive
            var ending: RunEnding?
            for case .endRun(let how) in effects { ending = how }
            keys.send(run.isActive ? .editorOpened : .editorClosed(ending))
        }
    }

    /// While an image is in the annotator, a card selected in the stack is queued to be annotated
    /// next, in the order picked, and one deselected leaves the queue: the same run a selection
    /// starts when Draw is pressed on it. Recordings never reach the annotator.
    private func selectionChanged(added: [UUID], removed: [UUID]) {
        guard run.isActive else { return }
        func keys(_ ids: [UUID]) -> [ScreenshotKey] {
            ids.compactMap { id in model.cards.first { $0.id == id } }.filter { $0.shot.kind == .image }.map(\.shot.key)
        }
        send(.selectionChanged(added: keys(added), removed: keys(removed)))
    }

    /// The card a `prepare` in this batch sends to the annotator, if the stack has it.
    private func preparedCard(in effects: [AnnotationRun.Effect]) -> Card? {
        for case .prepare(let opening) in effects { return model.cards.first { $0.shot.key == opening.key } }
        return nil
    }

    /// Whether this batch takes the annotator off the screen, so nothing is beside the stack.
    private func releasesRoom(_ effects: [AnnotationRun.Effect]) -> Bool {
        effects.contains { effect in
            if case .returnCard = effect { return true }
            return effect == .hideAnnotator
        }
    }

    private func perform(_ effect: AnnotationRun.Effect, leaving slot: NSRect?) {
        switch effect {
        case .prepare(let opening):
            let key = opening.key
            guard let card = model.cards.first(where: { $0.shot.key == key }) else { return }
            onTakesScreen?()
            sessionCard = card
            leaveTimer?.invalidate()
            for page in [EditorCore.Page.older, .newer] { flightImages.prefetch(model.neighbor(of: key, page)?.id) }
            // The selection stays: the card comes back to its slot, and a queued run needs the rest
            // of it to still be there when the last card is done.
            _ = model.outCards.insert(card.id)
            let target = targetFrame(for: card)
            annotationFrame = target
            dim.show(on: screen)
            parkedMarks = nil
            flights.annotatorStoppedDrawing()   // it draws this image from here, so not the one leaving
            shownCardOpens(card, opening: opening)
            onAnnotatorPrepare?(card.shot, opening, target, annotatorRoom)
            var from = slot ?? cardFrame(of: card)
            if model.offscreen.contains(card.id) { from = layout.offscreen(from) }
            // A capture starts where it was taken, looking like the screen there. The flight is
            // drawn on one screen, so a capture on another one starts at its card. A window's
            // shadow may run past the screen's edge, where the flight is cut off as the shadow was.
            var lookFrom = TransitionLayer.Look.card(ui)
            if let origin = captureOrigin, origin.key == key {
                captureOrigin = nil
                if screen.frame.contains(CGPoint(x: origin.rect.midX, y: origin.rect.midY)) {
                    from = origin.rect
                    lookFrom = .screen
                    Log.write("[annotate] from capture \(StateReport.topLeft(from, primaryHeight: StateReport.primaryHeight)) \(card.shot.url.lastPathComponent)")
                }
            }
            // Two moments. The window comes up at `covered`, where the flight is past the frame and
            // covers it, so it can take the keys and the pointer while the eye already reads the
            // card as still. The shadow and the picture change hands at `arrived`, on the exact
            // frame: the window draws the same ring and shadow there, so handing either over while
            // the spring still had a few points to go would step against the picture the flight is
            // showing.
            flights.fly(id: card.id, image: flightImages.image(for: card), marks: outFlightMarks(for: card, to: target), from: from, to: target,
                        lookFrom: lookFrom, lookTo: .annotator(ui), on: screen, covered: { [weak self] in
                self?.send(.shown(opening))
            }, arrived: { [weak self] in
                self?.send(.arrived(opening))
            }, dropped: { [weak self] in
                // The layer went down between the two moments — a new capture presenting the panel
                // anew while a lone thumbnail is being annotated. Nothing covers the window now.
                self?.onAnnotatorLanded?()
                self?.onAnnotatorLifted?()
            })
        case .show:
            onAnnotatorShow?(!keys.isStack)
            guard let card = sessionCard else { return }
            // A lone thumbnail alone in the corner leaves it. With other cards there, its slot stays
            // empty, as the stack's does, so it comes home to the same place.
            if !model.isStack, model.isAlone(card.id) { takeOutOfPanel(card) }
        case .park(let opening):
            parkedMarks = annotatorMarks()
            onAnnotatorHide? { [weak self] in self?.send(.parked(opening)) }
        case .abandon:
            // Before the editor lets its marks go: the flight home carries what the abandon parks.
            parkedMarks = annotatorMarks()
            onAnnotatorAbandon?()
        case .returnCard(let opening, let copied):
            guard let card = sessionCard, card.shot.key == opening.key else { return }
            returnCard(currentCard(card), copied: copied)
        case .hideAnnotator:
            // The image follows its slot off the screen, unless the stack came back during a fit-out.
            if let card = sessionCard, let leaving = leavingWithColumn, leaving.id == card.id, !visible {
                leaveWithColumn(card, to: leaving.to, marks: homeFlightMarks(for: currentCard(card)))
            } else if let card = sessionCard {
                model.outCards.remove(card.id)
                flights.end(id: card.id)
            }
            leavingWithColumn = nil
            parkedMarks = nil
        case .join:
            break   // `show(_:)` inserts the card; the run only confirms the annotator stays open.
        case .next(let key, let place, let total):
            Log.write("[annotate] next \(key.name) \(place) of \(total)")
        case .queued(let key, let place, let total):
            Log.write("[annotate] queued \(key.name) \(place) of \(total)")
        case .endRun:
            // Only now: between two files of a list the dim stays up and the focus stays here.
            sessionCard = nil
            dim.hide()
        case .landed:
            // Also while the image parks: Done or Esc is accepted between `covered` and the
            // arrival, and the window stays up through the park, still owed its shadow.
            guard let card = sessionCard else { return }
            onAnnotatorLanded?()
            flights.dropShadow(id: card.id)
        case .handOverPresses(let opening):
            for event in flightPress.ready(opening.key) { onAnnotatorPress?(event, opening.key) }
        case .liftFlight:
            guard let card = sessionCard else { return }
            takeFlightTexts(card)
            flights.lift(id: card.id)
            onAnnotatorLifted?()
        }
    }

    private func returnCard(_ card: Card, copied: Bool) {
        if leavesAtOnce(card, copied: copied) { return flyAway(card) }
        if !model.cards.contains(where: { $0.id == card.id }) {
            // A lone thumbnail left the panel when the annotator opened (see `.show`); it comes back
            // to the corner as an empty slot the flight lands on. No slide-in: the flight is the entrance.
            // The panel goes on screen once the flight covers the slot. Ordered in during this turn,
            // directly under the flight layer, it held this turn's change to the layer back, and the
            // image's shadow went missing (docs/exit-panel-2026-11-01.md).
            if visible { insert(card, entrance: .inPlace) } else { present(cards: [card], entrance: .inPlace, ordersPanel: false) }
            _ = model.outCards.insert(card.id)
        }
        // Shown when the card lands, like every notice on a card still on its way back.
        if copied { showCopied([card.shot]) }
        guard visible, model.cards.contains(where: { $0.id == card.id }) else {
            model.outCards.remove(card.id); flights.end(id: card.id); return
        }
        // The card takes its slot back only once the flight has settled on it: the card draws at the
        // exact slot, so a card and a shadow put there while the flight still had a few points to
        // go would both step. Nothing is visible before then; the flight covers the slot.
        flights.fly(id: card.id, image: flightImages.image(for: card), marks: homeFlightMarks(for: card), caption: annotatorTitle(card.shot.key),
                    from: annotationFrame, to: cardFrame(of: card), leavingAnnotator: true, lookFrom: .annotator(ui), lookTo: .card(ui), on: screen,
                    covered: { [weak self] in self?.orderPanelIn() }, arrived: { [weak self] in
            guard let self else { return }
            self.model.outCards.remove(card.id)
            self.hover(landing: card)
            self.flights.dropShadow(id: card.id)   // the card draws it now, in this same commit
            // The card view comes back on SwiftUI's next commit; lift the flight image after it.
            DispatchQueue.main.async { self.flights.lift(id: card.id) }
            if self.visible { self.keys.send(.cardLanded(card.id, others: !self.model.isAlone(card.id))) }
            // A card that lands with a notice left the corner's time to the notice.
            if !self.showsNotice(card) { self.leaveCorner(after: self.ui.thumbnailSeconds) }
        })
    }

    /// A lone thumbnail that comes home with no notice to show, and nothing else in the corner, is
    /// done: it leaves at once rather than waiting out its time there. `copied` is the notice it is
    /// about to take.
    private func leavesAtOnce(_ card: Card, copied: Bool) -> Bool {
        keys.leavesOnItsOwn && !copied && !showsNotice(card) && model.isAlone(card.id)
    }

    /// A notice is up on `card`. Each one set the corner's time when it went up.
    private func showsNotice(_ card: Card) -> Bool { model.notices.notice(on: card.shot.key) != nil }

    /// The image flies from the editor into the corner and on off the screen's edge: the offscreen
    /// slot a lone thumbnail slides in from, which is also where `annotate` flies a card from when
    /// nothing is on screen.
    private func flyAway(_ card: Card) {
        // Esc during the flight out: the card has not left the panel yet (see `.show`).
        if model.cards.contains(where: { $0.id == card.id }) { takeOutOfPanel(card) }
        areaReader.read(on: screen, layout: layout)
        let slot = layout.offscreen(layout.loneCardFrame(size: card.size, area: area))
        flights.fly(id: card.id, image: flightImages.image(for: card), marks: homeFlightMarks(for: card), caption: annotatorTitle(card.shot.key),
                    from: annotationFrame, to: slot, leavingAnnotator: true, lookFrom: .annotator(ui), lookTo: .card(ui), on: screen, arrived: { [weak self] in
            self?.flights.end(id: card.id)
            card.marks?.clear()   // the card is gone for good, as `removeCards` would have it
        })
    }

    /// A lone thumbnail alone in the corner has nothing to keep open behind the annotator; cards that
    /// join meanwhile stay. Its marks stay with it, for the flight home.
    private func takeOutOfPanel(_ card: Card) {
        model.cards.removeAll { $0.id == card.id }
        model.outCards.remove(card.id)
        if model.cards.isEmpty { visible = false; panel.orderOut(nil) } else { relayout() }
    }

    /// Swallows every press on the slot a click just opened a card from, for as long as a second
    /// click would make it a double click. Opening narrows the stack away from the slot and can
    /// slide another card into it, so that second click would reach the app behind or open that
    /// card. The slot is as the hovered card drew it, since that is where the click was.
    private func swallowSecondClick(on slot: NSRect) {
        flights.swallowPresses(in: layout.hovered(slot), for: NSEvent.doubleClickInterval, on: screen)
    }

    /// Hovers the card that has just landed when the pointer is on it, and only then. Its flight
    /// covered the slot, and a pointer that moved over the flight gave the stack a hover exit
    /// wherever the pointer was, so the stack's own hover state says nothing about this card.
    private func hover(landing card: Card) {
        let point = NSEvent.mouseLocation
        let over = cardFrame(of: card).contains(point)
            && NSApp.window(withWindowNumber: NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)) != nil
        if over { model.hoveredCard = card.id } else if model.hoveredCard == card.id { model.hoveredCard = nil }
    }

    /// The flight from `card` to the annotator at `frame` carries the drawing the editor has just
    /// opened, which is what it hands over to; the card's own until the editor has one.
    private func outFlightMarks(for card: Card, to frame: NSRect) -> MarkLayers? {
        let editor = annotatorMarks().flatMap { $0.drawing?.key == card.shot.key.path ? $0 : nil }
        guard let drawing = editor?.drawing ?? card.marks?.drawing else { return nil }
        let scale = max(annotatorTextScale(frame, drawing.pixels), cardTextScale(card.size, drawing.pixels))
        return flightMarks(drawing, scale: scale, adopting: [flights.marks(of: card.id), card.marks, editor])
    }

    /// The flight from the annotator back to `card` carries the drawing the editor parked, a flight
    /// turned around in mid-air included; the flight's own, or the card's, when the editor had none.
    private func homeFlightMarks(for card: Card) -> MarkLayers? {
        let key = card.shot.key
        let editor = [parkedMarks, annotatorMarks()].compactMap { $0 }.first { $0.drawing?.key == key.path }
        parkedMarks = nil
        let flying = flights.marks(of: card.id)
        guard let drawing = editor?.drawing ?? flying?.drawing ?? card.marks?.drawing else { return nil }
        let scale = max(annotatorTextScale(annotationFrame, drawing.pixels), cardTextScale(card.size, drawing.pixels))
        return flightMarks(drawing, scale: scale, adopting: [editor, flying, card.marks])
    }

    /// The editor takes over from the flight into it: a text whose bitmap the editor has not drawn yet
    /// shows the flight's until it has, so no text goes missing when the flight lifts.
    private func takeFlightTexts(_ card: Card) {
        guard let flying = flights.marks(of: card.id), let editor = annotatorMarks(), editor.drawing?.key == card.shot.key.path else { return }
        editor.adopt(from: flying)
    }

    private func targetFrame(for card: Card) -> NSRect {
        layout.annotationFrame(for: card.pointSize, visibleFrame: annotatorRoom, below: annotatorBelow()) { [annotatorAbove] in
            annotatorAbove(card.shot, $0)
        }
    }

    /// The rect the annotator fits and grows within. The recent stack keeps a strip of the screen
    /// on the right, so a wide image opens and zooms beside the cards instead of over them; a lone
    /// thumbnail leaves the panel when the annotator opens and reserves nothing.
    private var annotatorRoom: NSRect {
        guard visible, model.isStack else { return screen.visibleFrame }
        return layout.annotatorRoom(visibleFrame: screen.visibleFrame)
    }

    func annotatorRefitted(_ frame: NSRect) { annotationFrame = frame }

    /// The annotator's frame moved: a zoom step, or the fit it makes on its way out. The stack
    /// follows it straight rather than through a spring of its own, so the two move together and a
    /// frame that has grown never reaches a card that has not narrowed yet.
    func annotatorFrameMoved(_ frame: NSRect) {
        makeRoom(besides: frame, animated: false)
    }

    /// How wide the stack is drawn: the widest that still clears the annotator's frame by the gap,
    /// down to `ui.stackMinScale`, and back to full width when nothing is beside it.
    private func makeRoom(besides frame: NSRect?, animated: Bool) {
        guard visible, model.isStack else { return }
        let wanted = frame.map { layout.widthScale(clearing: $0, visibleFrame: screen.visibleFrame) } ?? 1
        // In hundredths: a zoom moves the frame at every display refresh, and a step under two
        // points of a card's width is not worth laying the column out for. Rounded down, so the
        // gap the stack keeps is never smaller than the one asked for.
        let next = min(1, (wanted * 100).rounded(.down) / 100)
        guard abs(next - model.widthScale) > 0.0001 else { return }
        var transaction = Transaction(animation: animated ? Anim.spring(ui.relayoutDuration) : nil)
        transaction.disablesAnimations = !animated
        // Narrower cards are a shorter column; the panel keeps the height it has at rest. The
        // scroll follows the column's height, so the cards in view stay in view and the column
        // comes back to the same place when the stack widens again.
        let before = drawnContentHeight
        withTransaction(transaction) {
            model.widthScale = next
            let after = drawnContentHeight
            let followed = before > 0 ? model.scroll * after / before : model.scroll
            model.scroll = min(followed, max(0, after - model.viewport))
        }
    }

    private func cardFrame(of card: Card) -> NSRect {
        guard let index = model.cards.firstIndex(where: { $0.id == card.id }) else { return annotationFrame }
        return cardFrame(index)
    }

    private func cardFrame(_ index: Int) -> NSRect {
        layout.cardFrame(index: index, cards: cardSizes, panelFrame: panel.frame,
                         scroll: model.scroll, safeBottom: area.safeBottom)
    }

    // MARK: Scrolling

    /// The column's height as it is drawn now, at the stack's width scale. `layoutPanel` sizes the
    /// panel from the full-width height instead, so a narrowed stack keeps the panel it comes back to.
    var drawnContentHeight: CGFloat { layout.contentHeight(cards: cardSizes) }

    var maxScroll: CGFloat { max(0, drawnContentHeight - model.viewport) }

    private func scroll(_ event: NSEvent) {
        guard visible else { return }
        switch swipe.scroll(event) {
        case .scrollColumn(let delta): scrollColumn(by: delta)
        case .moved: holdHover()
        case .none, .close: break
        }
    }

    private func scrollColumn(by delta: CGFloat) {
        defer { columnMoved(towardOlder: delta > 0) }
        guard maxScroll > 0 else { return }
        // Pulling the column down (fingers moving down) reveals older cards above.
        let next = min(maxScroll, max(0, model.scroll + delta))
        guard next != model.scroll else { return }
        holdHover()
        model.scroll = next
    }

    /// How long the column stands still after the wheel moved it before the hover follows the
    /// pointer again. A mouse wheel's events, and a script's, carry no phase that says the scroll
    /// ended, so a quiet interval is the end every device gives. Chromium waits up to 100 ms after a
    /// trackpad's fingers lift for momentum to begin; this is longer, so a fling's momentum keeps
    /// the hold.
    private static let wheelSettle: TimeInterval = 0.15

    /// Keeps the hover, and with it the focus, where they are while the wheel moves the column.
    /// Otherwise every card passing under the pointer takes the hover and runs its springs
    /// (docs/hover-hold-2026-10-30.md).
    private func holdHover() {
        model.holdsHover = true
        wheelSettling?.invalidate()
        wheelSettling = Timer.scheduledTimer(withTimeInterval: Self.wheelSettle, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hoverAfterWheel() }
        }
    }

    /// The card under the pointer takes the hover, tested as `hover(landing:)` tests one card:
    /// SwiftUI reported the cards passing under the pointer while the hover was held, and reports
    /// nothing more once the column stops.
    private func hoverAfterWheel() {
        model.holdsHover = false
        guard visible else { return }
        let point = NSEvent.mouseLocation
        let overThisApp = NSApp.window(withWindowNumber: NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)) != nil
        let under = overThisApp ? model.cards.indices.first { cardFrame($0).contains(point) } : nil
        let id = under.map { model.cards[$0].id }
        if model.hoveredCard != id { model.hoveredCard = id }
    }

    // MARK: Internals

    func card(for shot: Screenshot) -> Card? {
        model.cards.first { $0.shot.url == shot.url }
    }

    private func currentCard(_ card: Card) -> Card {
        model.cards.first { $0.id == card.id } ?? card
    }

    private func replaceImage(of card: Card, with image: NSImage?) {
        model.cards = model.cards.map { $0.id == card.id ? $0.with(image: image) : $0 }
    }

    /// A card appears at once; if its thumbnail is not cached yet it arrives a moment later. A file
    /// that is not downloaded is never read here: its card takes the shape kept for it, or the
    /// screen's until iCloud's thumbnail arrives, and a screenshot is downloaded in the background
    /// for the editor. A recording is not downloaded, and its badge shows no length.
    func makeCard(_ shot: Screenshot, lookup: Thumbnailer.Lookup? = nil, caches: Bool = true) -> Card? {
        let header: Thumbnailer.Header
        var notDownloaded = false
        switch lookup ?? Thumbnailer.lookUp(shot.url) {
        case .read(let read): header = read
        case .notDownloaded(let kept):
            notDownloaded = true
            header = kept ?? Thumbnailer.Header(size: screen.frame.size, duration: nil, exact: false)
        case .unreadable: return nil
        }
        let size = layout.cardSize(for: header.size)
        let maxPixel = notDownloaded ? cloudThumbnailPixels : thumbnailPixels(size: size, pointSize: header.size)
        let space = screenSpace
        let card = Card(id: UUID(), shot: shot, image: Thumbnailer.cached(at: shot.url, maxPixel: maxPixel, space: space),
                        pointSize: header.size, size: size, agent: Agent.of(shot.url), duration: header.duration,
                        agentMarks: agentMarkLayers(for: shot.key, size: size),
                        sent: sent(of: shot.url))
        if card.image == nil {
            Thumbnailer.loadCard(at: shot.url, maxPixel: maxPixel, space: space, caches: caches) { [weak self] image, kept in
                guard let self, self.model.cards.contains(where: { $0.id == card.id }) else { return }
                if let image { self.replaceImage(of: card, with: image) }
                if notDownloaded, let kept { self.reshape(card.id, to: kept) }
            }
        }
        if notDownloaded, shot.kind == .image {
            Thumbnailer.download(shot.url) { [weak self] header in
                if let header { self?.reshape(card.id, to: header) }
            }
        }
        // Read off the main thread; the card is in the column by the time its drawing arrives.
        if let drawings, drawings.keys.contains(shot.key) {
            if drawingReads.isEmpty { DispatchQueue.main.async { [weak self] in self?.readDrawings() } }
            drawingReads.append(shot.key)
        }
        return card
    }

    /// A card whose file is not downloaded learns its shape late: from iCloud's thumbnail, then from
    /// the file's own header once the file is here. A card in the annotator or mid-stitch keeps its
    /// size, since its slot is where a flight lands.
    private func reshape(_ id: UUID, to header: Thumbnailer.Header) {
        guard let card = model.cards.first(where: { $0.id == id }), card.pointSize != header.size || card.duration != header.duration,
              !model.outCards.contains(id), !model.forming.contains(id) else { return }
        let size = layout.cardSize(for: header.size)
        withAnimation(Anim.spring(ui.relayoutDuration)) {
            model.cards = model.cards.map { $0.id == id ? $0.with(pointSize: header.size, size: size, duration: header.duration) : $0 }
        }
        if size != card.size { relayout() }
    }

    /// Shows a new column. Cards start past the screen edge and arrive staggered, newest first.
    /// `keepOffscreen` leaves the cards parked past the edge, for a card that is about to fly out from there.
    /// Without `ordersPanel`, the panel is laid out but left for `orderPanelIn` to put on screen.
    func present(cards: [Card], entrance: Entrance = .slide, ordersPanel: Bool = true) {
        if !visible {
            // A capture opening in the editor shows on the screen it was taken on, where its flight starts.
            let shown = captureOrigin.flatMap { origin in
                NSScreen.screens.first { $0.frame.contains(CGPoint(x: origin.rect.midX, y: origin.rect.midY)) }
            }
            pinnedDisplay = (shown ?? NSScreen.main ?? NSScreen.screens[0]).displayNumber
        }
        leaveTimer?.invalidate()
        dismissGeneration += 1
        newColumn()
        // A column on screen becomes part of the new one: every card in it that the new one shows
        // stays where it is drawn, a flight home included, and only the others enter, above it.
        let entranceOver = visible ? StackEntrance(onScreen: model.cards.map { ($0.shot.key, $0.id) },
                                                   recent: cards.map(\.shot.key)) : nil
        let kept = Set(entranceOver?.kept.compactMap { $0 } ?? [])
        // The layout changes in one update with animations off, as `shiftUp`'s does: animated, the
        // panel's top edge moved at once while the cards sprang, and the cards on screen jumped.
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            flights.endAll(except: kept)
            model.entering = nil
            if let hovered = model.hoveredCard, !kept.contains(hovered) { model.hoveredCard = nil }
            model.clearSelection()
            model.outCards.formIntersection(kept)
            model.forming = []
            model.focused = nil
            model.entranceRanks = [:]
            model.setLifts([:])
            sweep.end()
            model.sweepCard = nil
            model.slidingOut = false
            model.scroll = 0
            model.widthScale = 1
        }
        keys.send(.cardsShown)
        swipe.presented()
        // A dismissal in progress is simply reversed: the same cards turn around. `visible` is
        // already false then; the panel stays up until the slide-out ends.
        let reusing = panel.isVisible && !model.cards.isEmpty && Set(cards.map(\.shot.url)) == Set(model.cards.map(\.shot.url))
        if !reusing {
            let ids = entranceOver?.kept ?? cards.map { _ in nil }
            let next = zip(cards, ids).map { card, id in id.flatMap { id in model.cards.first { $0.id == id } } ?? card }
            let now = CACurrentMediaTime()
            let lift = keptLift(to: next, kept: kept, at: now)
            withTransaction(still) {
                model.removeCards { card in !next.contains { $0.id == card.id } }
                model.cards = next
                model.offscreen = entrance == .inPlace ? [] : Set(next.map(\.id)).subtracting(kept)
                if let entranceOver {
                    for (card, rank) in zip(next, entranceOver.ranks) { model.entranceRanks[card.id] = rank }
                }
                model.setLifts(lift)
            }
            if !lift.isEmpty { springLifts(lift, from: now) }
        }
        visible = true
        layoutPanel(shrinkLater: false, animated: false)
        keepPictures()
        if ordersPanel { flights.orderIn(panel) }
        // The offscreen state must be committed before it is cleared, or nothing animates: next run loop turn.
        if entrance == .slide {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.visible else { return }
                self.model.offscreen = []
            }
        }
    }

    /// Cards of files put back in the folder come back to the open stack where they were in
    /// `column`, on `shiftUp`'s motion (`docs/rules/undo-timeline.md`).
    func putBack(_ shots: [Screenshot], in column: [ScreenshotKey]) {
        guard visible, model.isStack else { return }
        let returning = shots.filter { card(for: $0) == nil }.compactMap { makeCard($0) }
        guard !returning.isEmpty else { return }
        var next = model.cards
        for card in returning { next.insert(card, at: UndoTimeline.place(of: card.shot.key, in: column, among: next.map(\.shot.key))) }
        let ids = returning.map(\.id)
        dismissGeneration += 1
        sweep.end()
        shiftUp(to: next, entering: ids, scrollsHome: false)
        keepPictures()
        if ids.count > 1 || model.inSelectionMode { model.setSelection(next.reversed().map(\.id).filter(ids.contains)) }
        model.focused = next.first { ids.contains($0.id) }?.id
        relayout()
        revealFocused()
        Log.write("[stack] put back cards=\(ids.count)")
    }

    /// A card joins the bottom of the visible column and slides in.
    func insert(_ card: Card, entrance: Entrance = .slide) {
        guard !model.cards.contains(where: { $0.shot.url == card.shot.url }) else { return }
        dismissGeneration += 1
        sweep.end()
        if entrance != .inPlace { _ = model.offscreen.insert(card.id) }
        model.slidingOut = false
        if visible && !model.cards.isEmpty && entrance == .slide { return shiftUp(for: card) }
        model.cards.insert(card, at: 0)
        removeOverflow()
        withAnimation(Anim.spring(ui.relayoutDuration)) { model.scroll = 0 }
        layoutPanel(shrinkLater: false, animated: true)
        orderPanelIn()
        DispatchQueue.main.async { [weak self] in self?.model.offscreen.remove(card.id) }
    }

    /// Puts the panel on screen, under the flight layer, while the corner shows cards and the panel
    /// is not up yet: from a lone card's return until its flight home covers its slot (`returnCard`).
    /// Ordered after the layout, since a window shows at its current frame the moment it is ordered in.
    private func orderPanelIn() {
        guard visible, !panel.isVisible else { return }
        flights.orderBelow(panel)
    }

    /// How far below its slot in `new` each card in `kept` is drawn at `time`, so it starts where it
    /// is: a card that stays changes slot only when a newer screenshot enters below it, and one
    /// still rising from an insert carries on from there.
    private func keptLift(to new: [Card], kept: Set<UUID>, at time: CFTimeInterval) -> [UUID: CGFloat] {
        let newSizes = new.map { layout.drawn($0.size) }
        var lift: [UUID: CGFloat] = [:]
        for (index, card) in new.enumerated() where kept.contains(card.id) {
            guard let was = model.cards.firstIndex(where: { $0.id == card.id }) else { continue }
            let rise = layout.cardSpan(index: index, cards: newSizes).bottom - layout.cardSpan(index: was, cards: cardSizes).bottom
            let drawn = liftLeft(card.id, at: time) + rise
            if abs(drawn) > 0.5 { lift[card.id] = drawn }
        }
        return lift
    }

    /// The lifts just set spring to 0 on the next turn, on `ui.shiftUpDuration`'s spring. `first`
    /// runs before the spring starts and `alongside` inside it.
    private func springLifts(_ lift: [UUID: CGFloat], from time: CFTimeInterval,
                             first: @escaping () -> Void = {}, alongside: @escaping () -> Void = {}) {
        shift = (time, lift)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            first()
            withAnimation(Anim.spring(self.ui.shiftUpDuration)) {
                self.model.liftFraction = 0
                alongside()
            }
        }
    }

    /// When the lifts last sprang to 0, and what they were then, so a card joining while the others
    /// are still shifting up adds to where they are drawn.
    private var shift: (start: CFTimeInterval, lift: [UUID: CGFloat])?

    /// One card joining a visible column. The others shift up on `ui.shiftUpDuration`'s spring, and
    /// the card slides in as a lone thumbnail does once its slot is clear (`CardView.insertLead`).
    /// The layout changes in one update with no animation, the panel's growth included, and every
    /// card that was there is lifted back to where it was drawn; the lifts spring to 0 on the next
    /// turn. Animated as a layout change instead, the panel's top edge moved at once while the
    /// column's height sprang, so the cards jumped half a slot in one frame and the new card rode
    /// the column's motion (`docs/stack-insert-2026-09-26.md`).
    private func shiftUp(for card: Card) { shiftUp(to: [card] + model.cards, entering: [card.id], scrollsHome: true) }

    /// `entering` join the column as `next`; with `scrollsHome` the column drops back from its scroll too.
    private func shiftUp(to next: [Card], entering ids: [UUID], scrollsHome: Bool) {
        let now = CACurrentMediaTime()
        var lift = keptLift(to: next, kept: Set(model.cards.map(\.id)), at: now)
        if scrollsHome { for old in model.cards { lift[old.id, default: 0] += model.scroll } }
        layoutPanel(shrinkLater: false, animated: false) {
            model.slidingOut = false
            model.offscreen.formUnion(ids)
            model.entering = ids.count == 1 ? ids[0] : nil
            model.cards = next
            model.setLifts(lift)
            if scrollsHome { model.scroll = 0 }
        }
        orderPanelIn()
        springLifts(lift, from: now, first: { [weak self] in self?.model.offscreen.subtract(ids) }) { [weak self] in
            // The oldest card leaves the top with its transition, once the column is moving.
            guard let self else { return }
            if self.removeOverflow() { self.relayout() }
        }
        // The card's slide reads `entering` when it starts, on the next turn.
        DispatchQueue.main.asyncAfter(deadline: .now() + ui.shiftUpDuration) { [weak self] in
            guard let self, let entering = self.model.entering, ids.contains(entering) else { return }
            self.model.entering = nil
        }
    }

    /// Where the lift of card `id` is drawn at `time`: what it was when the lifts last sprang, less
    /// what `ui.shiftUpDuration`'s spring has covered since.
    private func liftLeft(_ id: UUID, at time: CFTimeInterval) -> CGFloat {
        guard let shift, let lift = shift.lift[id], ui.shiftUpDuration > 0 else { return 0 }
        let covered = Spring(duration: ui.shiftUpDuration, bounce: 0).value(target: 1.0, time: time - shift.start)
        return lift * CGFloat(max(0, 1 - covered))
    }

    @discardableResult
    private func removeOverflow() -> Bool { model.removeOverflow(over: older.columnLimit) }

    func relayout() {
        guard visible else { return }
        layoutPanel(shrinkLater: true, animated: true)
    }

    /// The panel grows at once so nothing is clipped while cards and the selection strip move, and
    /// shrinks once they have. Its bottom and right edges never move; the column is anchored there.
    /// A fresh presentation applies the viewport at once: animated, its change overlaps the cards'
    /// entrance and bends their path, since the column frame's height and the slide land in the
    /// same transaction.
    func layoutPanel(shrinkLater: Bool, animated: Bool, duration: Double? = nil, _ changes: () -> Void = {}) {
        var transaction = Transaction(animation: animated ? Anim.spring(duration ?? ui.relayoutDuration) : nil)
        transaction.disablesAnimations = !animated
        var viewport: CGFloat = 0
        withTransaction(transaction) {
            changes()
            // At the stack's full width, so a stack narrowed for the annotator keeps the panel it
            // will need when it comes back. The panel is transparent outside the column either way.
            let content = layout.contentHeight(cards: model.cards.map(\.size))
            areaReader.read(on: screen, layout: layout)
            viewport = layout.viewportHeight(content: content, area: area)
            model.viewport = viewport
            model.safeBottom = area.safeBottom
            model.scroll = min(model.scroll, max(0, content - viewport))
        }
        // The strip's room includes the reveal, so the labels coming out never resize the window.
        let target = layout.panelFrame(viewport: viewport, area: area, showsStrip: showsStrip,
                                       reveal: layout.stripReveal(rows: StackLayout.stripRows))
        shrinkGeneration += 1
        let grows = target.height >= panel.frame.height && target.width >= panel.frame.width
        if grows || !panel.isVisible || !shrinkLater {
            panel.setFrame(target, display: true)
        } else {
            let gen = shrinkGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + ui.relayoutDuration + 0.1) { [weak self] in
                guard let self, self.shrinkGeneration == gen, self.visible else { return }
                self.panel.setFrame(target, display: true)
            }
        }
    }

    /// A lone thumbnail leaves the corner `seconds` from now. The newest news sets the time, so
    /// each call replaces the last: a fresh capture's `thumbnailSeconds`, a notice's hold, a landing
    /// with no notice. A copy therefore shortens a fresh thumbnail's stay, which is the point: the
    /// person is done with it. It does not leave while the pointer is on a card, a card is in the
    /// annotator or flying to or from it, or a send waits for its answer, which sets a time of its
    /// own (`hold`). The recent stack stays until it is dismissed.
    func leaveCorner(after seconds: TimeInterval) {
        guard keys.leavesOnItsOwn else { return }
        leaveTimer?.invalidate()
        // Fires on the main run loop, like every other Timer here.
        leaveTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let delivering = self.model.notices.awaitsAnswer(on: self.model.cards.map(\.shot.key))
                if self.model.hoveredCard != nil || self.run.isActive || delivering { self.leaveCorner(after: 1.5); return }
                self.dismiss(by: .timeout)
            }
        }
    }
}

extension NSScreen {
    /// The display this screen shows, which stays the same across the `NSScreen` objects AppKit
    /// makes for it.
    var displayNumber: NSNumber? { deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber }
}
