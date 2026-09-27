import AppKit
import SwiftUI

/// The annotator's toolbar: a native panel that floats just below the image window, so it is
/// never clipped by the image and looks like the rest of macOS. The tools are the editor's; the
/// active one is the editor's to report, and a tap sets it there.
@MainActor
final class AnnotatorToolbar {
    final class Model: ObservableObject {
        @Published var tool: EditorCore.Tool? = nil
        @Published var shown = false     // drives the entrance and exit
        /// The agent sessions Send can go to, the one used last first, as far as the listing has
        /// answered for the image that is open.
        @Published private(set) var destinations: [AgentDestination] = []
        /// Every client has answered. Until then a session missing from the list may only be late.
        @Published private(set) var listed = false
        /// The session the open image came from, when it names one: an agent's reply, or a push
        /// that said which session it was. The bar is Reply alone, so the target is never guessed at.
        @Published private(set) var replyTo: AgentDestination?
        /// Where Send goes: the default until someone picks another in the menu.
        @Published private(set) var target: AgentDestination?
        /// The target was picked in the menu, so no later answer changes it.
        private var picked = false
        /// The target is the image before's, kept while the bar stays up so Send does not leave it
        /// for the 60 to 90 ms the listing takes. The first answer that settles a target replaces it.
        private var carried = false
        /// From Send's press until the bar leaves. The button shows the send and takes no second click.
        /// A new press puts a failure's reason away.
        @Published var sending = false { didSet { if sending { failure = nil } } }
        /// Why the last send failed before its request was stored, and what to do about it. While it
        /// is set the button says "Not sent" and the reason stands beside it, until the person moves
        /// on: a click elsewhere, or Send again.
        @Published var failure: String?
        var notSent: Bool { failure != nil }
        /// Counts those failures; each one shakes the button.
        @Published private(set) var failures = 0

        func sendFailed(_ reason: String) {
            sending = false
            failure = reason
            failures += 1
        }

        /// A new image opens with a button that offers Send.
        func resetSend() {
            sending = false
            failure = nil
        }
        /// What the person typed to go with Send or Reply, as typed. Kept until the next image opens,
        /// so a send that fails keeps it for the next try.
        @Published var message = ""
        /// The bar's panel holds the keys, which it does only while the message field is typed in.
        @Published var keyed = false

        /// A control Tab reaches, in the bar's order.
        enum Control: Hashable {
            case tool(EditorCore.Tool), copy, target, message, action

            /// For `[state]`: `copy`, or `tool.arrow`.
            var name: String {
                if case .tool(let tool) = self { return "tool.\(tool.rawValue)" }
                return "\(self)"
            }
        }
        /// The control the keyboard's focus is on, drawn with a ring. The editor keeps the keys
        /// meanwhile, and gives Tab and Space to the bar; the message field takes the keys itself.
        @Published var focus: Control?
        /// Counts the asks to type in the message field: Tab onto it, or M or P in the editor.
        @Published private(set) var messageAsks = 0
        func askForMessage() { messageAsks += 1 }
        /// Counts presses on the bar. A press puts a tooltip away, as AppKit's does.
        @Published private(set) var presses = 0
        func pressed() { presses += 1 }
        /// Points from the bar's bottom edge down to the bottom of the visible screen, the Dock's top
        /// when it is there. The message field grows down into it, and up out of the bar past it.
        @Published var roomBelow: CGFloat = .greatestFiniteMagnitude

        /// The controls on the bar for this offer.
        var controls: [Control] {
            let offer = self.offer
            var controls = EditorCore.Tool.allCases.map(Control.tool)
            if offer.destination == nil || offer.isSend { controls.append(.copy) }
            if offer.isSend { controls.append(.target) }
            if offer.destination != nil { controls += [.message, .action] }
            return controls
        }

        /// The most characters the message holds, as for a text mark.
        static let messageLimit = MarkFields.maxTextLength

        /// The message as it joins the line Send puts in the session, which is one line: its words with
        /// one space between each, whatever line breaks, tabs or spaces were there. Nil when there are none.
        var sentMessage: String? {
            let line = message.asOneLine
            return line.isEmpty ? nil : line
        }

        var offer: ToolbarOffer {
            ToolbarOffer(replyTo: replyTo, destinations: destinations, listed: listed, target: target)
        }

        /// A new image: nothing listed yet, and nothing picked. `carryingTarget`, when the bar is
        /// on screen for the image before, keeps that image's list and target until this one's settle.
        func begin(replyTo: AgentDestination?, carryingTarget: Bool) {
            self.replyTo = replyTo
            message = ""
            focus = nil
            listed = false
            picked = false
            carried = carryingTarget && target != nil
            guard !carried else { return }
            destinations = []
            target = nil
        }

        /// Another client answered. The target settles as soon as a focus names a session (herdr's,
        /// or the agent app you came from), and otherwise once every client has answered, since the
        /// session used last is a comparison across all of them. Once settled it changes only when
        /// its session is gone from the whole list, so it never changes under the pointer.
        func answered(_ list: [AgentDestination], complete: Bool) {
            destinations = list
            listed = complete
            if let current = target, let fresh = list.first(where: { $0.id == current.id }) { target = fresh }
            guard !picked else { return }
            if carried {
                guard list.contains(where: { $0.focus != nil }) || complete else { return }
                carried = false
                target = AgentDestination.defaultTarget(in: list)
                return
            }
            let gone = complete && target.map { current in !list.contains { $0.id == current.id } } == true
            guard target == nil || gone else { return }
            if list.contains(where: { $0.focus != nil }) || complete { target = AgentDestination.defaultTarget(in: list) }
        }

