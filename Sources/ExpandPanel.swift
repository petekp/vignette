import AppKit
import SwiftUI

/// Carries one card's image between its slot in the stack and the annotator frame. Two of these
/// run at once during a swap: one returning, one arriving.
final class ExpandPanel: NSPanel {
    private var hosting: NSHostingView<ExpandImage>?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Room around the image for its shadow; the panel frame is the image frame grown by this.
    static let pad: CGFloat = 40

    func animate(image: NSImage, from: NSRect, to: NSRect, cornerFrom: CGFloat, cornerTo: CGFloat, completion: @escaping () -> Void) {
        let host = NSHostingView(rootView: ExpandImage(image: image, corner: cornerFrom))
        hosting = host
        contentView = host
        setFrame(from.insetBy(dx: -Self.pad, dy: -Self.pad), display: true)
        orderFrontRegardless()
        let ui = Settings.shared.data.ui
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Corner radius eases along with the frame so the card's rounding becomes the window's.
            host.rootView = ExpandImage(image: image, corner: cornerTo)
            Anim.run(ui.expandDuration, curve: "easeInOut", {
                self.animator().setFrame(to.insetBy(dx: -Self.pad, dy: -Self.pad), display: true)
            }, completion: { [weak self] in
                // The annotator (or the stack card) is drawn first, then this panel leaves, so nothing blinks.
                completion()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { self?.orderOut(nil) }
            })
        }
    }
}

/// Fills its panel with the image, cover style, so the crop matches the card at the start and the
/// exact-aspect annotator frame at the end.
struct ExpandImage: View {
    let image: NSImage
    let corner: CGFloat
    var body: some View {
        GeometryReader { geo in
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
        }
        .padding(ExpandPanel.pad)
        .animation(.easeInOut(duration: Settings.shared.data.ui.expandDuration), value: corner)
    }
}
