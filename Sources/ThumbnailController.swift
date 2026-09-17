import AppKit
import SwiftUI

struct Card: Identifiable {
    let id: UUID
    let shot: Screenshot
    var image: NSImage?       // thumbnail-sized, or the draft preview; nil until decoded
    let pointSize: NSSize     // the screenshot in points, for the annotator frame
    let size: NSSize          // the card on screen
    let agent: String?        // the agent that added the file (see Agent); nil for a capture

    func with(image: NSImage?) -> Card { Card(id: id, shot: shot, image: image, pointSize: pointSize, size: size, agent: agent) }
    func with(size: NSSize) -> Card { Card(id: id, shot: shot, image: image, pointSize: pointSize, size: size, agent: agent) }
}

@MainActor
final class StackModel: ObservableObject {
    @Published var cards: [Card] = []          // index 0 is newest, drawn at the bottom
    @Published var offscreen: Set<UUID> = []   // cards parked past the right screen edge
    var slidingOut = false                     // picks the exit stagger order and curve for `offscreen`
    @Published var outCards: Set<UUID> = []    // cards currently in the annotator; their slots stay empty
    @Published var forming: Set<UUID> = []     // cards whose image is in the transition layer, mid-stitch; drawn as nothing
    @Published var drafts: Set<String> = []    // file paths with annotations in progress
    @Published var feedback: String? = nil
    @Published var hoveredCard: UUID? = nil { didSet { if hoveredCard != oldValue { onHover(hoveredCard) } } }
    @Published var pressedCard: UUID? = nil
    @Published var overControl = false         // the mouse is on a card's button or circle, where a click does not draw
    @Published var copied: Set<UUID> = []      // cards showing "Copied" over their image
    /// The selected cards, in the order they were selected. Every action, Stitch included, takes
    /// them in this order, and a card's circle shows its place here.
    @Published private(set) var selection: [UUID] = []
    @Published var focused: UUID? = nil        // keyboard focus ring
    @Published var isStack = false             // selection UI only exists in the recent stack
    @Published var scroll: CGFloat = 0         // how far the column is pulled down to show older cards
    @Published var viewport: CGFloat = 0       // visible height of the column

    var inSelectionMode: Bool { !selection.isEmpty }
    /// The row under the column, shown only for a feedback toast.
    var showsBar: Bool { isStack && feedback != nil }
    var onAction: (ShotAction, [Card]) -> Void = { _, _ in }
    var onSweep: (CGFloat) -> Void = { _ in }       // y from the column top, during a drag from a circle
    var onSweepEnd: () -> Void = {}
    var onClickImage: (Card) -> Void = { _ in }
    var onHover: (UUID?) -> Void = { _ in }

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
        selection = ids.filter { seen.insert($0).inserted }
    }
}

/// Owns the bottom-right panel: fresh-screenshot thumbnails, the recent stack, feedback toasts,
/// and the transitions into and out of the annotator.
@MainActor
final class ThumbnailController {
    weak var actions: Actions?
    /// A card starts travelling to `frame`; the annotator loads the image there while hidden.
    var onAnnotatorPrepare: ((Screenshot, NSRect) -> Void)?
    /// The card has arrived; the annotator becomes visible in its place.
    var onAnnotatorShow: (() -> Void)?
    /// A swap, return, or dismissal has started. The annotator parks its draft, hides, then calls back.
    var onAnnotatorHide: ((_ hidden: @escaping () -> Void) -> Void)?
    /// Space the annotator needs below its window, for the toolbar.
    var annotatorBelow: () -> CGFloat = { 0 }

    private let panel = ThumbnailPanel()
    private let backdrop = BackdropPanel()
    private let dim = DimPanel()
    private let flights = TransitionLayer()
    private let model = StackModel()
    private var hosting: NSHostingView<StackView>!
    private var dismissTimer: Timer?
    private var outsideClickMonitor: Any?
    private var visible = false {
        // Flight decodes are screen-sized; they are only worth keeping while the stack is up.
        didSet { if !visible { flightImages.removeAll(); flightOrder.removeAll() } }
    }
    private var dismissGeneration = 0
    private var shrinkGeneration = 0
    private var stitchGeneration = 0
    private var sweepAnchor: Int?
    private var sweepSelecting = true
    private var sweepBefore: [UUID] = []
    /// The one owner of the annotation session. Only `send` writes it; see AnnotatorTransition.
    private var transition = AnnotatorTransition()
    /// The card the session is about, kept here because a lone thumbnail leaves the model once the annotator shows.
    private var sessionCard: Card?
    private var annotating: Card? { transition.isActive ? sessionCard : nil }
    private var annotationFrame: NSRect = .zero
    /// Keys whose image the page reports on its canvas. The flight image lifts once the annotator
    /// is visible and its key is here, so an empty editor is never seen.
    private var loadedKeys: Set<String> = []
    /// True when the session ends by the user's hand, so focus returns to their app once the annotator is gone.
    private var restoreFocusOnEnd = false
    /// Renderings of drafts, by file path. Cards show these instead of the file while a draft exists.
    private var previews: [String: NSImage] = [:]
    /// Larger decodes for the flight to the annotator, by file path. Filled on hover.
    private var flightImages: [String: NSImage] = [:]
    private var flightOrder: [String] = []