        func pick(_ destination: AgentDestination) {
            target = destination
            picked = true
            carried = false
        }
    }

    let panel: ToolbarPanel
    let model = Model()
    var onTool: ((EditorCore.Tool) -> Void)?
    var onDone: (() -> Void)?
    var onSend: ((AgentDestination) -> Void)?
    /// Esc in the message field: the keys go back to the editor.
    var onMessageEnd: (() -> Void)?
    /// Tab past the last control, or Shift+Tab past the first: the editor takes the focus back. False
    /// when it has no marks to take it, and the bar goes round its own controls.
    var onLeave: ((_ backward: Bool) -> Bool)?
    /// The target's frame in the hosting view, where its menu drops down from.
    private var targetFrame: CGRect?
    private let targetMenuActions = TargetMenuActions()
    private var hosting: NSHostingView<ToolbarView>!
    private var keyObservers: [NSObjectProtocol] = []
    /// Where `place` last put the bar, so a bar whose contents change width can centre again.
    private var placedBelow: (frame: NSRect, gap: CGFloat)?

    static let height: CGFloat = 44
    /// Room around the bar inside its panel for the shadow and the entrance motion.
    static let padding: CGFloat = 28
    /// The room above and below the bar that the message field grows into while it is typed in. The
    /// panel always has it, and it is clear, so it passes presses through: a panel that grew when the
    /// field took focus drew a frame at the new height before `position` moved it, and the bar jumped.
    static let messageRoom: CGFloat = 110

    /// The panel's frame without the message field's room: the bar, its padding, and its shadow.
    var barFrame: NSRect {
        panel.frame.insetBy(dx: 0, dy: Self.messageRoom)
    }
    private var hideGeneration = 0

