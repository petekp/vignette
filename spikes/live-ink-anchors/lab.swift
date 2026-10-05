// Anchor lab: pins marks to real windows and follows them two ways at once.
// Hold Right Option alone for half a second and let go: a pin goes where the pointer is, on the window under it.
//   magenta ring  follows the content through Accessibility (a text range, a web text marker, or the element)
//   cyan ring     follows the content by registering captures of that window (never saved or sent)
// Each annotated window gets its own overlay window, ordered just above it, so other windows cover the marks.
// stdin: clear | stats | quit
import AppKit
import ScreenCaptureKit
import CoreMedia

setvbuf(stdout, nil, _IOLBF, 0)
func now() -> Double { CACurrentMediaTime() }
func ms(_ t: Double) -> String { String(format: "%.2f", t * 1000) }
let primaryHeight = NSScreen.screens[0].frame.height

struct Cost { var n = 0; var sum = 0.0; var max = 0.0
    mutating func add(_ v: Double) { n += 1; sum += v; if v > max { max = v } }
    var text: String { n == 0 ? "-" : "mean \(ms(sum / Double(n))) max \(ms(max)) ms (\(n))" } }

typealias ListCreate = @convention(c) (UInt32, UInt32) -> Unmanaged<CFArray>?
let listCreate = unsafeBitCast(dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreate"), to: ListCreate.self)
func windowIDs(_ option: CGWindowListOption, _ id: CGWindowID) -> [CGWindowID] {
    guard let array = listCreate(option.rawValue, id)?.takeRetainedValue() else { return [] }
    return (0..<CFArrayGetCount(array)).map { CGWindowID(UInt(bitPattern: CFArrayGetValueAtIndex(array, $0))) }
}
func describe(_ ids: [CGWindowID]) -> [[String: Any]] {
    var values = ids.map { UnsafeRawPointer(bitPattern: UInt($0)) }
    let array = CFArrayCreate(nil, &values, values.count, nil)
    return CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]] ?? []
}
func bounds(_ d: [String: Any]) -> CGRect { CGRect(dictionaryRepresentation: d[kCGWindowBounds as String] as! CFDictionary)! }

final class Flipped: NSView { override var isFlipped: Bool { true } }

// MARK: Accessibility anchors

func attr(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
}
func param(_ e: AXUIElement, _ name: String, _ p: CFTypeRef) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyParameterizedAttributeValue(e, name as CFString, p, &v) == .success ? v : nil
}
func rectValue(_ v: CFTypeRef?) -> CGRect? {
    guard let v, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var r = CGRect.zero
    return AXValueGetValue(v as! AXValue, .cgRect, &r) ? r : nil
}
func frameOf(_ e: AXUIElement) -> CGRect? {
    guard let p = attr(e, kAXPositionAttribute), let s = attr(e, kAXSizeAttribute) else { return nil }
    var point = CGPoint.zero, size = CGSize.zero
    AXValueGetValue(p as! AXValue, .cgPoint, &point)
    AXValueGetValue(s as! AXValue, .cgSize, &size)
    return CGRect(origin: point, size: size)
}

// A line of a text view that gives its visible text but no positions (Ghostty): found again by its
// words, with the lines round it to tell repeats apart, and placed by row on a uniform grid.
final class LineAnchor {
    let element: AXUIElement
    let line: String, before: String, after: String
    var row: Int
    init(element: AXUIElement, line: String, before: String, after: String, row: Int) {
        self.element = element; self.line = line; self.before = before; self.after = after; self.row = row
    }

    static func lines(_ e: AXUIElement) -> [String]? {
        (attr(e, kAXValueAttribute) as? String).map { $0.components(separatedBy: "\n") }
    }

    func rect() -> CGRect? {
        guard let lines = LineAnchor.lines(element), let frame = frameOf(element), !lines.isEmpty else { return nil }
        var best: (row: Int, score: Int)?
        for (i, l) in lines.enumerated() where l == line {
            var score = 4
            if i > 0, lines[i - 1] == before { score += 2 }
            if i + 1 < lines.count, lines[i + 1] == after { score += 2 }
            score -= min(3, abs(i - row) / 10)
            if best == nil || score > best!.score { best = (i, score) }
        }
        guard let found = best else { return nil }
        row = found.row
        let height = frame.height / CGFloat(lines.count)
        return CGRect(x: frame.minX, y: frame.minY + CGFloat(row) * height, width: frame.width, height: height)
    }
}

