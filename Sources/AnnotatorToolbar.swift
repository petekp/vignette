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
        /// A send is rendering or submitting. The button says so and takes no second click.
        @Published var sending = false
        /// What the person typed to go with Send or Reply, as typed. Kept until the next image opens,
        /// so a send that fails keeps it for the next try.
        @Published var message = ""
        /// The bar's panel holds the keys, which it does only while the message field is typed in.
        @Published var keyed = false

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

        /// A new image: nothing listed yet, and nothing picked.
        func begin(replyTo: AgentDestination?) {
            self.replyTo = replyTo
            message = ""
            destinations = []
            listed = false
            target = nil
            picked = false
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
            let gone = complete && target.map { current in !list.contains { $0.id == current.id } } == true
            guard target == nil || gone else { return }
            if list.contains(where: { $0.focus != nil }) || complete { target = AgentDestination.defaultTarget(in: list) }
        }

        func pick(_ destination: AgentDestination) {
            target = destination
            picked = true
        }
    }

    let panel: NSPanel
    let model = Model()
    var onTool: ((EditorCore.Tool) -> Void)?
    var onDone: (() -> Void)?
    var onSend: ((AgentDestination) -> Void)?
    /// Esc in the message field: the keys go back to the editor.
    var onMessageEnd: (() -> Void)?
    private var hosting: NSHostingView<ToolbarView>!
    private var keyObservers: [NSObjectProtocol] = []
    /// Where `place` last put the bar, so a bar whose contents change width can centre again.
    private var placedBelow: (frame: NSRect, gap: CGFloat)?

    static let height: CGFloat = 44
    /// Room around the bar inside its panel for the shadow and the entrance motion.
    static let padding: CGFloat = 28
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
                                                      onPick: { [weak self] in
                                                          self?.model.pick($0)
                                                          self?.refit()
                                                      },
                                                      onMessageFocus: { [weak self] _ in self?.refit() },
                                                      onMessageEnd: { [weak self] in self?.onMessageEnd?() }))
        panel.contentView = hosting
        panel.onCommandReturn = { [weak self] in
            guard let self, !model.sending, let destination = model.offer.destination else { return }
            onSend?(destination)
        }
        // A field keeps first responder in a panel that is not key, and AppKit makes it the panel's
        // first responder when the bar comes up. So the field counts as typed in only while the
        // panel is key, and losing the keys ends typing in it, as a click elsewhere does.
        keyObservers = [
            NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.keyed = true }
            },
            NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.model.keyed = false
                    _ = self?.panel.makeFirstResponder(nil)
                }
            },
        ]
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

    /// Centres the bar again under the frame it was placed below, after its contents changed width:
    /// Send and the target arrive with the session list, a pick in the menu renames the target, and
    /// Reply can give way to Send. It waits a turn, because SwiftUI lays out the new contents after
    /// the model changes, and until then the bar measures its old width. The bar moves in place
    /// rather than sliding, so it reads as the same bar growing; a swap's slide already under way
    /// carries on to the new place. Unlike `place`, it leaves a `hideSoon` or a `hide` alone, and a
    /// bar on its way out stays where it is.
    func refit() {
        DispatchQueue.main.async { [weak self] in
            guard let self, model.shown || !panel.isVisible else { return }
            position(slide: sliding)
        }
    }

    private func position(slide: Bool) {
        guard let (frame, gap) = placedBelow else { return }
        let size = hosting.fittingSize   // includes `padding` on every side
        let origin = NSPoint(x: (frame.midX - size.width / 2).rounded(), y: frame.minY - gap - size.height + Self.padding)
        // The window server may give the panel a frame a fraction off the size asked for, so the
        // bar's own size is compared with a point of tolerance; a bar whose contents really changed
        // size is placed rather than slid.
        let sameSize = abs(panel.frame.width - size.width) < 1 && abs(panel.frame.height - size.height) < 1
        guard slide, model.shown, panel.isVisible, sameSize else {
            sliding = false
            slideX.stop(); slideY.stop()
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
            return
        }
        if !sliding {
            // The springs start from where the bar really is, not from the last value they carried.
            slideX.set(panel.frame.minX)
            slideY.set(panel.frame.minY)
            sliding = true
        }
        slideX.animate(to: origin.x, duration: slideSeconds, curve: "spring")
        slideY.animate(to: origin.y, duration: slideSeconds, curve: "spring")
    }

    /// The bar's own move, one spring per direction, so a move retargeted part way through keeps
    /// its velocity into the new place instead of restarting.
    private lazy var slideX = Tween(initial: 0) { [weak self] _ in self?.applySlide() }
    private lazy var slideY = Tween(initial: 0) { [weak self] _ in self?.applySlide() }
    /// Whether the two springs are the ones placing the panel. False while they are being seeded,
    /// so the half-seeded pair never reaches the panel.
    private var sliding = false

    private func applySlide() {
        guard sliding else { return }
        let origin = NSPoint(x: slideX.value, y: slideY.value)
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
private final class ToolbarPanel: NSPanel {
    private var pressOnField = false
    /// Cmd+Return while the message field has the keys: Send, as in the editor.
    var onCommandReturn: (() -> Void)?
    override var canBecomeKey: Bool { pressOnField || isKeyWindow }
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

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
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
    let onPick: (AgentDestination) -> Void
    let onMessageFocus: (Bool) -> Void
    let onMessageEnd: () -> Void
    @FocusState private var focused: Bool
    /// Counts Returns in the message field that did not send, each of which bounces Send's ⌘↩.
    @State private var sendNudges = 0
    /// The message field is being typed in.
    private var typing: Bool { focused && model.keyed }

    /// The message field's width in the bar, and the most lines it grows to while it is typed in.
    private static let messageWidth: CGFloat = 220
    private static let messageLines = 6
    /// The room under the bar the grown field may take, reserved in the panel while it is typed in.
    private static let messageRoom: CGFloat = 110

    var body: some View {
        HStack(spacing: 2) {
            ForEach(EditorCore.Tool.allCases, id: \.self) { tool in
                Button { onTool(tool) } label: {
                    Image(systemName: tool.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 32, height: 30)
                        // Grey, not the accent: blue belongs to the one action at the end of the bar.
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(model.tool == tool ? Color.primary.opacity(0.16) : .clear))
                }
                .buttonStyle(TactileButtonStyle(shape: .rounded))
                .help("\(tool.label) (\(String(tool.key).uppercased()))")
            }
            Divider().frame(height: 20).padding(.horizontal, 6)
            switch model.offer {
            case .copy:
                copyButton(filled: true)
            case .send(let target):
                copyButton(filled: false)
                    .disabled(model.sending)
                    .padding(.trailing, 6)
                targetMenu(target)
                    .disabled(model.sending)
                    .padding(.trailing, 4)
                // Vignette picked this session, so Return in the field sends only when Settings says so
                // (`sendWithReturn`); otherwise it points at ⌘↩, which sends either way.
                messageField(returnSends: { settings.data.sendWithReturn }) { onSend(target) }
                    .padding(.trailing, 4)
                actionButton(model.sending ? "Sending…" : "Send", key: "⌘↩", logo: nil) { onSend(target) }
                    .help("Send the drawing to this session (⌘↩)")
                    .keyframeAnimator(initialValue: CGFloat(1), trigger: sendNudges) { content, scale in content.scaleEffect(scale) } keyframes: { _ in
                        let motion = Settings.shared.motionScale
                        CubicKeyframe(motion > 0 ? 1.08 : 1, duration: 0.09)
                        SpringKeyframe(1, duration: 0.35 * max(motion, 0.01), spring: .bouncy)
                    }
            case .reply(let origin):
                messageField(returnSends: { true }) { onSend(origin) }
                    .padding(.trailing, 4)
                actionButton(model.sending ? "Sending…" : "Reply", key: "↩", logo: origin.client) { onSend(origin) }
                    .help("Send the drawing back to the session it came from (↩)")
            }
        }
        .padding(.horizontal, 7)
        .frame(height: AnnotatorToolbar.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.15), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .fixedSize()
        .padding(AnnotatorToolbar.padding)
        // Room below for the field to grow into. The panel's top stays where it is (`position`).
        .padding(.bottom, typing ? Self.messageRoom : 0)
        .onChange(of: typing) { _, now in onMessageFocus(now) }
        // In: rises a little and settles on a spring. Out: a short fade while it sinks back.
        .opacity(model.shown ? 1 : 0)
        .scaleEffect(model.shown ? 1 : 0.94, anchor: .top)
        .offset(y: model.shown ? 0 : 8)
        .animation(entrance, value: model.shown)
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
        }
        .buttonStyle(TactileButtonStyle(shape: .rounded, hoverScale: 1))
        .help("Copy the drawing and close (↩)")
    }

    /// What goes with the drawing, typed in the bar. One line wide in the bar; while it is typed in
    /// it grows down past the bar's bottom, up to `messageLines` lines, and the bar keeps its size.
    /// Cmd+Return sends (`ToolbarPanel`). Return sends only when `returnSends`: beside Reply, as in
    /// the editor, and beside Send when `sendWithReturn` is on. It is asked when Return is pressed,
    /// because the field keeps the submit action it was made with when the setting changes under it.
    /// Esc hands the keys back to the editor.
    private func messageField(returnSends: @escaping () -> Bool, send: @escaping () -> Void) -> some View {
        let grown = typing && !model.message.isEmpty
        return Color.clear
            .frame(width: Self.messageWidth, height: 30)
            .overlay(alignment: .top) {
                TextField("Add a message", text: $model.message, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(typing ? 1...Self.messageLines : 1...1)
                    .focused($focused)
                    .disabled(model.sending)
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
                    // Its own height, not the slot's, so it grows down past the bar.
                    .fixedSize(horizontal: false, vertical: true)
                    .background {
                        // Grown, it hangs below the bar over whatever is behind, so it takes a blur of
                        // that, as a popover does. The shape under the blur casts its shadow.
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(0.09))
                                .shadow(color: .black.opacity(grown ? 0.3 : 0), radius: 10, y: 4)
                            BehindWindowBlur(cornerRadius: 7).opacity(grown ? 1 : 0)
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.accentColor.opacity(typing ? 0.8 : 0), lineWidth: 1))
                    .animation(Anim.spring(0.25 * Settings.shared.motionScale), value: model.message)
                    .animation(Anim.spring(0.25 * Settings.shared.motionScale), value: typing)
            }
            .help("Words to send with the drawing")
    }

    /// Send or Reply: the filled button, with the agent's logo when it goes back to one.
    private func actionButton(_ title: String, key: String, logo client: AgentClient?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let client { AgentLogo(client: client, template: true).frame(width: 13, height: 13) }
                Text(title).font(.system(size: 13, weight: .semibold))
                if !model.sending { keyText(key, filled: true) }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(Color.accentColor.opacity(model.sending ? 0.55 : 1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(TactileButtonStyle(shape: .rounded, hoverScale: 1))
        .disabled(model.sending)
    }

    private func keyText(_ key: String, filled: Bool) -> some View {
        Text(key)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(filled ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.secondary))
    }

    /// Where Send goes: the agent's logo and the session's project, apart from Send itself. The menu
    /// is only for changing it: the active sessions used last, the target among them
    /// (`AgentDestination.menu`).
    private func targetMenu(_ target: AgentDestination) -> some View {
        Menu {
            Section("Send to") {
                ForEach(AgentDestination.menu(model.destinations, target: target)) { row($0, target: target) }
            }
        } label: {
            HStack(spacing: 6) {
                AgentLogo(client: target.client, template: false).frame(width: 14, height: 14)
                Text(Self.project(of: target)).font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.leading, 8)
            .padding(.trailing, 9)
            .frame(height: 30)
            .background(Color.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(TactileButtonStyle(shape: .rounded, hoverScale: 1))
        .menuIndicator(.hidden)
        .fixedSize()
        .help("\(target.name), \(target.client.label). Choose another session")
    }

    /// One session in the menu: its logo, its project, and its title in grey under it. The target
    /// carries the check.
    private func row(_ destination: AgentDestination, target: AgentDestination) -> some View {
        Toggle(isOn: Binding(get: { destination.id == target.id }, set: { _ in onPick(destination) })) {
            AgentLogo(client: destination.client, template: false, menu: true)
            Text(Self.project(of: destination))
            Text(destination.name)
        }
    }

    /// What names a session at a glance: its project's folder, which you chose, or its agent's name
    /// when it reported none.
    private static func project(of destination: AgentDestination) -> String {
        destination.detail.isEmpty ? destination.client.label : destination.detail
    }

    private var entrance: Animation {
        let scale = Settings.shared.motionScale
        guard scale > 0 else { return .linear(duration: 0) }
        return model.shown ? .spring(response: 0.45 * scale, dampingFraction: 0.72) : Anim.spring(0.18 * scale)
    }
}

/// An agent's logo from the bundle, or the fallback symbol for a vendor without one. `template`
/// draws it in the foreground colour, for the white of a filled button. A one-colour logo is always
/// drawn in the foreground colour.
private struct AgentLogo: View {
    let client: AgentClient
    let template: Bool
    /// A menu draws an item's image at the image's own size, whatever SwiftUI asks for, so a menu
    /// row gets a copy the size of a menu icon.
    var menu = false

    var body: some View {
        if let logo = Agent.logo(for: client.rawValue) {
            if menu {
                Image(nsImage: Self.menuSized(logo))
            } else {
                Image(nsImage: logo).renderingMode(template || logo.isTemplate ? .template : .original).resizable().aspectRatio(contentMode: .fit)
            }
        } else {
            Image(systemName: Agent.fallbackSymbol).resizable().aspectRatio(contentMode: .fit)
        }
    }

    private static func menuSized(_ logo: NSImage) -> NSImage {
        let small = logo.copy() as? NSImage ?? logo
        small.size = NSSize(width: 16, height: 16)
        return small
    }
}
