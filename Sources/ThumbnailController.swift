import AppKit
import SwiftUI

struct Card: Identifiable {
    let id: UUID
    let shot: Screenshot
    var image: NSImage?       // thumbnail-sized, or the draft preview; nil until decoded
    let pointSize: NSSize     // the screenshot in points, for the annotator frame
    let size: NSSize          // the card on screen

    func with(image: NSImage?) -> Card { Card(id: id, shot: shot, image: image, pointSize: pointSize, size: size) }
    func with(size: NSSize) -> Card { Card(id: id, shot: shot, image: image, pointSize: pointSize, size: size) }
}

@MainActor
final class StackModel: ObservableObject {
    @Published var cards: [Card] = []          // index 0 is newest, drawn at the bottom
    @Published var offscreen: Set<UUID> = []   // cards parked past the right screen edge
    var slidingOut = false                     // picks the exit stagger order and curve for `offscreen`
    @Published var outCards: Set<UUID> = []    // cards currently in the annotator; drawn as placeholders
    @Published var drafts: Set<String> = []    // file paths with annotations in progress
    @Published var feedback: String? = nil
    @Published var hoveredCard: UUID? = nil { didSet { if hoveredCard != oldValue { onHover(hoveredCard) } } }
    @Published var pressedCard: UUID? = nil
    @Published var selected: Set<UUID> = []
    @Published var focused: UUID? = nil        // keyboard focus ring
    @Published var isStack = false             // selection UI only exists in the recent stack
    @Published var scroll: CGFloat = 0         // how far the column is pulled down to show older cards
    @Published var viewport: CGFloat = 0       // visible height of the column

    var inSelectionMode: Bool { !selected.isEmpty }
    var onAction: (ShotAction, [Card]) -> Void = { _, _ in }
    var onSweep: (CGFloat) -> Void = { _ in }       // y from the column top, during a drag from a circle
    var onSweepEnd: () -> Void = {}
    var onClickImage: (Card) -> Void = { _ in }
    var onHover: (UUID?) -> Void = { _ in }

