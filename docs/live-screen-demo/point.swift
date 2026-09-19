import AppKit

// Draw a rectangle over another app's window for a few seconds. Throwaway demo.
// Usage: point <owner name substring> [seconds]
let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: point <app> [seconds]"); exit(2) }
let wanted = args[1].lowercased()
let seconds = args.count > 2 ? Double(args[2]) ?? 20 : 20

func targetBounds() -> CGRect? {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
    for w in list {  // front to back
        guard let owner = w[kCGWindowOwnerName as String] as? String, owner.lowercased().contains(wanted),
              (w[kCGWindowLayer as String] as? Int) == 0,
              let b = w[kCGWindowBounds as String] as? [String: CGFloat],
              let x = b["X"], let y = b["Y"], let wd = b["Width"], let ht = b["Height"], wd > 50, ht > 50 else { continue }
        return CGRect(x: x, y: y, width: wd, height: ht)   // Quartz: global top-left origin
    }
    return nil
}

final class Ring: NSView {
    override func draw(_ r: NSRect) {
        let inset: CGFloat = 4
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset), xRadius: 12, yRadius: 12)
        path.lineWidth = 5
        NSColor(red: 0.93, green: 0.2, blue: 0.18, alpha: 1).setStroke()
        path.stroke()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
guard let first = targetBounds() else { print("no on-screen window owned by \(wanted)"); exit(1) }
let primaryHeight = NSScreen.screens[0].frame.height   // Quartz y -> AppKit y

func appKitFrame(_ q: CGRect, margin: CGFloat) -> NSRect {
    NSRect(x: q.minX - margin, y: primaryHeight - q.maxY - margin, width: q.width + 2 * margin, height: q.height + 2 * margin)
}

let margin: CGFloat = 8
let panel = NSPanel(contentRect: appKitFrame(first, margin: margin), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
panel.level = .screenSaver
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = false
panel.ignoresMouseEvents = true
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
panel.contentView = Ring()
panel.alphaValue = 0
panel.orderFrontRegardless()
NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.25; panel.animator().alphaValue = 1 }
print("ring over \(wanted) at \(first)")

var timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { _ in
    if let b = targetBounds() { panel.setFrame(appKitFrame(b, margin: margin), display: true) }
}
RunLoop.main.add(timer, forMode: .common)
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
    NSAnimationContext.runAnimationGroup({ ctx in ctx.duration = 0.3; panel.animator().alphaValue = 0 }, completionHandler: { exit(0) })
}
app.run()
