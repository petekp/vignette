import AppKit
import SwiftUI

struct Card: Identifiable {
    let id: UUID
    let shot: Screenshot
    let image: NSImage
    let size: NSSize

    init(shot: Screenshot, image: NSImage, size: NSSize, id: UUID = UUID()) {
        self.id = id; self.shot = shot; self.image = image; self.size = size
    }
}

final class StackModel: ObservableObject {
    @Published var cards: [Card] = []          // index 0 is newest, drawn at the bottom
    @Published var offscreen: Set<UUID> = []   // cards parked past the right screen edge
    var slidingOut = false                     // picks the exit stagger order and curve for `offscreen`
    @Published var outCards: Set<UUID> = []    // cards currently in the annotator; drawn as placeholders
    @Published var feedback: String? = nil
    @Published var hoveredCard: UUID? = nil
    @Published var selected: Set<UUID> = []
    @Published var focused: UUID? = nil        // keyboard focus ring
    @Published var isStack = false             // selection UI only exists in the recent stack

    var inSelectionMode: Bool { !selected.isEmpty }
    var onAction: (ShotAction, [Card]) -> Void = { _, _ in }
    var onSweep: (CGFloat) -> Void = { _ in }       // y from the panel top, during a drag from a circle
    var onSweepEnd: () -> Void = {}
    var onClickImage: (Card) -> Void = { _ in }

    /// Cards for a bulk action, oldest first.
    func selectedCards() -> [Card] { cards.filter { selected.contains($0.id) }.reversed() }
}

/// Owns the bottom-right panel: the single fresh-screenshot thumbnail, the recent stack, feedback
/// toasts, and the transitions into and out of the annotator.
final class ThumbnailController {
    weak var actions: Actions?
    /// A card starts travelling to `frame`; the annotator loads the image there while hidden.
    var onAnnotatorPrepare: ((Screenshot, NSRect) -> Void)?
    /// The card has arrived; the annotator becomes visible in its place.
    var onAnnotatorShow: (() -> Void)?
    /// A swap, return, or dismissal has started; the annotator hides at once.
    var onAnnotatorHide: (() -> Void)?

    private let panel = ThumbnailPanel()
    private let backdrop = BackdropPanel()
    private let expanders = [ExpandPanel(), ExpandPanel()]
    private let model = StackModel()
    private var hosting: NSHostingView<StackView>!
    private var dismissTimer: Timer?
    private var outsideClickMonitor: Any?
    private var visible = false
    private var sweepAnchor: Int?
    private var sweepSelecting = true
    private var annotating: Card?
    private var annotationFrame: NSRect = .zero

    init() {
        hosting = NSHostingView(rootView: StackView(model: model))
        panel.contentView = hosting
        panel.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        model.onAction = { [weak self] action, cards in self?.run(action, on: cards) }
        model.onClickImage = { [weak self] card in
            guard let self else { return }
            if self.annotating != nil { self.annotate(card); return }
            if self.model.inSelectionMode { self.toggle(card) }
            else if let action = Config.actions.first(where: \.isDefault) { self.run(action, on: [card]) }
        }
        model.onSweep = { [weak self] y in self?.sweep(toYFromTop: y) }
        model.onSweepEnd = { [weak self] in self?.sweepAnchor = nil }
    }

