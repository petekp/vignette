import AppKit
import Vision

// Point an arrow at a word inside another app's window, found by OCR. Throwaway demo.
// Usage: arrow <app> <word> [seconds]
let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: arrow <app> <word> [seconds]"); exit(2) }
let wanted = args[1].lowercased(), word = args[2].lowercased()
let seconds = args.count > 3 ? Double(args[3]) ?? 20 : 20

func targetBounds() -> CGRect? {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
    for w in list {
        guard let owner = w[kCGWindowOwnerName as String] as? String, owner.lowercased().contains(wanted),
              (w[kCGWindowLayer as String] as? Int) == 0,
              let b = w[kCGWindowBounds as String] as? [String: CGFloat],
              let x = b["X"], let y = b["Y"], let wd = b["Width"], let ht = b["Height"], wd > 50, ht > 50 else { continue }
        return CGRect(x: x, y: y, width: wd, height: ht)
    }
    return nil
}

/// The word's box as fractions of the window (x from the left, y from the top).
func find(_ word: String, in window: CGRect) -> CGRect? {
    let path = NSTemporaryDirectory() + "arrow-\(getpid()).png"
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "-R", "\(Int(window.minX)),\(Int(window.minY)),\(Int(window.width)),\(Int(window.height))", path]
    try? p.run(); p.waitUntilExit()
    guard let img = NSImage(contentsOfFile: path), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    let req = VNRecognizeTextRequest(); req.recognitionLevel = .accurate; req.usesLanguageCorrection = false
    try? VNImageRequestHandler(cgImage: cg).perform([req])
    for obs in req.results ?? [] {
        guard let cand = obs.topCandidates(1).first else { continue }
        let text = cand.string.lowercased()
        guard let r = text.range(of: word) else { continue }
        let box = (try? cand.boundingBox(for: r))?.boundingBox ?? obs.boundingBox   // Vision: origin bottom-left, normalized
        return CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
    }
    return nil
}

final class ArrowView: NSView {
    var tip = CGPoint.zero, tail = CGPoint.zero   // in view coordinates (AppKit, bottom-left)
    override func draw(_ r: NSRect) {
        let red = NSColor(red: 0.93, green: 0.2, blue: 0.18, alpha: 1); red.setStroke(); red.setFill()
        let line = NSBezierPath(); line.lineWidth = 5; line.lineCapStyle = .round
        line.move(to: tail); line.line(to: tip); line.stroke()
        let a = atan2(tip.y - tail.y, tip.x - tail.x), s: CGFloat = 18
        let head = NSBezierPath(); head.move(to: tip)
        head.line(to: CGPoint(x: tip.x - s * cos(a - .pi / 6), y: tip.y - s * sin(a - .pi / 6)))
        head.line(to: CGPoint(x: tip.x - s * cos(a + .pi / 6), y: tip.y - s * sin(a + .pi / 6)))
        head.close(); head.fill()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
guard let first = targetBounds() else { print("no window for \(wanted)"); exit(1) }
guard var frac = find(word, in: first) else { print("\(word) not found in \(wanted)'s window"); exit(1) }
print("found \(word) at \(frac) of the window")
let primaryHeight = NSScreen.screens[0].frame.height

let panel = NSPanel(contentRect: NSRect(x: first.minX, y: primaryHeight - first.maxY, width: first.width, height: first.height),
                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
panel.level = .screenSaver; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
panel.ignoresMouseEvents = true
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
let view = ArrowView(); panel.contentView = view

var lastSize = first.size
func place(_ w: CGRect) {
    panel.setFrame(NSRect(x: w.minX, y: primaryHeight - w.maxY, width: w.width, height: w.height), display: false)
    // The word's box in view coordinates: x from the left, y flipped to bottom-left.
    let bx = frac.minX * w.width, by = w.height - (frac.minY + frac.height / 2) * w.height
    view.tip = CGPoint(x: bx + frac.width * w.width + 10, y: by)          // just right of the word
    view.tail = CGPoint(x: view.tip.x + 140, y: by + 90)                    // from the upper right
    view.needsDisplay = true
}
place(first)
panel.alphaValue = 0; panel.orderFrontRegardless()
NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.25; panel.animator().alphaValue = 1 }

let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { _ in
    guard let w = targetBounds() else { return }
    if w.size != lastSize { lastSize = w.size; if let f = find(word, in: w) { frac = f } }   // text reflows on resize
    place(w)
}
RunLoop.main.add(timer, forMode: .common)
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
    NSAnimationContext.runAnimationGroup({ ctx in ctx.duration = 0.3; panel.animator().alphaValue = 0 }, completionHandler: { exit(0) })
}
app.run()
