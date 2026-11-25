import AppKit
import SwiftUI

/// The annotator's toolbar: a native panel that floats just below the image window, so it is
/// never clipped by the image and looks like the rest of macOS. The tools are the editor's; the
/// active one is the editor's to report, and a tap sets it there.
@MainActor
final class AnnotatorToolbar {
    let panel: ToolbarPanel
    let model = Model()
    var onTool: ((EditorCore.Tool) -> Void)?
    var onDone: (() -> Void)?
    var onSend: ((AgentDestination) -> Void)?
    /// A session picked in the target's menu, before the bar applies it.
    var onPick: (() -> Void)?
    /// Esc in the message field: the keys go back to the editor.
    var onMessageEnd: (() -> Void)?
    /// A press on the bar, or the field losing the keys: typing in the message field next is a new
    /// undo step.
    var onMessageTypingEnded: (() -> Void)?
    /// Esc in a message field that took the keys on its own and is still empty: the editor closes.
    var onClose: (() -> Void)?
    /// Left or Right in that same field: the screenshot beside this one, as on the image.
    var onPage: ((EditorCore.Page, _ isRepeat: Bool) -> Void)?
    /// Tab past the last control, or Shift+Tab past the first: the editor takes the focus back. False
    /// when it has no marks to take it, and the bar goes round its own controls.
    var onLeave: ((_ backward: Bool) -> Bool)?
    /// The target's frame in the hosting view, where its menu drops down from.
    private(set) var targetFrame: CGRect?
    /// A press on the Pins button, with the button's rect in `barView`: the editor lists every pin from it.
    var onPins: ((CGRect, NSView) -> Void)?
    private var pinsFrame: CGRect?
    let targetMenuActions = TargetMenuActions()
    private var hosting: NSHostingView<ToolbarView>!
    /// The view the bar is drawn in, where the target's frame is measured and its menu drops from.
    var barView: NSView { hosting }
    /// How far past the target its presses reach, as for every control on the bar.
    static var targetSlop: EdgeInsets { ToolbarView.slop }
    /// The panel's size for the bar as SwiftUI lays it out now, with `padding` on every side.
    var fittingSize: NSSize { hosting.fittingSize }
    private var keyObservers: [NSObjectProtocol] = []
    /// The key `model.toolLetter` holds, replayed into the field when a character follows it.
    var heldLetter: NSEvent?
    /// Where `place` last put the bar, so a bar whose contents change width can centre again.
    var placedBelow: (frame: NSRect, gap: CGFloat)?
    /// Where a zoom or re-fit put the middle of the bar's top edge (`follow`), nil at its place.
    var carried: NSPoint?

    static let height: CGFloat = 44
    /// Room around the bar inside its panel for the shadow and the entrance motion.
    static let padding: CGFloat = 28
    /// The room above and below the bar that the message field grows into while it is typed in. The
    /// panel always has it, and it is clear, so it passes presses through: a panel that grew with the
    /// field would draw a frame at the new height before `position` moved it.
    static let messageRoom: CGFloat = 110

    /// The panel's frame without the message field's room: the bar, its padding, and its shadow.
    var barFrame: NSRect {
        panel.frame.insetBy(dx: 0, dy: Self.messageRoom)
    }
    var hideGeneration = 0

