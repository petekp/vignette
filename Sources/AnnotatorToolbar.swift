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

        var offer: ToolbarOffer {
            ToolbarOffer(replyTo: replyTo, destinations: destinations, listed: listed, target: target)
        }

        /// A new image: nothing listed yet, and nothing picked.
        func begin(replyTo: AgentDestination?) {
            self.replyTo = replyTo
            destinations = []
            listed = false
            target = nil
            picked = false
        }

        /// Another client answered. The target settles as soon as herdr's focus names a session,
        /// and otherwise once every client has answered, since the session used last is a comparison
        /// across all of them. Once settled it changes only when its session is gone from the whole
        /// list, so it never changes under the pointer.
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
    private var hosting: NSHostingView<ToolbarView>!
    /// Where `place` last put the bar, so a bar whose contents change width can centre again.
    private var placedBelow: (frame: NSRect, gap: CGFloat)?

    static let height: CGFloat = 44
    /// Room around the bar inside its panel for the shadow and the entrance motion.
    static let padding: CGFloat = 28
    private var hideGeneration = 0

    init() {
        panel = ToolbarPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
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
                                                      }))
        panel.contentView = hosting
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

/// Never key: typing and shortcuts stay with the editor window this panel belongs to.
@MainActor
private final class ToolbarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
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

private struct ToolbarView: View {
    @ObservedObject var model: AnnotatorToolbar.Model
    let onTool: (EditorCore.Tool) -> Void
    let onDone: () -> Void
    let onSend: (AgentDestination) -> Void
    let onPick: (AgentDestination) -> Void

    /// How many sessions the menu shows before "More sessions". The one you are sending to is
    /// almost always among the few used last.
    private static let recentCount = 5

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
                actionButton(model.sending ? "Sending…" : "Send", key: "⌘↩", logo: nil) { onSend(target) }
                    .help("Send the drawing to this session (⌘↩)")
            case .reply(let origin):
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
    /// is only for changing it; the session used last leads it.
    private func targetMenu(_ target: AgentDestination) -> some View {
        let sessions = model.destinations
        return Menu {
            Section("Send to") {
                ForEach(Array(sessions.prefix(Self.recentCount))) { row($0, target: target) }
            }
            if sessions.count > Self.recentCount {
                Menu("More sessions") {
                    ForEach(Array(sessions.dropFirst(Self.recentCount))) { row($0, target: target) }
                }
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
/// draws it in the foreground colour, for the white of a filled button.
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
                Image(nsImage: logo).renderingMode(template ? .template : .original).resizable().aspectRatio(contentMode: .fit)
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
