import AppKit
import SwiftUI

struct Card: Identifiable {
    let id = UUID()
    let shot: Screenshot
    let image: NSImage
    let size: NSSize
}

final class StackModel: ObservableObject {
    @Published var cards: [Card] = []          // index 0 is newest, drawn at the bottom
    @Published var expandingCard: Card? = nil  // set while a card grows into the annotation window
    @Published var feedback: String? = nil
    @Published var hoveredCard: UUID? = nil
    var onCopy: (Card) -> Void = { _ in }
    var onAnnotate: (Card) -> Void = { _ in }
    var onDelete: (Card) -> Void = { _ in }
}

/// Owns the bottom-right panel: the single fresh-screenshot thumbnail, the recent stack, and feedback toasts.
final class ThumbnailController {
    var onCopy: ((Screenshot) -> Void)?
    var onDelete: ((Screenshot) -> Void)?
    var onAnnotate: ((Screenshot, NSRect) -> Void)?

    private let panel = ThumbnailPanel()
    private let model = StackModel()
    private var hosting: NSHostingView<StackView>!
    private var dismissTimer: Timer?
    private var outsideClickMonitor: Any?
    private var isStackMode = false
    private var visible = false

    init() {
        hosting = NSHostingView(rootView: StackView(model: model))
        panel.contentView = hosting
        model.onCopy = { [weak self] card in self?.copy(card) }
        model.onDelete = { [weak self] card in self?.delete(card) }
        model.onAnnotate = { [weak self] card in self?.annotate(card) }
    }

    private var screen: NSScreen { NSScreen.main ?? NSScreen.screens[0] }
    private var cardSizes: [NSSize] { model.cards.map(\.size) }

    // MARK: Public

    /// A fresh screenshot: single card, slides in, leaves after a few seconds unless hovered.
    func show(_ shot: Screenshot) {
        guard let card = makeCard(shot) else { return }
        isStackMode = false
        present(cards: [card])
        scheduleDismiss(after: 5)
    }

    /// The recent stack: toggles. Stays until dismissed by Esc, the hotkey, or a click elsewhere.
    func toggleRecent(_ shots: [Screenshot]) {
        if visible && isStackMode { dismiss(); return }
        let cards = shots.compactMap(makeCard)
        guard !cards.isEmpty else { return }
        isStackMode = true
        present(cards: cards)
        installOutsideClickMonitor()
    }

    /// Opens the annotator for the newest visible card, as if it were clicked.
    func annotateFirst() {
        guard let card = model.cards.first else { return }
        annotate(card)
    }

    func showFeedback(_ text: String) {
        model.cards = []
        model.expandingCard = nil
        model.feedback = text
        let size = NSSize(width: 220 + StackLayout.inset * 2, height: 40 + StackLayout.inset * 2)
        slideIn(size: size)
        scheduleDismiss(after: 1.4)
    }

    func dismiss() {
        guard visible else { return }
        visible = false
        dismissTimer?.invalidate()
        removeOutsideClickMonitor()
        let target = StackLayout.offscreenFrame(size: panel.frame.size, on: screen)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(target, display: true)
        }, completionHandler: { [weak self] in
            guard let self, !self.visible else { return }
            self.panel.orderOut(nil)
            self.model.cards = []
            self.model.feedback = nil
        })
    }

    // MARK: Internals

    private func makeCard(_ shot: Screenshot) -> Card? {
        guard let image = NSImage(contentsOf: shot.url) else { return nil }
        return Card(shot: shot, image: image, size: StackLayout.cardSize(for: image.size))
    }

    private func present(cards: [Card]) {
        dismissTimer?.invalidate()
        model.feedback = nil
        model.expandingCard = nil
        model.hoveredCard = nil
        model.cards = cards
        slideIn(size: StackLayout.panelSize(cards: cards.map(\.size)))
    }

    private func slideIn(size: NSSize) {
        let resting = StackLayout.restingFrame(size: size, on: screen)
        if visible {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(resting, display: true)
            }
            return
        }
        visible = true
        panel.setFrame(StackLayout.offscreenFrame(size: size, on: screen), display: false)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.0)
            panel.animator().setFrame(resting, display: true)
        }
    }

    private func scheduleDismiss(after seconds: TimeInterval) {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.model.hoveredCard != nil { self.scheduleDismiss(after: 1.5); return }
            self.dismiss()
        }
    }

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func removeOutsideClickMonitor() {
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m) }
        outsideClickMonitor = nil
    }

    private func copy(_ card: Card) {
        onCopy?(card.shot)
        showFeedback("Copied to clipboard")
    }

    private func delete(_ card: Card) {
        onDelete?(card.shot)
        model.cards.removeAll { $0.id == card.id }
        if model.cards.isEmpty { dismiss(); return }
        slideIn(size: StackLayout.panelSize(cards: cardSizes))
    }

    /// Grow the chosen card from its spot in the corner into the centered annotation frame,
    /// then hand that frame to the annotation window.
    private func annotate(_ card: Card) {
        dismissTimer?.invalidate()
        removeOutsideClickMonitor()
        guard let index = model.cards.firstIndex(where: { $0.id == card.id }) else { return }
        let start = StackLayout.cardFrame(index: index, cards: cardSizes, panelFrame: panel.frame)
        let target = StackLayout.annotationFrame(for: card.image.size, on: screen)

        model.cards = [card]
        model.expandingCard = card
        panel.setFrame(start, display: true)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.38
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0.0, 0.2, 1.0)
            panel.animator().setFrame(target, display: true)
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.onAnnotate?(card.shot, target)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                self.visible = false
                self.panel.orderOut(nil)
                self.model.cards = []
                self.model.expandingCard = nil
            }
        })
    }
}
