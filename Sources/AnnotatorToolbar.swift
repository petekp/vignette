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
    }

    let panel: NSPanel
    let model = Model()
    var onTool: ((String) -> Void)?
    var onDone: (() -> Void)?
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
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.isMovable = false
        hosting = NSHostingView(rootView: ToolbarView(model: model, onTool: { [weak self] in self?.onTool?($0) }, onDone: { [weak self] in self?.onDone?() }))
        panel.contentView = hosting
    }

    /// Centers the toolbar under `frame`, `gap` points below it.
    func place(below frame: NSRect, gap: CGFloat) {
        let size = hosting.fittingSize   // includes `padding` on every side
        panel.setFrame(NSRect(x: (frame.midX - size.width / 2).rounded(), y: frame.minY - gap - size.height + Self.padding, width: size.width, height: size.height), display: true)
    }

    /// Orders the panel in hidden and lets the bar rise into place a turn later, so the
    /// entrance animates from the hidden state instead of appearing already in place.
    func show() {
        hideGeneration += 1
        panel.orderFront(nil)
        DispatchQueue.main.async { [weak self] in self?.model.shown = true }
    }

    /// Fades the bar out, then orders the panel out.
    func hide() {
        hideGeneration += 1
        let gen = hideGeneration
        model.shown = false
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