    private var screen: NSScreen { NSScreen.main ?? NSScreen.screens[0] }
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
        "visible=\(visible) stack=\(model.isStack) cards=\(model.cards.map { $0.shot.url.lastPathComponent }) selected=\(model.selectedCards().map { $0.shot.url.lastPathComponent }) focused=\(model.cards.first { $0.id == model.focused }?.shot.url.lastPathComponent ?? "nil") annotating=\(annotating?.shot.url.lastPathComponent ?? "nil") out=\(model.outCards.count) feedback=\(model.feedback ?? "nil") key=\(panel.isKeyWindow)"
    }

    // MARK: Public

    /// A fresh screenshot: single card, slides in, leaves after a few seconds unless hovered.
    func show(_ shot: Screenshot) {
        guard let card = makeCard(shot) else { return }
        present(cards: [card], stack: false)
        scheduleDismiss(after: ui.thumbnailSeconds)
    }

    /// The recent stack: toggles. Takes keyboard focus. Stays until Esc, the hotkey, or a click elsewhere.
    func toggleRecent(_ shots: [Screenshot]) {
        if visible && model.isStack { dismiss(); return }
        let cards = shots.compactMap(makeCard)
        guard !cards.isEmpty else { return }
        present(cards: cards, stack: true)
        installOutsideClickMonitor()
        backdrop.show(on: screen, below: panel)
        panel.acceptsKeys = true
        panel.makeKey()
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
        if visible && model.isStack { returnCard(card) } else { model.outCards = [] }
    }

    /// Drops cards whose files no longer exist.
    func remove(_ shots: [Screenshot]) {
        let urls = Set(shots.map(\.url))
        if let card = annotating, urls.contains(card.shot.url) {
            annotating = nil
            model.outCards.remove(card.id)
            onAnnotatorHide?()
        }
        model.cards.removeAll { urls.contains($0.shot.url) }
        model.selected = model.selected.filter { id in model.cards.contains { $0.id == id } }
        if model.cards.isEmpty { dismiss(); return }
        relayout()
    }

    /// Re-applies layout tweaks to whatever is on screen. Called when settings.ui changes.
    func applyTweaks() {
        guard visible else { return }
        model.cards = model.cards.map { Card(shot: $0.shot, image: $0.image, size: StackLayout.cardSize(for: $0.image.size), id: $0.id) }
        relayout()
        if model.isStack { backdrop.refresh(on: screen) }
    }

    /// In the stack the toast sits under the cards; on its own it replaces the single thumbnail.
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
        let size = NSSize(width: 220 + StackLayout.inset * 2, height: 40 + StackLayout.inset * 2)
        slidePanelIn(size: size)
        scheduleDismiss(after: ui.toastSeconds)
    }

    func dismiss() {
        guard visible else { return }
        visible = false
        dismissTimer?.invalidate()
        removeOutsideClickMonitor()
        releaseKeys()
        backdrop.hide()
        if annotating != nil {
            annotating = nil
            model.outCards = []
            onAnnotatorHide?()
        }
        if model.cards.isEmpty {
            // Toast-only panel slides out as one piece.
            let target = StackLayout.offscreenFrame(size: panel.frame.size, on: screen)
            Anim.run(ui.slideOutDuration, curve: "easeInOut", { panel.animator().setFrame(target, display: true) }, completion: { [weak self] in
                self?.finishDismiss()
            })
            return
        }
        // Cards leave the way they came: staggered, top of the column first (see CardView).
        model.selected = []
        model.slidingOut = true
        model.offscreen = Set(model.cards.map(\.id))
        let total = ui.slideOutDuration + Double(max(0, model.cards.count - 1)) * ui.staggerDelay + 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + total) { [weak self] in self?.finishDismiss() }
    }

    private func finishDismiss() {
        guard !visible else { return }
        panel.orderOut(nil)
        model.cards = []
        model.selected = []
        model.offscreen = []
        model.slidingOut = false
        model.feedback = nil
        FocusReturn.shared.restore(reason: "stack dismissed")
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
        let from = cardFrame(of: card)
        onAnnotatorPrepare?(card.shot, target)
        expanders[0].animate(image: card.image, from: from, to: target, cornerFrom: ui.cardCornerRadius, cornerTo: ui.annotationCornerRadius) { [weak self] in
            guard let self, self.annotating?.id == card.id else { return }
            self.onAnnotatorShow?()
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
    private func swap(from old: Card, to new: Card) {
        annotating = new
        onAnnotatorHide?()
        _ = model.outCards.insert(new.id)
        let target = targetFrame(for: new)
        expanders[0].animate(image: old.image, from: annotationFrame, to: cardFrame(of: old), cornerFrom: ui.annotationCornerRadius, cornerTo: ui.cardCornerRadius) { [weak self] in
            self?.model.outCards.remove(old.id)
        }
        annotationFrame = target
        onAnnotatorPrepare?(new.shot, target)
        expanders[1].animate(image: new.image, from: cardFrame(of: new), to: target, cornerFrom: ui.cardCornerRadius, cornerTo: ui.annotationCornerRadius) { [weak self] in
            guard let self, self.annotating?.id == new.id else { return }
            self.onAnnotatorShow?()
        }
    }

    private func returnCard(_ card: Card) {
        expanders[0].animate(image: card.image, from: annotationFrame, to: cardFrame(of: card), cornerFrom: ui.annotationCornerRadius, cornerTo: ui.cardCornerRadius) { [weak self] in
            self?.model.outCards.remove(card.id)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.visible, self.model.isStack else { return }
            self.panel.acceptsKeys = true
            self.panel.makeKey()
        }
    }

    /// Centered in the part of the screen left of the stack, so the annotator never hides the cards.
    private func targetFrame(for card: Card) -> NSRect {
        let avoid = model.isStack ? StackLayout.maxCardWidth + StackLayout.margin * 2 : 0
        return StackLayout.annotationFrame(for: card.image.size, on: screen, avoidRight: avoid)
    }

    private func cardFrame(of card: Card) -> NSRect {
        guard let index = model.cards.firstIndex(where: { $0.id == card.id }) else { return annotationFrame }
        return cardFrame(index)
    }

    private func cardFrame(_ index: Int) -> NSRect {
        StackLayout.cardFrame(index: index, cards: cardSizes, panelFrame: panel.frame, showsBar: showsBar)
    }

    // MARK: Selection

    private func toggle(_ card: Card) {
        if model.selected.contains(card.id) { model.selected.remove(card.id) } else { model.selected.insert(card.id) }
        model.focused = card.id
        relayout()
    }

    private func sweep(toYFromTop y: CGFloat) {
        guard let index = StackLayout.cardIndex(atYFromTop: y, cards: cardSizes) else { return }
        if sweepAnchor == nil {
            sweepAnchor = index
            sweepSelecting = !model.selected.contains(model.cards[index].id)
        }
        let range = min(sweepAnchor!, index)...max(sweepAnchor!, index)
        for i in range {
            let id = model.cards[i].id
            if sweepSelecting { model.selected.insert(id) } else { model.selected.remove(id) }
        }
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
        let chars = event.charactersIgnoringModifiers ?? ""
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
    }

    private func releaseKeys() {
        panel.acceptsKeys = false
        if panel.isKeyWindow { panel.resignKey() }
        model.focused = nil
    }

    // MARK: Internals

    private func card(for shot: Screenshot) -> Card? {
        model.cards.first { $0.shot.url == shot.url }
    }

    private func makeCard(_ shot: Screenshot) -> Card? {
        guard let image = NSImage(contentsOf: shot.url) else { return nil }
        return Card(shot: shot, image: image, size: StackLayout.cardSize(for: image.size))
    }

    private func present(cards: [Card], stack: Bool) {
        dismissTimer?.invalidate()
        if annotating != nil { annotating = nil; onAnnotatorHide?() }
        model.feedback = nil
        model.hoveredCard = nil
        model.selected = []
        model.outCards = []
        model.focused = nil
        model.isStack = stack
        model.cards = cards
        if !stack { releaseKeys() }
        let size = StackLayout.panelSize(cards: cards.map(\.size), showsBar: false)
        let resting = StackLayout.restingFrame(size: size, on: screen)
        if visible {
            Anim.run(ui.relayoutDuration) { panel.animator().setFrame(resting, display: true) }
        } else {
            visible = true
            panel.setFrame(resting, display: true)
            panel.orderFrontRegardless()
        }
        // Cards start past the screen edge and arrive staggered, bottom of the column first (see CardView).
        // The offscreen state must be committed before it is cleared, or nothing animates.
        model.slidingOut = false
        model.offscreen = Set(cards.map(\.id))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            guard let self, self.visible else { return }
            self.model.offscreen = []
        }
    }

    private func relayout() {
        slidePanelIn(size: StackLayout.panelSize(cards: cardSizes, showsBar: showsBar))
    }

    private func slidePanelIn(size: NSSize) {
        let resting = StackLayout.restingFrame(size: size, on: screen)
        if visible {
            Anim.run(ui.relayoutDuration, curve: "easeOut") { panel.animator().setFrame(resting, display: true) }
            return
        }
        visible = true
        panel.setFrame(StackLayout.offscreenFrame(size: size, on: screen), display: false)
        panel.orderFrontRegardless()
        Anim.run(ui.slideInDuration, curve: ui.slideInCurve) { panel.animator().setFrame(resting, display: true) }
    }

    private func scheduleDismiss(after seconds: TimeInterval) {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.model.hoveredCard != nil || self.annotating != nil { self.scheduleDismiss(after: 1.5); return }
            self.dismiss()
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
