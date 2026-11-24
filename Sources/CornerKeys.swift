import AppKit

/// Floating, non-activating panel. It can take key focus for the recent stack without activating
/// Vignette, so the app you are working in keeps its menu bar and gets focus back when we close.
/// Only `CornerKeys` lets it take the keys.
@MainActor
final class ThumbnailPanel: NSPanel {
    fileprivate(set) var acceptsKeys = false
    var onKey: ((NSEvent) -> Bool)?
    var onScroll: ((NSEvent) -> Void)?
    /// The stack's Undo and Redo, which the Edit menu names while the panel has the keys, and
    /// VoiceOver hears after each.
    weak var timeline: UndoTimeline? {
        didSet {
            timeline?.announce = { [weak self] words in
                guard let self else { return }
                NSAccessibility.post(element: self, notification: .announcementRequested,
                                     userInfo: [.announcement: words, .priority: NSAccessibilityPriorityLevel.high.rawValue])
            }
        }
    }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { acceptsKeys }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKey?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    @objc func undo(_ sender: Any?) { timeline?.undo() }
    @objc func redo(_ sender: Any?) { timeline?.redo() }

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let timeline, let title = timeline.menuTitle(for: item.action) else { return super.validateMenuItem(item) }
        item.title = title
        return timeline.canRun(item.action)
    }

    /// Scroll events reach the window under the cursor whether or not it is key.
    override func scrollWheel(with event: NSEvent) {
        onScroll?(event)
    }
}

/// Runs what `CornerPresentation` decides. The panel's keys, the backdrop, the watch for a click
/// outside and the hand-back of the focus are this type's alone: the controller can only send events,
/// and gets back the effects on the cards' side to run (`perform`).
@MainActor
final class CornerKeys {
    private(set) var presentation = CornerPresentation()
    /// Runs each effect's part on the cards' side, after this has run its window side.
    var perform: (CornerPresentation.Effect) -> Void = { _ in }
    /// Called after every event, with the presentation as it was and as it now is.
    var changed: (_ old: CornerPresentation, _ new: CornerPresentation) -> Void = { _, _ in }

    private let panel: ThumbnailPanel
    private let screen: () -> NSScreen
    private let backdrop = BackdropPanel()
    private let outsideClick = OutsideClick()
    private let hold = EventHold<CornerPresentation.Event>()
    /// `holdKeys` brought the panel up and the listing has not filled it yet, so letting the keys go
    /// takes it down again.
    private var heldPanelUp = false
    /// When `holdKeys` took the keys, for the `after=` of the stack taking them once it has cards.
    private var heldAt: CFTimeInterval?

    init(panel: ThumbnailPanel, screen: @escaping () -> NSScreen) {
        self.panel = panel
        self.screen = screen
    }

    var isStack: Bool { presentation.isStack }
    var becomesStack: Bool { presentation.becomesStack }
    var isKeyed: Bool { presentation.isKeyed }
    var leavesOnItsOwn: Bool { presentation.leavesOnItsOwn }
    var backdropState: [String: Any] { backdrop.stateJSON }

    /// The screen changed under a stack: the backdrop follows it.
    func refreshBackdrop(on screen: NSScreen) {
        if presentation.isStack { backdrop.refresh(on: screen) }
    }

    /// An event sent while another is being handled runs right after it, in order.
    func send(_ event: CornerPresentation.Event) {
        hold.send(event) { event in
            // While the window the person was in is still key, so closing goes back to it.
            if event == .cardsShown, !panel.isVisible { FocusReturn.shared.sessionStarting() }
            if event == .listed(found: true) { heldPanelUp = false }
            let old = presentation
            let effects = presentation.reduce(event)
            if !effects.isEmpty || presentation.mode != old.mode {
                Log.write("[corner] \(event) -> \(presentation.mode) effects=\(effects.map { "\($0)" }.joined(separator: " "))")
            }
            // The rule holds by construction: the backdrop and the watch for a click outside go
            // with the stack, whatever event made or ended it.
            if presentation.isStack != old.isStack {
                if presentation.isStack {
                    backdrop.show(on: screen(), below: panel)
                    outsideClick.start { [weak self] in self?.send(.dismiss(.clickOutside)) }
                } else {
                    outsideClick.stop()
                    backdrop.hide()
                }
            }
            for effect in effects {
                runWindowSide(effect)
                perform(effect)
            }
            changed(old, presentation)
        }
    }

    private func runWindowSide(_ effect: CornerPresentation.Effect) {
        switch effect {
        case .holdKeys:
            heldAt = CACurrentMediaTime()
            // The corner can be empty with its cards gone, as after a lone thumbnail's editor.
            heldPanelUp = !panel.isVisible
            if heldPanelUp {
                FocusReturn.shared.sessionStarting()
                panel.orderFrontRegardless()
            }
            panel.acceptsKeys = true
            panel.makeKey()
            Log.write("[stack] keys held key=\(panel.isKeyWindow)")
        case .takeKeys:
            panel.acceptsKeys = true
            panel.makeKey()
            Log.write("[stack] keys key=\(panel.isKeyWindow)\(heldAt.map { " after=\(Int((CACurrentMediaTime() - $0) * 1000))ms" } ?? "")")
            heldAt = nil
            // The panel can refuse key status right after resigning it (a dismissal being reversed),
            // so it asks twice.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self, self.presentation.isKeyed, self.panel.isVisible, !self.panel.isKeyWindow else { return }
                self.panel.makeKey()
                Log.write("[stack] keys retry key=\(self.panel.isKeyWindow)")
            }
        case .releaseKeys:
            panel.acceptsKeys = false
            if panel.isKeyWindow { panel.resignKey() }
            if heldPanelUp { panel.orderOut(nil) }
            heldPanelUp = false
            heldAt = nil
        case .restoreFocus(let reason):
            FocusReturn.shared.restore(reason: reason)
        case .closeEditor, .listRecent, .slideOut:
            break
        }
    }
}
