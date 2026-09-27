// The stage's helpers, one binary:
//
//   stage desktop                     a wallpaper over the whole main screen, behind the stage's windows
//   stage place <pid> <x> <y> <w> <h> moves an app's front window to a frame
//   stage frame <pid>                 prints an app's front window frame
//   stage fields <pid>                prints the frame of every text field in an app's windows
//   stage owner <x> <y>               which app's window is frontmost under a global point
//   stage pasteboard save|restore <dir>
//
// Frames are global points, top left, y down. The desktop prints `ready x y w h`, the screen below
// the menu bar, once it is on screen, and quits when its stdin closes or reads `quit`, so it never
// outlives the script that started it.
import AppKit
import ApplicationServices

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func say(_ line: String) {
    print(line)
    fflush(stdout)
}

// MARK: desktop

/// The stage's wallpaper: a dark plum field with a soft glow behind the browser. It is a window at
/// the normal level, ordered in before the stage's windows, so the windows of every other app stay
/// behind it and the stage's own come up in front.
final class Desktop: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ note: Notification) {
        guard let screen = NSScreen.screens.first else { fail("stage: no screen") }
        window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = true
        window.hasShadow = false
        window.collectionBehavior = [.stationary, .ignoresCycle]
        let view = NSImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.imageScaling = .scaleAxesIndependently
        view.image = wallpaper(size: screen.frame.size, scale: screen.backingScaleFactor)
        window.contentView = view
        window.orderFrontRegardless()
        // The part of the screen below the menu bar, which is what the camera may show. The Dock is
        // hidden for a take, so it reaches the bottom.
        let visible = screen.visibleFrame
        let top = screen.frame.maxY - visible.maxY
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            say("ready \(visible.minX) \(top) \(visible.width) \(visible.height)")
        }
        Thread.detachNewThread {
            while let line = readLine() {
                if line == "quit" { break }
            }
            exit(0)
        }
    }

    /// Two soft glows over a near-black plum, with a little noise so the gradient does not band once
    /// the video is compressed.
    func wallpaper(size: NSSize, scale: CGFloat) -> NSImage {
        let w = Int(size.width * scale), h = Int(size.height * scale)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0.055, green: 0.027, blue: 0.047, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        func glow(_ x: Double, _ y: Double, _ radius: Double, _ r: Double, _ g: Double, _ b: Double, _ a: Double) {
            let colors = [CGColor(srgbRed: r, green: g, blue: b, alpha: a), CGColor(srgbRed: r, green: g, blue: b, alpha: 0)] as CFArray
            let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
            let centre = CGPoint(x: x * Double(w), y: (1 - y) * Double(h))
            ctx.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre,
                                   endRadius: radius * Double(w), options: [])
        }
        glow(0.66, 0.3, 0.62, 0.30, 0.09, 0.22, 0.85)
        glow(0.18, 0.85, 0.5, 0.14, 0.07, 0.2, 0.7)
        let data = ctx.data!.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * h)
        var seed: UInt64 = 0x9e3779b97f4a7c15
        for i in stride(from: 0, to: ctx.bytesPerRow * h, by: 4) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let n = Int((seed >> 60) & 3) - 1
            for c in 0..<3 { data[i + c] = UInt8(clamping: Int(data[i + c]) + n) }
        }
        return NSImage(cgImage: ctx.makeImage()!, size: size)
    }
}

// MARK: windows

func frontWindow(of pid: pid_t) -> AXUIElement {
    let app = AXUIElementCreateApplication(pid)
    var value: CFTypeRef?
    for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
        if AXUIElementCopyAttributeValue(app, attribute as CFString, &value) == .success, let value {
            return (value as! AXUIElement)
        }
    }
    if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
       let windows = value as? [AXUIElement], let first = windows.first {
        return first
    }
    fail("stage: process \(pid) has no window, or this process is not trusted for Accessibility")
}

func frame(of element: AXUIElement) -> CGRect? {
    var p: CFTypeRef?, s: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &p) == .success,
          AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &s) == .success else { return nil }
    var point = CGPoint.zero, size = CGSize.zero
    AXValueGetValue(p as! AXValue, .cgPoint, &point)
    AXValueGetValue(s as! AXValue, .cgSize, &size)
    return CGRect(origin: point, size: size)
}

func place(_ pid: pid_t, _ rect: CGRect) {
    let window = frontWindow(of: pid)
    var point = rect.origin, size = rect.size
    // Size, move, then size again: a window that does not fit where it is refuses the full size.
    for _ in 0..<2 {
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &point)!)
    }
    AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
    guard let now = frame(of: window) else { fail("stage: cannot read the window's frame") }
    say("\(now.minX) \(now.minY) \(now.width) \(now.height)")
}

