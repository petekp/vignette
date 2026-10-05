// Probe: a mark on another process's window that sits in that window's layer and follows it.
// overlay <target pid> [ax] [rec] [noreorder] [mask]
//   ax         anchor to the green block through Accessibility (AXBoundsForRange), not a fixed window offset
//   rec        record only the two probe apps with ScreenCaptureKit and log, per frame, ring centre minus block centre
//   noreorder  never re-order the overlay above the target
//   mask       clip the mark to the target's frame
// Commands on stdin: stats | quit
import AppKit
import ScreenCaptureKit
import CoreMedia
import CoreImage

setvbuf(stdout, nil, _IOLBF, 0)
let args = CommandLine.arguments
let targetPid = pid_t(args[1])!
let useAX = args.contains("ax")
let useVision = args.contains("vis")
let debug = args.contains("debug")
let record = args.contains("rec")
let reorder = !args.contains("noreorder")
let useMask = args.contains("mask")
let alsoPids = args.compactMap { $0.hasPrefix("also=") ? pid_t($0.dropFirst(5)) : nil }
var snapName: String?

func ms(_ t: Double) -> String { String(format: "%.2f", t * 1000) }
func now() -> Double { CACurrentMediaTime() }

// CGWindowListCreate returns window numbers only, without the dictionaries; Swift marks it unavailable.
typealias ListCreate = @convention(c) (UInt32, UInt32) -> Unmanaged<CFArray>?
let listCreate = unsafeBitCast(dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreate"), to: ListCreate.self)
func windowIDs(_ option: CGWindowListOption, _ id: CGWindowID) -> [CGWindowID] {
    guard let array = listCreate(option.rawValue, id)?.takeRetainedValue() else { return [] }
    return (0..<CFArrayGetCount(array)).map { CGWindowID(UInt(bitPattern: CFArrayGetValueAtIndex(array, $0))) }
}

func owners(_ ids: [CGWindowID]) -> [pid_t] {
    var values = ids.map { UnsafeRawPointer(bitPattern: UInt($0)) }
    let array = CFArrayCreate(nil, &values, values.count, nil)
    return (CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]] ?? []).map { $0[kCGWindowOwnerPID as String] as? pid_t ?? 0 }
}

final class Flipped: NSView { override var isFlipped: Bool { true } }

struct Cost { var n = 0; var sum = 0.0; var max = 0.0
    mutating func add(_ v: Double) { n += 1; sum += v; if v > max { max = v } }
    var text: String { n == 0 ? "-" : "mean \(ms(sum / Double(n))) max \(ms(max)) ms" } }

final class Probe: NSObject {
    var window: NSWindow!
    var ring = CAShapeLayer()
    var mask = CALayer()
    var targetID: CGWindowID = 0
    var offset = CGPoint.zero          // ring centre from the target window's top-left, window mode
    var ringSize = CGSize(width: 64, height: 40)
    var textArea: AXUIElement?
    var blockRange = CFRange(location: 0, length: 4)
    var link: CADisplayLink?
    // The description call takes raw window numbers as the array's values, not CFNumbers.
    lazy var idArray: CFArray = {
        var value = UnsafeRawPointer(bitPattern: UInt(targetID))
        return CFArrayCreate(nil, &value, 1, nil)
    }()
    var bounds = Cost(), axCost = Cost(), zCost = Cost(), tick = Cost()
    var reorders = 0
    var lastReorder = 0.0
    var hiddenSince: Double?
    var onScreen = true
    var lastBounds = CGRect.zero
    var visionShift = 0.0