    init() {
        hosting = NSHostingView(rootView: StackView(model: model))
        panel.contentView = hosting
        panel.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        panel.onScroll = { [weak self] event in self?.scroll(event) }
        model.onAction = { [weak self] action, cards in
            guard let self else { return }
            if cards.count == 1, let index = self.model.cards.firstIndex(where: { $0.id == cards[0].id }) { self.scrollToReveal(index) }
            self.run(action, on: cards)
        }
        model.onClickImage = { [weak self] card in
            guard let self else { return }
            if self.transition.isActive { self.annotate(card); return }
            if self.model.inSelectionMode { self.toggle(card) }
            else if let action = Config.actions.first(where: \.isDefault) { self.run(action, on: [card]) }
        }
        model.onSweep = { [weak self] y in self?.sweep(toYFromTop: y) }
        model.onSweepEnd = { [weak self] in
            guard let self else { return }
            self.sweepAnchor = nil
            self.revealFocused()
        }
        model.onHover = { [weak self] id in self?.prefetchFlightImage(id) }
    }

    /// The screen a presentation started on. `NSScreen.main` follows the active display, which is
    /// what the user is looking at; pinning it keeps every frame of one presentation on one screen.
    private var pinnedScreen: NSScreen?
    private var screen: NSScreen {
        if let pinned = pinnedScreen, NSScreen.screens.contains(pinned) { return pinned }
        return NSScreen.main ?? NSScreen.screens[0]
    }
    /// A display was added, removed, or rearranged. Whatever is showing moves to a screen that exists.
    func screensChanged() {
        guard visible else { return }
        if let pinned = pinnedScreen, !NSScreen.screens.contains(pinned) { pinnedScreen = NSScreen.main ?? NSScreen.screens[0] }
        Log.write("[screen] changed; relayout on \(screen.localizedName)")
        relayout()
        if model.isStack { backdrop.refresh(on: screen) }
    }
    private var cardSizes: [NSSize] { model.cards.map(\.size) }
    private var ui: UITweaks { Settings.shared.motionUI }
    private var layout: StackLayout { StackLayout(ui: ui) }
    private var showsBar: Bool { model.showsBar }
    private var showsStrip: Bool { model.isStack && model.inSelectionMode }