    init() {
        let panel = ToolbarPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        self.panel = panel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false   // the bar draws its own; a window shadow cannot follow the animated content
        panel.level = AnnotationWindow.level
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.isMovable = false
        hosting = NSHostingView(rootView: ToolbarView(model: model, onTool: { [weak self] in self?.onTool?($0) },
                                                      onDone: { [weak self] in self?.onDone?() },
                                                      onSend: { [weak self] in self?.onSend?($0) },
                                                      onTargetMenu: { [weak self] in self?.showTargetMenu() },
                                                      onFocusMessage: { [weak self] in self?.focusMessage() },
                                                      onTargetFrame: { [weak self] in self?.targetFrame = $0 },
                                                      onMessageEnd: { [weak self] in self?.onMessageEnd?() }))
        panel.contentView = hosting
        targetMenuActions.onPick = { [weak self] destination in
            self?.model.pick(destination)
            self?.refit()
        }
        panel.onTab = { [weak self] backward in self?.move(backward: backward) }
        panel.onPress = { [weak self] onField in
            guard let self else { return }
            model.pressed()
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
                    if self?.model.focus == .message { self?.model.focus = nil }
                    _ = self?.panel.makeFirstResponder(nil)
                }
            },
        ]
    }

    // MARK: Keyboard focus

    /// Tab came from the editor past its last mark, or Shift+Tab past its first.
    func enter(backward: Bool) {
        focus(on: backward ? model.controls.last : model.controls.first)
    }

    /// Tab or Shift+Tab on the bar: the next control, or back to the editor past either end.
    func move(backward: Bool) {
        let controls = model.controls
        guard let current = model.focus, let index = controls.firstIndex(of: current) else { return enter(backward: backward) }
        let next = index + (backward ? -1 : 1)
        if controls.indices.contains(next) { return focus(on: controls[next]) }
        focus(on: nil)
        if onLeave?(backward) != true { enter(backward: backward) }
    }

    /// Space on the focused control presses it, as a click would.
    func activate() {
        switch model.focus {
        case .tool(let tool)?: onTool?(tool)
        case .copy?: onDone?()
        case .target?:
            // Opened from inside the editor's keyDown, the menu took no keys and read a press on its
            // items as one outside the editor. A turn later it is opened as a click opens it.
            DispatchQueue.main.async { [weak self] in self?.showTargetMenu() }
        case .action?:
            guard !model.sending, let destination = model.offer.destination else { return }
            onSend?(destination)
        case .message?, nil: break
        }
    }

    /// M or P in the editor: the keys go to the message field, when the bar has one.
    func focusMessage() {
        guard model.controls.contains(.message) else { return }
        focus(on: .message)
    }

    /// A press on the image takes the focus back from a control. The message field loses it when the
    /// panel gives up the keys.
    func clearFocus() {
        if model.focus != .message { model.focus = nil }
    }

    private func focus(on control: Model.Control?) {
        let typing = model.focus == .message && panel.isKeyWindow
        model.focus = control
        if control == .message {
            panel.takeKeys()
            model.askForMessage()
        } else if typing {
            onMessageEnd?()
        }
    }

    /// The target's menu, under it: the active sessions used last, the target among them with a check
    /// (`AgentDestination.menu`). AppKit's own menu, so Space on the focused target opens it as a
    /// click does.
    private func showTargetMenu() {
        guard case .send(let target) = model.offer, let frame = targetFrame else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(.sectionHeader(title: "Send to"))
        for destination in AgentDestination.menu(model.destinations, target: target) {
            let item = NSMenuItem(title: destination.project, action: #selector(TargetMenuActions.pick(_:)), keyEquivalent: "")
            item.target = targetMenuActions
            item.representedObject = destination
            item.image = AgentLogo.menuImage(for: destination.client)
            item.state = destination.id == target.id ? .on : .off
            if #available(macOS 14.4, *) { item.subtitle = destination.name } else { item.toolTip = destination.name }
            menu.addItem(item)
        }
        let below = hosting.isFlipped ? frame.maxY + 4 : hosting.bounds.height - frame.maxY - 4
        menu.popUp(positioning: nil, at: NSPoint(x: frame.minX, y: below), in: hosting)
    }

    /// Centers the toolbar under `frame`, `gap` points below it. A bar that is already up — one
    /// image following another with no gap between them — slides to the new place instead of being
    /// taken down and raised again, so the controls stay where the hand left them and only move
    /// with the image's height. It also cancels a `hideSoon` waiting its turn: this bar is wanted.
    func place(below frame: NSRect, gap: CGFloat) {
        placedBelow = (frame, gap)
        hideGeneration += 1
        position(slide: true)
    }

    /// Makes room for the bar after its contents changed: Send and the target arrive with the
    /// session list, a pick in the menu renames the target, and Reply can give way to Send. It
    /// waits a turn, because SwiftUI lays out the new contents after the model changes, and until
    /// then the bar measures its old size. The bar
    /// itself springs to its new width inside the panel (`ToolbarView`); a swap's slide already
    /// under way carries on. Unlike `place`, it leaves a `hideSoon` or a `hide` alone, and a bar on
    /// its way out stays where it is.
    func refit() {
        DispatchQueue.main.async { [weak self] in
            guard let self, model.shown || !panel.isVisible else { return }
            position(slide: sliding)
        }
    }

    private func position(slide: Bool) {
        guard let (frame, gap) = placedBelow else { return }
        let fit = hosting.fittingSize   // includes `padding` on every side
        // While the bar is up the panel never narrows, so a bar springing narrower keeps the room it
        // is animating in. The bar is centred in the panel and the rest is clear, which passes
        // presses through. A new session starts at the bar's own width.
        let up = model.shown && panel.isVisible
        let size = NSSize(width: up ? max(fit.width, panel.frame.width) : fit.width, height: fit.height)
        let barTop = frame.minY - gap
        let center = frame.midX, top = barTop + Self.padding + Self.messageRoom
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: frame.midX, y: barTop)) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let room = barTop - Self.height - visible.minY
            if model.roomBelow != room { model.roomBelow = room }
        }
        guard slide, up else {
            sliding = false
            slideX.stop(); slideY.stop()
            panel.setFrame(Self.rect(center: center, top: top, size: size), display: true)
            return
        }
        if !sliding {
            // The springs start from where the bar really is, not from the last value they carried.
            slideX.set(panel.frame.midX)
            slideY.set(panel.frame.maxY)
            sliding = true
        }
        // The window server may give the panel a frame a fraction off the size asked for, so the
        // size is compared with a point of tolerance. A new size keeps the slide's centre and top.
        if abs(panel.frame.width - size.width) >= 1 || abs(panel.frame.height - size.height) >= 1 {
            panel.setFrame(Self.rect(center: slideX.value, top: slideY.value, size: size), display: true)
        }
        slideX.animate(to: center, duration: slideSeconds, curve: "spring")
        slideY.animate(to: top, duration: slideSeconds, curve: "spring")
    }

    /// The panel's frame from its centre and top edge, which is what the springs move, so a change of
    /// size never moves the bar.
    private static func rect(center: CGFloat, top: CGFloat, size: NSSize) -> NSRect {
        NSRect(x: (center - size.width / 2).rounded(), y: top - size.height, width: size.width, height: size.height)
    }

    /// The bar's own move, one spring per direction (the panel's centre and its top edge), so a move
    /// retargeted part way through keeps its velocity into the new place instead of restarting.
    private lazy var slideX = Tween(initial: 0) { [weak self] _ in self?.applySlide() }
    private lazy var slideY = Tween(initial: 0) { [weak self] _ in self?.applySlide() }
    /// Whether the two springs are the ones placing the panel. False while they are being seeded,
    /// so the half-seeded pair never reaches the panel.
    private var sliding = false

    private func applySlide() {
        guard sliding else { return }
        let origin = Self.rect(center: slideX.value, top: slideY.value, size: panel.frame.size).origin
        guard origin != panel.frame.origin else { return }
        panel.setFrameOrigin(origin)
    }

    /// How long that move takes: the moment the incoming card's flight first covers the annotator's
    /// frame, which is when that window comes up (`TransitionLayer.fly`). The motion scale is in
    /// `motionUI`, so `ui.motion: 0` puts the bar at the next place at once.
    private var slideSeconds: Double {
        Anim.passesTarget(Settings.shared.motionUI.expandDuration, bounce: Anim.flightBounce)
    }

    /// Orders the panel in hidden and lets the bar rise into place a turn later, so the
    /// entrance animates from the hidden state instead of appearing already in place.
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