func fields(_ pid: pid_t) {
    let app = AXUIElementCreateApplication(pid)
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
          let windows = value as? [AXUIElement] else { fail("stage: cannot list the windows of \(pid)") }
    func walk(_ element: AXUIElement, depth: Int) {
        guard depth < 40 else { return }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        if (role as? String) == (kAXTextFieldRole as String), let f = frame(of: element) {
            say("\(f.minX) \(f.minY) \(f.width) \(f.height)")
        }
        var children: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
           let children = children as? [AXUIElement] {
            for child in children { walk(child, depth: depth + 1) }
        }
    }
    for window in windows { walk(window, depth: 0) }
}

// MARK: owner

func owner(x: Double, y: Double) {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    for w in list {
        guard let b = w[kCGWindowBounds as String] as? [String: Double],
              (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
              // The Dock's window spans the whole screen on macOS 15 and passes clicks through.
              w[kCGWindowOwnerName as String] as? String != "Dock",
              // While the screen is recorded, the pointer is a window of its own.
              w[kCGWindowLayer as String] as? Int32 != CGWindowLevelForKey(.cursorWindow) else { continue }
        if x >= b["X"]! && x < b["X"]! + b["Width"]! && y >= b["Y"]! && y < b["Y"]! + b["Height"]! {
            say("\(w[kCGWindowOwnerName as String] ?? "?") pid=\(w[kCGWindowOwnerPID as String] ?? 0) layer=\(w[kCGWindowLayer as String] ?? 0)")
            return
        }
    }
    say("none")
}

// MARK: pasteboard

func pasteboard(_ action: String, _ dir: URL) {
    let pb = NSPasteboard.general
    let manifestURL = dir.appendingPathComponent("manifest.json")
    if action == "save" {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var manifest: [[String]] = []
        for (i, item) in (pb.pasteboardItems ?? []).enumerated() {
            var types: [String] = []
            for (j, type) in item.types.enumerated() {
                guard let data = item.data(forType: type) else { continue }
                do { try data.write(to: dir.appendingPathComponent("\(i)-\(j)")) } catch { fail("stage: \(error)") }
                types.append(type.rawValue)
            }
            manifest.append(types)
        }
        do { try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL) } catch { fail("stage: \(error)") }
        say("saved items=\(manifest.count)")
    } else {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [[String]] else { fail("stage: no saved pasteboard in \(dir.path)") }
        let items: [NSPasteboardItem] = manifest.enumerated().map { i, types in
            let item = NSPasteboardItem()
            for (j, type) in types.enumerated() {
                if let data = try? Data(contentsOf: dir.appendingPathComponent("\(i)-\(j)")) {
                    item.setData(data, forType: NSPasteboard.PasteboardType(type))
                }
            }
            return item
        }
        pb.clearContents()
        pb.writeObjects(items)
        say("restored items=\(items.count)")
    }
}

let args = CommandLine.arguments
func pid(_ text: String) -> pid_t {
    guard let value = pid_t(text) else { fail("stage: \(text) is not a pid") }
    return value
}
switch args.count > 1 ? args[1] : "" {
case "desktop":
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = Desktop()
    app.delegate = delegate
    app.run()
case "place":
    guard args.count == 7, let x = Double(args[3]), let y = Double(args[4]), let w = Double(args[5]), let h = Double(args[6])
    else { fail("usage: stage place <pid> <x> <y> <w> <h>") }
    place(pid(args[2]), CGRect(x: x, y: y, width: w, height: h))
case "frame":
    guard args.count == 3 else { fail("usage: stage frame <pid>") }
    guard let f = frame(of: frontWindow(of: pid(args[2]))) else { fail("stage: cannot read the window's frame") }
    say("\(f.minX) \(f.minY) \(f.width) \(f.height)")
case "fields":
    guard args.count == 3 else { fail("usage: stage fields <pid>") }
    fields(pid(args[2]))
case "owner":
    guard args.count == 4, let x = Double(args[2]), let y = Double(args[3]) else { fail("usage: stage owner <x> <y>") }
    owner(x: x, y: y)
case "pasteboard":
    guard args.count == 4, ["save", "restore"].contains(args[2]) else { fail("usage: stage pasteboard save|restore <dir>") }
    pasteboard(args[2], URL(fileURLWithPath: args[3]))
default:
    fail("usage: stage desktop | place <pid> <x> <y> <w> <h> | frame <pid> | fields <pid> | owner <x> <y> | pasteboard save|restore <dir>")
}
