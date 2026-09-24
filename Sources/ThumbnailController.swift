import AppKit
import SwiftUI

struct Card: Identifiable {
    let id: UUID
    let shot: Screenshot
    var image: NSImage?       // thumbnail-sized; nil until decoded
    let pointSize: NSSize     // the screenshot in points, for the annotator frame
    let size: NSSize          // the card on screen
    let agent: String?        // the agent that added the file (see Agent); nil for a capture
    var duration: TimeInterval? = nil   // a recording's length, for its badge; nil for an image
    /// The drawing's marks, drawn over the thumbnail; nil for a screenshot with no drawing.
    var marks: MarkLayers? = nil

    func with(image: NSImage?) -> Card { var card = self; card.image = image; return card }
    func with(size: NSSize) -> Card {
        Card(id: id, shot: shot, image: image, pointSize: pointSize, size: size, agent: agent, duration: duration, marks: marks)
    }
}

/// Why the selection strip's labels are out. The cursor on the strip brings them out; so does a
/// selection built from the keyboard, where the shortcuts beside the labels are what a hand on the
/// keys needs. The mouse takes over when it moves onto a card or the strip, as the focus does.
@MainActor
final class StackModel: ObservableObject {
    @Published var cards: [Card] = []          // index 0 is newest, drawn at the bottom
    @Published var offscreen: Set<UUID> = []   // cards parked past the right screen edge
    @Published var entering: UUID? = nil       // the one card joining a visible column, for the length of its entrance
    var slidingOut = false                     // picks the exit stagger order and curve for `offscreen`
    @Published var outCards: Set<UUID> = []    // cards currently in the annotator; their slots stay empty
    @Published var forming: Set<UUID> = []     // cards whose image is in the transition layer, mid-stitch; drawn as nothing
    @Published var feedback: String? = nil
    @Published var hoveredCard: UUID? = nil { didSet { if hoveredCard != oldValue { onHover(hoveredCard) } } }
    @Published var pressedCard: UUID? = nil
    @Published var overControl = false         // the mouse is on a card's button or circle, where a click does not draw
    /// A card is in the annotator. The strip stands aside for it: the strip hangs to the left of
    /// the column, which is further left than the room the annotator's frame is kept out of, so
    /// the two would overlap. The selection is untouched and the strip comes back when the session
    /// ends. Set from `send`, which is the one place the session changes.
    @Published var annotating = false
    @Published var copied: Set<UUID> = []      // cards showing the copied mark over their image
    @Published var copiedLabel = "Copied"      // what that mark says; one action marks every card the same
    /// The selected cards, in the order they were selected. Every action, Stitch included, takes
    /// them in this order, and a card's circle shows its place here.
    @Published private(set) var selection: [UUID] = []
    @Published var focused: UUID? = nil        // keyboard focus ring
    @Published var isStack = false             // selection UI only exists in the recent stack
    @Published var scroll: CGFloat = 0         // how far the column is pulled down to show older cards
    @Published var viewport: CGFloat = 0       // visible height of the column, at the stack's full width
    /// The room the Dock keeps at the bottom of the panel when the column is over it. The column
    /// sits this far above the panel's bottom edge, and its mask ends there. See `StackArea`.
    @Published var safeBottom: CGFloat = 0
    /// How wide the stack is drawn, 1 at rest. It narrows while the annotator's frame comes near
    /// it; the column keeps its right edge, so the cards stay in their corner. See `StackLayout`.
    @Published var widthScale: CGFloat = 1

    var inSelectionMode: Bool { !selection.isEmpty }
    /// The row under the column, shown only for a feedback toast.
    var showsBar: Bool { isStack && feedback != nil }
    var onAction: (ShotAction, [Card]) -> Void = { _, _ in }
    var onSweep: (CGFloat) -> Void = { _ in }       // y from the column top, during a drag from a circle
    var onSweepEnd: () -> Void = {}
    var onClickImage: (Card) -> Void = { _ in }
    var onHover: (UUID?) -> Void = { _ in }
    /// The selection changed: the cards that joined it, in the order they were picked, and the
    /// cards that left it.
    var onSelectionChanged: (_ added: [UUID], _ removed: [UUID]) -> Void = { _, _ in }

    /// Takes cards out of the column for good and lets their marks go, with every text still being
    /// drawn for them. A lone thumbnail that leaves for the annotator comes back, and does not come here.
    func removeCards(where leaves: (Card) -> Bool) {
        for card in cards where leaves(card) { card.marks?.clear() }
        cards.removeAll(where: leaves)
    }

    /// Cards for a bulk action, in the order they were selected.
    func selectedCards() -> [Card] { selection.compactMap { id in cards.first { $0.id == id } } }
    /// Where the selected cards sit in the column; 0 is the newest, at the bottom.
    func selectedIndices() -> [Int] { cards.indices.filter { isSelected(cards[$0].id) } }

    /// A selected card's place in `selectedCards()`, counting from 1: the first card selected is 1,
    /// which is the order every action receives them and the badge `Stitch` draws on each one.
    func selectionNumber(of id: UUID) -> Int? { selection.firstIndex(of: id).map { $0 + 1 } }

    func isSelected(_ id: UUID) -> Bool { selection.contains(id) }
    /// Puts the cards that are not selected yet at the end of the selection, in the order given.
    func select(_ ids: [UUID]) { setSelection(selection + ids) }
    func deselect(_ ids: [UUID]) { setSelection(selection.filter { !ids.contains($0) }) }
    /// A card selected again goes to the end: its number is where it was picked this time.
    func toggleSelection(of id: UUID) { isSelected(id) ? deselect([id]) : select([id]) }
    func clearSelection() { setSelection([]) }
    /// Replaces the selection, keeping the given order. A card named twice keeps its first place.
    func setSelection(_ ids: [UUID]) {
        var seen = Set<UUID>()
        let was = selection
        selection = ids.filter { seen.insert($0).inserted }
        let added = selection.filter { !was.contains($0) }, removed = was.filter { !selection.contains($0) }
        if !added.isEmpty || !removed.isEmpty { onSelectionChanged(added, removed) }
    }
}

/// Owns the bottom-right panel: fresh-screenshot thumbnails, the recent stack, feedback toasts,
/// and the transitions into and out of the annotator. An NSObject because the drag-select's
/// auto-scroll takes its ticks from a display link, which calls a target and a selector.
@MainActor
final class ThumbnailController: NSObject {
    weak var actions: Actions?
    /// Which screenshots have a drawing, and each one read for its card.
    var drawings: Drawings?
    /// A card starts travelling to `frame`; the annotator loads the image there while hidden.
    /// `room` is the rect its frame may grow within, which a zoom may not leave.
    var onAnnotatorPrepare: ((Screenshot, NSRect, NSRect) -> Void)?
    /// The flight covers the annotator's frame; the window comes up behind it and takes the keys.
    var onAnnotatorShow: (() -> Void)?
    /// The flight is exactly on the frame; the annotator draws the shadow itself from here on.
    var onAnnotatorLanded: (() -> Void)?
    /// A swap, return, or dismissal has started. The annotator parks its drawing, hides, then calls back.
    var onAnnotatorHide: ((_ hidden: @escaping () -> Void) -> Void)?
    /// The session ends before the window came up. The annotator stores the drawing and lets the image go, with no fit-out.
    var onAnnotatorAbandon: (() -> Void)?
    /// Space the annotator needs below its window, for the toolbar.
    var annotatorBelow: () -> CGFloat = { 0 }
    /// The editor's marks, whose text bitmaps a flight to or from the annotator takes.
    var annotatorMarks: () -> MarkLayers? = { nil }
    /// A press begun on the card flying into the editor, for the image with this key; see `FlightPress`.
    var onAnnotatorPress: ((FlightPress.Event, String) -> Void)?

