import AppKit
import SwiftUI

extension AnnotationController {
    /// Draws the agent's marks for the image open now over the person's drawing, in the picture's
    /// own layer so they follow every zoom, with a bar to keep or clear them at the top of the frame.
    /// Takes away the ones shown before. Run after `editor.open`, which puts the drawing's marks on top.
    func showAgentMarks() {
        agentMarks?.layers.clear()
        agentMarks?.layers.layer.removeFromSuperlayer()
        agentMarks?.bar.removeFromSuperview()
        agentMarks = nil
        guard let key = current?.key, let entry = pendingMarks(key), let container else { return }
        let backing = window?.backingScaleFactor ?? 2
        let pixels = entry.drawing.pixels
        // Texts are drawn at twice the fitted size, so a zoom in keeps them sharp for a while, and at
        // most two device px to each of the image's.
        let fitted = container.bounds.width / CGFloat(max(1, pixels.width)) * backing
        let layers = MarkLayers(pixels: pixels, queue: MarkLayers.textQueue)
        layers.setScale(backing)
        layers.show(entry.drawing, scale: min(max(fitted * 2, 1), backing * 2), bound: pixels.bounds, style: textStyle,
                    markStyle: Settings.shared.data.ui.markStyle)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        editor.picture.layer.addSublayer(layers.layer)
        CATransaction.commit()
        let bar = NSHostingView(rootView: AgentMarksBar(agent: entry.agent, sender: entry.sender) { [weak self] keep in self?.onAgentMarks?(key, keep) })
        bar.setFrameSize(bar.fittingSize)
        bar.setFrameOrigin(NSPoint(x: (container.bounds.width - bar.frame.width) / 2, y: container.bounds.height - bar.frame.height - Self.agentMarksBarInset))
        bar.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        container.addSubview(bar)
        agentMarks = (layers, bar)
    }

    /// The agent's marks on `key` changed: the editor shows what is left of them when `key` is open.
    func agentMarksChanged(_ key: ScreenshotKey) {
        guard current?.key == key else { return }
        showAgentMarks()
    }

    /// The bar's distance from the top of the frame.
    static let agentMarksBarInset: CGFloat = 10
}

/// The bar over an image whose agent's marks are on top: who drew them, then Clear and Keep. A
/// capsule of the system's material, as a toolbar's overlay is.
struct AgentMarksBar: View {
    let agent: String
    let sender: String?
    let onMarks: (_ keep: Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let image = Agent.logo(for: agent) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(width: 14, height: 14)
            }
            Text(Self.title(agent, sender: sender)).font(.system(size: 12, weight: .medium))
            AgentMarksButtons(onMarks: onMarks)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
        .padding(8)
        .fixedSize()
    }

    /// "Marks from vignette" or "Marks from Claude", from the words of an agent's tab.
    static func title(_ agent: String, sender: String?) -> String {
        let from = Agent.label(for: agent, sender: sender)
        return "Marks " + from.prefix(1).lowercased() + from.dropFirst()
    }
}