    /// The selection strip's screen frame, or nil when nothing is selected.
    private var stripFrame: NSRect? {
        guard showsStrip, let strip = layout.stripPlacement(rows: Config.stripActions.count, selection: model.selectedIndices(),
                                                            cards: cardSizes, showsBar: showsBar,
                                                            scroll: model.scroll, viewport: model.viewport) else { return nil }
        return layout.stripFrame(strip, panelFrame: panel.frame, scroll: model.scroll)
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
                            "draft": model.drafts.contains(card.shot.url.path), "agent": card.agent as Any]
                },
                "selected": model.selectedCards().map(\.shot.url.path),
                "focused": model.cards.first { $0.id == model.focused }?.shot.url.path as Any,
                "feedback": model.feedback as Any, "key": panel.isKeyWindow,
                "scroll": Int(model.scroll), "viewport": Int(model.viewport),
                "panel": StateReport.topLeft(panel.frame, primaryHeight: h),
                "strip": stripFrame.map { StateReport.topLeft($0, primaryHeight: h) } as Any,
            ] as [String: Any],
            "transition": ["phase": "\(transition.phase)", "annotating": annotating?.shot.url.path as Any, "isActive": transition.isActive],
            "screen": ["name": s.localizedName, "frame": StateReport.topLeft(s.frame, primaryHeight: h),
                       "visibleFrame": StateReport.topLeft(s.visibleFrame, primaryHeight: h), "scale": s.backingScaleFactor, "pinned": pinnedScreen != nil],
            "previews": previews.keys.sorted(),
            "backdrop": backdrop.stateJSON,
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
        if transition.isActive { send(.dismiss) }   // a lone annotation gives way to the stack
        let started = CACurrentMediaTime()
        let cards = shots.compactMap(makeCard)
        guard !cards.isEmpty else { return .empty }
        present(cards: cards, stack: true)
        installOutsideClickMonitor()
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
        Thumbnailer.warm(items)
    }

    /// The panel can refuse key status right after resigning it (a dismissal being reversed), so try twice.
    private func takeKeys() {
        panel.acceptsKeys = true
        panel.makeKey()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.visible, self.model.isStack, !self.transition.isActive, !self.panel.isKeyWindow else { return }
            self.panel.makeKey()
        }
    }

    /// Opens the annotator on `shot`, or swaps to it if the annotator is already open. Shows the
    /// card first if it is not on screen.
    func annotate(_ shot: Screenshot) {
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

    /// The page abandoned the session (Esc, click outside, Cmd+W). The reducer decides what returns.
    func annotationEnded() {
        restoreFocusOnEnd = true
        send(.close)
    }

    /// Done or Return: the result is on the clipboard. The card comes back marked copied; in quick
    /// mode everything closes instead.
    func annotationFinished(quick: Bool) {
        restoreFocusOnEnd = true
        if quick {
            if visible { dismiss() } else { send(.dismiss) }
        } else {
            send(.finish)
        }
    }

    /// The page has the image for `key` on its canvas.
    func pageLoaded(_ key: String) {
        loadedKeys.insert(key)
        if case .annotating(let k) = transition.phase, k == key, let card = sessionCard { flights.end(id: card.id) }
    }

    func setDrafts(_ paths: Set<String>) {
        model.drafts = paths
        // A draft that was emptied or forgotten shows the file again.
        for path in previews.keys where !paths.contains(path) {
            previews[path] = nil
            if let card = model.cards.first(where: { $0.shot.url.path == path }) {
                replaceImage(of: card, with: Thumbnailer.image(at: card.shot.url, maxPixel: thumbnailPixels(size: card.size, pointSize: card.pointSize)))
            }
        }
    }

    /// The preview lands a moment later, decoded off the main thread; a draft emptied meanwhile wins.
    func setPreview(_ path: String, _ png: Data) {
        Thumbnailer.decode(png: png) { [weak self] image in
            guard let self, let image, self.model.drafts.contains(path) else { return }
            self.previews[path] = image
            if let card = self.model.cards.first(where: { $0.shot.url.path == path }) {
                self.replaceImage(of: card, with: image)
                self.flights.setImage(id: card.id, image)
            }
        }
    }

    /// Drops cards whose files no longer exist.
    func remove(_ shots: [Screenshot]) {
        let urls = Set(shots.map(\.url))
        for url in urls { send(.remove(url.path)) }
        for card in model.cards where urls.contains(card.shot.url) { flights.end(id: card.id) }
        model.cards.removeAll { urls.contains($0.shot.url) }
        model.setSelection(model.selection.filter { id in model.cards.contains { $0.id == id } })
        if model.cards.isEmpty { dismiss(); return }
        relayout()
    }

    /// Re-applies layout tweaks to whatever is on screen. Called when settings.ui changes.
    func applyTweaks() {
        guard visible else { return }
        model.cards = model.cards.map { card in
            let size = layout.cardSize(for: card.pointSize)
            let image = previews[card.shot.url.path] ?? Thumbnailer.image(at: card.shot.url, maxPixel: thumbnailPixels(size: size, pointSize: card.pointSize)) ?? card.image
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
        // Where each card is now, while the selection bar is still part of the column.
        let flying = cards.map { (id: $0.id, image: flightImage(for: $0), from: cardFrame(of: $0)) }
        let ids = Set(cards.map(\.id))
        model.forming.formUnion(ids)
        model.forming.insert(result.id)
        model.cards.removeAll { ids.contains($0.id) }
        model.clearSelection()
        if let focused = model.focused, ids.contains(focused) { model.focused = nil }
        model.cards.insert(result, at: 0)
        withAnimation(Anim.spring(ui.relayoutDuration)) { model.scroll = 0 }
        relayout()
        stitchGeneration += 1
        let generation = stitchGeneration
        flights.converge(pieces: flying, result: (id: result.id, image: stitched, frame: cardFrame(of: result)),
                         corner: ui.cardCornerRadius, on: screen) { [weak self] in
            guard let self else { return }
            self.model.forming.subtract(ids)
            self.model.forming.remove(result.id)
            guard self.stitchGeneration == generation, self.visible,
                  self.model.cards.contains(where: { $0.id == result.id }) else { return }
            self.showCopied([result.shot])
        }
        Log.write("[stack] stitched cards=\(cards.count) into=\(url.lastPathComponent)")
        return true
    }

    /// The stitched image decodes here and not on the background queue `makeCard` uses: the card is
    /// the destination of a flight that starts in the same run loop turn, so it cannot arrive later.
    private func makeStitchedCard(_ url: URL) -> Card? {
        guard let pointSize = Thumbnailer.pointSize(of: url) else { return nil }
        let size = layout.cardSize(for: pointSize)
        guard let image = Thumbnailer.image(at: url, maxPixel: thumbnailPixels(size: size, pointSize: pointSize)) else { return nil }
        return Card(id: UUID(), shot: Screenshot(url: url), image: image, pointSize: pointSize, size: size,
                    agent: Agent.of(url))
    }

    /// "Copied" over the cards themselves; the toast only when none of them is showing.
    func showCopied(_ shots: [Screenshot]) {
        let ids = shots.compactMap { shot in model.cards.first { $0.shot.url == shot.url }?.id }
        guard visible, !ids.isEmpty else {
            showFeedback(shots.count == 1 ? "Copied to clipboard" : "Copied \(shots.count) images")
            return
        }
        model.copied.formUnion(ids)
        // A card still on its way back from the annotator shows the mark when it lands.
        let hold = ui.toastSeconds + ui.expandDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) { [weak self] in self?.model.copied.subtract(ids) }
        if !model.isStack { scheduleDismiss(after: hold) }
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
        model.cards = []
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
        dismissGeneration += 1
        let gen = dismissGeneration
        dismissTimer?.invalidate()
        removeOutsideClickMonitor()
        releaseKeys()
        backdrop.hide()
        if let card = annotating, model.isStack {
            // The image in the annotator leaves with the stack while the page parks its draft.
            var slot = cardFrame(of: card)
            slot.origin.x += layout.offscreenDistance(cardWidth: slot.width)
            flights.fly(id: card.id, image: flightImage(for: currentCard(card)), from: annotationFrame, to: slot, cornerFrom: ui.annotationCornerRadius, cornerTo: ui.cardCornerRadius, on: screen) { [weak self] in
                self?.flights.end(id: card.id)
            }
        }
        if transition.isActive { send(.dismiss) }
        // Cards leave the way they came, newest first (see CardView). The selection and any toast
        // stay in the layout and slide out with them; the block below clears them once gone.
        model.slidingOut = true
        model.offscreen = Set(model.cards.map(\.id))
        let total = ui.slideOutDuration + Double(max(0, model.cards.count - 1)) * StackView.staggerStep(count: model.cards.count) + 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + (model.cards.isEmpty ? ui.slideOutDuration : total)) { [weak self] in
            guard let self, self.dismissGeneration == gen, !self.visible else { return }
            self.panel.orderOut(nil)
            self.model.cards = []
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

    private func send(_ event: AnnotatorTransition.Event) {
        let effects = transition.reduce(event)
        Log.write("[transition] \(event) -> \(transition.phase) effects=\(effects.map(\.description).joined(separator: " "))")
        for effect in effects { perform(effect) }
    }

    private func perform(_ effect: AnnotatorTransition.Effect) {
        switch effect {
        case .prepare(let key):
            guard let card = model.cards.first(where: { $0.shot.url.path == key }) else { return }
            sessionCard = card
            loadedKeys.remove(key)
            dismissTimer?.invalidate()
            model.clearSelection()
            releaseKeys()
            _ = model.outCards.insert(card.id)
            let target = targetFrame(for: card)
            annotationFrame = target
            dim.show(on: screen)
            onAnnotatorPrepare?(card.shot, target)
            var from = cardFrame(of: card)
            if model.offscreen.contains(card.id) { from.origin.x += layout.offscreenDistance(cardWidth: from.width) }
            flights.fly(id: card.id, image: flightImage(for: card), from: from, to: target, cornerFrom: ui.cardCornerRadius, cornerTo: ui.annotationCornerRadius, on: screen) { [weak self] in
                guard let self, self.transition.phase == .flyingOut(key) else { return }
                self.send(.shown)
            }
        case .show:
            onAnnotatorShow?()
            guard let card = sessionCard else { return }
            if loadedKeys.contains(card.shot.url.path) { flights.end(id: card.id) }   // else pageLoaded lifts it
            if !model.isStack {
                // A lone thumbnail has nothing to keep open behind the annotator; cards that joined stay.
                model.cards.removeAll { $0.id == card.id }
                model.outCards.remove(card.id)
                if model.cards.isEmpty { visible = false; panel.orderOut(nil) } else { relayout() }
            }
        case .park:
            onAnnotatorHide? { [weak self] in self?.send(.parked) }
        case .returnCard(let key):
            guard let card = sessionCard, card.shot.url.path == key else { return }
            if !transition.isActive { sessionCard = nil; dim.hide(); endSession() }
            returnCard(currentCard(card))
        case .hideAnnotator:
            // While the stack slides out, the image is flying to its slot's offscreen position
            // (see `dismiss`); that flight ends itself, and the slide-out's completion clears the card.
            if let card = sessionCard, !model.slidingOut { model.outCards.remove(card.id); flights.end(id: card.id) }
            sessionCard = nil
            dim.hide()
            endSession()
        case .markCopied(let key):
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
        flights.fly(id: card.id, image: flightImage(for: card), from: annotationFrame, to: cardFrame(of: card), cornerFrom: ui.annotationCornerRadius, cornerTo: ui.cardCornerRadius, on: screen) { [weak self] in
            guard let self else { return }
            self.model.outCards.remove(card.id)
            // The card view comes back on SwiftUI's next commit; lift the flight image after it.
            DispatchQueue.main.async { self.flights.end(id: card.id) }
            if !self.transition.isActive, self.visible, self.model.isStack { self.takeKeys() }
            // A lone thumbnail leaves on its own; the copied mark usually sets a shorter timer first.
            if !self.model.isStack, self.dismissTimer == nil { self.scheduleDismiss(after: self.ui.thumbnailSeconds) }
        }
    }

    private func targetFrame(for card: Card) -> NSRect {
        layout.annotationFrame(for: card.pointSize, visibleFrame: screen.visibleFrame, below: annotatorBelow())
    }

    /// The best image for the flight: the draft preview, a larger decode if hovering fetched one,
    /// else the thumbnail, upgraded as soon as a larger decode arrives.
    private func flightImage(for card: Card) -> NSImage {
        let path = card.shot.url.path
        if let preview = previews[path] { return preview }
        if let image = flightImages[path] { return image }
        prefetchFlightImage(card.id)
        return card.image ?? NSImage(size: card.size)
    }

    private func prefetchFlightImage(_ id: UUID?) {
        guard let id, let card = model.cards.first(where: { $0.id == id }) else { return }
        let path = card.shot.url.path
        guard flightImages[path] == nil, previews[path] == nil else { return }
        let maxPixel = Int(ceil(max(screen.visibleFrame.width, screen.visibleFrame.height) * (screen.backingScaleFactor)))
        Thumbnailer.load(at: card.shot.url, maxPixel: maxPixel) { [weak self] image in
            // `visible`: a decode that lands after the stack hid must not refill the cache it cleared.
            guard let self, let image, self.visible, self.previews[path] == nil else { return }
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
        layout.cardFrame(index: index, cards: cardSizes, panelFrame: panel.frame, showsBar: showsBar, scroll: model.scroll)
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

    /// Dragging from a circle selects (or deselects) every card between the start and the cursor,
    /// in the order the drag reached them. Backing up restores cards the drag passed over.
    private func sweep(toYFromTop y: CGFloat) {
        guard let index = layout.cardIndex(atYFromTop: y, cards: cardSizes) else { return }
        if sweepAnchor == nil {
            sweepAnchor = index
            sweepSelecting = !model.isSelected(model.cards[index].id)
            sweepBefore = model.selection
        }
        let anchor = sweepAnchor!
        let passed = stride(from: anchor, through: index, by: index < anchor ? -1 : 1).map { model.cards[$0].id }
        model.setSelection(sweepSelecting ? sweepBefore + passed : sweepBefore.filter { !passed.contains($0) })
        model.focused = model.cards[index].id
        relayout()
    }

    private func run(_ action: ShotAction, on cards: [Card]) {
        guard let actions, cards.count >= action.minimumCount else { return }
        action.run(cards.map(\.shot), actions)
    }

    /// Cards a shortcut acts on: the selection, else the focused card, else the hovered one, else the newest.
    private func targetCards() -> [Card] {
        if model.inSelectionMode { return model.selectedCards() }
        if let id = model.focused ?? model.hoveredCard, let card = model.cards.first(where: { $0.id == id }) { return [card] }
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
        for action in Config.actions {
            guard let key = action.key else { continue }
            let matches = (key.character == "\u{7f}" && isDelete) || (key.character == "\r" && isReturn)
                || (key.character != "\u{7f}" && key.character != "\r" && key.character == chars)
            if matches && mods == key.modifiers {
                run(action, on: targetCards())
                return true
            }
        }
        return false
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

    private var maxScroll: CGFloat {
        max(0, layout.contentHeight(cards: cardSizes, showsBar: showsBar) - model.viewport)
    }

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
        let card = Card(id: UUID(), shot: shot, image: previews[shot.url.path] ?? Thumbnailer.cached(at: shot.url, maxPixel: maxPixel),
                        pointSize: pointSize, size: size, agent: Agent.of(shot.url))
        if card.image == nil {
            Thumbnailer.load(at: shot.url, maxPixel: maxPixel) { [weak self] image in
                guard let self, let image, self.previews[shot.url.path] == nil, self.model.cards.contains(where: { $0.id == card.id }) else { return }
                self.replaceImage(of: card, with: image)
            }
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
        model.hoveredCard = nil
        model.clearSelection()
        model.outCards = []
        model.forming = []
        model.focused = nil
        let wasStack = model.isStack
        model.isStack = stack
        model.slidingOut = false
        model.scroll = 0
        if !stack { releaseKeys() }
        // A dismissal in progress is simply reversed: the same cards turn around. `visible` is
        // already false then; the panel stays up until the slide-out ends.
        let reusing = panel.isVisible && !model.cards.isEmpty && Set(cards.map(\.shot.url)) == Set(model.cards.map(\.shot.url))
        if !reusing {
            // A lone thumbnail that is part of the stack stays where it is; the rest slides in above it.
            let staying = (visible && !wasStack && stack) ? model.cards.first { existing in cards.contains { $0.shot.url == existing.shot.url } } : nil
            let next = cards.map { card in card.shot.url == staying?.shot.url ? staying! : card }
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
        panel.setFrame(layout.panelFrame(viewport: 40, visibleFrame: screen.visibleFrame, showsStrip: false), display: false)
        panel.orderFrontRegardless()
    }

    /// A card joins the bottom of the visible column and slides in.
    private func insert(_ card: Card, entrance: Entrance = .slide) {
        guard !model.cards.contains(where: { $0.shot.url == card.shot.url }) else { return }
        dismissGeneration += 1
        if model.feedback != nil && !model.isStack { model.feedback = nil; model.cards = [] }
        if entrance != .inPlace { _ = model.offscreen.insert(card.id) }
        model.slidingOut = false
        model.cards.insert(card, at: 0)
        if model.cards.count > Settings.shared.data.recentCount, let last = model.cards.last {
            model.cards.removeLast()
            model.deselect([last.id])
        }
        withAnimation(Anim.spring(ui.relayoutDuration)) { model.scroll = 0 }
        layoutPanel(shrinkLater: false, animated: true)
        DispatchQueue.main.async { [weak self] in self?.model.offscreen.remove(card.id) }
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
    private func layoutPanel(shrinkLater: Bool, animated: Bool) {
        let content = layout.contentHeight(cards: cardSizes, showsBar: showsBar)
        let viewport = layout.viewportHeight(content: content, visibleFrame: screen.visibleFrame)
        var transaction = Transaction(animation: animated ? Anim.spring(ui.relayoutDuration) : nil)
        transaction.disablesAnimations = !animated
        withTransaction(transaction) {
            model.viewport = viewport
            model.scroll = min(model.scroll, max(0, content - viewport))
        }
        let target = layout.panelFrame(viewport: viewport, visibleFrame: screen.visibleFrame, showsStrip: showsStrip)
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

    /// A click outside this app's windows closes the stack, and the annotator with it.
    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = OutsideClick.monitor { [weak self] in self?.dismiss() }
    }

    private func removeOutsideClickMonitor() {
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m) }
        outsideClickMonitor = nil
    }
}
