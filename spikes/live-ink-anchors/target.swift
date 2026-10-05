// A stand-in for "another app's window": a titled window with a scrolling text view of numbered lines.
// Line 40 carries a solid green block, the marker the overlay's ring should stay around.
// Commands on stdin, one a line:
//   move x y | glide dx dy secs | size w h | scroll y | smooth dy secs | activate | mini | unmini | close | frame | quit
import AppKit

final class App: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var text: NSTextView!
    var scroll: NSScrollView!
    var timer: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 640, height: 520),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Anchor Target"
        window.isReleasedWhenClosed = false
        scroll = NSTextView.scrollableTextView()
        text = (scroll.documentView as! NSTextView)
        text.isEditable = false
        text.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        text.backgroundColor = NSColor(white: 0.12, alpha: 1)
        text.textColor = NSColor(white: 0.85, alpha: 1)
        let body = NSMutableAttributedString()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), .foregroundColor: NSColor(white: 0.85, alpha: 1)]
        let words = ["let", "frame", "window", "scroll", "anchor", "mark", "return", "guard", "if", "else", "self", "point", "count", "value", "x", "y", "{", "}", "(", ")", "=", "+", "0", "1", "layer", "ink"]
        var seed: UInt64 = 7
        func next() -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int(seed >> 33) }
        for i in 1...300 {
            let indent = String(repeating: "    ", count: next() % 4)
            let line = (0..<(2 + next() % 9)).map { _ in words[next() % words.count] }.joined(separator: " ")
            body.append(NSAttributedString(string: String(format: "%03d ", i) + indent + line + " ", attributes: attrs))
            if i == 40 {
                body.append(NSAttributedString(string: "████", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), .foregroundColor: NSColor(red: 0, green: 1, blue: 0, alpha: 1)]))
            }
            body.append(NSAttributedString(string: "\n", attributes: attrs))
        }
        text.textStorage?.setAttributedString(body)
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        print("ready pid=\(getpid()) window=\(window.windowNumber)")
        fflush(stdout)
        Thread.detachNewThread { self.readCommands() }
    }

    func readCommands() {
        while let line = readLine() {
            let parts = line.split(separator: " ").map(String.init)
            DispatchQueue.main.async { self.run(parts) }
        }
    }

    func animate(_ seconds: Double, _ step: @escaping (Double) -> Void) {
        timer?.invalidate()
        let start = CACurrentMediaTime()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { t in
            let p = min(1, (CACurrentMediaTime() - start) / seconds)
            step(p)
            if p >= 1 { t.invalidate() }
        }
    }

    func run(_ p: [String]) {
        guard let cmd = p.first else { return }
        let n = p.dropFirst().compactMap(Double.init)
        switch cmd {
        case "move": window.setFrameOrigin(NSPoint(x: n[0], y: n[1]))
        case "glide":
            let from = window.frame.origin
            animate(n[2]) { t in
                let e = 0.5 - cos(t * .pi) / 2
                self.window.setFrameOrigin(NSPoint(x: from.x + n[0] * e, y: from.y + n[1] * e))
            }
        case "grow":
            let from = window.frame
            animate(n[2]) { t in
                let e = 0.5 - cos(t * .pi) / 2
                // Grows from the top-left corner, as a drag on the bottom-right corner does.
                let size = NSSize(width: from.width + n[0] * e, height: from.height + n[1] * e)
                self.window.setFrame(NSRect(x: from.minX, y: from.maxY - size.height, width: size.width, height: size.height), display: true)
            }
        case "size": window.setContentSize(NSSize(width: n[0], height: n[1]))
        case "scroll":
            scroll.contentView.scroll(to: NSPoint(x: 0, y: n[0]))
            scroll.reflectScrolledClipView(scroll.contentView)
        case "smooth":
            let from = scroll.contentView.bounds.origin.y
            animate(n[1]) { t in
                let e = 0.5 - cos(t * .pi) / 2
                self.scroll.contentView.scroll(to: NSPoint(x: 0, y: from + n[0] * e))
                self.scroll.reflectScrolledClipView(self.scroll.contentView)
            }
        case "activate": NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
        case "mini": window.miniaturize(nil)
        case "unmini": window.deminiaturize(nil)
        case "close": window.orderOut(nil)
        case "show": window.makeKeyAndOrderFront(nil)
        case "full": window.toggleFullScreen(nil)
        case "frame": print("frame \(window.frame) scrollY=\(scroll.contentView.bounds.origin.y)")
        case "quit": exit(0)
        default: print("unknown \(cmd)")
        }
        fflush(stdout)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = App()
app.delegate = delegate
app.run()