/// Key only for the message field: a press on it takes the keys, and a press anywhere else in the
/// bar leaves them, and so the tool keys and shortcuts, with the editor window. SwiftUI's buttons
/// ask for the keys as a text field does, so `becomesKeyOnlyIfNeeded` cannot tell them apart.
@MainActor
final class ToolbarPanel: NSPanel {
    private var pressOnField = false
    private var wantsKeys = false
    /// Cmd+Return while the message field has the keys: Send, as in the editor.
    var onCommandReturn: (() -> Void)?
    /// Tab or Shift+Tab (true) while the message field has the keys.
    var onTab: ((_ backward: Bool) -> Void)?
    /// A press on the bar, and whether it is on the message field.
    var onPress: ((_ onField: Bool) -> Void)?
    override var canBecomeKey: Bool { pressOnField || wantsKeys || isKeyWindow }

    /// Takes the keys for the message field without a press on it: Tab onto it, or M or P.
    func takeKeys() {
        wantsKeys = true
        makeKey()
        wantsKeys = false
    }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, [36, 76].contains(event.keyCode), event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            onCommandReturn?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, let content = contentView {
            // NSWindow makes itself key inside `super.sendEvent`, so the answer is ready before it asks.
            var view = content.hitTest(content.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow)
            while let current = view, !(current is NSTextField || current is NSText) { view = current.superview }
            pressOnField = view != nil
            onPress?(pressOnField)
        }
        // Tab leaves the field for the next control rather than the key view loop, unless an input
        // method is composing.
        if event.type == .keyDown, event.keyCode == 48, event.modifierFlags.isDisjoint(with: [.command, .control, .option]),
           (firstResponder as? NSTextView)?.hasMarkedText() != true {
            onTab?(event.modifierFlags.contains(.shift))
            return
        }
        super.sendEvent(event)
    }
}

/// What the bar offers for the open image, and so what Return and Cmd+Return do. Each case has one
/// filled button: the action that takes the drawing furthest.
enum ToolbarOffer: Equatable {
    /// Nothing to send to: Copy alone.
    case copy
    /// A session to send to: Copy on Return, then the target, and Send on Cmd+Return.
    case send(AgentDestination)
    /// The image names the session it came from: Reply alone, on Return and Cmd+Return.
    case reply(AgentDestination)

    /// A reply goes back where the image came from, unless the whole list has answered without that
    /// Claude Code session: herdr lists every pane, so it has closed. Codex's listing holds only the
    /// threads used last, so a Codex thread missing from it may still be there.
    init(replyTo: AgentDestination?, destinations: [AgentDestination], listed: Bool, target: AgentDestination?) {
        if let replyTo {
            let closed = listed && replyTo.client == .claude && !destinations.contains { $0.id == replyTo.id }
            if !closed {
                self = .reply(destinations.first { $0.id == replyTo.id } ?? replyTo)
                return
            }
        }
        self = target.map(ToolbarOffer.send) ?? .copy
    }

    var isSend: Bool {
        if case .send = self { return true }
        return false
    }

    /// Where the drawing goes when the offer's filled button is pressed, or nil for Copy.
    var destination: AgentDestination? {
        switch self {
        case .copy: return nil
        case .send(let destination), .reply(let destination): return destination
        }
    }

    /// Return never sends to a session Vignette picked, only to the one the image came from.
    var finishes: EditorCore.Finishes {
        switch self {
        case .copy: return .init(returnKey: .done, commandReturn: .done)
        case .send: return .init(returnKey: .done, commandReturn: .send)
        case .reply: return .init(returnKey: .send, commandReturn: .send)
        }
    }
}