enum AXAnchor {
    case line(LineAnchor)
    case range(AXUIElement, CFRange)
    case marker(AXUIElement, CFTypeRef)        // a text marker range of one character
    case element(AXUIElement)

    var name: String {
        switch self { case .line: "terminal line"; case .range: "text range"; case .marker: "text marker"; case .element: "element" }
    }

    func rect() -> CGRect? {
        switch self {
        case .range(let e, var r): return rectValue(param(e, kAXBoundsForRangeParameterizedAttribute, AXValueCreate(.cfRange, &r)!))
        case .marker(let e, let m): return rectValue(param(e, "AXBoundsForTextMarkerRange", m))
        case .element(let e): return frameOf(e)
        case .line(let l): return l.rect()
        }
    }

    static func at(_ point: CGPoint, pid: pid_t) -> (AXAnchor, CGRect, AXUIElement?)? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit) == .success, let e = hit else { return nil }
        let role = attr(e, kAXRoleAttribute) as? String ?? "?"
        print("ax hit role=\(role)")
        var p = point
        let pv = AXValueCreate(.cgPoint, &p)!
        let scroll = enclosing(e, role: "AXScrollArea")
        if let rv = param(e, kAXRangeForPositionParameterizedAttribute, pv) {
            var r = CFRange()
            AXValueGetValue(rv as! AXValue, .cfRange, &r)
            r.length = 1
            let a = AXAnchor.range(e, r)
            if let rect = a.rect(), rect.width > 0, rect.insetBy(dx: -40, dy: -40).contains(point) { return (a, rect, scroll) }
        }
        if let m = param(e, "AXTextMarkerForPosition", pv),
           let next = param(e, "AXNextTextMarkerForTextMarker", m),
           let range = param(e, "AXTextMarkerRangeForUnorderedTextMarkers", [m, next] as CFArray) {
            let a = AXAnchor.marker(e, range)
            if let rect = a.rect(), rect.width > 0, rect.insetBy(dx: -40, dy: -40).contains(point) { return (a, rect, scroll) }
        }
        var names: CFArray?
        AXUIElementCopyParameterizedAttributeNames(e, &names)
        let hasBounds = ((names as? [String]) ?? []).contains(kAXBoundsForRangeParameterizedAttribute)
        if !hasBounds, let lines = LineAnchor.lines(e), lines.count > 2, let frame = frameOf(e) {
            let height = frame.height / CGFloat(lines.count)
            let row = Int((point.y - frame.minY) / height)
            if row >= 0, row < lines.count, !lines[row].trimmingCharacters(in: .whitespaces).isEmpty {
                let anchor = LineAnchor(element: e, line: lines[row], before: row > 0 ? lines[row - 1] : "",
                                        after: row + 1 < lines.count ? lines[row + 1] : "", row: row)
                if let rect = anchor.rect() { return (AXAnchor.line(anchor), rect, scroll) }
            } else {
                print("ax: blank terminal line; no line anchor")
            }
        }
        let a = AXAnchor.element(e)
        if let rect = a.rect(), rect.width * rect.height < 400_000 { return (a, rect, scroll) }
        return nil
    }

    static func enclosing(_ e: AXUIElement, role: String) -> AXUIElement? {
        var current: AXUIElement? = e
        for _ in 0..<20 {
            guard let c = current else { return nil }
            if attr(c, kAXRoleAttribute) as? String == role { return c }
            current = attr(c, kAXParentAttribute).map { $0 as! AXUIElement }
        }
        return nil
    }
}

// MARK: Visual follower

// Follows the content under a pin by registering captures of its window. While the window is being
// resized it stops (the frames are scaled to the old size) and reports itself hidden; once the size has
// held for a moment it searches the new frame in x and y for the content it last had, and shows again
// only if it found it.
final class Follower: NSObject, SCStreamOutput, SCStreamDelegate {
    enum State: String { case tracking, resizing, lost }
    var stream: SCStream?
    let queue = DispatchQueue(label: "vis")
    var key: [UInt8] = []
    var w = 0, h = 0
    var expected = (w: 0, h: 0)
    var keyShift = 0, lastS = 0, velocity = 0
    var shiftX = 0                      // pixels the content moved right, from relocations
    var scale = 2.0
    var anchor = CGPoint.zero
    var cost = Cost(), relocate = Cost()
    var rekeys = 0, relocations = 0, failures = 0, attempts = 0
    var awaitingSize = false     // frames until the stream is reconfigured are scaled to the old size
    var state = State.tracking
    var filter: SCContentFilter?
    var resizeGeneration = 0
    var onMove: ((CGPoint, State) -> Void)?    // (dx right, dy up) in points, and the state