    func start() {
        guard let info = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]])?
            .first(where: { ($0[kCGWindowOwnerPID as String] as? pid_t) == targetPid && ($0[kCGWindowLayer as String] as? Int) == 0 })
        else { print("no target window"); exit(1) }
        targetID = info[kCGWindowNumber as String] as! CGWindowID
        let frame = CGRect(dictionaryRepresentation: info[kCGWindowBounds as String] as! CFDictionary)!
        lastBounds = frame

        let screen = NSScreen.screens[0].frame
        window = NSWindow(contentRect: screen, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .normal
        let view = Flipped(frame: CGRect(origin: .zero, size: screen.size))
        view.wantsLayer = true
        window.contentView = view
        ring.fillColor = nil
        ring.strokeColor = CGColor(red: 1, green: 0, blue: 1, alpha: 1)
        ring.lineWidth = 5
        ring.path = CGPath(ellipseIn: CGRect(origin: .zero, size: ringSize), transform: nil)
        ring.bounds = CGRect(origin: .zero, size: ringSize)
        view.layer!.addSublayer(ring)
        if useMask {
            mask.backgroundColor = .black
            view.layer!.mask = mask
        }

        if let block = axBlock() {
            offset = CGPoint(x: block.midX - frame.minX, y: block.midY - frame.minY)
            print("block \(block) offset \(offset)")
        } else {
            offset = CGPoint(x: 120, y: 120)
            print("no AX block; fixed offset")
        }
        place(frame)
        window.order(.above, relativeTo: Int(targetID))
        print("overlay window=\(window.windowNumber) above target=\(targetID)")
        link = view.displayLink(target: self, selector: #selector(step))
        link!.add(to: .main, forMode: .common)
        Thread.detachNewThread { while let l = readLine() { DispatchQueue.main.async { self.command(l) } } }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            print(String(format: "%.3f activated %@", now(), app?.localizedName ?? "?"))
        }
    }

    func axBlock() -> CGRect? {
        let app = AXUIElementCreateApplication(targetPid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let wins = value as? [AXUIElement], let win = wins.first else { print("AX: no windows"); return nil }
        textArea = find(win, role: "AXTextArea")
        guard let area = textArea else { print("AX: no text area"); return nil }
        var text: CFTypeRef?
        AXUIElementCopyAttributeValue(area, kAXValueAttribute as CFString, &text)
        if let s = text as? String, let r = s.range(of: "████") {
            blockRange = CFRange(location: s.utf16.distance(from: s.utf16.startIndex, to: r.lowerBound.samePosition(in: s.utf16)!), length: 4)
        }
        return axBounds()
    }

    func axBounds() -> CGRect? {
        guard let area = textArea else { return nil }
        var range = blockRange
        let param = AXValueCreate(.cfRange, &range)!
        var out: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(area, kAXBoundsForRangeParameterizedAttribute as CFString, param, &out) == .success else { return nil }
        var rect = CGRect.zero
        AXValueGetValue(out as! AXValue, .cgRect, &rect)
        return rect
    }

    func find(_ e: AXUIElement, role: String, depth: Int = 0) -> AXUIElement? {
        var r: CFTypeRef?
        AXUIElementCopyAttributeValue(e, kAXRoleAttribute as CFString, &r)
        if (r as? String) == role { return e }
        guard depth < 8 else { return nil }
        var kids: CFTypeRef?
        AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &kids)
        for k in (kids as? [AXUIElement]) ?? [] { if let f = find(k, role: role, depth: depth + 1) { return f } }
        return nil
    }

    func place(_ frame: CGRect, block: CGRect? = nil) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let centre = block.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: frame.minX + offset.x, y: frame.minY + offset.y - visionShift)
        ring.position = centre
        mask.frame = frame
        CATransaction.commit()
    }

    @objc func step(_ l: CADisplayLink) {
        let t0 = now()
        let desc = (CGWindowListCreateDescriptionFromArray(idArray) as? [[String: Any]])?.first
        let t1 = now()
        bounds.add(t1 - t0)
        guard let d = desc else {
            if onScreen { print(String(format: "%.3f target gone", t1)); onScreen = false; ring.isHidden = true }
            return
        }
        let visible = (d[kCGWindowIsOnscreen as String] as? Bool) ?? false
        if visible != onScreen {
            onScreen = visible
            ring.isHidden = !visible
            print(String(format: "%.3f target onscreen=%@", t1, visible ? "yes" : "no"))
        }
        let frame = CGRect(dictionaryRepresentation: d[kCGWindowBounds as String] as! CFDictionary)!
        var block: CGRect?
        if useAX {
            let a = now(); block = axBounds(); axCost.add(now() - a)
        }
        if frame != lastBounds || block != nil { place(frame, block: block) }
        lastBounds = frame

        if visible {
            let z0 = now()
            let above = windowIDs(.optionOnScreenAboveWindow, targetID)
            let mine = CGWindowID(window.windowNumber)
            // In place when only the target's own windows (title bar parts, sheets, popovers) sit between it and the overlay.
            var inPlace = false
            if let index = above.lastIndex(of: mine) {
                let between = Array(above[(index + 1)...])
                inPlace = between.isEmpty || owners(between).allSatisfy { $0 == targetPid }
            }
            zCost.add(now() - z0)
            if !inPlace {
                if hiddenSince == nil { hiddenSince = z0 }
                if reorder {
                    window.order(.above, relativeTo: Int(targetID))
                    reorders += 1
                    print(String(format: "%.3f reordered (overlay was %@)", now(), above.contains(mine) ? "above another app's window" : "below"))
                    hiddenSince = nil
                }
            } else if let h = hiddenSince {
                print(String(format: "%.3f in place again after %@ ms", z0, ms(z0 - h))); hiddenSince = nil
            }
        }
        tick.add(now() - t0)
    }

    func command(_ line: String) {
        switch line {
        case "stats":
            print("vis \(follower.cost.text) shift \(follower.shift) rekeys \(follower.rekeys)"); follower.cost = Cost()
            print("ticks \(tick.n) tick \(tick.text) | bounds \(bounds.text) | ax \(axCost.text) | z \(zCost.text) | reorders \(reorders)")
            bounds = Cost(); axCost = Cost(); zCost = Cost(); tick = Cost()
        case "quit": exit(0)
        case let l where l.hasPrefix("snap "): snapName = String(l.dropFirst(5))
        default: break
        }
    }
}