/// A blur of what is behind the window, as a popover has. SwiftUI's materials blend only with the
/// window's own content, so over the bar's panel they show the bar's edge through them.
private struct BehindWindowBlur: NSViewRepresentable {
    let cornerRadius: CGFloat
    var material: NSVisualEffectView.Material = .popover

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        // The bar's panel is seldom key, and an inactive effect view draws flat.
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private struct ToolbarView: View {
    @ObservedObject var model: AnnotatorToolbar.Model
    @ObservedObject private var settings = Settings.shared
    let onTool: (EditorCore.Tool) -> Void
    let onDone: () -> Void
    let onSend: (AgentDestination) -> Void
    let onTargetMenu: () -> Void
    let onFocusMessage: () -> Void
    let onTargetFrame: (CGRect) -> Void
    let onMessageEnd: () -> Void
    @FocusState private var focused: Bool
    /// Counts Returns in the message field that did not send, each of which bounces Send's ⌘↩.
    @State private var sendNudges = 0
    /// The control the pointer is on, and the one whose tooltip is up (`tip`).
    @State private var tipOver: AnnotatorToolbar.Model.Control?
    @State private var tipShown: AnnotatorToolbar.Model.Control?
    @State private var tipWait: DispatchWorkItem?
    @State private var tipLeft = Date.distantPast
    /// The message field's height as its text needs it. The box springs to it (`GrowingField`).
    @State private var fieldHeight: CGFloat = 30
    /// The message field is being typed in.
    private var typing: Bool { focused && model.keyed }
    @Environment(\.colorScheme) private var colorScheme

    /// How far past a control its presses reach: to the bar's top and bottom edges, which are 7 pt
    /// from a 30 pt control, and into the gaps beside it. Not past the bar: the panel is clear there,
    /// and the window server passes a press on a clear pixel to the window behind.
    private static let slop = EdgeInsets(top: 7, leading: 2, bottom: 7, trailing: 2)
    /// The tools sit 2 pt apart, so each takes half the gap.
    private static let toolSlop = EdgeInsets(top: 7, leading: 1, bottom: 7, trailing: 1)

    /// The message field's width in the bar, and the most lines it grows to while it is typed in.
    private static let messageWidth: CGFloat = 220
    private static let messageLines = 6

    var body: some View {
        HStack(spacing: 2) {
            ForEach(EditorCore.Tool.allCases, id: \.self) { tool in
                Button { onTool(tool) } label: {
                    Image(systemName: tool.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 32, height: 30)
                        // Grey, not the accent: blue belongs to the one action at the end of the bar.
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(model.tool == tool ? Color.primary.opacity(0.16) : .clear))
                        // In the label, since a button acts only on presses on its label.
                        .padding(Self.toolSlop)
                        .contentShape(Rectangle())
                }
                .buttonStyle(TactileButtonStyle(shape: .rounded, hitSlop: Self.toolSlop))
                .padding(Self.toolSlop.negated)
                .modifier(FocusRing(on: model.focus == .tool(tool)))
                .modifier(TipSpot(control: .tool(tool), text: "\(tool.label) (\(String(tool.key).uppercased()))", hover: tip))
            }
            Divider().frame(height: 20).padding(.horizontal, 6)
            // One slot per control rather than one branch per offer, so a control two offers share
            // (Copy, the message field, the filled button) moves and restyles when the offer changes,
            // instead of fading out in one place while its twin fades in at another.
            let offer = model.offer, controls = model.controls
            if controls.contains(.copy) {
                copyButton(filled: offer == .copy)
                    .modifier(FocusRing(on: model.focus == .copy))
                    .modifier(Resting(while: model.sending))
                    .padding(.trailing, offer.isSend ? 6 : 0)
                    .transition(Self.slot)
            }
            if case .send(let target) = offer {
                targetMenu(target)
                    .modifier(FocusRing(on: model.focus == .target))
                    .modifier(Resting(while: model.sending))
                    .padding(.trailing, 4)
                    .transition(Self.slot)
            }
            if let destination = offer.destination {
                // Beside Send, Vignette picked the session, so Return in the field sends only when
                // Settings says so (`sendWithReturn`); otherwise it points at ⌘↩, which sends either way.
                messageField(returnSends: { !offer.isSend || settings.data.sendWithReturn }) { onSend(destination) }
                    .modifier(Resting(while: model.sending))
                    .padding(.trailing, 4)
                actionButton(offer.isSend ? "Send" : "Reply", key: offer.isSend ? "⌘↩" : "↩",
                             logo: offer.isSend ? nil : destination.client) { onSend(destination) }
                    .modifier(FocusRing(on: model.focus == .action))
                    .keyframeAnimator(initialValue: CGFloat(1), trigger: sendNudges) { content, scale in content.scaleEffect(scale) } keyframes: { _ in
                        let motion = Settings.shared.motionScale
                        CubicKeyframe(motion > 0 ? 1.08 : 1, duration: 0.09)
                        SpringKeyframe(1, duration: 0.35 * max(motion, 0.01), spring: .bouncy)
                    }
            }
        }
        .padding(.horizontal, 7)
        .frame(height: AnnotatorToolbar.height)
        // Controls coming or going while the bar changes width are cut at its sides. Above and below
        // stay open, for the message field growing down past the bar.
        .mask { Rectangle().padding(.vertical, -(AnnotatorToolbar.messageRoom + AnnotatorToolbar.padding)) }
        .background { glass }
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        // A change of offer springs the bar to its new width about its centre, which stays under
        // the image; the panel already has the room (`AnnotatorToolbar.position`).
        .animation(Anim.spring(0.35 * Settings.shared.motionScale), value: model.offer)
        .fixedSize()
        .padding(AnnotatorToolbar.padding)
        // In: rises a little and settles on a spring. Out: a short fade while it sinks back.
        .opacity(model.shown ? 1 : 0)
        .scaleEffect(model.shown ? 1 : 0.94, anchor: .top)
        .offset(y: model.shown ? 0 : 8)
        .animation(entrance, value: model.shown)
        // Room above and below for the field to grow into, outside the entrance's scale.
        .padding(.vertical, AnnotatorToolbar.messageRoom)
        .onChange(of: model.messageAsks) { focused = true }
        // Centred in a panel that may be wider than the bar.
        .frame(maxWidth: .infinity)
        .overlayPreferenceValue(TipSpots.self) { spots in
            GeometryReader { geometry in
                if let shown = tipShown, let spot = spots[shown], let text = spot.text {
                    // Under the control, or over it when the Dock leaves no room below the bar.
                    TipPlacement(target: geometry[spot.anchor], below: model.roomBelow > 40) {
                        TipLabel(text: text)
                    }
                    .id(shown)
                    .transition(.opacity.animation(Anim.spring(0.15 * Settings.shared.motionScale)))
                }
            }
            .allowsHitTesting(false)
        }
        .onChange(of: model.presses) { hideTip() }
        .onChange(of: model.shown) { hideTip() }
    }

