import AppKit
import SwiftUI

/// A card dragged out of the stack and dropped pours into the point it was dropped on, as setup's
/// window pours into the menu bar icon (`FunnelFlight`). At a drop that took the card, macOS takes
/// the drag image down in one frame; this puts the same picture back where the drag image was and
/// pours it into the release point. The picture is the card with its corners, border and shadow,
/// in a clear margin (`DragSourceView.lift`), so the pour bends its whole rect and draws no shadow
/// of its own; the corners it grows fall in the margin. A drop that fails or is cancelled plays nothing here: macOS slides the
/// drag image home.
@MainActor
enum DropLanding {
    /// The rect the pour narrows into, centred on the release point, in points.
    static let mouth = CGSize(width: 4, height: 4)
    private static var panels: [NSPanel] = []

    /// Pours `picture`, drawn at `frame` in screen coordinates, into `point`. Nothing plays at motion 0
    /// or with Reduce Motion. Answers whether it played.
    @discardableResult
    static func play(_ picture: CGImage, from frame: NSRect, into point: NSPoint) -> Bool {
        let duration = Settings.shared.motionUI.dropDuration
        guard duration > 0, let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else { return false }
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        // The drag image's own level, so the picture takes its place over whatever it was dropped on.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.draggingWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        // SwiftUI's y runs down from the panel's top edge.
        let down = { (rect: NSRect) in
            CGRect(x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        }
        // On whole device pixels, where the picture's pixels were drawn to lie, so the first frame
        // does not resample them on a screen of the same scale.
        let pixel = 1 / screen.backingScaleFactor
        let frame = NSRect(x: (frame.minX / pixel).rounded() * pixel, y: (frame.minY / pixel).rounded() * pixel,
                           width: frame.width, height: frame.height)
        let target = NSRect(x: point.x - mouth.width / 2, y: point.y - mouth.height / 2, width: mouth.width, height: mouth.height)
        // The clock starts at the first frame drawn, so that frame is the drag image's last, and
        // the panel goes three frames after the pour ends on that clock. The last row is gone as it
        // arrives, so a frame drawn late still draws nothing rather than ending the pour a frame early.
        var begin: CFTimeInterval?
        let progress: @MainActor () -> Double = {
            let now = CACurrentMediaTime()
            if begin == nil {
                begin = now
                DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) { remove(panel) }
            }
            return min(1, max(0, (now - (begin ?? now)) / duration))
        }
        let look: @MainActor () -> FunnelLook = {
            var look = FunnelLook.intro()
            look.strength = 1
            look.corner = min(mouth.width, mouth.height) / 2
            look.shadow = 0
            return look
        }
        let view = NSHostingView(rootView: FunnelFlight(image: picture, card: down(frame), icon: down(target),
                                                        cardRadius: 0, progress: progress, look: look))
        view.frame = NSRect(origin: .zero, size: screen.frame.size)
        panel.contentView = view
        panel.orderFrontRegardless()
        panels.append(panel)
        // Should no frame ever be drawn, the panel still goes.
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 1) { remove(panel) }
        return true
    }

    /// Takes `panel` down and lets go of its view, whose clock holds the panel.
    private static func remove(_ panel: NSPanel) {
        guard panels.contains(where: { $0 === panel }) else { return }
        panel.orderOut(nil)
        panel.contentView = nil
        panels.removeAll { $0 === panel }
    }
}