// Records the two probe apps alone and reports ring centre minus block centre per frame, in points.
final class Recorder: NSObject, SCStreamOutput {
    var stream: SCStream?
    let queue = DispatchQueue(label: "rec")
    var frames = 0

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let display = content.displays[0]
        let apps = content.applications.filter { $0.processID == targetPid || $0.processID == getpid() || alsoPids.contains($0.processID) }
        let filter = SCContentFilter(display: display, including: apps, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 120)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.colorSpaceName = CGColorSpace.sRGB
        config.queueDepth = 8
        let s = SCStream(filter: filter, configuration: config, delegate: nil)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await s.startCapture()
        stream = s
        print("recording \(display.width)x\(display.height) apps=\(apps.map(\.applicationName))")
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = (attachments.first?[.status] as? Int).flatMap(SCFrameStatus.init(rawValue:)), status == .complete,
              let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer), row = CVPixelBufferGetBytesPerRow(buffer)
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        var g = (x: 0.0, y: 0.0, n: 0.0), m = (x: 0.0, y: 0.0, n: 0.0)
        var y = 0
        while y < h {
            var x = 0
            let p = base + y * row
            while x < w {
                let b = p[x * 4], gr = p[x * 4 + 1], r = p[x * 4 + 2]
                if gr > 200 && r < 60 && b < 60 { g.x += Double(x); g.y += Double(y); g.n += 1 }
                else if r > 200 && b > 200 && gr < 60 { m.x += Double(x); m.y += Double(y); m.n += 1 }
                x += 1
            }
            y += 1
        }
        frames += 1
        if let name = snapName {
            snapName = nil
            let image = CIImage(cvPixelBuffer: buffer)
            let rep = NSBitmapImageRep(ciImage: image)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: name))
        }
        let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        if g.n > 10 && m.n > 10 {
            let gx = g.x / g.n, gy = g.y / g.n, mx = m.x / m.n, my = m.y / m.n
            print(String(format: "frame %.4f block %.1f,%.1f ring %.1f,%.1f err %.1f,%.1f", t, gx, gy, mx, my, mx - gx, my - gy))
        } else {
            print(String(format: "frame %.4f block %d ring %d", t, Int(g.n), Int(m.n)))
        }
    }
}