    private let panel = ThumbnailPanel()
    private let backdrop = BackdropPanel()
    private let dim = DimPanel()
    private let flights = TransitionLayer()
    private let model = StackModel()
    private var hosting: NSHostingView<StackView>!
    private var dismissTimer: Timer?
    private let outsideClick = OutsideClick()
    private var visible = false {
        didSet {
            // Flight decodes are screen-sized; they are only worth keeping while the stack is up.
            if !visible { flightImages.removeAll(); flightOrder.removeAll() }
            // A presentation asks the Dock afresh: one that did not answer last time may answer now.
            else { dockReadsLeft = Self.dockReadAttempts }
        }
    }
    private var dismissGeneration = 0
    private var shrinkGeneration = 0
    private var stitchGeneration = 0
    private var sweepAnchor: Int?
    private var sweepSelecting = true
    private var sweepBefore: [UUID] = []
    /// How far the drag point sits below the top of the visible column, kept while a sweep runs so
    /// the auto-scroll can re-select from it without a mouse event. Nil when no sweep is running.
    private var sweepFromTop: CGFloat?
    private var autoScrollLink: CADisplayLink?
    private var autoScrollTick: CFTimeInterval = 0
    /// The one owner of the annotation session. Only `send` writes it; see AnnotatorTransition.
    private var transition = AnnotatorTransition()
    /// The annotation queue: the files still waiting, in the order they were given, how many the
    /// run started with, and how many of them have opened, which is what the `[annotate] next` line
    /// counts. Only the queue continues itself; every other request to annotate replaces it.
    private var queue: [String] = []
    private var queueTotal = 0
    private var queueOpened = 0
    /// The file the queue hands over to, held for the length of one `send`: it is taken before the
    /// finished card's effects run, so `returnCard` knows another image follows and leaves the
    /// session open.
    private var handover: Screenshot?
    /// The card the session is about, kept here because a lone thumbnail leaves the model once the annotator shows.
    private var sessionCard: Card?
    private var annotating: Card? { transition.isActive ? sessionCard : nil }
    private var annotationFrame: NSRect = .zero
    /// The editor's marks as its park left them, until the flight home has taken their texts. The
    /// editor lets them go once it is hidden, which is before the card is sent home.
    private var parkedMarks: MarkLayers?
    /// Keys whose screenshot the editor has at the screen's size. The flight image lifts once the
    /// annotator is visible and its key is here, so an editor still waiting for its decode is never seen.
    private var loadedKeys: Set<String> = []
    /// The image whose editor window the window server gives presses to now. The flight into it
    /// lifts no earlier: until then a press where the card was would reach the app behind.
    private var takingEvents: String?
    /// Where a press on a flying card goes.
    private var flightPress = FlightPress()
    /// Cards made in this turn whose stored drawings are still to be read. A stack opening makes
    /// every card in one turn, and reading theirs together gives the column one change of `cards`.
    private var drawingReads: [URL] = []
    /// True when the session ends by the user's hand, so focus returns to their app once the annotator is gone.
    private var restoreFocusOnEnd = false
    /// The file whose Done failed to copy before its card came home, so the card takes no copied mark.
    private var uncopied: String?
    /// Larger decodes for the flight to the annotator, by file path. Filled on hover.
    private var flightImages: [String: NSImage] = [:]
    private var flightOrder: [String] = []