    init() {
        let panel = ToolbarPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        self.panel = panel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false   // the bar draws its own; a window shadow cannot follow the animated content
        // Above the flight layer (`.statusBar`): a flight into or out of the editor passes under the
        // bar as the editor does, so its shadow never falls across the controls.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.isMovable = false
        hosting = NSHostingView(rootView: ToolbarView(model: model, onTool: { [weak self] in self?.onTool?($0) },
                                                      onDone: { [weak self] in self?.onDone?() },
                                                      onSend: { [weak self] in self?.onSend?($0) },
                                                      onTargetMenu: { [weak self] in self?.showTargetMenu() },
                                                      onFocusMessage: { [weak self] in self?.focusMessage() },
                                                      onTargetFrame: { [weak self] in self?.targetFrame = $0 },
                                                      onPins: { [weak self] in self?.showPins() },
                                                      onPinsFrame: { [weak self] in self?.pinsFrame = $0 },
                                                      onWidth: { [weak self] in self?.refit() },
                                                      onMessageEnd: { [weak self] in self?.onMessageEnd?() },
                                                      onClose: { [weak self] in self?.onClose?() }))
        // `position` alone sizes the panel, about the bar's centre (`onWidth`). As the window's
        // content view, the hosting view would resize the window from its left edge.
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.autoresizingMask = [.width, .height]
        let content = NSView()
        content.addSubview(hosting)
        panel.contentView = content
        takeTargetMenuPicks()
        panel.onTab = { [weak self] backward in self?.move(backward: backward) }
        panel.onKey = { [weak self] event in self?.keyDown(event) ?? false }
        panel.onPressMenu = { [weak self] event in self?.pressTarget(event) ?? false }
        panel.onMenuKey = { [weak self] in
            guard let self, model.offer.offersTarget, targetFrame != nil else { return false }
            openTargetMenuFromKeys()
            return true
        }
        panel.onPress = { [weak self] onField in
            guard let self else { return }
            onMessageTypingEnded?()
            model.pressed()
            keepHeldTool()
            guard !onField, model.focus != .message else { return }
            model.focus = nil
        }
        panel.onCommandReturn = { [weak self] in
            guard let self, !model.sending, let destination = model.offer.destination else { return }
            onSend?(destination)
        }
        // A field keeps first responder in a panel that is not key, and AppKit makes it the panel's
        // first responder when the bar comes up. So the field counts as typed in only while the
        // panel is key, and losing the keys ends typing in it, as a click elsewhere does.
        keyObservers = [
            NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.model.keyed = true
                    self?.model.focus = .message
                }
            },
            NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.model.keyed = false
                    self?.onMessageTypingEnded?()
                    self?.keepHeldTool()
                    self?.model.tookKeysOnOpen = false
                    self?.panel.caretToEnd = false
                    if self?.model.focus == .message { self?.model.focus = nil }
                    _ = self?.panel.makeFirstResponder(nil)
                }
            },
        ]
    }

    /// Makes room for the bar, about its centre, when its width changed: Send and the target arrive
    /// with the session list, a pick in the menu renames the target, and Reply can give way to
    /// Send. It waits a turn, since SwiftUI reports the change from inside its layout.
    /// The bar itself springs to its new width inside the panel (`ToolbarView`); a swap's slide
    /// already under way carries on. Unlike `place`, it leaves a `hideSoon` or a `hide` alone, and a
    /// bar on its way out stays where it is.
    private func refit() {
        DispatchQueue.main.async { [weak self] in
            guard let self, model.shown || !panel.isVisible else { return }
            position(slide: sliding)
        }
    }

    /// The bar's own move, one spring per direction (the panel's centre and its top edge), so a move
    /// retargeted part way through keeps its velocity into the new place instead of restarting.
    lazy var slideX = Tween(initial: 0) { [weak self] _ in self?.applySlide() }
    lazy var slideY = Tween(initial: 0) { [weak self] _ in self?.applySlide() }
    /// Whether the two springs are the ones placing the panel. False while they are being seeded,
    /// so the half-seeded pair never reaches the panel.
    var sliding = false

    /// Orders the panel in hidden and lets the bar rise into place a turn later, so the
    /// entrance animates.
    func show() {
        hideGeneration += 1
        panel.orderFront(nil)
        panel.makeFirstResponder(nil)
        DispatchQueue.main.async { [weak self] in self?.model.shown = true }
    }

    /// Takes the bar down unless another image asks for it first. The exit waits one turn of the
    /// run loop: a swap's park answer and the next `prepare` land in the same turn, so a bar that
    /// is about to be given a new place never fades out in between. The reducer says nothing about
    /// this, and does not have to: the queue's handover sends its `annotate` from that same turn.
    func hideSoon() {
        hideGeneration += 1
        let gen = hideGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.hideGeneration == gen else { return }
            self.hide()
        }
    }

    /// Fades the bar out, then orders the panel out.
    func hide() {
        hideGeneration += 1
        let gen = hideGeneration
        model.shown = false
        sliding = false
        slideX.stop(); slideY.stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2 * Settings.shared.motionScale) { [weak self] in
            guard let self, self.hideGeneration == gen else { return }
            self.panel.orderOut(nil)
        }
    }
}

extension AnnotatorToolbar {
    /// The Pins button was pressed, or Space was on it.
    func showPins() {
        guard model.pinCount > 0, let frame = pinsFrame else { return }
        let rect = barView.isFlipped ? frame : CGRect(x: frame.minX, y: barView.bounds.height - frame.maxY, width: frame.width, height: frame.height)
        onPins?(rect, barView)
    }
}
