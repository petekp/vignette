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
        @Published private(set) var destinations: [AgentDestination] = [] { didSet { refreshTargetRow(); reportOffer() } }
        /// The sessions Vignette can start, which only the target's menu shows.
        @Published private(set) var startable: [AgentDestination] = [] { didSet { reportOffer() } }
        /// Every client has answered. Until then a session missing from the list may only be late.
        @Published private(set) var listed = false
        /// The last list every client answered: this image's, or while the bar stays up for a swap,
        /// the image before's. Whether a reply's Claude Code session has closed is read from it, so
        /// the bar does not show Reply for a closed session until this image's list says so again.
        @Published private(set) var whole: [AgentDestination]? { didSet { reportOffer() } }
        /// The session the open image came from, when it names one: an agent's reply, or a push
        /// that said which session it was. The bar is Reply alone, so the target is never guessed at.
        @Published private(set) var replyTo: AgentDestination? { didSet { reportOffer() } }
        /// Where Send goes: the default until someone picks another in the menu.
        @Published private(set) var target: AgentDestination? { didSet { refreshTargetRow(); reportOffer() } }
        private var cachedTargetRow: SessionMenu.Row?

        /// The target's row among the listed sessions, worded once when either changes: ranking and
        /// wording every row to read one is too much for a view body that runs on every keystroke.
        func targetRow(for target: AgentDestination) -> SessionMenu.Row {
            if let cached = cachedTargetRow, cached.destination.id == target.id { return cached }
            return SessionMenu.row(of: target, among: destinations)
        }

        private func refreshTargetRow() {
            cachedTargetRow = target.map { SessionMenu.row(of: $0, among: destinations) }
        }
        /// The target was picked in the menu, so no later answer changes it.
        private var picked = false
        /// The target is the image before's, kept while the bar stays up so Send does not leave it
        /// for the 60 to 90 ms the listing takes. The first answer that settles a target replaces it.
        private var carried = false
        /// One more at each `begin`, so a late menu pick lands only on its own image.
        private(set) var imageNumber = 0
        /// From Send's press until the bar leaves. The button shows the send and takes no second click.
        /// A new press puts a failure's reason away.
        @Published var sending = false { didSet { if sending { failure = nil } } }
        /// Why the last send failed before its request was stored, and what to do about it. While it
        /// is set the button says "Not sent" and the reason stands beside it, until the person moves
        /// on: a click elsewhere, or Send again.
        @Published var failure: String?
        var notSent: Bool { failure != nil }
        /// The open image's drawing is exactly what its agent sent (`Agent.hasSentDrawing`).
        @Published var drawingAsSent = false
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
        /// The message field took the keys on its own as the image opened, and has kept them since.
        var tookKeysOnOpen = false
        /// A tool letter typed first into that field, waiting to learn whether it began a word.
        var toolLetter = HeldToolLetter()

        /// The message field took the keys on its own and is still empty, so nothing in it asks to
        /// send: Return and Esc do what they do on the image.
        var fieldUntouched: Bool { tookKeysOnOpen && fieldEmpty }

        /// What Return in the message field does. In an untouched field, what it does on the image,
        /// which never sends to a session Vignette picked.
        var fieldReturn: EditorCore.Finish { fieldUntouched ? offer.finishes.returnKey : .send }

        /// Esc in an untouched field closes the editor, as on the image. Otherwise it hands the keys back.
        var fieldEscCloses: Bool { fieldUntouched }

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
            if offer.offersTarget { controls.append(.target) }
            if offer.destination != nil { controls += nothingToReply ? [.message] : [.message, .action] }
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
            ToolbarOffer(replyTo: replyTo, destinations: whole ?? destinations, listed: whole != nil, target: target, startable: startable)
        }

        /// Called with the offer each time it changes, whatever changed it: an answer, a new image or a pick.
        var onOfferChanged: ((ToolbarOffer) -> Void)?
        private var reportedOffer = ToolbarOffer.copy

        private func reportOffer() {
            let offer = self.offer
            guard offer != reportedOffer else { return }
            reportedOffer = offer
            onOfferChanged?(offer)
        }

        /// A new image: nothing listed yet, and nothing picked. `carryingTarget`, when the bar is
        /// on screen for the image before, keeps that image's list and target until this one's settle.
        func begin(replyTo: AgentDestination?, carryingTarget: Bool) {
            self.replyTo = replyTo
            imageNumber += 1
            message = ""
            focus = nil
            tookKeysOnOpen = false
            toolLetter = HeldToolLetter()
            listed = false
            picked = false
            carried = carryingTarget && target != nil
            guard !carried else { return }
            destinations = []
            startable = []
            target = nil
            whole = nil
        }

        /// Another client answered. The target settles on the first answer that decides a pick
        /// (`DestinationChoice`). Once settled it changes only when its session is gone from the whole
        /// list, so it never changes under the pointer.
        func answered(_ answer: DestinationChoice.Answer) {
            let list = answer.list
            destinations = list
            startable = answer.startable
            listed = answer.complete
            if answer.complete { whole = list }
            if let current = target, let fresh = list.first(where: { $0.id == current.id }) { target = fresh }
            guard !picked else { return }
            if carried {
                guard answer.decided else { return }
                carried = false
                target = answer.pick
                return
            }
            let gone = answer.complete && target.map { current in !list.contains { $0.id == current.id } } == true
            guard target == nil || gone, answer.decided else { return }
            target = answer.pick
        }

        /// A hand pick, which also chooses to write to it: the field counts as pressed from here.
        func pick(_ destination: AgentDestination) {
            target = destination
            picked = true
            carried = false
            tookKeysOnOpen = false
        }

        func isHandPick(_ destination: AgentDestination) -> Bool { picked && target?.id == destination.id }
    }

    let panel: ToolbarPanel
    let model = Model()
    var onTool: ((EditorCore.Tool) -> Void)?
    var onDone: (() -> Void)?
    var onSend: ((AgentDestination) -> Void)?
    /// A session picked in the target's menu, before the bar applies it.
    var onPick: (() -> Void)?
    /// Esc in the message field: the keys go back to the editor.
    var onMessageEnd: (() -> Void)?
    /// Esc in a message field that took the keys on its own and is still empty: the editor closes.
    var onClose: (() -> Void)?
    /// Left or Right in that same field: the screenshot beside this one, as on the image.
    var onPage: ((EditorCore.Page, _ isRepeat: Bool) -> Void)?
    /// Tab past the last control, or Shift+Tab past the first: the editor takes the focus back. False
    /// when it has no marks to take it, and the bar goes round its own controls.
    var onLeave: ((_ backward: Bool) -> Bool)?
    /// The target's frame in the hosting view, where its menu drops down from.
    private(set) var targetFrame: CGRect?
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
        targetMenuActions.onPick = { [weak self] destination, menuLine in
            let image = self?.model.imageNumber
            // A turn later, once the menu's own event loop has ended.
            DispatchQueue.main.async {
                guard let self else { return }
                Log.write("[send] picked \(destination.address.description) project=\(destination.detail) role=\(destination.role ?? "none")")
                if let menuLine { Log.write(menuLine) }
                guard self.model.shown, self.model.imageNumber == image else { return Log.write("[send] pick dropped") }
                // Before the pick changes the offer, which may offer the field the keys as on open.
                self.onPick?()
                withAnimation(Anim.spring(0.35 * Settings.shared.motionScale)) { self.model.pick(destination) }
                self.typeAfterPick()
            }
        }
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
    let onTool: (EditorCore.Tool) -> Void
    let onDone: () -> Void
    let onSend: (AgentDestination) -> Void
    let onTargetMenu: () -> Void
    let onFocusMessage: () -> Void
    let onTargetFrame: (CGRect) -> Void
    /// The bar's width changed. A control coming or going opens or closes in the row, so the
    /// width moves on every frame of the spring, and the panel grows with it.
    let onWidth: () -> Void
    let onMessageEnd: () -> Void
    let onClose: () -> Void
    @FocusState private var focused: Bool
    /// The control the pointer is on, and the one whose tooltip is up (`tip`).
    @State private var tipOver: AnnotatorToolbar.Model.Control?
    @State private var tipShown: AnnotatorToolbar.Model.Control?
    @State private var tipWait: DispatchWorkItem?
    @State private var tipLeft = Date.distantPast
    /// The message field's height as its text needs it. The box springs to it (`GrowingField`).
    @State private var fieldHeight: CGFloat = 30
    @State private var targetHovered = false
    /// The message field is being typed in.
    private var typing: Bool { focused && model.keyed }
    @Environment(\.colorScheme) private var colorScheme

    /// How far past a control its presses reach: to the bar's top and bottom edges, which are 7 pt
    /// from a 30 pt control, and into the gaps beside it. Not past the bar: the panel is clear there,
    /// and the window server passes a press on a clear pixel to the window behind.
    fileprivate static let slop = EdgeInsets(top: 7, leading: 2, bottom: 7, trailing: 2)
    private static let spacing: CGFloat = 2
    /// The tools sit 2 pt apart, so each takes half the gap.
    private static let toolSlop = EdgeInsets(top: 7, leading: 1, bottom: 7, trailing: 1)

    /// The widest the target's project name is drawn. Past it the name is cut, so a long folder name
    /// cannot stretch the bar.
    private static let targetNameMax: CGFloat = 132

    /// The message field's width in the bar, and the most lines it grows to while it is typed in.
    private static let messageWidth: CGFloat = 220
    private static let messageLines = 6

    var body: some View {
        HStack(spacing: Self.spacing) {
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
                copyButton(filled: offer.destination == nil)
                    .modifier(FocusRing(on: model.focus == .copy))
                    .modifier(Resting(while: model.sending))
                    .padding(.trailing, offer.offersTarget ? 6 : 0)
                    .transition(Self.slot)
            }
            // With a message field beside it, the target sits inside the field's box, so the two
            // read as one control. It draws above the field, whose box reaches under it.
            let joined = offer.offersTarget && offer.destination != nil
            if offer.offersTarget {
                targetMenu(offer.destination, joined: joined)
                    .modifier(FocusRing(on: model.focus == .target && !joined))
                    .modifier(Resting(while: model.sending))
                    .padding(.trailing, joined ? 0 : 4)
                    .zIndex(1)
                    .transition(Self.slot)
            }
            if let destination = offer.destination {
                messageField(sessionRoom: joined ? Self.targetWidth(nameWidth: targetNameWidth(offer.destination)) + Self.spacing : 0) { onSend(destination) }
                    .modifier(Resting(while: model.sending))
                    .padding(.trailing, 4)
                actionButton(offer.isSend ? "Send" : "Reply", key: offer.isSend ? "⌘↩" : "↩",
                             logo: offer.isSend ? nil : destination.client) { onSend(destination) }
                    .modifier(FocusRing(on: model.focus == .action))
                    .modifier(Resting(while: model.nothingToReply))
                    .contentShape(Rectangle())
                    .modifier(TipSpot(control: .action, text: model.nothingToReply ? AnnotatorToolbar.Model.nothingToReplyTip : nil, hover: tip))
            }
        }
        .padding(.horizontal, 7)
        .frame(height: AnnotatorToolbar.height)
        // Controls coming or going while the bar changes width are cut at its sides. Above and below
        // stay open, for the message field growing down past the bar.
        .mask { Rectangle().padding(.vertical, -(AnnotatorToolbar.messageRoom + AnnotatorToolbar.padding)) }
        .background { glass }
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .fixedSize()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _ in onWidth() }
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
        // A change of offer springs the bar to its new width about its centre, which stays under
        // the image. The centring is inside the spring: outside it, the bar jumped to its new place
        // and only its width sprang. The panel already has the room (`AnnotatorToolbar.position`).
        .animation(Anim.spring(0.35 * Settings.shared.motionScale), value: model.offer)
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

    /// A control an offer adds or takes away. Its width grows from nothing as it comes and shrinks to
    /// nothing as it goes, on the offer's spring, so the controls beside it move with it: placed at its
    /// full width at once, it was drawn over the message field still sliding out of its way. It fades
    /// in once it has begun to open, and out before it is cut.
    private static var slot: AnyTransition {
        AnyTransition.modifier(active: Reveal(fraction: 0), identity: Reveal(fraction: 1)).combined(with: words)
    }

    /// Words giving way to others in one place: the old ones leave quickly, and the new ones fade in
    /// a moment later.
    private static var words: AnyTransition {
        let motion = Settings.shared.motionScale
        return .asymmetric(insertion: .opacity.animation(.easeIn(duration: 0.15 * motion).delay(0.1 * motion)),
                           removal: .opacity.animation(.easeOut(duration: 0.08 * motion)))
    }

    /// The target's name giving way to the next: the old one goes at once and the new one comes in
    /// while the name's width is still springing, so the box is never empty for long.
    private static var nameSwap: AnyTransition {
        let motion = Settings.shared.motionScale
        return .asymmetric(insertion: .opacity.animation(.easeIn(duration: 0.12 * motion).delay(0.05 * motion)),
                           removal: .opacity.animation(.easeOut(duration: 0.06 * motion)))
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
    /// Return and Cmd+Return send (`ToolbarPanel`), since typing a message is the intent to send it.
    /// Esc hands the keys back to the editor. In a field that took the keys on its own and is still
    /// empty, Return and Esc do what they do on the image (`Model.fieldReturn`).
    /// `sessionRoom` is how far the box reaches left past the field, under the target.
    private func messageField(sessionRoom: CGFloat, send: @escaping () -> Void) -> some View {
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
                        switch model.fieldReturn {
                        case .done: onDone()
                        case .send: if !model.sending { send() }
                        }
                    }
                    .onExitCommand { if model.fieldEscCloses { onClose() } else { onMessageEnd() } }
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
            // The part under the target takes no presses or hover, which are the target's.
            .background(alignment: .trailing) {
                ZStack {
                    box.fill(Color.primary.opacity(0.09)).shadow(color: .black.opacity(grown ? 0.3 : 0), radius: 10, y: 4)
                    BehindWindowBlur(cornerRadius: 7).opacity(grown ? 1 : 0)
                }
                .frame(width: Self.messageWidth + sessionRoom)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .trailing) {
                box.stroke(Color.accentColor.opacity(typing ? 0.8 : 0), lineWidth: 1)
                    .frame(width: Self.messageWidth + sessionRoom)
                    .allowsHitTesting(false)
            }
            // The text field takes presses only on its text. Its padding and the room around it in
            // the bar start typing too, on the press, through the gesture behind the box. A gesture
            // on the text as well took the release of a quick click, and the text field then waited
            // for it with every other event queued behind, Esc included, until the next click.
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
                .transition(Self.words)
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

    /// Where Send goes: the agent's logo and the session's title, apart from Send itself. A press
    /// opens the menu for changing it before the button sees the press (`AnnotatorToolbar.pressTarget`),
    /// so the button's own action is the accessibility press.
    /// With no target, the box asks for one, and its menu lists the sessions Vignette can start.
    /// `joined`: it sits inside the message field's box, which is its fill.
    private func targetMenu(_ target: AgentDestination?, joined: Bool) -> some View {
        // The name's width is set rather than left to the text, so it springs with the bar when the
        // target changes and the controls beside it move with it. The old name leaves and the new
        // one comes in the place between, as a control does (`slot`). A long name is cut in the
        // middle, where a worktree's suffix survives; the tooltip has it whole.
        let row = target.map { model.targetRow(for: $0) }
        let title = row?.title ?? Self.chooseSession
        let nameWidth = targetNameWidth(target)
        return Button(action: onTargetMenu) {
            HStack(spacing: 6) {
                ZStack(alignment: .leading) {
                    HStack(spacing: 6) {
                        AgentLogo(client: target?.client ?? .claude, template: false).frame(width: 14, height: 14)
                        Text(title).font(.system(size: 13, weight: .semibold))
                            .lineLimit(1).truncationMode(.middle)
                            .frame(width: nameWidth, alignment: .leading)
                    }
                    .id(target?.id ?? "")
                    .transition(Self.nameSwap)
                }
                .frame(width: 14 + 6 + nameWidth, alignment: .leading)
                .clipped()
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    .frame(width: Self.chevronWidth)
            }
            .foregroundStyle(.primary)
            .padding(.leading, 8)
            .padding(.trailing, 9)
            .frame(width: Self.targetWidth(nameWidth: nameWidth), height: 30)
            .background { TargetFill(joined: joined, hovered: targetHovered, focused: model.focus == .target) }
            .padding(Self.slop)
            .contentShape(Rectangle())
            .onHover { targetHovered = $0 }
        }
        .buttonStyle(TargetButtonStyle(joined: joined))
        .padding(Self.slop.negated)
        .fixedSize()
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onTargetFrame($0) }
        .modifier(TipSpot(control: .target, text: row?.tooltip ?? Self.chooseSessionTip, hover: tip))
    }

    private func targetNameWidth(_ target: AgentDestination?) -> CGFloat {
        min(ButtonLabel.width(target.map { model.targetRow(for: $0).title } ?? Self.chooseSession, size: 13), Self.targetNameMax)
    }

    private static let chevronWidth: CGFloat = 10

    /// The target's width for a name that wide. The message field's box reaches under it and the
    /// space after it, on the same spring, so the box's leading edge is the target's.
    static func targetWidth(nameWidth: CGFloat) -> CGFloat { 8 + 14 + 6 + nameWidth + 6 + chevronWidth + 9 }

    static let chooseSession = "Choose a session"
    static let chooseSessionTip = "No session is running. You can continue a past one or start a new one."

    private var entrance: Animation {
        let scale = Settings.shared.motionScale
        guard scale > 0 else { return .linear(duration: 0) }
        return model.shown ? .spring(response: 0.45 * scale, dampingFraction: 0.72) : Anim.spring(0.18 * scale)
    }
}

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