    override init() {
        super.init()
        hosting = NSHostingView(rootView: StackView(model: model))
        panel.contentView = hosting
        panel.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        flights.onPress = { [weak self] id, event in self?.flightPressed(id, event) }
        panel.onScroll = { [weak self] event in self?.scroll(event) }
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
            if self.transition.isActive { self.endQueue(); self.annotate(card); self.holdSlot(slot); return }
            if self.model.inSelectionMode { self.toggle(card) }
            else if let action = Config.defaultAction(for: [card.shot]) {
                self.run(action, on: [card])
                if action.id == "annotate" { self.holdSlot(slot) }
            }
        }
        model.onSweep = { [weak self] y in self?.sweep(toYFromTop: y) }
        model.onSweepEnd = { [weak self] in
            guard let self else { return }
            self.endSweep()
            self.revealFocused()
        }
        model.onHover = { [weak self] id in
            guard let self else { return }
            self.prefetchFlightImage(id)
            // Focus follows the pointer: one variable says where a key acts, and moving onto a card
            // moves it there. Leaving a card leaves the focus behind, so keys still act on the card
            // the pointer last named. Only while the stack holds the keys and nothing is in the
            // annotator: the stack keeps them through the flight out, and a key there is about the
            // card that is flying, not the one the cursor happens to be over.
            if let id, self.model.isStack, self.panel.acceptsKeys, !self.transition.isActive { self.model.focused = id }
        }
        model.onSelectionChanged = { [weak self] added, removed in self?.queueFromSelection(added: added, removed: removed) }
    }

    /// The screen a presentation started on. `NSScreen.main` follows the active display, which is
    /// what the user is looking at; pinning it keeps every frame of one presentation on one screen.
    private var pinnedScreen: NSScreen?
    private var screen: NSScreen {
        if let pinned = pinnedScreen, NSScreen.screens.contains(pinned) { return pinned }
        return NSScreen.main ?? NSScreen.screens[0]
    }
    /// What every card and flight image is decoded in, so no first commit has a colour conversion to do.
    private var screenSpace: CGColorSpace? { screen.colorSpace?.cgColorSpace }
    /// A display was added, removed, or rearranged. Whatever is showing moves to a screen that exists.
    func screensChanged() {
        guard visible else { return }
        if let pinned = pinnedScreen, !NSScreen.screens.contains(pinned) { pinnedScreen = NSScreen.main ?? NSScreen.screens[0] }
        Log.write("[screen] changed; relayout on \(screen.localizedName)")
        relayout()
        if model.isStack { backdrop.refresh(on: screen) }
    }

    /// Where the stack is laid out on its screen, and the room a Dock under the column keeps. Read
    /// when the panel is laid out, so the panel, the cards and the strip are placed from one
    /// reading of the screen and the Dock.
    private var area = StackArea(bounds: .zero)
    /// The tiles from the last read that answered. A read fails while the Dock is restarting — a
    /// crash, some display changes, login before it is up — and for that moment the process is
    /// there but its Accessibility tree is not. Taking a failed read as "the Dock spans the whole
    /// edge" lifts the whole column by the Dock's reserved height, and the area is only read on a
    /// layout pass, so it would stay lifted until something unrelated laid the panel out again. The
    /// last rect is the better guess: a restart puts the same Dock back.
    private var dockTiles: NSRect?
    private var dockRetry: DispatchWorkItem?
    private var dockReadsLeft = ThumbnailController.dockReadAttempts
    /// How often, and how many times, a failed Dock read is tried again. In code: a cadence for a
    /// system read that has failed, not a number a user would tune. Eight at half a second covers a
    /// `killall Dock`, which is back inside two.
    private static let dockReadDelay: TimeInterval = 0.5
    private static let dockReadAttempts = 8

    private func readArea() {
        let s = screen
        if let tiles = Dock.tiles() {
            dockTiles = tiles
            dockRetry?.cancel()
            dockRetry = nil
        } else {
            scheduleDockRead()
        }
        area = layout.area(visibleFrame: s.visibleFrame, screenFrame: s.frame, dock: dockTiles)
    }

    /// Asks again after a failed read, and lays out once the Dock answers, so a stack opened while
    /// the Dock was restarting is not left in the place that reading gave it. Bounded: an app
    /// untrusted for Accessibility never gets an answer, and its layout — the Dock taken to span the
    /// whole edge — is the right one to settle on.
    private func scheduleDockRead() {
        guard dockRetry == nil, dockReadsLeft > 0 else { return }
        dockReadsLeft -= 1
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.dockRetry = nil
            guard self.visible else { return }
            if Dock.tiles() != nil { self.relayout() } else { self.scheduleDockRead() }
        }
        dockRetry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dockReadDelay, execute: work)
    }

    /// The cards as they are drawn now: at the stack's full width, or narrowed for the annotator.
    private var cardSizes: [NSSize] { model.cards.map { layout.drawn($0.size) } }
    private var ui: UITweaks { Settings.shared.motionUI }
    private var layout: StackLayout { StackLayout.current.at(widthScale: model.widthScale) }
    private var showsBar: Bool { model.showsBar }
    private var showsStrip: Bool { model.isStack && model.inSelectionMode }

    /// The selection strip's screen frame, or nil when nothing is selected or the annotator has an
    /// image. Asked here and in `StackView`, never in `showsStrip`: that one sizes the panel, and
    /// the panel's window must not be resized while a session is running.
    private var stripFrame: NSRect? {
        guard !model.annotating else { return nil }
        guard showsStrip, let strip = layout.stripPlacement(rows: Config.stripRows.count, selection: model.selectedIndices(),
                                                            cards: cardSizes, showsBar: showsBar,
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
                    return ["file": card.shot.url.path, "frame": StateReport.topLeft(cardFrame(i), primaryHeight: h),
                            "out": model.outCards.contains(card.id), "forming": model.forming.contains(card.id),
                            "drawing": drawings?.keys.contains(card.shot.url.path) ?? false, "agent": card.agent as Any,
                            "kind": card.shot.kind == .recording ? "recording" : "image"]
                },
                "selected": model.selectedCards().map(\.shot.url.path),
                "queue": queue,
                "focused": model.cards.first { $0.id == model.focused }?.shot.url.path as Any,
                "hovered": model.cards.first { $0.id == model.hoveredCard }?.shot.url.path as Any,
                "feedback": model.feedback as Any, "key": panel.isKeyWindow,
                "scroll": Int(model.scroll), "viewport": Int(model.viewport), "safeBottom": Int(area.safeBottom),
                "widthScale": model.widthScale,
                "panel": StateReport.topLeft(panel.frame, primaryHeight: h),
                "strip": stripFrame.map { StateReport.topLeft($0, primaryHeight: h) } as Any,
            ] as [String: Any],
            "transition": ["phase": "\(transition.phase)", "annotating": annotating?.shot.url.path as Any, "isActive": transition.isActive],
            "screen": ["name": s.localizedName, "frame": StateReport.topLeft(s.frame, primaryHeight: h),
                       "visibleFrame": StateReport.topLeft(s.visibleFrame, primaryHeight: h), "scale": s.backingScaleFactor, "pinned": pinnedScreen != nil],
            "backdrop": backdrop.stateJSON,
            "dim": ["visible": dim.isVisible, "alpha": dim.alphaValue],
        ]
    }

    // MARK: Public

    /// A fresh screenshot. Joins the bottom of whatever is showing; on its own it leaves after a
    /// few seconds unless hovered.
    func show(_ shot: Screenshot) {
        guard let card = makeCard(shot) else { return }
        // A new shot never closes an open annotator: the reducer answers `join` and the card joins the panel.
        send(.newShot(shot.url.path))
        if visible { insert(card) } else { present(cards: [card], stack: false) }
        if !model.isStack { scheduleDismiss(after: ui.thumbnailSeconds) }
    }

    enum StackToggle: Equatable { case shown(Int), dismissed, empty }

    var stackShowing: Bool { visible && model.isStack }

    /// The card with the keyboard focus ring, while the stack is up.
    var focusedShot: Screenshot? { model.cards.first { $0.id == model.focused }?.shot }

    /// The recent stack: toggles. Takes keyboard focus. Stays until Esc, the hotkey, or a click elsewhere.
    @discardableResult
    func toggleRecent(_ shots: [Screenshot], detail: String = "") -> StackToggle {
        if visible && model.isStack { dismiss(); return .dismissed }
        // Before the dismissal: its park can answer in the same turn, and a queue still holding
        // files would open the next one then, under a stack that is about to replace the panel.
        endQueue()   // a stack presented anew starts with nothing queued
        if transition.isActive { send(.dismiss) }   // a lone annotation gives way to the stack
        let started = CACurrentMediaTime()
        let cards = shots.compactMap(makeCard)
        guard !cards.isEmpty else { return .empty }
        present(cards: cards, stack: true)
        // A click outside this app's windows closes the stack, and the annotator with it.
        outsideClick.start { [weak self] in self?.dismiss() }
        backdrop.show(on: screen, below: panel)
        takeKeys()
        Log.write("[stack] shown cards=\(cards.count) \(detail)shown=\(Int((CACurrentMediaTime() - started) * 1000))ms decoding=\(cards.filter { $0.image == nil }.count)")
        return .shown(cards.count)
    }

    /// Decodes thumbnails for `shots` in the background so the stack opens without waiting.
    func warm(_ shots: [Screenshot]) {
        let items = shots.compactMap { shot -> (url: URL, maxPixel: Int)? in
            guard let pointSize = Thumbnailer.pointSize(of: shot.url) else { return nil }
            return (shot.url, thumbnailPixels(size: layout.cardSize(for: pointSize), pointSize: pointSize))
        }
        Thumbnailer.warm(items, space: screenSpace)
    }

    /// The panel can refuse key status right after resigning it (a dismissal being reversed), so try twice.
    /// The stack has a focused card from the moment it takes keys, so arrows, Space, and Return act
    /// on the newest card without a click or a first arrow press.
    private func takeKeys() {
        panel.acceptsKeys = true
        if model.focused == nil { model.focused = model.hoveredCard ?? model.cards.first?.id }
        panel.makeKey()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.visible, self.model.isStack, !self.transition.isActive, !self.panel.isKeyWindow else { return }
            self.panel.makeKey()
        }
    }

    /// Opens the annotator on the first of `shots` and queues the rest: finishing one opens the
    /// next, until the list is done. The selection is untouched by the whole run, so the same cards
    /// can be copied or stitched after the last one.
    func annotate(_ shots: [Screenshot]) {
        guard let first = shots.first else { return }
        queue = shots.dropFirst().map(\.url.path)
        queueTotal = shots.count
        queueOpened = 1
        annotate(first)
    }

    /// Opens the annotator on `shot`, or swaps to it if the annotator is already open. Shows the
    /// card first if it is not on screen.
    private func annotate(_ shot: Screenshot) {
        if visible {
            // A shot the panel does not have yet joins it; the flight starts from its offscreen slot.
            if card(for: shot) == nil, let card = makeCard(shot) { insert(card) }
            if let card = card(for: shot) { annotate(card) }
            return
        }
        // Not on screen: the card flies straight from its offscreen slot, so nothing waits for a slide-in.
        guard let card = makeCard(shot) else { return }
        present(cards: [card], stack: false, entrance: .stayOffscreen)
        annotate(card)
    }

    /// The editor asked to close (Esc, click outside, Cmd+W). The reducer decides what returns.
    func annotationEnded() {
        restoreFocusOnEnd = true
        endQueue()   // ending one card ends the run; the rest of the list is dropped
        send(.close)
    }

    /// Send: the drawing is stored as a request and the card comes home without a copied mark.
    /// The run carries on, because a queue is a list the person asked for and sending one of its
    /// cards to an agent does not withdraw the rest; only Esc, which is a person stopping, empties
    /// it. Copying is Done's, so this is `close` rather than `finish`.
    func annotationSent() {
        restoreFocusOnEnd = true
        send(.close)
    }

    /// Done or Return: the result is on the clipboard. The card comes back marked copied; in quick
    /// mode everything closes instead.
    func annotationFinished(quick: Bool) {
        restoreFocusOnEnd = true
        if quick {
            endQueue()   // quick annotate closes everything; nothing follows it
            if visible { dismiss() } else { send(.dismiss) }
        } else {
            send(.finish)
        }
    }

    /// The editor has the screenshot for `key`.
    func editorLoaded(_ key: String) {
        loadedKeys.insert(key)
        liftIntoEditor(key)
    }

    /// The annotator's window for `key` takes presses now: one held on its flight goes to it.
    func annotatorTakesEvents(_ key: String) {
        guard transition.key == key else { return }
        takingEvents = key
        for event in flightPress.ready(key) { onAnnotatorPress?(event, key) }
        liftIntoEditor(key)
    }

    /// The flight into the editor lifts once the editor has its image and its window takes presses,
    /// and once the flight has arrived, which `lift` waits for itself.
    private func liftIntoEditor(_ key: String) {
        guard transition.key == key, loadedKeys.contains(key), takingEvents == key, let card = sessionCard else { return }
        takeFlightTexts(card)
        flights.lift(id: card.id)
    }

    /// A press, drag or release on a flying card. See `FlightPress`.
    private func flightPressed(_ id: UUID?, _ event: FlightPress.Event) {
        let key: String?
        let now: [FlightPress.Event]
        if case .pressed = event.phase {
            key = id.flatMap(keyFlyingIn)
            now = flightPress.press(event, into: key, ready: key != nil && takingEvents == key)
        } else {
            key = flightPress.key
            now = flightPress.move(event)
        }
        guard let key else { return }
        for event in now { onAnnotatorPress?(event, key) }
    }

    /// The image the flight `id` is carrying into the editor, nil for a flight going anywhere else.
    private func keyFlyingIn(_ id: UUID) -> String? {
        guard sessionCard?.id == id else { return nil }
        switch transition.phase {
        case .flyingOut(let key), .annotating(let key): return key
        case .idle, .parking: return nil
        }
    }

    /// The screenshot at `key` has this drawing now, or none: its card draws it at once, and so does
    /// the card in the annotator, which a lone thumbnail keeps out of the column.
    func setDrawing(_ drawing: Drawing?, for key: String) { setDrawings([key: drawing]) }

    /// Each key's drawing, or none, reaching the column in one change of `cards`.
    private func setDrawings(_ drawings: [String: Drawing?]) {
        var cards = model.cards, changed = false
        for index in cards.indices {
            guard let drawing = drawings[cards[index].shot.url.path] else { continue }
            let marks = marks(drawing, on: cards[index])
            if marks !== cards[index].marks { cards[index].marks = marks; changed = true }
        }
        if changed { model.cards = cards }
        guard let card = sessionCard, let drawing = drawings[card.shot.url.path] else { return }
        sessionCard?.marks = model.cards.first { $0.id == card.id }.map(\.marks) ?? marks(drawing, on: card)
    }

    /// Reads the drawings of the cards made since the last read, together.
    private func readDrawings() {
        let urls = drawingReads
        drawingReads = []
        guard let drawings, !urls.isEmpty else { return }
        drawings.load(urls, style: ui.textStyle) { [weak self] loaded in self?.setDrawings(loaded) }
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
        marks?.show(drawing, filling: card.size, backingScale: screen.backingScaleFactor, style: ui.textStyle, arrowhead: ui.arrowhead)
        return marks
    }

    /// Drops cards whose files no longer exist.
    func remove(_ shots: [Screenshot]) {
        let urls = Set(shots.map(\.url))
        let paths = Set(urls.map(\.path))
        queue.removeAll { paths.contains($0) }
        // The file in the annotator going ends the run: the annotator hides, and nothing should
        // take its place in the same turn.
        if let key = transition.key, paths.contains(key) { endQueue() }
        for url in urls { send(.remove(url.path)) }
        for card in model.cards where urls.contains(card.shot.url) { flights.end(id: card.id) }
        endSweep()
        model.removeCards { urls.contains($0.shot.url) }
        model.setSelection(model.selection.filter { id in model.cards.contains { $0.id == id } })
        if model.cards.isEmpty { dismiss(); return }
        // The focused card is where keys act; when its file goes, the newest takes the focus.
        if let focused = model.focused, !model.cards.contains(where: { $0.id == focused }) { model.focused = model.cards.first?.id }
        relayout()
    }

    /// Re-applies layout tweaks to whatever is on screen. Called when settings.ui changes.
    func applyTweaks() {
        let style = ui.textStyle, arrowhead = ui.arrowhead
        // Marks drawn outside the column: in flight, and a lone thumbnail's while its image is in the annotator.
        flights.restyle(style, arrowhead: arrowhead)
        sessionCard?.marks?.restyle(style, arrowhead: arrowhead)
        guard visible else { return }
        model.cards = model.cards.map { card in
            let size = layout.cardSize(for: card.pointSize)
            let image = Thumbnailer.image(at: card.shot.url, maxPixel: thumbnailPixels(size: size, pointSize: card.pointSize),
                                          space: screenSpace) ?? card.image
            if let marks = card.marks, let drawing = marks.drawing {
                marks.show(drawing, filling: size, backingScale: screen.backingScaleFactor, style: style, arrowhead: arrowhead)
            }
            return card.with(size: size).with(image: image)
        }
        relayout()
        if model.isStack { backdrop.refresh(on: screen) }
    }

    /// The stitched file is written: the cards it was made from converge into its slot and the new
    /// card takes their place as the newest. The originals leave the stack; their files are
    /// untouched, so the next stack open has them back. False when the stack is not showing all of
    /// them, and the caller falls back to a toast.
    ///
    /// The watcher reports the new file a moment later like any capture. The card is already in the
    /// column by then, so `insert` ignores it; with `annotateOnCapture` on, the same report carries
    /// it into the annotator from the slot the stitch just filled.
    @discardableResult
    func stitched(_ pieces: [Screenshot], into url: URL) -> Bool {
        guard visible, model.isStack, !transition.isActive, pieces.count > 1 else { return false }
        let cards = pieces.compactMap { shot in model.cards.first { $0.shot.url == shot.url } }
        guard cards.count == pieces.count, let result = makeStitchedCard(url), let stitched = result.image else { return false }
        // Where each card is now, while the selection bar is still part of the column, with its marks
        // made before the card lets its own go.
        let flying = cards.map { card in
            let drawing = card.marks?.drawing
            let scale = drawing.map { max(cardTextScale(card.size, $0.pixels), cardTextScale(result.size, $0.pixels)) } ?? 0
            return (id: card.id, image: flightImage(for: card), marks: flightMarks(drawing, scale: scale, adopting: [card.marks]),
                    from: cardFrame(of: card))
        }
        let ids = Set(cards.map(\.id))
        model.forming.formUnion(ids)
        model.forming.insert(result.id)
        model.removeCards { ids.contains($0.id) }
        model.clearSelection()
        endSweep()   // the pieces leave the column and the new card takes index 0: the anchor moved
        if let focused = model.focused, ids.contains(focused) { model.focused = nil }
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
            // The card takes the copied mark; if the stack has gone meanwhile, or the card with it,
            // the toast says what the stitch did instead, so a stitch never finishes in silence.
            if self.visible, self.model.cards.contains(where: { $0.id == result.id }) { self.showCopied([result.shot]) }
            else { self.showFeedback("Stitched \(cards.count) images, copied") }
        }
        Log.write("[stack] stitched cards=\(cards.count) into=\(url.lastPathComponent)")
        return true
    }

    /// The stitched image decodes here and not on the background queue `makeCard` uses: the card is
    /// the destination of a flight that starts in the same run loop turn, so it cannot arrive later.
    private func makeStitchedCard(_ url: URL) -> Card? {
        guard let pointSize = Thumbnailer.pointSize(of: url) else { return nil }
        let size = layout.cardSize(for: pointSize)
        guard let image = Thumbnailer.image(at: url, maxPixel: thumbnailPixels(size: size, pointSize: pointSize), space: screenSpace) else { return nil }
        return Card(id: UUID(), shot: Screenshot(url: url), image: image, pointSize: pointSize, size: size,
                    agent: Agent.of(url), duration: Thumbnailer.duration(of: url))
    }

    /// The copied mark over the cards themselves; the toast only when none of them is showing.
    /// `label` is what the mark says and `fallback` what the toast says, since what was copied is
    /// the caller's to name.
    func showCopied(_ shots: [Screenshot], label: String = "Copied", fallback: String? = nil) {
        let ids = shots.compactMap { shot in model.cards.first { $0.shot.url == shot.url }?.id }
        guard visible, !ids.isEmpty else {
            showFeedback(fallback ?? (shots.count == 1 ? "Copied to clipboard" : "Copied \(shots.count) images"))
            return
        }
        model.copiedLabel = label
        model.copied.formUnion(ids)
        // A card still on its way back from the annotator shows the mark when it lands.
        let hold = ui.toastSeconds + ui.expandDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) { [weak self] in self?.model.copied.subtract(ids) }
        if !model.isStack { scheduleDismiss(after: hold) }
    }

    /// A copy the card was marked for did not happen: the mark comes off, and a card still on its
    /// way back from the annotator does not take it when it lands.
    func takeBackCopied(_ shot: Screenshot) {
        let key = shot.url.path
        if case .parking(key, then: .finish) = transition.phase { uncopied = key }
        if let card = model.cards.first(where: { $0.shot.url.path == key }) { model.copied.remove(card.id) }
    }

    /// In the stack the toast sits under the cards; on its own it replaces the thumbnails.
    func showFeedback(_ text: String) {
        dismissTimer?.invalidate()
        if visible && model.isStack {
            model.feedback = text
            relayout()
            DispatchQueue.main.asyncAfter(deadline: .now() + ui.toastSeconds) { [weak self] in
                guard let self, self.model.feedback == text else { return }
                self.model.feedback = nil
                self.relayout()
            }
            return
        }
        model.removeCards { _ in true }
        model.clearSelection()
        model.outCards = []
        model.forming = []
        model.feedback = text
        releaseKeys()
        backdrop.hide()
        present(toast: text)
        scheduleDismiss(after: ui.toastSeconds)
    }

    func dismiss() {
        guard visible else { return }
        visible = false
        endQueue()
        dismissGeneration += 1
        let gen = dismissGeneration
        dismissTimer?.invalidate()
        outsideClick.stop()
        releaseKeys()
        backdrop.hide()
        // A stitch still converging ends with the stack: its pieces stop where they are, and the
        // new card, an empty slot while its image was in the layer, slides out with the column.
        if !model.forming.isEmpty {
            for id in model.forming { flights.end(id: id) }
            model.forming = []
        }
        if let card = annotating, model.isStack {
            // The image in the annotator leaves with the stack while the annotator parks its drawing.
            var slot = cardFrame(of: card)
            slot.origin.x += layout.offscreenDistance(cardWidth: slot.width)
            flights.fly(id: card.id, image: flightImage(for: currentCard(card)), marks: homeFlightMarks(for: currentCard(card)),
                        from: annotationFrame, to: slot,
                        lookFrom: .annotator(ui), lookTo: .card(ui), on: screen, arrived: { [weak self] in
                self?.flights.end(id: card.id)
            })
        }
        // Before the event: a park that answers in the same turn hides the annotator, and that must
        // leave the flight just aimed offscreen to the slide-out.
        model.slidingOut = true
        if transition.isActive { send(.dismiss) }
        // Cards leave the way they came, newest first (see CardView). The selection and any toast
        // stay in the layout and slide out with them; the block below clears them once gone.
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
            self.model.feedback = nil
            self.model.scroll = 0
            self.pinnedScreen = nil
            FocusReturn.shared.restore(reason: "stack dismissed")
        }
    }

    // MARK: Annotation transitions. The reducer decides; this section only runs its effects.

    private func annotate(_ card: Card) {
        send(.annotate(card.shot.url.path, from: model.isStack ? .stack : .thumbnail))
    }

    /// Events that arrived while one was still being handled, in the order they came. A park or a
    /// flight can answer inside the effects of the event that asked for it, and its answer runs once
    /// that event is done, so the reducer's events stay in order.
    private var heldEvents: [AnnotatorTransition.Event] = []
    private var handlingEvent = false

    private func send(_ event: AnnotatorTransition.Event) {
        heldEvents.append(event)
        guard !handlingEvent else { return }
        handlingEvent = true
        while !heldEvents.isEmpty { handle(heldEvents.removeFirst()) }
        handlingEvent = false
    }

    private func handle(_ event: AnnotatorTransition.Event) {
        let effects = transition.reduce(event)
        Log.write("[transition] \(event) -> \(transition.phase) effects=\(effects.map(\.description).joined(separator: " "))")
        // A queue hands over in the turn the finished card is sent home, so its flight back and the
        // next card's flight out run together, the way a swap's two flights do.
        if event == .parked, !transition.isActive { handover = takeNext() }
        // The stack's width is set before this batch's flights are aimed, so a swap's returning
        // card and the card leaving are aimed at one column. The card leaving is still drawn at the
        // width the stack had, so it flies from the slot it has now. A handover keeps the annotator
        // open, so the room is made for the image the queue opens next instead of being given back.
        let leaving = preparedCard(in: effects)
        let slot = leaving.map { cardFrame(of: $0) }
        let opening = leaving ?? handover.flatMap { shot in model.cards.first { $0.shot.url.path == shot.url.path } }
        if opening != nil || (releasesRoom(effects) && handover == nil) {
            makeRoom(besides: opening.map { targetFrame(for: $0) }, animated: true)
        }
        for effect in effects { perform(effect, leaving: slot) }
        // A press held for, or handed to, an image that is no longer on its way in or in the editor.
        if let key = flightPress.key, transition.phase != .flyingOut(key), transition.phase != .annotating(key) {
            flightPress.ended(key)
        }
        if let next = handover {
            handover = nil
            annotate(next)
        }
        model.annotating = transition.isActive
    }

    /// Ends the run: nothing waits, and the next run counts from its own first image.
    /// While a card is in the annotator, a card selected in the stack is queued to be annotated
    /// next, in the order picked, and one deselected leaves the queue: the same run a selection
    /// starts when Draw is pressed on it. The card in the annotator itself is not "next".
    private func queueFromSelection(added: [UUID], removed: [UUID]) {
        guard transition.isActive else { return }
        let gone = Set(removed.compactMap { id in model.cards.first { $0.id == id }?.shot.url.path })
        let before = queue.count
        queue.removeAll { gone.contains($0) }
        queueTotal -= before - queue.count
        for id in added {
            guard let card = model.cards.first(where: { $0.id == id }), card.shot.kind == .image else { continue }
            let key = card.shot.url.path
            guard key != transition.key, !queue.contains(key) else { continue }
            queue.append(key)
            queueTotal += 1
            Log.write("[annotate] queued \((key as NSString).lastPathComponent) \(queueOpened + queue.count) of \(queueTotal)")
        }
    }

    private func endQueue() {
        queue = []
        queueTotal = 0
        queueOpened = 0
    }

    /// The next file the queue has for the annotator. Files that have gone since drop out.
    private func takeNext() -> Screenshot? {
        while !queue.isEmpty {
            let key = queue.removeFirst()
            guard FileManager.default.fileExists(atPath: key) else { continue }
            queueOpened += 1
            Log.write("[annotate] next \((key as NSString).lastPathComponent) \(queueOpened) of \(queueTotal)")
            return Screenshot(url: URL(fileURLWithPath: key))
        }
        return nil
    }

    /// The card a `prepare` in this batch sends to the annotator, if the stack has it.
    private func preparedCard(in effects: [AnnotatorTransition.Effect]) -> Card? {
        for effect in effects {
            if case .prepare(let key) = effect { return model.cards.first { $0.shot.url.path == key } }
        }
        return nil
    }

    /// Whether this batch takes the annotator off the screen, so nothing is beside the stack.
    private func releasesRoom(_ effects: [AnnotatorTransition.Effect]) -> Bool {
        effects.contains { effect in
            if case .returnCard = effect { return true }
            return effect == .hideAnnotator
        }
    }

    private func perform(_ effect: AnnotatorTransition.Effect, leaving slot: NSRect?) {
        switch effect {
        case .prepare(let key):
            uncopied = nil   // the session it was for has ended
            guard let card = model.cards.first(where: { $0.shot.url.path == key }) else { return }
            sessionCard = card
            loadedKeys.remove(key)
            takingEvents = nil
            dismissTimer?.invalidate()
            // The selection stays: the card comes back to its slot, and a queued run needs the rest
            // of it to still be there when the last card is done.
            _ = model.outCards.insert(card.id)
            let target = targetFrame(for: card)
            annotationFrame = target
            dim.show(on: screen)
            parkedMarks = nil
            onAnnotatorPrepare?(card.shot, target, annotatorRoom)
            // After the annotator's window has taken the keys, so they pass from one to the other
            // rather than being nobody's: a tool key or Esc pressed during the flight reaches the
            // editor, and its Esc comes back through `onClosed` as `close`, which turns the card around.
            releaseKeys()
            var from = slot ?? cardFrame(of: card)
            if model.offscreen.contains(card.id) { from.origin.x += layout.offscreenDistance(cardWidth: from.width) }
            // Two moments. The window comes up at `covered`, where the flight is past the frame and
            // covers it, so it can take the keys and the pointer while the eye already reads the
            // card as still. The shadow and the picture change hands at `arrived`, on the exact
            // frame: the window draws the same ring and shadow there, so handing either over while
            // the spring still had a few points to go would step against the picture the flight is
            // showing.
            flights.fly(id: card.id, image: flightImage(for: card), marks: outFlightMarks(for: card, to: target), from: from, to: target,
                        lookFrom: .card(ui), lookTo: .annotator(ui), on: screen, covered: { [weak self] in
                guard let self, self.transition.phase == .flyingOut(key) else { return }
                self.send(.shown)
            }, arrived: { [weak self] in
                // On the key, not the phase: Done or Esc is accepted between `covered` and here,
                // and the window then stays up through the park, still owed its shadow.
                guard let self, self.transition.key == key, let card = self.sessionCard else { return }
                self.onAnnotatorLanded?()
                self.flights.dropShadow(id: card.id)
                self.liftIntoEditor(key)
            }, dropped: { [weak self] in
                // The layer went down between the two moments — a new capture presenting the panel
                // anew while a lone thumbnail is being annotated. Nothing covers the window now.
                self?.onAnnotatorLanded?()
            })
        case .show:
            onAnnotatorShow?()
            guard let card = sessionCard else { return }
            if !model.isStack {
                // A lone thumbnail has nothing to keep open behind the annotator; cards that joined stay.
                // Its marks stay with it: it comes back to the corner when the session ends.
                model.cards.removeAll { $0.id == card.id }
                model.outCards.remove(card.id)
                if model.cards.isEmpty { visible = false; panel.orderOut(nil) } else { relayout() }
            }
        case .park:
            parkedMarks = annotatorMarks()
            onAnnotatorHide? { [weak self] in self?.send(.parked) }
        case .abandon:
            // Before the editor lets its marks go: the flight home carries what the abandon parks.
            parkedMarks = annotatorMarks()
            onAnnotatorAbandon?()
        case .returnCard(let key):
            guard let card = sessionCard, card.shot.url.path == key else { return }
            // With another file coming from the queue the session is not over: the dim stays up and
            // the user's app does not get the focus back between two cards.
            if !transition.isActive, handover == nil { sessionCard = nil; dim.hide(); endSession() }
            returnCard(currentCard(card))
        case .hideAnnotator:
            // While the stack slides out, the image is flying to its slot's offscreen position
            // (see `dismiss`); that flight ends itself, and the slide-out's completion clears the card.
            // A lone thumbnail's panel has no such flight.
            if let card = sessionCard, !(model.slidingOut && model.isStack) { model.outCards.remove(card.id); flights.end(id: card.id) }
            sessionCard = nil
            parkedMarks = nil
            dim.hide()
            endSession()
        case .markCopied(let key):
            if uncopied == key { uncopied = nil; return }
            if let card = model.cards.first(where: { $0.shot.url.path == key }) { showCopied([card.shot]) }
        case .join:
            break   // `show(_:)` inserts the card; the reducer only confirms the annotator stays open.
        }
    }

    private func endSession() {
        if restoreFocusOnEnd { FocusReturn.shared.restore(reason: "annotator closed") }
        restoreFocusOnEnd = false
    }

    private func returnCard(_ card: Card) {
        if !model.cards.contains(where: { $0.id == card.id }) {
            // A lone thumbnail left the panel when the annotator opened (see `.show`); it comes back
            // to the corner as an empty slot the flight lands on. No slide-in: the flight is the entrance.
            if visible { insert(card, entrance: .inPlace) } else { present(cards: [card], stack: false, entrance: .inPlace) }
            _ = model.outCards.insert(card.id)
        }
        guard visible, model.cards.contains(where: { $0.id == card.id }) else {
            model.outCards.remove(card.id); flights.end(id: card.id); return
        }
        // The card takes its slot back only once the flight has settled on it: the card draws at the
        // exact slot, so a card and a shadow put there while the flight still had a few points to
        // go would both step. Nothing is visible before then; the flight covers the slot.
        flights.fly(id: card.id, image: flightImage(for: card), marks: homeFlightMarks(for: card), from: annotationFrame, to: cardFrame(of: card),
                    lookFrom: .annotator(ui), lookTo: .card(ui), on: screen, arrived: { [weak self] in
            guard let self else { return }
            self.model.outCards.remove(card.id)
            self.hover(landing: card)
            self.flights.dropShadow(id: card.id)   // the card draws it now, in this same commit
            // The card view comes back on SwiftUI's next commit; lift the flight image after it.
            DispatchQueue.main.async { self.flights.lift(id: card.id) }
            if !self.transition.isActive, self.visible, self.model.isStack { self.takeKeys() }
            // A lone thumbnail leaves on its own; the copied mark usually sets a shorter timer first.
            if !self.model.isStack, self.dismissTimer == nil { self.scheduleDismiss(after: self.ui.thumbnailSeconds) }
        })
    }

    /// Takes every press on the slot a click just opened a card from, for as long as a second click
    /// would make it a double click. Opening narrows the stack away from the slot and can slide
    /// another card into it, so that second click would reach the app behind or open that card.
    /// The slot is as the hovered card drew it, since that is where the click was.
    private func holdSlot(_ slot: NSRect) {
        flights.hold(layout.hovered(slot), for: NSEvent.doubleClickInterval, on: screen)
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

    /// The marks a flight carries: `drawing` with every text drawn at `scale` device px to a px, the
    /// larger of the flight's two ends, over the whole image, and showing the bitmaps `sources` have
    /// until its own arrive. Nil for a drawing with no marks.
    private func flightMarks(_ drawing: Drawing?, scale: CGFloat, adopting sources: [MarkLayers?]) -> MarkLayers? {
        guard let drawing, !drawing.marks.isEmpty else { return nil }
        let marks = MarkLayers(pixels: drawing.pixels, queue: MarkLayers.textQueue)
        marks.setScale(screen.backingScaleFactor)
        marks.show(drawing, scale: scale, bound: drawing.pixels.bounds, style: ui.textStyle, arrowhead: ui.arrowhead, adopting: sources.compactMap { $0 })
        return marks
    }

    /// The flight from `card` to the annotator at `frame` carries the drawing the editor has just
    /// opened, which is what it hands over to; the card's own until the editor has one.
    private func outFlightMarks(for card: Card, to frame: NSRect) -> MarkLayers? {
        let editor = annotatorMarks().flatMap { $0.drawing?.key == card.shot.url.path ? $0 : nil }
        guard let drawing = editor?.drawing ?? card.marks?.drawing else { return nil }
        let scale = max(annotatorTextScale(frame, drawing.pixels), cardTextScale(card.size, drawing.pixels))
        return flightMarks(drawing, scale: scale, adopting: [flights.marks(of: card.id), card.marks, editor])
    }

    /// The flight from the annotator back to `card` carries the drawing the editor parked, a flight
    /// turned around in mid-air included; the flight's own, or the card's, when the editor had none.
    private func homeFlightMarks(for card: Card) -> MarkLayers? {
        let key = card.shot.url.path
        let editor = [parkedMarks, annotatorMarks()].compactMap { $0 }.first { $0.drawing?.key == key }
        parkedMarks = nil
        let flying = flights.marks(of: card.id)
        guard let drawing = editor?.drawing ?? flying?.drawing ?? card.marks?.drawing else { return nil }
        let scale = max(annotatorTextScale(annotationFrame, drawing.pixels), cardTextScale(card.size, drawing.pixels))
        return flightMarks(drawing, scale: scale, adopting: [editor, flying, card.marks])
    }

    /// The editor takes over from the flight into it: a text whose bitmap the editor has not drawn yet
    /// shows the flight's until it has, so no text goes missing when the flight lifts.
    private func takeFlightTexts(_ card: Card) {
        guard let flying = flights.marks(of: card.id), let editor = annotatorMarks(), editor.drawing?.key == card.shot.url.path else { return }
        editor.adopt(from: flying)
    }

    /// Device px per image px of the editor's texts in the annotator at `frame`, fitted: the editor's
    /// own sum, so a flight's texts and the editor's are the same bitmaps.
    private func annotatorTextScale(_ frame: NSRect, _ pixels: PixelSize) -> CGFloat {
        pixels.width > 0 ? frame.width / CGFloat(pixels.width) * screen.backingScaleFactor : 0
    }

    /// Device px per image px of a card's texts, at the card's `size` at rest.
    private func cardTextScale(_ size: NSSize, _ pixels: PixelSize) -> CGFloat {
        guard pixels.width > 0, pixels.height > 0 else { return 0 }
        return max(size.width / CGFloat(pixels.width), size.height / CGFloat(pixels.height)) * screen.backingScaleFactor
    }

    private func targetFrame(for card: Card) -> NSRect {
        layout.annotationFrame(for: card.pointSize, visibleFrame: annotatorRoom, below: annotatorBelow())
    }

    /// The rect the annotator fits and grows within. The recent stack keeps a strip of the screen
    /// on the right, so a wide image opens and zooms beside the cards instead of over them; a lone
    /// thumbnail leaves the panel when the annotator opens and reserves nothing.
    private var annotatorRoom: NSRect {
        guard visible, model.isStack else { return screen.visibleFrame }
        return layout.annotatorRoom(visibleFrame: screen.visibleFrame)
    }

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

    /// The best image for the flight: a larger decode if hovering fetched one, else the thumbnail,
    /// upgraded as soon as a larger decode arrives.
    private func flightImage(for card: Card) -> NSImage {
        let path = card.shot.url.path
        if let image = flightImages[path] { return image }
        prefetchFlightImage(card.id)
        return card.image ?? NSImage(size: card.size)
    }

    private func prefetchFlightImage(_ id: UUID?) {
        guard let id, let card = model.cards.first(where: { $0.id == id }) else { return }
        let path = card.shot.url.path
        guard flightImages[path] == nil else { return }
        Thumbnailer.load(at: card.shot.url, maxPixel: Thumbnailer.screenPixels(on: screen), space: screenSpace) { [weak self] image in
            // `visible`: a decode that lands after the stack hid must not refill the cache it cleared.
            guard let self, let image, self.visible else { return }
            self.flightImages[path] = image
            self.flightOrder.append(path)
            if self.flightOrder.count > 4 { self.flightImages[self.flightOrder.removeFirst()] = nil }
            self.flights.setImage(id: id, image)
        }
    }

    private func cardFrame(of card: Card) -> NSRect {
        guard let index = model.cards.firstIndex(where: { $0.id == card.id }) else { return annotationFrame }
        return cardFrame(index)
    }

    private func cardFrame(_ index: Int) -> NSRect {
        layout.cardFrame(index: index, cards: cardSizes, panelFrame: panel.frame, showsBar: showsBar,
                         scroll: model.scroll, safeBottom: area.safeBottom)
    }

    // MARK: Selection

    private func toggle(_ card: Card) {
        model.toggleSelection(of: card.id)
        model.focused = card.id
        relayout()
        revealFocused()
    }

    /// A card that was just interacted with while partly out of view scrolls into it.
    private func revealFocused() {
        guard let index = model.cards.firstIndex(where: { $0.id == model.focused }) else { return }
        scrollToReveal(index)
    }

    /// The drag is over: it ended, or the cards it was sweeping changed under it, which makes the
    /// anchor point at another card. The selection stays as it is.
    private func endSweep() {
        sweepAnchor = nil
        sweepFromTop = nil
        stopAutoScroll()
    }

    /// The drag moved. Its place in the column is kept as a distance from the top of what is on
    /// screen, so the auto-scroll can keep selecting from the same point while the cards move under it.
    private func sweep(toYFromTop y: CGFloat) {
        sweepFromTop = y - drawnContentHeight + model.viewport + model.scroll
        select(toYFromTop: y)
        updateAutoScroll()
    }

    /// Dragging from a circle selects (or deselects) every card between the start and the cursor,
    /// in the order the drag reached them. Backing up restores cards the drag passed over.
    private func select(toYFromTop y: CGFloat) {
        guard let index = layout.cardIndex(atYFromTop: y, cards: cardSizes) else { return }
        if sweepAnchor == nil {
            sweepAnchor = index
            sweepSelecting = !model.isSelected(model.cards[index].id)
            sweepBefore = model.selection
        }
        let anchor = sweepAnchor!
        let passed = stride(from: anchor, through: index, by: index < anchor ? -1 : 1).map { model.cards[$0].id }
        let next = sweepSelecting ? sweepBefore + passed : sweepBefore.filter { !passed.contains($0) }
        // The auto-scroll runs this every frame; a relayout that changes nothing would still move
        // the panel and animate the strip.
        guard next != model.selection || model.focused != model.cards[index].id else { return }
        model.setSelection(next)
        model.focused = model.cards[index].id
        relayout()
    }

    /// While the drag sits in a band at either end of the column, the column scrolls on its own and
    /// the cards passing under the drag keep joining the selection. This is the user's own drag, so
    /// the motion scale leaves it alone; it stops at the ends of the column and when the drag leaves
    /// the band or ends.
    private func updateAutoScroll() {
        let speed = sweepFromTop.map { layout.autoScrollSpeed(fromTop: $0, viewport: model.viewport) } ?? 0
        guard speed != 0, visible, model.isStack else { stopAutoScroll(); return }
        guard autoScrollLink == nil else { return }
        autoScrollTick = CACurrentMediaTime()
        let link = screen.displayLink(target: self, selector: #selector(autoScrollStep))
        link.add(to: .main, forMode: .common)
        autoScrollLink = link
    }

    private func stopAutoScroll() {
        autoScrollLink?.invalidate()
        autoScrollLink = nil
    }

    @objc private func autoScrollStep(_ link: CADisplayLink) {
        guard let fromTop = sweepFromTop, visible, model.isStack else { stopAutoScroll(); return }
        let speed = layout.autoScrollSpeed(fromTop: fromTop, viewport: model.viewport)
        guard speed != 0 else { stopAutoScroll(); return }
        let now = CACurrentMediaTime()
        // A stalled run loop would otherwise scroll the whole column in one step.
        let dt = min(0.1, now - autoScrollTick)
        autoScrollTick = now
        let next = min(maxScroll, max(0, model.scroll + speed * dt))
        guard next != model.scroll else { return }
        model.scroll = next
        select(toYFromTop: fromTop + drawnContentHeight - model.viewport - model.scroll)
    }

    private func run(_ action: ShotAction, on cards: [Card]) {
        guard let actions, action.applies(to: cards.map(\.shot)) else { return }
        action.run(cards.map(\.shot), actions)
    }

    /// Cards a shortcut acts on: the selection, else the focused card. The focus is the newest card
    /// while the stack has keys and follows the pointer, so the card under the mouse is the target.
    private func targetCards() -> [Card] {
        if model.inSelectionMode { return model.selectedCards() }
        if let id = model.focused, let card = model.cards.first(where: { $0.id == id }) { return [card] }
        return model.cards.first.map { [$0] } ?? []
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard model.isStack else { return false }
        let mods = event.modifierFlags.intersection([.command, .option, .shift, .control])
        // Shift shortcuts arrive uppercase; action keys are declared lowercase.
        let chars = (event.charactersIgnoringModifiers ?? "").lowercased()
        // Virtual key codes: 53 esc, 126 up, 125 down, 36 return, 76 enter, 51 delete, 117 fwd delete.
        let code = event.keyCode
        let isReturn = code == 36 || code == 76
        let isDelete = code == 51 || code == 117

        if code == 53 {
            if model.inSelectionMode { model.clearSelection(); relayout() }
            else { dismiss() }
            return true
        }
        if code == 126 || code == 125 {
            moveFocus(toward: code == 125 ? -1 : 1, extend: mods.contains(.shift))
            return true
        }
        if chars == " " {
            if let id = model.focused, let card = model.cards.first(where: { $0.id == id }) { toggle(card) }
            return true
        }
        if chars == "a" && mods == [.command] {
            // Nobody picked an order, so the column's own is the answer: oldest first, top to bottom.
            model.setSelection(model.cards.reversed().map(\.id))
            relayout()
            return true
        }
        if chars == "a" && mods == [.command, .shift] {
            model.clearSelection()
            relayout()
            return true
        }
        let targets = targetCards()
        let match = Config.action(for: { key in
            let pressed = (key.character == "\u{7f}" && isDelete) || (key.character == "\r" && isReturn)
                || (key.character != "\u{7f}" && key.character != "\r" && key.character == chars)
            return pressed && mods == key.modifiers
        }, on: targets.map(\.shot))
        switch match {
        case .run(let action): run(action, on: targets); return true
        // The row for it is greyed out in the strip; the key says so the way a disabled menu
        // item's shortcut does, rather than nothing happening.
        case .unavailable: NSSound.beep(); return true
        case .none: return false
        }
    }

    /// Down arrow moves toward the newest card (index 0), which sits at the bottom. Shift extends
    /// the selection in the direction of travel; turning back takes off the card added last.
    private func moveFocus(toward delta: Int, extend: Bool) {
        guard !model.cards.isEmpty else { return }
        let current = model.cards.firstIndex { $0.id == model.focused }
        let next: Int
        if let current { next = max(0, min(model.cards.count - 1, current + delta)) } else { next = delta < 0 ? model.cards.count - 1 : 0 }
        if extend {
            let here = current.map { model.cards[$0].id }
            if let here, model.selection.last == here, model.selection.dropLast().last == model.cards[next].id {
                model.deselect([here])
            } else {
                model.select([here, model.cards[next].id].compactMap { $0 })
            }
            relayout()
        }
        model.focused = model.cards[next].id
        scrollToReveal(next)
    }

    private func releaseKeys() {
        panel.acceptsKeys = false
        if panel.isKeyWindow { panel.resignKey() }
        model.focused = nil
    }

    // MARK: Scrolling

    /// The column's height as it is drawn now, at the stack's width scale. `layoutPanel` sizes the
    /// panel from the full-width height instead, so a narrowed stack keeps the panel it comes back to.
    private var drawnContentHeight: CGFloat { layout.contentHeight(cards: cardSizes, showsBar: showsBar) }

    private var maxScroll: CGFloat { max(0, drawnContentHeight - model.viewport) }

    private func scroll(_ event: NSEvent) {
        guard visible, maxScroll > 0 else { return }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 10
        // Pulling the column down (fingers moving down) reveals older cards above.
        model.scroll = min(maxScroll, max(0, model.scroll + delta))
    }

    private func scrollToReveal(_ index: Int) {
        let span = layout.cardSpan(index: index, cards: cardSizes, showsBar: showsBar)
        var target = model.scroll
        if span.top - model.scroll > model.viewport { target = span.top - model.viewport }
        if span.bottom - model.scroll < 0 { target = span.bottom }
        target = min(maxScroll, max(0, target))
        guard target != model.scroll else { return }
        withAnimation(Anim.spring(ui.relayoutDuration)) { model.scroll = target }
    }

    // MARK: Internals

    private func card(for shot: Screenshot) -> Card? {
        model.cards.first { $0.shot.url == shot.url }
    }

    private func currentCard(_ card: Card) -> Card {
        model.cards.first { $0.id == card.id } ?? card
    }

    private func replaceImage(of card: Card, with image: NSImage?) {
        model.cards = model.cards.map { $0.id == card.id ? $0.with(image: image) : $0 }
    }

    /// A card appears at once; if its thumbnail is not cached yet it arrives a moment later.
    private func makeCard(_ shot: Screenshot) -> Card? {
        guard let pointSize = Thumbnailer.pointSize(of: shot.url) else { return nil }
        let size = layout.cardSize(for: pointSize)
        let maxPixel = thumbnailPixels(size: size, pointSize: pointSize)
        let space = screenSpace
        let card = Card(id: UUID(), shot: shot, image: Thumbnailer.cached(at: shot.url, maxPixel: maxPixel, space: space),
                        pointSize: pointSize, size: size, agent: Agent.of(shot.url), duration: Thumbnailer.duration(of: shot.url))
        if card.image == nil {
            Thumbnailer.load(at: shot.url, maxPixel: maxPixel, space: space) { [weak self] image in
                guard let self, let image, self.model.cards.contains(where: { $0.id == card.id }) else { return }
                self.replaceImage(of: card, with: image)
            }
        }
        // Read off the main thread; the card is in the column by the time its drawing arrives.
        if let drawings, drawings.keys.contains(shot.url.path) {
            if drawingReads.isEmpty { DispatchQueue.main.async { [weak self] in self?.readDrawings() } }
            drawingReads.append(shot.url)
        }
        return card
    }

    /// Pixels on the longest side for a decode that covers the card at this screen's scale, with margin.
    private func thumbnailPixels(size: NSSize, pointSize: NSSize) -> Int {
        let cover = max(size.width / max(pointSize.width, 1), size.height / max(pointSize.height, 1))
        return Int(ceil(max(pointSize.width, pointSize.height) * cover * screen.backingScaleFactor * 1.5))
    }

    /// Shows a new column. Cards start past the screen edge and arrive staggered, newest first.
    /// `keepOffscreen` leaves the cards parked past the edge, for a card that is about to fly out from there.
    /// How presented cards arrive: sliding in from the right edge, parked past it for a flight to
    /// start from, or already in place because a flight lands on them.
    enum Entrance { case slide, stayOffscreen, inPlace }

    private func present(cards: [Card], stack: Bool, entrance: Entrance = .slide) {
        if !visible { pinnedScreen = NSScreen.main ?? NSScreen.screens[0] }
        dismissTimer?.invalidate()
        dismissGeneration += 1
        flights.endAll()
        model.feedback = nil
        model.entering = nil
        model.hoveredCard = nil
        model.clearSelection()
        model.outCards = []
        model.forming = []
        model.focused = nil
        endSweep()
        let wasStack = model.isStack
        model.isStack = stack
        model.slidingOut = false
        model.scroll = 0
        model.widthScale = 1
        if !stack { releaseKeys() }
        // A dismissal in progress is simply reversed: the same cards turn around. `visible` is
        // already false then; the panel stays up until the slide-out ends.
        let reusing = panel.isVisible && !model.cards.isEmpty && Set(cards.map(\.shot.url)) == Set(model.cards.map(\.shot.url))
        if !reusing {
            // A lone thumbnail that is part of the stack stays where it is; the rest slides in above it.
            let staying = (visible && !wasStack && stack) ? model.cards.first { existing in cards.contains { $0.shot.url == existing.shot.url } } : nil
            let next = cards.map { card in card.shot.url == staying?.shot.url ? staying! : card }
            model.removeCards { card in !next.contains { $0.id == card.id } }
            model.cards = next
            model.offscreen = entrance == .inPlace ? [] : Set(next.map(\.id)).subtracting(staying.map { [$0.id] } ?? [])
        }
        visible = true
        layoutPanel(shrinkLater: false, animated: false)
        panel.orderFrontRegardless()
        // The offscreen state must be committed before it is cleared, or nothing animates: next run loop turn.
        if entrance == .slide {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.visible else { return }
                self.model.offscreen = []
            }
        }
    }

    /// A toast on its own, in the corner.
    private func present(toast: String) {
        if !visible { pinnedScreen = NSScreen.main ?? NSScreen.screens[0] }
        dismissGeneration += 1
        model.isStack = false
        model.slidingOut = false
        model.scroll = 0
        visible = true
        model.viewport = 40
        readArea()
        model.safeBottom = area.safeBottom
        panel.setFrame(layout.panelFrame(viewport: 40, area: area, showsStrip: false), display: false)
        panel.orderFrontRegardless()
    }

    /// A card joins the bottom of the visible column and slides in.
    private func insert(_ card: Card, entrance: Entrance = .slide) {
        guard !model.cards.contains(where: { $0.shot.url == card.shot.url }) else { return }
        dismissGeneration += 1
        endSweep()   // the new card takes index 0 and shifts every other, the sweep's anchor included
        if model.feedback != nil && !model.isStack { model.feedback = nil; model.removeCards { _ in true } }
        if entrance != .inPlace { _ = model.offscreen.insert(card.id) }
        model.slidingOut = false
        // One card joining a visible column moves through `ui.insertDuration`, the card and the room
        // the others make alike, which is slower than a relayout: it is an arrival, not a shuffle.
        let joining = visible && !model.cards.isEmpty && entrance == .slide
        let duration = joining ? ui.insertDuration : ui.relayoutDuration
        if joining { model.entering = card.id }
        model.cards.insert(card, at: 0)
        if model.cards.count > Settings.shared.data.recentCount, let last = model.cards.last {
            model.removeCards { $0.id == last.id }
            model.deselect([last.id])
        }
        withAnimation(Anim.spring(duration)) { model.scroll = 0 }
        layoutPanel(shrinkLater: false, animated: true, duration: duration)
        DispatchQueue.main.async { [weak self] in self?.model.offscreen.remove(card.id) }
        if joining {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                guard let self, self.model.entering == card.id else { return }
                self.model.entering = nil
            }
        }
    }

    private func relayout() {
        guard visible else { return }
        layoutPanel(shrinkLater: true, animated: true)
    }

    /// The panel grows at once so nothing is clipped while cards and the selection strip move, and
    /// shrinks once they have. Its bottom and right edges never move; the column is anchored there.
    /// A fresh presentation applies the viewport at once: animated, its change overlaps the cards'
    /// entrance and bends their path, since the column frame's height and the slide land in the
    /// same transaction.
    private func layoutPanel(shrinkLater: Bool, animated: Bool, duration: Double? = nil) {
        // At the stack's full width, so a stack narrowed for the annotator keeps the panel it will
        // need when it comes back. The panel is transparent outside the column either way.
        let content = layout.contentHeight(cards: model.cards.map(\.size), showsBar: showsBar)
        readArea()
        let viewport = layout.viewportHeight(content: content, area: area)
        var transaction = Transaction(animation: animated ? Anim.spring(duration ?? ui.relayoutDuration) : nil)
        transaction.disablesAnimations = !animated
        withTransaction(transaction) {
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

    private func scheduleDismiss(after seconds: TimeInterval) {
        dismissTimer?.invalidate()
        // Fires on the main run loop, like every other Timer here.
        dismissTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.model.hoveredCard != nil || self.transition.isActive { self.scheduleDismiss(after: 1.5); return }
                self.dismiss()
            }
        }
    }
}
