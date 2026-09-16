import AppKit
import SwiftUI

/// The annotator's toolbar: a native panel that floats just below the image window, so it is
/// never clipped by the image and looks like the rest of macOS. Tools and colors come from the
/// page at load; the active state is mirrored from the page; taps are sent back to it.
@MainActor
final class AnnotatorToolbar {
    final class Model: ObservableObject {
        @Published var tools: [ToolInfo] = []
        @Published var colors: [ColorInfo] = []
        @Published var tool: String? = nil
        @Published var color: String = ""
    }

    let panel: NSPanel
    let model = Model()
    var onTool: ((String) -> Void)?
    var onColor: ((String) -> Void)?
    var onDone: (() -> Void)?
    private var hosting: NSHostingView<ToolbarView>!

    static let height: CGFloat = 44

    init() {
        panel = ToolbarPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.isMovable = false
        hosting = NSHostingView(rootView: ToolbarView(model: model, onTool: { [weak self] in self?.onTool?($0) }, onColor: { [weak self] in self?.onColor?($0) }, onDone: { [weak self] in self?.onDone?() }))
        panel.contentView = hosting
    }

    /// Centers the toolbar under `frame`, `gap` points below it.
    func place(below frame: NSRect, gap: CGFloat) {
        let size = hosting.fittingSize
        panel.setFrame(NSRect(x: (frame.midX - size.width / 2).rounded(), y: frame.minY - gap - size.height, width: size.width, height: size.height), display: true)
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
    let onColor: (String) -> Void
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
            ForEach(model.colors) { color in
                Button { onColor(color.id) } label: {
                    Circle()
                        .fill(Color(hex: color.hex))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(.white, lineWidth: model.color == color.id ? 2 : 0))
                        .shadow(color: .black.opacity(model.color == color.id ? 0.4 : 0), radius: 2)
                        .frame(width: 28, height: 30)
                }
                .buttonStyle(TactileButtonStyle(shape: .circle))
                .help(color.id)
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
        .fixedSize()
    }
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
        self.init(red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255, blue: Double(value & 0xff) / 255)
    }
}
