import AppKit
import SwiftUI

/// The annotator's toolbar: a native panel that floats just below the image window, so it is
/// never clipped by the image and looks like the rest of macOS. The tools come from the page at
/// load; the active state is mirrored from the page; taps are sent back to it.
@MainActor
final class AnnotatorToolbar {
    final class Model: ObservableObject {
        @Published var tools: [ToolInfo] = []
        @Published var tool: String? = nil
        /// The colour the next mark will be drawn in. Nothing in the bar shows it; it is what
        /// `[state] annotator.color` reports.
        @Published var color: String = ""
        @Published var shown = false     // drives the entrance and exit
        /// The agent sessions Send offers, read when the image opened. Empty hides the button:
        /// a control that can only say "nothing here" is not worth the width.
        @Published var destinations: [AgentDestination] = []
        /// Where a reply goes back to, when the open image is an agent's reply. It leads the menu
        /// and turns Send into Reply, so the recorded target is never guessed at.
        @Published var replyTo: AgentDestination?
        /// A send is rendering or submitting. The button says so and takes no second click.
        @Published var sending = false
    }

    let panel: NSPanel
    let model = Model()
    var onTool: ((String) -> Void)?
    var onDone: (() -> Void)?
    var onSend: ((AgentDestination) -> Void)?
    private var hosting: NSHostingView<ToolbarView>!

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
                                                      onSend: { [weak self] in self?.onSend?($0) }))
        panel.contentView = hosting
    }

    /// Centers the toolbar under `frame`, `gap` points below it. A bar that is already up — one
    /// image following another with no gap between them — slides to the new place instead of being
    /// taken down and raised again, so the controls stay where the hand left them and only move
    /// with the image's height. It also cancels a `hideSoon` waiting its turn: this bar is wanted.
    func place(below frame: NSRect, gap: CGFloat) {
        hideGeneration += 1
        let size = hosting.fittingSize   // includes `padding` on every side
        let origin = NSPoint(x: (frame.midX - size.width / 2).rounded(), y: frame.minY - gap - size.height + Self.padding)
        // The window server may give the panel a frame a fraction off the size asked for, so the
        // bar's own size is compared with a point of tolerance; a bar whose contents really changed
        // size is placed rather than slid.
        let sameSize = abs(panel.frame.width - size.width) < 1 && abs(panel.frame.height - size.height) < 1
        guard model.shown, panel.isVisible, sameSize else {
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

private struct ToolbarView: View {
    @ObservedObject var model: AnnotatorToolbar.Model
    let onTool: (String) -> Void
    let onDone: () -> Void
    let onSend: (AgentDestination) -> Void

    /// The sessions the menu lists, grouped by the project each one is working in, since that is
    /// what a person picking between a dozen of them navigates by. A project with no name comes
    /// last under no heading, which is also the whole menu when nothing reports one.
    /// The reply target is not in here: it leads the menu on its own.
    private var groups: [(project: String, sessions: [AgentDestination])] {
        let rest = model.destinations.filter { $0.id != model.replyTo?.id }
        return Dictionary(grouping: rest, by: \.detail)
            .map { (project: $0.key, sessions: $0.value.sorted { $0.name < $1.name }) }
            .sorted {
                if $0.project.isEmpty != $1.project.isEmpty { return $1.project.isEmpty }
                return $0.project < $1.project
            }
    }

    /// Whether the menu has anything to show at all.
    private var hasDestinations: Bool { !model.destinations.isEmpty || model.replyTo != nil }

    /// Above this many projects each one becomes a submenu; at or below it they are sections and
    /// every session is visible in one press. Six projects is about twenty rows once their
    /// headings and separators are counted, which fits the shortest screen this runs on: the
    /// headings are what push a longer list off the bottom, and that is where a second press
    /// costs less than a menu that scrolls.
    private static let submenuThreshold = 6

    @ViewBuilder private func rows(_ sessions: [AgentDestination]) -> some View {
        ForEach(sessions) { destination in
            Button(destination.name) { onSend(destination) }
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(model.tools) { tool in
                Button { onTool(tool.id) } label: {
                    Image(systemName: tool.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 32, height: 30)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(model.tool == tool.id ? Color.accentColor : .clear))
                        .foregroundStyle(model.tool == tool.id ? .white : .primary)
                }
                .buttonStyle(TactileButtonStyle(shape: .rounded))
                .help("\(tool.label) (\(tool.key.uppercased()))")
            }
            Divider().frame(height: 20).padding(.horizontal, 6)
            // No default target and no last-used one: the menu is the whole control, so where a
            // drawing is going is read before it goes rather than remembered from last time.
            if hasDestinations {
                Menu {
                    // The conversation a card came from leads, named with its project, so replying
                    // never means finding it again among the rest.
                    if let reply = model.replyTo {
                        Section("Reply to") {
                            Button { onSend(reply) } label: {
                                Text(reply.detail.isEmpty ? reply.name : "\(reply.name) — \(reply.detail)")
                            }
                        }
                    }
                    // A project with no name has no submenu and no heading to sit under, so its
                    // sessions stand at the level they are on. `groups` puts it last either way.
                    if groups.count > Self.submenuThreshold {
                        ForEach(groups, id: \.project) { group in
                            if group.project.isEmpty { rows(group.sessions) }
                            else { Menu(group.project) { rows(group.sessions) } }
                        }
                    } else {
                        ForEach(groups, id: \.project) { group in
                            if group.project.isEmpty { Section { rows(group.sessions) } }
                            else { Section(group.project) { rows(group.sessions) } }
                        }
                    }
                } label: {
                    Text(model.sending ? "Sending…" : (model.replyTo == nil ? "Send" : "Reply"))
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(model.sending)
                .help("Hand this drawing to an agent session")
            }
            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(TactileButtonStyle(shape: .rounded))
            .help("Copy the image and close (↩)")
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

    private var entrance: Animation {
        let scale = Settings.shared.motionScale
        guard scale > 0 else { return .linear(duration: 0) }
        return model.shown ? .spring(response: 0.45 * scale, dampingFraction: 0.72) : Anim.spring(0.18 * scale)
    }
}