    /// Cards for a bulk action, oldest first.
    func selectedCards() -> [Card] { cards.filter { selected.contains($0.id) }.reversed() }
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
    private var visible = false
    private var dismissGeneration = 0
    private var shrinkGeneration = 0
    private var sweepAnchor: Int?
    private var sweepSelecting = true
    private var sweepBefore: Set<UUID> = []
    private var annotating: Card?
    private var annotationFrame: NSRect = .zero
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
        model.onAction = { [weak self] action, cards in self?.run(action, on: cards) }
        model.onClickImage = { [weak self] card in
            guard let self else { return }
            if self.annotating != nil { self.annotate(card); return }
            if self.model.inSelectionMode { self.toggle(card) }
            else if let action = Config.actions.first(where: \.isDefault) { self.run(action, on: [card]) }
        }
        model.onSweep = { [weak self] y in self?.sweep(toYFromTop: y) }
        model.onSweepEnd = { [weak self] in self?.sweepAnchor = nil }
        model.onHover = { [weak self] id in self?.prefetchFlightImage(id) }
    }

    /// The screen a presentation started on. `NSScreen.main` follows the active display, which is
    /// what the user is looking at; pinning it keeps every frame of one presentation on one screen.
    private var pinnedScreen: NSScreen?
    private var screen: NSScreen {
        if let pinned = pinnedScreen, NSScreen.screens.contains(pinned) { return pinned }
        return NSScreen.main ?? NSScreen.screens[0]
    }
    var screenDescription: String {
        let s = screen
        return "screen=\"\(s.localizedName)\" screenFrame=\(Int(s.frame.minX)),\(Int(s.frame.minY)),\(Int(s.frame.width)),\(Int(s.frame.height)) pinned=\(pinnedScreen != nil)"
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
    private var ui: UITweaks { Settings.shared.data.ui }
    private var showsBar: Bool { model.isStack && (model.inSelectionMode || model.feedback != nil) }

    var backdropDescription: String { backdrop.stateDescription }

    /// Card frames in screen points, newest first, for scripts that need to click on cards.
    var cardFramesDescription: String {
        (0..<model.cards.count).map { i in
            let f = cardFrame(i)
            return "\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width)),\(Int(f.height))"
        }.joined(separator: " ")
    }

    var stateDescription: String {
        "visible=\(visible) stack=\(model.isStack) cards=\(model.cards.map { $0.shot.url.lastPathComponent }) selected=\(model.selectedCards().map { $0.shot.url.lastPathComponent }) focused=\(model.cards.first { $0.id == model.focused }?.shot.url.lastPathComponent ?? "nil") annotating=\(annotating?.shot.url.lastPathComponent ?? "nil") out=\(model.outCards.count) feedback=\(model.feedback ?? "nil") key=\(panel.isKeyWindow) scroll=\(Int(model.scroll)) viewport=\(Int(model.viewport)) panel=\(panel.frame)"
    }

    // MARK: Public

    /// A fresh screenshot. Joins the bottom of whatever is showing; on its own it leaves after a
    /// few seconds unless hovered.
    func show(_ shot: Screenshot) {
        guard let card = makeCard(shot) else { return }
        if visible {
            insert(card)
        } else {
            present(cards: [card], stack: false)
        }
        if !model.isStack { scheduleDismiss(after: ui.thumbnailSeconds) }
    }

    enum StackToggle: Equatable { case shown(Int), dismissed, empty }

    /// The recent stack: toggles. Takes keyboard focus. Stays until Esc, the hotkey, or a click elsewhere.
    @discardableResult
    func toggleRecent(_ shots: [Screenshot]) -> StackToggle {
        if visible && model.isStack { dismiss(); return .dismissed }
        let started = CACurrentMediaTime()
        let cards = shots.compactMap(makeCard)
        guard !cards.isEmpty else { return .empty }
        present(cards: cards, stack: true)
        installOutsideClickMonitor()
        backdrop.show(on: screen, below: panel)
        takeKeys()
        Log.write("[stack] shown in \(Int((CACurrentMediaTime() - started) * 1000))ms, \(cards.filter { $0.image == nil }.count) still decoding")
        return .shown(cards.count)
    }

    /// Decodes thumbnails for `shots` in the background so the stack opens without waiting.
    func warm(_ shots: [Screenshot]) {
        let items = shots.compactMap { shot -> (url: URL, maxPixel: Int)? in
            guard let pointSize = Thumbnailer.pointSize(of: shot.url) else { return nil }
            return (shot.url, thumbnailPixels(size: StackLayout.cardSize(for: pointSize), pointSize: pointSize))
        }
        Thumbnailer.warm(items)
    }

    /// The panel can refuse key status right after resigning it (a dismissal being reversed), so try twice.
    private func takeKeys() {
        panel.acceptsKeys = true
        panel.makeKey()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.visible, self.model.isStack, self.annotating == nil, !self.panel.isKeyWindow else { return }
            self.panel.makeKey()
        }
    }

    /// Opens the annotator on `shot`, or swaps to it if the annotator is already open. Shows the
    /// card first if it is not on screen.
    func annotate(_ shot: Screenshot) {
        if visible, let card = card(for: shot) { annotate(card); return }
        show(shot)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, let card = self.card(for: shot) else { return }
            self.annotate(card)
        }
    }

    /// The annotator closed (Esc, click out, or Done). In the stack the card returns to its slot.
    func annotationEnded() {
        guard let card = annotating else { return }
        annotating = nil
        dim.hide()
        if visible && model.isStack { returnCard(currentCard(card)) } else { model.outCards = [] }
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

    func setPreview(_ path: String, _ png: Data) {
        guard let image = NSImage(data: png) else { return }
        previews[path] = image
        if let card = model.cards.first(where: { $0.shot.url.path == path }) {
            replaceImage(of: card, with: image)
            flights.setImage(id: card.id, image)
        }
    }

    /// Drops cards whose files no longer exist.
    func remove(_ shots: [Screenshot]) {
        let urls = Set(shots.map(\.url))
        if let card = annotating, urls.contains(card.shot.url) {
            annotating = nil
            model.outCards.remove(card.id)
            dim.hide()
            flights.end(id: card.id)
            onAnnotatorHide? {}
        }
        for card in model.cards where urls.contains(card.shot.url) { flights.end(id: card.id) }
        model.cards.removeAll { urls.contains($0.shot.url) }
        model.selected = model.selected.filter { id in model.cards.contains { $0.id == id } }
        if model.cards.isEmpty { dismiss(); return }
        relayout()
    }

    /// Re-applies layout tweaks to whatever is on screen. Called when settings.ui changes.
    func applyTweaks() {
        guard visible else { return }
        model.cards = model.cards.map { card in
            let size = StackLayout.cardSize(for: card.pointSize)
            let image = previews[card.shot.url.path] ?? Thumbnailer.image(at: card.shot.url, maxPixel: thumbnailPixels(size: size, pointSize: card.pointSize)) ?? card.image
            return card.with(size: size).with(image: image)
        }
        relayout()
        if model.isStack { backdrop.refresh(on: screen) }
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
        model.selected = []
        model.outCards = []
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
        if let card = annotating {
            annotating = nil
            dim.hide()
            onAnnotatorHide? {}
            // The image in the annotator leaves with the stack.
            var slot = cardFrame(of: card)
            slot.origin.x += StackLayout.offscreenDistance(cardWidth: slot.width)
            flights.fly(id: card.id, image: flightImage(for: currentCard(card)), from: annotationFrame, to: slot, cornerFrom: ui.annotationCornerRadius, cornerTo: ui.cardCornerRadius, on: screen) { [weak self] in
                self?.flights.end(id: card.id)
            }
        }
        // Cards leave the way they came: staggered, top of the column first (see CardView).
        model.selected = []
        model.slidingOut = true
        model.offscreen = Set(model.cards.map(\.id))
        let total = ui.slideOutDuration + Double(max(0, model.cards.count - 1)) * StackView.staggerStep(count: model.cards.count) + 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + (model.cards.isEmpty ? ui.slideOutDuration : total)) { [weak self] in
            guard let self, self.dismissGeneration == gen, !self.visible else { return }
            self.panel.orderOut(nil)
            self.model.cards = []
            self.model.selected = []
            self.model.offscreen = []
            self.model.outCards = []
            self.model.slidingOut = false
            self.model.feedback = nil
            self.model.scroll = 0
            self.pinnedScreen = nil
            FocusReturn.shared.restore(reason: "stack dismissed")
        }
    }

    // MARK: Annotation transitions

    private func annotate(_ card: Card) {
        if let current = annotating {
            if current.id == card.id { return }
            swap(from: current, to: card)
            return
        }
        dismissTimer?.invalidate()
        annotating = card
        model.selected = []
        releaseKeys()
        _ = model.outCards.insert(card.id)
        let target = targetFrame(for: card)
        annotationFrame = target
        dim.show(on: screen)
        onAnnotatorPrepare?(card.shot, target)
        flights.fly(id: card.id, image: flightImage(for: card), from: cardFrame(of: card), to: target, cornerFrom: ui.cardCornerRadius, cornerTo: ui.annotationCornerRadius, on: screen) { [weak self] in
            guard let self, self.annotating?.id == card.id else { return }
            self.onAnnotatorShow?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { self.flights.end(id: card.id) }
            if !self.model.isStack {
                // A lone fresh thumbnail has nothing to keep open behind the annotator.
                self.visible = false
                self.panel.orderOut(nil)
                self.model.cards = []
                self.model.outCards = []
            }
        }
    }

    /// The current image returns to its slot while the new one travels out, at the same time.
    /// Both wait for the annotator to park its draft so the returning image carries the drawing.
    private func swap(from old: Card, to new: Card) {
        annotating = new
        _ = model.outCards.insert(new.id)
        let from = annotationFrame
        let target = targetFrame(for: new)
        annotationFrame = target
        onAnnotatorHide? { [weak self] in
            guard let self, self.annotating?.id == new.id else { return }
            let old = self.currentCard(old)
            self.flights.fly(id: old.id, image: self.flightImage(for: old), from: from, to: self.cardFrame(of: old), cornerFrom: self.ui.annotationCornerRadius, cornerTo: self.ui.cardCornerRadius, on: self.screen) { [weak self] in
                self?.model.outCards.remove(old.id)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { self?.flights.end(id: old.id) }
            }
            self.onAnnotatorPrepare?(new.shot, target)
            self.flights.fly(id: new.id, image: self.flightImage(for: new), from: self.cardFrame(of: new), to: target, cornerFrom: self.ui.cardCornerRadius, cornerTo: self.ui.annotationCornerRadius, on: self.screen) { [weak self] in
                guard let self, self.annotating?.id == new.id else { return }
                self.onAnnotatorShow?()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { self.flights.end(id: new.id) }
            }
        }
    }

    private func returnCard(_ card: Card) {
        flights.fly(id: card.id, image: flightImage(for: card), from: annotationFrame, to: cardFrame(of: card), cornerFrom: ui.annotationCornerRadius, cornerTo: ui.cardCornerRadius, on: screen) { [weak self] in
            self?.model.outCards.remove(card.id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { self?.flights.end(id: card.id) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.visible, self.model.isStack else { return }
            self.takeKeys()
        }
    }

    /// Centered in the part of the screen left of the stack, so the annotator never hides the cards.
    private func targetFrame(for card: Card) -> NSRect {
        let avoid = model.isStack ? StackLayout.maxCardWidth + StackLayout.margin * 2 : 0
        return StackLayout.annotationFrame(for: card.pointSize, on: screen, avoidRight: avoid, below: annotatorBelow())
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
            guard let self, let image, self.previews[path] == nil else { return }
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
        StackLayout.cardFrame(index: index, cards: cardSizes, panelFrame: panel.frame, showsBar: showsBar, scroll: model.scroll)
    }

    // MARK: Selection

    private func toggle(_ card: Card) {
        if model.selected.contains(card.id) { model.selected.remove(card.id) } else { model.selected.insert(card.id) }
        model.focused = card.id
        relayout()
    }

    /// Dragging from a circle selects (or deselects) every card between the start and the cursor.
    /// Backing up restores cards the drag passed over.
    private func sweep(toYFromTop y: CGFloat) {
        guard let index = StackLayout.cardIndex(atYFromTop: y, cards: cardSizes) else { return }
        if sweepAnchor == nil {
            sweepAnchor = index
            sweepSelecting = !model.selected.contains(model.cards[index].id)
            sweepBefore = model.selected
        }
        var next = sweepBefore
        for i in min(sweepAnchor!, index)...max(sweepAnchor!, index) {
            let id = model.cards[i].id
            if sweepSelecting { next.insert(id) } else { next.remove(id) }
        }
        model.selected = next
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
            if model.inSelectionMode { model.selected = []; relayout() }
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
            model.selected = Set(model.cards.map(\.id))
            relayout()
            return true
        }
        if chars == "a" && mods == [.command, .shift] {
            model.selected = []
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

    /// Down arrow moves toward the newest card (index 0), which sits at the bottom.
    private func moveFocus(toward delta: Int, extend: Bool) {
        guard !model.cards.isEmpty else { return }
        let current = model.cards.firstIndex { $0.id == model.focused }
        let next: Int
        if let current { next = max(0, min(model.cards.count - 1, current + delta)) } else { next = delta < 0 ? model.cards.count - 1 : 0 }
        model.focused = model.cards[next].id
        if extend { model.selected.insert(model.cards[next].id); if let current { model.selected.insert(model.cards[current].id) }; relayout() }
        scrollToReveal(next)
    }

    private func releaseKeys() {
        panel.acceptsKeys = false
        if panel.isKeyWindow { panel.resignKey() }
        model.focused = nil
    }

    // MARK: Scrolling

    private var maxScroll: CGFloat {
        max(0, StackLayout.contentHeight(cards: cardSizes, showsBar: showsBar) - model.viewport)
    }

    private func scroll(_ event: NSEvent) {
        guard visible, maxScroll > 0 else { return }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 10
        // Pulling the column down (fingers moving down) reveals older cards above.
        model.scroll = min(maxScroll, max(0, model.scroll + delta))
    }

    private func scrollToReveal(_ index: Int) {
        let span = StackLayout.cardSpan(index: index, cards: cardSizes, showsBar: showsBar)
        var target = model.scroll
        if span.top - model.scroll > model.viewport { target = span.top - model.viewport }
        if span.bottom - model.scroll < 0 { target = span.bottom }
        target = min(maxScroll, max(0, target))
        guard target != model.scroll else { return }
        withAnimation(.easeOut(duration: ui.relayoutDuration)) { model.scroll = target }
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
        let size = StackLayout.cardSize(for: pointSize)
        let maxPixel = thumbnailPixels(size: size, pointSize: pointSize)
        let card = Card(id: UUID(), shot: shot, image: previews[shot.url.path] ?? Thumbnailer.cached(at: shot.url, maxPixel: maxPixel), pointSize: pointSize, size: size)
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
    private func present(cards: [Card], stack: Bool) {
        if !visible { pinnedScreen = NSScreen.main ?? NSScreen.screens[0] }
        dismissTimer?.invalidate()
        dismissGeneration += 1
        if annotating != nil { annotating = nil; dim.hide(); onAnnotatorHide? {} }
        flights.endAll()
        model.feedback = nil
        model.hoveredCard = nil
        model.selected = []
        model.outCards = []
        model.focused = nil
        model.isStack = stack
        model.slidingOut = false
        model.scroll = 0
        if !stack { releaseKeys() }
        // A dismissal in progress is simply reversed: the same cards turn around.
        let reusing = visible && Set(cards.map(\.shot.url)) == Set(model.cards.map(\.shot.url))
        if !reusing {
            model.cards = cards
            model.offscreen = Set(cards.map(\.id))
        }
        visible = true
        layoutPanel(shrinkLater: false)
        panel.orderFrontRegardless()
        // The offscreen state must be committed before it is cleared, or nothing animates.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            guard let self, self.visible else { return }
            self.model.offscreen = []
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
        panel.setFrame(StackLayout.panelFrame(viewport: 40, on: screen), display: false)
        panel.orderFrontRegardless()
    }

    /// A card joins the bottom of the visible column and slides in.
    private func insert(_ card: Card) {
        guard !model.cards.contains(where: { $0.shot.url == card.shot.url }) else { return }
        dismissGeneration += 1
        if model.feedback != nil && !model.isStack { model.feedback = nil; model.cards = [] }
        _ = model.offscreen.insert(card.id)
        model.slidingOut = false
        model.cards.insert(card, at: 0)
        if model.cards.count > Settings.shared.data.recentCount, let last = model.cards.last {
            model.cards.removeLast()
            model.selected.remove(last.id)
        }
        withAnimation(.easeOut(duration: ui.relayoutDuration)) { model.scroll = 0 }
        layoutPanel(shrinkLater: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            self?.model.offscreen.remove(card.id)
        }
    }

    private func relayout() {
        guard visible else { return }
        layoutPanel(shrinkLater: true)
    }

    /// The panel grows at once so nothing is clipped while cards move, and shrinks once they have.
    /// Its bottom edge never moves; the column is anchored there.
    private func layoutPanel(shrinkLater: Bool) {
        let content = StackLayout.contentHeight(cards: cardSizes, showsBar: showsBar)
        let viewport = StackLayout.viewportHeight(content: content, on: screen)
        withAnimation(.easeOut(duration: ui.relayoutDuration)) {
            model.viewport = viewport
            model.scroll = min(model.scroll, max(0, content - viewport))
        }
        let target = StackLayout.panelFrame(viewport: viewport, on: screen)
        shrinkGeneration += 1
        if target.height >= panel.frame.height || !panel.isVisible || !shrinkLater {
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
                if self.model.hoveredCard != nil || self.annotating != nil { self.scheduleDismiss(after: 1.5); return }
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