// Follows the content under the mark by registration: captures the target window alone, in pixels, and
// finds where a reference patch round the mark has moved to. The reference is replaced only when the
// patch nears the edge of where it was taken, so error adds up once per replacement, not once per frame.
final class Follower: NSObject, SCStreamOutput {
    var stream: SCStream?
    let queue = DispatchQueue(label: "vis")
    var key: [UInt8] = []
    var keyShift = 0          // pixels of shift when the reference was taken
    var lastS = 0, velocity = 0
    var w = 0, h = 0
    var scale = 2.0
    var anchor = CGPoint.zero      // mark centre in window points from the top-left, at shift 0
    var cost = Cost()
    var rekeys = 0
    var shift: Double { Double(keyShift + lastS) / scale }
    var onShift: ((Double) -> Void)?

    func start(windowID: CGWindowID, anchor: CGPoint) async throws {
        self.anchor = anchor
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let win = content.windows.first(where: { $0.windowID == windowID }) else { print("vis: no window"); return }
        let filter = SCContentFilter(desktopIndependentWindow: win)
        scale = Double(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.width = Int(win.frame.width * scale)
        config.height = Int(win.frame.height * scale)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 120)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.queueDepth = 5
        let s = SCStream(filter: filter, configuration: config, delegate: nil)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await s.startCapture()
        stream = s
        print("vis following window \(windowID) at \(config.width)x\(config.height) scale \(scale) anchor \(anchor)")
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = (attachments.first?[.status] as? Int).flatMap(SCFrameStatus.init(rawValue:)), status == .complete,
              let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
        let t0 = now()
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        let fw = CVPixelBufferGetWidth(buffer), fh = CVPixelBufferGetHeight(buffer), row = CVPixelBufferGetBytesPerRow(buffer)
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        var gray = [UInt8](repeating: 0, count: fw * fh)
        for y in 0..<fh { let p = base + y * row; for x in 0..<fw { gray[y * fw + x] = p[x * 4 + 1] } }
        CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        defer { cost.add(now() - t0) }
        guard key.count == gray.count else { key = gray; w = fw; h = fh; keyShift = Int((Double(keyShift) )); lastS = 0; return }
        // The patch in the reference: round the mark as it was when the reference was taken.
        let cx = Int(anchor.x * scale), cy = min(max(Int(anchor.y * scale) - keyShift, 260), h - 220)
        let x0 = 0, x1 = w - 40
        let y0 = max(0, cy - 180), y1 = min(h, cy + 180)
        guard x1 - x0 > 80, y1 - y0 > 80 else { return }
        let predicted = lastS + velocity
        var best = (s: lastS, d: Double.infinity)
        for s in (predicted - 60)...(predicted + 60) {
            var d = 0, n = 0
            var y = y0
            while y < y1 {
                let cyy = y - s           // where reference row y is in this frame
                if cyy >= 0 && cyy < h {
                    var x = x0
                    while x < x1 { d += abs(Int(key[y * w + x]) - Int(gray[cyy * w + x])); n += 1; x += 3 }
                }
                y += 2
            }
            guard n > 2000 else { continue }
            let mean = Double(d) / Double(n)
            if mean < best.d { best = (s, mean) }
        }
        velocity = best.s - lastS
        lastS = best.s
        if abs(lastS) > 200 {
            keyShift += lastS; lastS = 0; key = gray; rekeys += 1
        }
        if debug { print("vis s=\(best.s) d=\(String(format: "%.1f", best.d)) total=\(shift)") }
        let total = shift
        DispatchQueue.main.async { self.onShift?(total) }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let probe = Probe()
let recorder = Recorder()
let follower = Follower()
DispatchQueue.main.async {
    probe.start()
    if record { Task { do { try await recorder.start() } catch { print("rec error \(error)") } } }
    if useVision {
        follower.onShift = { probe.visionShift = $0; probe.place(probe.lastBounds) }
        Task { do { try await follower.start(windowID: probe.targetID, anchor: probe.offset) } catch { print("vis error \(error)") } }
    }
}
app.run()