    /// The pointer came onto a control or left it. Like AppKit's, a tooltip comes up after the pointer
    /// has rested a second, and while one is up, or was a moment ago, the next comes up at once.
    private func tip(_ control: AnnotatorToolbar.Model.Control, _ inside: Bool) {
        if inside {
            tipOver = control
            tipWait?.cancel()
            if tipShown != nil || Date().timeIntervalSince(tipLeft) < 0.5 {
                tipShown = control
                return
            }
            let wait = DispatchWorkItem { if tipOver == control { tipShown = control } }
            tipWait = wait
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: wait)
        } else if tipOver == control {
            if tipShown != nil { tipLeft = Date() }
            hideTip()
        }
    }

    private func hideTip() {
        tipWait?.cancel()
        tipOver = nil
        tipShown = nil
    }

    /// A control an offer adds or takes away. It leaves quickly, before the controls sliding into its
    /// place reach it, and a new one fades in once the bar has begun to make room for it.
    private static var slot: AnyTransition {
        let motion = Settings.shared.motionScale
        return .asymmetric(insertion: .opacity.animation(.easeIn(duration: 0.15 * motion).delay(0.1 * motion)),
                           removal: .opacity.animation(.easeOut(duration: 0.08 * motion)))
    }

    /// The bar's background: a blur of what is behind it under a neutral gray, since a material alone
    /// takes on the picture's colour, with a faint light along the top edge and a hairline outside it
    /// so the edge holds against a light picture as well as a dark one.
    private var glass: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let dark = colorScheme == .dark
        return shape.fill(.ultraThinMaterial)
            .overlay(shape.fill(Color(white: dark ? 0.14 : 0.95).opacity(0.72)))
            .overlay(shape.strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(dark ? 0.2 : 0.6), location: 0),
                                                              .init(color: .white.opacity(dark ? 0.05 : 0.2), location: 0.5),
                                                              .init(color: .white.opacity(dark ? 0.08 : 0.3), location: 1)],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .overlay(shape.inset(by: -0.5).strokeBorder(.black.opacity(dark ? 0.35 : 0.12), lineWidth: 0.5))
    }

    /// Copy: the drawing onto the clipboard and the editor closed. The filled button when there is
    /// nowhere to send.
    private func copyButton(filled: Bool) -> some View {
        Button(action: onDone) {
            HStack(spacing: 6) {
                Text("Copy").font(.system(size: 13, weight: .semibold))
                keyText("↩", filled: filled)
            }
            .foregroundStyle(filled ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(filled ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.09)),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .padding(Self.slop)
            .contentShape(Rectangle())
        }
        .buttonStyle(TactileButtonStyle(shape: .rounded, hoverScale: 1, hitSlop: Self.slop))
        .padding(Self.slop.negated)
        .modifier(TipSpot(control: .copy, text: "Copy your drawing and close the editor", hover: tip))
    }

    /// What goes with the drawing, typed in the bar. One line wide in the bar; while it is typed in
    /// it grows down past the bar's bottom, up to `messageLines` lines, and the bar keeps its size.
    /// Cmd+Return sends (`ToolbarPanel`). Return sends only when `returnSends`: beside Reply, as in
    /// the editor, and beside Send when `sendWithReturn` is on. It is asked when Return is pressed,
    /// because the field keeps the submit action it was made with when the setting changes under it.
    /// Esc hands the keys back to the editor.
    private func messageField(returnSends: @escaping () -> Bool, send: @escaping () -> Void) -> some View {
        let grown = typing && !model.message.isEmpty
        // The bar's middle is 7 pt above its bottom edge; a margin keeps the field off the Dock.
        let below = model.roomBelow + (AnnotatorToolbar.height - 30) / 2 - 8
        let box = RoundedRectangle(cornerRadius: 7, style: .continuous)
        return GrowingField(height: fieldHeight, below: below) {
            // Grown, it hangs past the bar over whatever is behind, so it takes a blur of that, as a
            // popover does.
            BehindWindowBlur(cornerRadius: 7).opacity(grown ? 1 : 0)
            // The text at its own height, always. A text field shorter than its text scrolls to its
            // caret, so while the box grew around it the text jumped up a line and back. The box
            // clips it instead, and a new line comes into view as the box grows.
            .overlay(alignment: .top) {
                TextField("Add a message", text: $model.message, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(typing ? 1...Self.messageLines : 1...1)
                    .focused($focused)
                    .onSubmit {
                        if !returnSends() { sendNudges += 1 } else if !model.sending { send() }
                    }
                    .onExitCommand { onMessageEnd() }
                    .onChange(of: model.message) { _, words in
                        if words.count > AnnotatorToolbar.Model.messageLimit { model.message = String(words.prefix(AnnotatorToolbar.Model.messageLimit)) }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .frame(width: Self.messageWidth, alignment: .topLeading)
                    .frame(minHeight: 30)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        withAnimation(Anim.spring(0.25 * Settings.shared.motionScale)) { fieldHeight = height }
                    }
            }
            .clipShape(box)
            .background { box.fill(Color.primary.opacity(0.09)).shadow(color: .black.opacity(grown ? 0.3 : 0), radius: 10, y: 4) }
            .overlay(box.stroke(Color.accentColor.opacity(typing ? 0.8 : 0), lineWidth: 1))
            // The text field takes presses only on its text; its padding and the room around it in
            // the bar start typing too, on the press, as the text does.
            .contentShape(box)
            .simultaneousGesture(pressToType)
            .modifier(IBeam())
        }
        .frame(width: Self.messageWidth, height: 30)
        .padding(Self.slop)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .gesture(pressToType)
                .modifier(IBeam())
        }
        .padding(Self.slop.negated)
        .animation(Anim.spring(0.25 * Settings.shared.motionScale), value: typing)
        .modifier(TipSpot(control: .message, text: typing ? nil : "Add a message (M)", hover: tip))
    }

    private var pressToType: some Gesture {
        DragGesture(minimumDistance: 0).onChanged { _ in if !typing { onFocusMessage() } }
    }

    /// Send or Reply: the filled button, with the agent's logo when it goes back to one. From the
    /// press it shows the send, and after a failure before the store it says "Not sent". Its label
    /// stays in the layout under both, so the button keeps its width and nothing beside it moves.
    /// It keeps its fill, since it is busy rather than disabled, and takes no clicks while sending.
    /// After a failure a click sends again.
    private func actionButton(_ title: String, key: String, logo client: AgentClient?, action: @escaping () -> Void) -> some View {
        let motion = Settings.shared.motionScale
        let busy = model.sending || model.notSent
        return Button(action: action) {
            // Send and Reply are one button. Its words leave before the new ones come, in one place,
            // since two words drawn through each other read as neither.
            ZStack {
                HStack(spacing: 6) {
                    if let client { AgentLogo(client: client, template: true).frame(width: 13, height: 13) }
                    Text(title).font(.system(size: 13, weight: .semibold))
                    keyText(key, filled: true)
                }
                .id(title)
                .transition(Self.slot)
            }
            .opacity(busy ? 0 : 1)
            .blur(radius: busy ? 4 : 0)
            .offset(y: model.sending ? -6 : 0)
            .overlay {
                if model.sending {
                    SendingGlyph(leaving: !model.shown).transition(.blurReplace)
                } else if model.notSent {
                    Text("Not sent").font(.system(size: 13, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .transition(.blurReplace)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(model.notSent ? Color(nsColor: .systemRed) : Color.accentColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .padding(Self.slop)
            .contentShape(Rectangle())
        }
        .buttonStyle(TactileButtonStyle(shape: .rounded, hoverScale: 1, hitSlop: Self.slop))
        .padding(Self.slop.negated)
        .allowsHitTesting(!model.sending)
        // The reason, attached to the button that failed, as a popover: it stays until a click
        // elsewhere, which also gives the button back.
        .popover(isPresented: Binding(get: { model.failure != nil }, set: { if !$0 { model.failure = nil } }), arrowEdge: .bottom) {
            FailureReason(text: model.failure ?? "")
        }
        .keyframeAnimator(initialValue: CGFloat(0), trigger: model.failures) { content, x in content.offset(x: x) } keyframes: { _ in
            let reach: CGFloat = motion > 0 ? 5 : 0
            CubicKeyframe(-reach, duration: 0.05)
            CubicKeyframe(reach, duration: 0.08)
            CubicKeyframe(-reach * 0.6, duration: 0.08)
            SpringKeyframe(0, duration: 0.3 * max(motion, 0.01), spring: .bouncy)
        }
        .animation(Anim.spring(0.3 * motion, bounce: 0.2), value: model.sending)
        .animation(Anim.spring(0.3 * motion), value: model.notSent)
    }

    private func keyText(_ key: String, filled: Bool) -> some View {
        Text(key)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(filled ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.secondary))
    }

    /// Where Send goes: the agent's logo and the session's project, apart from Send itself. It opens
    /// the menu for changing it (`AnnotatorToolbar.showTargetMenu`).
    private func targetMenu(_ target: AgentDestination) -> some View {
        Button(action: onTargetMenu) {
            HStack(spacing: 6) {
                AgentLogo(client: target.client, template: false).frame(width: 14, height: 14)
                Text(target.project).font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.leading, 8)
            .padding(.trailing, 9)
            .frame(height: 30)
            .background(Color.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .padding(Self.slop)
            .contentShape(Rectangle())
        }
        .buttonStyle(TactileButtonStyle(shape: .rounded, hoverScale: 1, hitSlop: Self.slop))
        .padding(Self.slop.negated)
        .fixedSize()
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onTargetFrame($0) }
        .modifier(TipSpot(control: .target, text: "“\(target.name)” in \(target.client.label)", hover: tip))
    }

    /// What names a session at a glance: its project's folder, which you chose, or its agent's name
    /// when it reported none.
    private var entrance: Animation {
        let scale = Settings.shared.motionScale
        guard scale > 0 else { return .linear(duration: 0) }
        return model.shown ? .spring(response: 0.45 * scale, dampingFraction: 0.72) : Anim.spring(0.18 * scale)
    }
}

/// An agent's logo from the bundle, or the fallback symbol for a vendor without one. `template`
/// draws it in the foreground colour, for the white of a filled button. A one-colour logo is always
/// drawn in the foreground colour.
/// What went wrong with a send and what to do about it, in the popover on the button.
private struct FailureReason: View {
    let text: String
    var body: some View {
        Label {
            Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        } icon: {
            // Two colours, since a red fill with the mark cut out of it disappears on a dark popover.
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.palette).foregroundStyle(.white, Color(nsColor: .systemRed))
        }
        .frame(width: 260, alignment: .leading)
        .padding(12)
    }
}

/// A control beside a send in progress: it fades back, on a spring rather than in one frame, and
/// takes no clicks. Not `.disabled`, whose look AppKit's controls switch in one frame.
private struct Resting: ViewModifier {
    let resting: Bool
    init(while resting: Bool) { self.resting = resting }
    func body(content: Content) -> some View {
        content
            .opacity(resting ? 0.4 : 1)
            .allowsHitTesting(!resting)
            .animation(Anim.spring(0.3 * Settings.shared.motionScale), value: resting)
    }
}

/// The send inside Send's button: a paper plane that comes in from the lower left and settles, and
/// carries on up and to the right as the bar leaves. The wait is usually a rendering of about
/// 150 ms, too short for a spinner to read as anything but a flicker; past half a second a spinner
/// takes the plane's place.
private struct SendingGlyph: View {
    let leaving: Bool
    @State private var arrived = false
    @State private var slow = false

    var body: some View {
        let motion = Settings.shared.motionScale
        ZStack {
            if slow && !leaving {
                ProgressView().controlSize(.small).environment(\.colorScheme, .dark)
                    .transition(.blurReplace)
            } else {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .offset(x: leaving ? 16 : (arrived ? 0 : -10), y: leaving ? -12 : (arrived ? 0 : 6))
                    .opacity(leaving ? 0 : 1)
                    .transition(.blurReplace)
            }
        }
        .onAppear {
            withAnimation(Anim.spring(0.35 * motion, bounce: 0.3)) { arrived = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(Anim.spring(0.3 * motion)) { slow = true }
            }
        }
    }
}

/// Where each control's tooltip goes, and what it says.
private struct TipSpots: PreferenceKey {
    struct Spot { let anchor: Anchor<CGRect>; let text: String? }
    static let defaultValue: [AnnotatorToolbar.Model.Control: Spot] = [:]
    static func reduce(value: inout [AnnotatorToolbar.Model.Control: Spot], nextValue: () -> [AnnotatorToolbar.Model.Control: Spot]) {
        value.merge(nextValue()) { $1 }
    }
}

/// A control with a tooltip. The bar draws its own: AppKit shows a window's tooltips only while it is
/// key or was the last one clicked, and the editor's window holds the keys, so the bar's never came.
private struct TipSpot: ViewModifier {
    let control: AnnotatorToolbar.Model.Control
    let text: String?
    let hover: (AnnotatorToolbar.Model.Control, Bool) -> Void
    func body(content: Content) -> some View {
        content
            .onHover { hover(control, $0) }
            .anchorPreference(key: TipSpots.self, value: .bounds) { [control: TipSpots.Spot(anchor: $0, text: text)] }
            .accessibilityHint(text ?? "")
    }
}

/// A tooltip as macOS draws one.
private struct TipLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(BehindWindowBlur(cornerRadius: 5, material: .toolTip))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
            .fixedSize()
    }
}