    func start(window: SCWindow, anchor: CGPoint) async throws {
        self.anchor = anchor
        let filter = SCContentFilter(desktopIndependentWindow: window)
        self.filter = filter
        scale = Double(filter.pointPixelScale)
        let s = SCStream(filter: filter, configuration: config(window.frame.size), delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await s.startCapture()
        stream = s
    }

    func config(_ size: CGSize) -> SCStreamConfiguration {
        let c = SCStreamConfiguration()
        c.width = Int(size.width * scale)
        c.height = Int(size.height * scale)
        c.minimumFrameInterval = CMTime(value: 1, timescale: 120)
        c.pixelFormat = kCVPixelFormatType_32BGRA
        c.showsCursor = false
        c.queueDepth = 5
        queue.async { self.expected = (c.width, c.height) }
        return c
    }

    // Called on every size change; the stream is reconfigured once the size has held for 0.15 s.
    func resized(to size: CGSize) {
        resizeGeneration += 1
        let generation = resizeGeneration
        queue.async { self.awaitingSize = true; if self.state != .resizing { self.state = .resizing; self.report() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard generation == self.resizeGeneration, let s = self.stream else { return }
            s.updateConfiguration(self.config(size)) { error in
                if let error { print("vis reconfigure: \(error.localizedDescription)") }
                self.queue.async { if generation == self.resizeGeneration { self.awaitingSize = false } }
            }
        }
    }

    func stop() { stream?.stopCapture { _ in }; stream = nil }
    func stream(_ stream: SCStream, didStopWithError error: Error) { print("vis stopped: \(error.localizedDescription)") }

    var position: CGPoint { CGPoint(x: Double(shiftX) / scale, y: Double(keyShift + lastS) / scale) }
    func report() {
        let p = position, s = state
        DispatchQueue.main.async { self.onMove?(p, s) }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = (attachments.first?[.status] as? Int).flatMap(SCFrameStatus.init(rawValue:)), status == .complete,
              let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
        let t0 = now()
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        let fw = CVPixelBufferGetWidth(buffer), fh = CVPixelBufferGetHeight(buffer), row = CVPixelBufferGetBytesPerRow(buffer)
        guard fw == expected.w, fh == expected.h else { CVPixelBufferUnlockBaseAddress(buffer, .readOnly); return }
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        var gray = [UInt8](repeating: 0, count: fw * fh)
        for y in 0..<fh { let p = base + y * row; for x in 0..<fw { gray[y * fw + x] = p[x * 4 + 1] } }
        CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        defer { cost.add(now() - t0) }
        if key.isEmpty { key = gray; w = fw; h = fh; return }
        if fw != w || fh != h || state != .tracking {
            // A new size, or still lost: look for the content the last good reference held. A lost pin
            // stays hidden until that is found; it never resumes from a reference taken after it was lost.
            guard !awaitingSize, state == .resizing || (state == .lost && attempts % 6 == 0) else { attempts += 1; return }
            attempts += 1
            let r0 = now()
            let found = locate(in: gray, fw, fh)
            relocate.add(now() - r0)
            if let (dx, dy) = found {
                shiftX += dx; keyShift += lastS + dy; lastS = 0; velocity = 0
                key = gray; w = fw; h = fh
                relocations += 1
                state = .tracking
                print("vis relocated: dx \(dx) dy \(dy) px in \(ms(now() - r0)) ms")
                report()
            } else if state == .resizing {
                failures += 1
                state = .lost
                print("vis not found after resize (\(ms(now() - r0)) ms); hidden until found")
                report()
            }
            return
        }
        let cx = Int(anchor.x * scale) + shiftX
        let cy = min(max(Int(anchor.y * scale) - keyShift, 260), h - 220)
        let x0 = max(0, cx - 500), x1 = min(w - 40, cx + 500)
        let y0 = max(0, cy - 180), y1 = min(h, cy + 180)
        guard x1 - x0 > 80, y1 - y0 > 80 else { return }
        let predicted = lastS + velocity
        var best = (s: lastS, d: Double.infinity)
        for s in (predicted - 80)...(predicted + 80) {
            var d = 0, n = 0
            var y = y0
            while y < y1 {
                let cyy = y - s
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
        // Content that changed in place (new output, video, typing) gives no clean match: keep the last shift.
        guard best.d < 6 else { return }
        let moved = best.s != lastS
        velocity = best.s - lastS
        lastS = best.s
        if abs(lastS) > 200 { keyShift += lastS; lastS = 0; key = gray; rekeys += 1 }
        if moved { report() }
    }

    // Searches the new frame for the patch round the pin in the last reference, coarsely at a quarter of
    // the resolution, then exactly. Nil when nothing matches well.
    func locate(in gray: [UInt8], _ fw: Int, _ fh: Int) -> (Int, Int)? {
        let cx = Int(anchor.x * scale) + shiftX
        let cy = Int(anchor.y * scale) - keyShift - lastS
        let px0 = max(0, cx - 300), px1 = min(w, cx + 300)
        let py0 = max(0, cy - 120), py1 = min(h, cy + 120)
        guard px1 - px0 > 80, py1 - py0 > 80 else { return nil }
        let k = key, kw = w
        func score(_ dx: Int, _ dy: Int, step: Int, limit: Double) -> Double {
            k.withUnsafeBufferPointer { kp in gray.withUnsafeBufferPointer { gp in
                var d = 0, n = 0
                var y = py0
                while y < py1 {
                    let ny = y + dy
                    if ny >= 0 && ny < fh {
                        var x = max(px0, -dx)
                        let end = min(px1, fw - dx)
                        let krow = y * kw, grow = ny * fw + dx
                        while x < end { d += abs(Int(kp[krow + x]) - Int(gp[grow + x])); n += 1; x += step }
                    }
                    y += step
                }
                return n > (px1 - px0) * (py1 - py0) / (step * step) / 2 ? Double(d) / Double(n) : .infinity
            } }
        }
        // Content stays put, follows the bottom edge or stays centred, so it moves by at most the size change.
        let reach = abs(fw - w) + 60, reachY = abs(fh - h) + 60
        var best = (dx: 0, dy: 0, d: Double.infinity)
        var dy = -reachY
        while dy <= reachY {
            var dx = -reach
            while dx <= reach {
                let d = score(dx, dy, step: 8, limit: best.d)
                if d < best.d { best = (dx, dy, d) }
                dx += 4
            }
            dy += 4
        }
        let coarse = best
        for dy in (coarse.dy - 4)...(coarse.dy + 4) {
            for dx in (coarse.dx - 4)...(coarse.dx + 4) {
                let d = score(dx, dy, step: 2, limit: best.d)
                if d < best.d { best = (dx, dy, d) }
            }
        }
        // dy is how far the content moved down; the shift counts movement up.
        return best.d < 8 ? (best.dx, -best.dy) : nil
    }
}

// MARK: Pins and overlays

final class Pin {
    let number: Int
    var ax: AXAnchor?
    var axOffset = CGPoint.zero       // pinned point minus the anchor rect's origin
    var axLost = false
    var scrollArea: AXUIElement?
    var windowOffset: CGPoint         // pinned point from the window's top-left, at shift 0
    var follower = Follower()
    var vision = CGPoint.zero        // content movement found by the follower: x right, y up
    var visionState = Follower.State.tracking
    let axRing = CAShapeLayer(), visRing = CAShapeLayer(), label = CATextLayer()
    var axCost = Cost()
    var apart = Cost()     // distance between the two rings, in points (stored in the "seconds" field)

    init(number: Int, windowOffset: CGPoint) {
        self.number = number
        self.windowOffset = windowOffset
        for (ring, color) in [(axRing, CGColor(red: 1, green: 0, blue: 1, alpha: 1)), (visRing, CGColor(red: 0, green: 0.85, blue: 1, alpha: 1))] {
            ring.fillColor = nil
            ring.strokeColor = color
            ring.lineWidth = 3
            ring.bounds = CGRect(x: 0, y: 0, width: 44, height: 30)
            ring.path = CGPath(ellipseIn: ring.bounds.insetBy(dx: 2, dy: 2), transform: nil)
            ring.shadowOpacity = 0.6; ring.shadowRadius = 2; ring.shadowOffset = .zero
        }
        label.string = "\(number)"
        label.fontSize = 12
        label.foregroundColor = .white
        label.backgroundColor = CGColor(red: 1, green: 0, blue: 1, alpha: 1)
        label.cornerRadius = 8
        label.alignmentMode = .center
        label.bounds = CGRect(x: 0, y: 0, width: 16, height: 16)
        label.contentsScale = 2
    }
}

final class Overlay {
    let target: CGWindowID
    let pid: pid_t
    let window: NSWindow
    let root: CALayer
    let clip = CALayer()
    var frame: CGRect
    var pins: [Pin] = []
    var onScreen = true
    var reorders = 0

    init(target: CGWindowID, pid: pid_t, frame: CGRect) {
        self.target = target
        self.pid = pid
        self.frame = frame
        window = NSWindow(contentRect: Overlay.appKit(frame), styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .normal
        window.animationBehavior = .none
        window.collectionBehavior = [.moveToActiveSpace, .transient, .ignoresCycle]
        let view = Flipped(frame: CGRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        window.contentView = view
        root = view.layer!
        root.masksToBounds = true
        window.order(.above, relativeTo: Int(target))
    }

    static func appKit(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height) }
    func local(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - frame.minX, y: p.y - frame.minY) }
}

final class Lab: NSObject {
    var overlays: [CGWindowID: Overlay] = [:]
    var link: CADisplayLink?
    var count = 0
    var tick = Cost(), list = Cost(), z = Cost()
    var optionDown: Double?
    var otherKey = false

    func start() {
        link = NSScreen.screens[0].displayLink(target: self, selector: #selector(step))
        link!.add(to: .main, forMode: .common)
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] e in self?.flags(e) }
        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .scrollWheel]) { [weak self] e in
            if e.type != .scrollWheel { self?.otherKey = true }
        }
        Thread.detachNewThread { while let l = readLine() { DispatchQueue.main.async { self.command(l) } } }
        print("lab ready: hold Right Option alone for half a second and let go to pin")
    }

    func flags(_ e: NSEvent) {
        let rightOption = e.keyCode == 61
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .function, .numericPad])
        if rightOption && mods == .option { optionDown = now(); otherKey = false; return }
        if rightOption && mods.isEmpty, let down = optionDown {
            optionDown = nil
            if now() - down >= 0.45 && !otherKey { pin(at: NSEvent.mouseLocation) }
            return
        }
        optionDown = nil
    }

    func pin(at mouse: NSPoint) {
        let point = CGPoint(x: mouse.x, y: primaryHeight - mouse.y)
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        guard let info = infos.first(where: {
            ($0[kCGWindowLayer as String] as? Int) == 0 && ($0[kCGWindowOwnerPID as String] as? pid_t) != getpid()
                && bounds($0).contains(point) && (($0[kCGWindowAlpha as String] as? Double) ?? 1) > 0
        }) else { print("no window under the pointer"); return }
        let id = info[kCGWindowNumber as String] as! CGWindowID
        let pid = info[kCGWindowOwnerPID as String] as! pid_t
        let frame = bounds(info)
        count += 1
        let pin = Pin(number: count, windowOffset: CGPoint(x: point.x - frame.minX, y: point.y - frame.minY))
        let t0 = now()
        if let (anchor, rect, scroll) = AXAnchor.at(point, pid: pid) {
            pin.ax = anchor
            pin.axOffset = CGPoint(x: point.x - rect.minX, y: point.y - rect.minY)
            pin.scrollArea = scroll
            print("pin \(count) on \(info[kCGWindowOwnerName as String] ?? "?") window \(id): AX \(anchor.name) \(rect.integral) scrollArea=\(scroll != nil) in \(ms(now() - t0)) ms")
        } else {
            print("pin \(count) on \(info[kCGWindowOwnerName as String] ?? "?") window \(id): no AX anchor (\(ms(now() - t0)) ms)")
        }
        let overlay = overlays[id] ?? Overlay(target: id, pid: pid, frame: frame)
        overlays[id] = overlay
        overlay.pins.append(pin)
        if pin.ax != nil { overlay.root.addSublayer(pin.axRing) }
        overlay.root.addSublayer(pin.visRing)
        overlay.root.addSublayer(pin.label)
        place(pin, in: overlay)
        pin.follower.onMove = { [weak self, weak overlay] p, state in
            pin.vision = p
            if state != pin.visionState { print("pin \(pin.number): visual \(state.rawValue)") }
            pin.visionState = state
            if let self, let overlay { self.place(pin, in: overlay) }
        }
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let w = content.windows.first(where: { $0.windowID == id }) else { print("vis: window not shareable"); return }
                try await pin.follower.start(window: w, anchor: pin.windowOffset)
            } catch { print("vis error \(error.localizedDescription)") }
        }
    }

    func place(_ pin: Pin, in overlay: Overlay) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let visual = overlay.local(CGPoint(x: overlay.frame.minX + pin.windowOffset.x + pin.vision.x, y: overlay.frame.minY + pin.windowOffset.y - pin.vision.y))
        pin.visRing.isHidden = pin.visionState != .tracking
        pin.visRing.position = visual
        pin.label.position = CGPoint(x: visual.x + 24, y: visual.y - 14)
        if let anchor = pin.ax {
            let t = now()
            let rect = anchor.rect()
            pin.axCost.add(now() - t)
            if let r = rect, r.width > 0 || r.height > 0 {
                if pin.axLost { print("pin \(pin.number): AX anchor back") }
                pin.axLost = false
                var p = CGPoint(x: r.minX + pin.axOffset.x, y: r.minY + pin.axOffset.y)
                var visible = true
                if let area = pin.scrollArea, let f = frameOf(area) { visible = f.insetBy(dx: -4, dy: -4).contains(p) }
                pin.axRing.isHidden = !visible
                p = overlay.local(p)
                pin.axRing.position = p
                if visible { pin.apart.add(hypot(p.x - visual.x, p.y - visual.y) / 1000) }
            } else if !pin.axLost {
                pin.axLost = true
                pin.axRing.isHidden = true
                print("pin \(pin.number): AX anchor lost")
            }
        }
        CATransaction.commit()
    }

    @objc func step(_ l: CADisplayLink) {
        guard !overlays.isEmpty else { return }
        let t0 = now()
        let infos = describe(Array(overlays.keys))
        list.add(now() - t0)
        var seen = Set<CGWindowID>()
        for d in infos {
            let id = d[kCGWindowNumber as String] as! CGWindowID
            guard let o = overlays[id] else { continue }
            seen.insert(id)
            let visible = (d[kCGWindowIsOnscreen as String] as? Bool) ?? false
            if visible != o.onScreen {
                o.onScreen = visible
                print(String(format: "%.3f window %d onscreen=%@", now(), id, visible ? "yes" : "no"))
                if visible { o.window.order(.above, relativeTo: Int(id)) } else { o.window.orderOut(nil) }
            }
            guard visible else { continue }
            let f = bounds(d)
            if f != o.frame {
                let resized = f.size != o.frame.size
                o.frame = f
                o.window.setFrame(Overlay.appKit(f), display: false)
                if resized { o.pins.forEach { $0.follower.resized(to: f.size) } }
            }
            for pin in o.pins { place(pin, in: o) }
            let z0 = now()
            let above = windowIDs(.optionOnScreenAboveWindow, id)
            let mine = CGWindowID(o.window.windowNumber)
            var inPlace = false
            if let i = above.lastIndex(of: mine) {
                let between = Array(above[(i + 1)...])
                inPlace = between.isEmpty || describe(between).allSatisfy { ($0[kCGWindowOwnerPID as String] as? pid_t) == o.pid }
            }
            if !inPlace {
                o.window.order(.above, relativeTo: Int(id))
                o.reorders += 1
            }
            z.add(now() - z0)
        }
        for (id, o) in overlays where !seen.contains(id) {
            print("window \(id) closed; dropping its \(o.pins.count) pins")
            o.pins.forEach { $0.follower.stop() }
            o.window.orderOut(nil)
            overlays[id] = nil
        }
        tick.add(now() - t0)
    }

    func command(_ line: String) {
        switch line {
        case "clear":
            for o in overlays.values { o.pins.forEach { $0.follower.stop() }; o.window.orderOut(nil) }
            overlays = [:]
            print("cleared")
        case "stats":
            print("tick \(tick.text) | list \(list.text) | z \(z.text)")
            for o in overlays.values {
                for p in o.pins {
                    print("  pin \(p.number) window \(o.target) ax=\(p.ax?.name ?? "none") \(p.axCost.text) lost=\(p.axLost) | vis \(p.follower.cost.text) at \(p.vision) \(p.visionState.rawValue) rekeys \(p.follower.rekeys) relocations \(p.follower.relocations) failed \(p.follower.failures) relocate \(p.follower.relocate.text) | apart(pt) \(p.apart.text) | reorders \(o.reorders)")
                    p.axCost = Cost(); p.follower.cost = Cost(); p.apart = Cost()
                }
            }
            tick = Cost(); list = Cost(); z = Cost()
        case "quit": exit(0)
        default: if line.hasPrefix("pin ") {
            let n = line.split(separator: " ").compactMap { Double($0) }
            if n.count == 2 { pin(at: NSPoint(x: n[0], y: primaryHeight - n[1])) }
        }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let lab = Lab()
DispatchQueue.main.async { lab.start() }
app.run()