/// Puts a tooltip centred under or over `target`, kept inside the panel.
private struct TipPlacement: Layout {
    let target: CGRect
    let below: Bool
    /// From the control's edge past the bar's, which is 7 pt further.
    static let gap: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let x = min(max(target.midX - size.width / 2, 4), bounds.width - 4 - size.width)
            let y = below ? target.maxY + Self.gap : target.minY - Self.gap - size.height
            subview.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(size))
        }
    }
}

/// The ring around the control the keyboard's focus is on, in the system's focus colour. It comes in
/// from a little larger, as AppKit's does.
private struct FocusRing: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        content
            .overlay {
                if on {
                    RoundedRectangle(cornerRadius: 9.5, style: .continuous)
                        .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 3)
                        .padding(-3)
                        .allowsHitTesting(false)
                        .transition(.scale(scale: 1.25).combined(with: .opacity))
                }
            }
            .animation(Anim.spring(0.2 * Settings.shared.motionScale), value: on)
    }
}

/// The I-beam over the message field. A field shows it itself only in the key window, and the bar's
/// panel is key only while the field is typed in.
private struct IBeam: ViewModifier {
    func body(content: Content) -> some View {
        content.onContinuousHover { phase in
            switch phase {
            case .active: NSCursor.iBeam.set()
            case .ended: NSCursor.arrow.set()
            }
        }
    }
}

/// Places the message field in its slot on the bar: from the slot's top down, and once it would
/// reach further down than `below` allows, moved up by the rest, out of the top of the bar.
private struct GrowingField: Layout {
    /// The field's height, which SwiftUI animates, and the layout with it.
    var height: CGFloat
    let below: CGFloat

    var animatableData: CGFloat {
        get { height }
        set { height = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let height = max(height, bounds.height)
        let up = min(max(0, height - bounds.height - max(0, below)), height - bounds.height)
        for subview in subviews {
            subview.place(at: CGPoint(x: bounds.minX, y: bounds.minY - up), anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: height))
        }
    }
}

/// The target menu's items answer here: AppKit calls an item's action on an object.
@MainActor
private final class TargetMenuActions: NSObject {
    var onPick: ((AgentDestination) -> Void)?
    @objc func pick(_ item: NSMenuItem) {
        if let destination = item.representedObject as? AgentDestination { onPick?(destination) }
    }
}

private struct AgentLogo: View {
    let client: AgentClient
    let template: Bool

    var body: some View {
        if let logo = Agent.logo(for: client.rawValue) {
            Image(nsImage: logo).renderingMode(template || logo.isTemplate ? .template : .original).resizable().aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: Agent.fallbackSymbol).resizable().aspectRatio(contentMode: .fit)
        }
    }

    /// The agent's logo at a menu icon's size, or the fallback symbol. A menu draws an item's image at
    /// the image's own size.
    static func menuImage(for client: AgentClient) -> NSImage? {
        Agent.logo(for: client.rawValue).map(menuSized)
            ?? NSImage(systemSymbolName: Agent.fallbackSymbol, accessibilityDescription: client.label)
    }

    private static func menuSized(_ logo: NSImage) -> NSImage {
        let small = logo.copy() as? NSImage ?? logo
        small.size = NSSize(width: 16, height: 16)
        return small
    }
}
