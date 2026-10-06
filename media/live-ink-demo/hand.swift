// The demo's hand: one process that reads commands on stdin, one a line, and answers each with a
// line that starts `ok` or `error`. It holds the chord across commands, so a stroke drawn while it
// is down is ink. Points are global, top left, y down.
//
//   chord down|up                          hold or let go of ⌃⌥ (left Control, then left Option)
//   glide X Y SECONDS                      move like a hand: eased, on a slight bow; drags while pressed
//   press | release                        the left button, where the pointer is
//   click                                  press and release where the pointer is
//   loop CX CY RX RY SECONDS               glide to the loop's start, then draw it by hand, a little uneven
//   scroll DY SECONDS MOMENTUM             a trackpad scroll under the pointer; positive DY reveals what is below
//   type PID CPS TEXT                      type TEXT into that process's key window, unevenly, at about CPS
//   key PID CODE [cmd]                     a key to that process, or with PID 0 to whatever is frontmost
//   find PID TEXT                          OCR that process's windows: the box of the first line holding TEXT
//   unminimize PID                         bring that process's minimised windows back
//   windows PID                            that process's windows on screen, as JSON: title and frame
//   owner X Y PASSPID                      the pid of the topmost window under the point, passing over
//                                          PASSPID's windows at the normal level: Vignette's mark overlays,
//                                          which let every press through
import AppKit
import ApplicationServices
import ScreenCaptureKit
import Vision

setvbuf(stdout, nil, _IOLBF, 0)
let source = CGEventSource(stateID: .hidSystemState)
var flags: CGEventFlags = []
var pressed = false
var pointer = CGEvent(source: nil)?.location ?? .zero
var random = SystemRandomNumberGenerator()

func pause(_ seconds: Double) { usleep(UInt32(max(0, seconds) * 1_000_000)) }
func jitter(_ amount: Double) -> Double { Double.random(in: -amount...amount, using: &random) }

func mouse(_ type: CGEventType, _ point: CGPoint) {
    guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
    event.flags = flags
    event.post(tap: .cghidEventTap)
    pointer = point
}

func moveTo(_ point: CGPoint) { mouse(pressed ? .leftMouseDragged : .mouseMoved, point) }

func modifier(_ code: CGKeyCode, _ newFlags: CGEventFlags) {
    guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true) else { return }
    event.type = .flagsChanged
    event.flags = newFlags
    event.post(tap: .cghidEventTap)
    flags = newFlags
}

/// Eased, with the middle bowed off the straight line by a few percent of its length.
func glide(to end: CGPoint, seconds: Double) {
    let start = pointer
    let steps = max(2, Int(seconds * 120))
    let dx = end.x - start.x, dy = end.y - start.y
    let bow = (0.03 + jitter(0.015)) * (Bool.random() ? 1 : -1)
    for i in 1...steps {
        let t = Double(i) / Double(steps)
        let e = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        let lift = sin(.pi * e) * bow
        moveTo(CGPoint(x: start.x + dx * e - dy * lift, y: start.y + dy * e + dx * lift))
        pause(1.0 / 120)
    }
}

/// A loop as a hand draws one: it starts up and to the left, runs clockwise a little past where it
/// began, and its radius wanders a few percent.
func loop(center: CGPoint, rx: Double, ry: Double, seconds: Double) {
    let start = -2.0 + jitter(0.15)
    let sweep = 2 * Double.pi * (1.06 + jitter(0.03))
    let phase = jitter(3), wobble = 0.04 + jitter(0.015)
    func point(_ t: Double) -> CGPoint {
        let a = start + sweep * t
        let r = 1 + wobble * sin(3 * a + phase)
        return CGPoint(x: center.x + rx * r * cos(a), y: center.y + ry * r * sin(a))
    }
    glide(to: point(0), seconds: 0.35)
    pause(0.08)
    mouse(.leftMouseDown, point(0)); pressed = true
    let steps = max(10, Int(seconds * 120))
    for i in 1...steps {
        let t = Double(i) / Double(steps)
        moveTo(point(t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2))
        pause(1.0 / 120)
    }
    pause(0.05)
    mouse(.leftMouseUp, pointer); pressed = false
}

func scroll(_ total: Double, seconds: Double, momentum: Double) {
    func post(_ dy: Double, phase: Int64, momentumPhase: Int64) {
        guard let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 1, wheel1: Int32(dy.rounded()), wheel2: 0, wheel3: 0) else { return }
        event.location = pointer
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: dy)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: dy)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentumPhase)
        event.post(tap: .cghidEventTap)
    }
    let frame = 1.0 / 120
    let steps = max(1, Int(seconds / frame))
    post(0, phase: 128, momentumPhase: 0)
    post(0, phase: 1, momentumPhase: 0)
    // Fast in the middle of the stroke, as fingers move.
    let weights = (0..<steps).map { sin(.pi * (Double($0) + 0.5) / Double(steps)) }
    let sum = weights.reduce(0, +)
    var velocity = 0.0
    for weight in weights {
        velocity = total * weight / sum
        post(velocity, phase: 2, momentumPhase: 0)
        pause(frame)
    }
    post(0, phase: 4, momentumPhase: 0)
    guard momentum > 0 else { return }
    let n = Int(momentum / frame)
    let decay = pow(0.02, 1.0 / Double(n))
    post(velocity, phase: 0, momentumPhase: 1)
    for _ in 0..<n { velocity *= decay; post(velocity, phase: 0, momentumPhase: 2); pause(frame) }
    post(0, phase: 0, momentumPhase: 3)
}

func type(_ text: String, into pid: pid_t, rate: Double) {
    for character in text {
        let units = Array(String(character).utf16)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
            event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            event.postToPid(pid)
            pause(0.012)
        }
        pause(max(0.03, 1 / rate + jitter(0.4 / rate)) + (character == " " ? 0.05 : 0))
    }
}

func key(_ code: CGKeyCode, to pid: pid_t, command: Bool) {
    for down in [true, false] {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
        event.flags = command ? .maskCommand : []
        if pid == 0 { event.post(tap: .cghidEventTap) } else { event.postToPid(pid) }
        pause(0.03)
    }
}

/// The box of the first line holding `needle`, or of `needle` within it, in global points.
func find(_ needle: String, in pid: pid_t) async -> CGRect? {
    guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return nil }
    let windows = content.windows.filter { $0.owningApplication?.processID == pid && $0.windowLayer == 0 && $0.frame.width > 100 }
    for window in windows {
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width * 2)
        config.height = Int(window.frame.height * 2)
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config) else { continue }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image).perform([request])
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first,
                  let range = candidate.string.range(of: needle, options: .caseInsensitive) else { continue }
            let box = (try? candidate.boundingBox(for: range))?.boundingBox ?? observation.boundingBox
            let f = window.frame
            return CGRect(x: f.minX + box.minX * f.width, y: f.minY + (1 - box.maxY) * f.height,
                          width: box.width * f.width, height: box.height * f.height)
        }
    }
    return nil
}

func unminimize(_ pid: pid_t) -> Int {
    let app = AXUIElementCreateApplication(pid)
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success, let windows = value as? [AXUIElement] else { return 0 }
    var count = 0
    for window in windows {
        var minimised: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimised) == .success, (minimised as? Bool) == true {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            count += 1
        }
    }
    return count
}

func run(_ line: String) async -> String {
    let words = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    guard let command = words.first else { return "error empty" }
    let n = words.dropFirst().compactMap { Double($0) }
    switch command {
    case "chord":
        if words.count > 1, words[1] == "down" {
            modifier(59, .maskControl); pause(0.04)
            modifier(58, [.maskControl, .maskAlternate])
        } else {
            modifier(58, .maskControl); pause(0.04)
            modifier(59, [])
        }
    case "glide": glide(to: CGPoint(x: n[0], y: n[1]), seconds: n[2])
    case "press": mouse(.leftMouseDown, pointer); pressed = true
    case "release": mouse(.leftMouseUp, pointer); pressed = false
    case "click":
        mouse(.leftMouseDown, pointer); pause(0.07 + jitter(0.02)); mouse(.leftMouseUp, pointer)
    case "loop": loop(center: CGPoint(x: n[0], y: n[1]), rx: n[2], ry: n[3], seconds: n[4])
    case "scroll": scroll(n[0], seconds: n[1], momentum: n[2])
    case "type":
        guard words.count > 3, let pid = pid_t(words[1]), let rate = Double(words[2]) else { return "error type PID CPS TEXT" }
        let text = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)[3]
        type(String(text), into: pid, rate: rate)
    case "key":
        guard words.count > 2, let pid = pid_t(words[1]), let code = CGKeyCode(words[2]) else { return "error key PID CODE" }
        key(code, to: pid, command: words.contains("cmd"))
    case "find":
        guard words.count > 2, let pid = pid_t(words[1]) else { return "error find PID TEXT" }
        let needle = String(line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)[2])
        guard let box = await find(needle, in: pid) else { return "ok none" }
        return String(format: "ok %.1f %.1f %.1f %.1f", box.minX, box.minY, box.width, box.height)
    case "windows":
        guard words.count > 1, let pid = pid_t(words[1]) else { return "error windows PID" }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let mine: [[String: Any]] = list.compactMap { info in
            guard info[kCGWindowOwnerPID as String] as? pid_t == pid, info[kCGWindowLayer as String] as? Int == 0,
                  let b = info[kCGWindowBounds as String] as? [String: Double], b["Width"]! > 100 else { return nil }
            return ["title": info[kCGWindowName as String] as? String ?? "", "frame": [b["X"]!, b["Y"]!, b["Width"]!, b["Height"]!]]
        }
        let data = (try? JSONSerialization.data(withJSONObject: mine)) ?? Data()
        return "ok " + (String(data: data, encoding: .utf8) ?? "[]")
    case "owner":
        guard words.count > 3, let x = Double(words[1]), let y = Double(words[2]), let pass = pid_t(words[3]) else { return "error owner X Y PASSPID" }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in list {
            guard let b = info[kCGWindowBounds as String] as? [String: Double], (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  info[kCGWindowOwnerName as String] as? String != "Dock",
                  info[kCGWindowLayer as String] as? Int32 != CGWindowLevelForKey(.cursorWindow) else { continue }
            let pid = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
            if pid == pass, info[kCGWindowLayer as String] as? Int == 0 { continue }
            if x >= b["X"]! && x < b["X"]! + b["Width"]! && y >= b["Y"]! && y < b["Y"]! + b["Height"]! { return "ok \(pid)" }
        }
        return "ok 0"
    case "unminimize":
        guard words.count > 1, let pid = pid_t(words[1]) else { return "error unminimize PID" }
        return "ok \(unminimize(pid))"
    default:
        return "error unknown \(command)"
    }
    return "ok"
}

guard AXIsProcessTrusted() else {
    FileHandle.standardError.write("hand: not trusted for Accessibility, so its events would be dropped\n".data(using: .utf8)!)
    exit(1)
}
Thread.detachNewThread {
    while let line = readLine() {
        let done = DispatchSemaphore(value: 0)
        Task {
            print(await run(line))
            done.signal()
        }
        done.wait()
    }
    // The script is gone: never leave the chord or the button held.
    if pressed { mouse(.leftMouseUp, pointer) }
    if !flags.isEmpty { modifier(58, .maskControl); modifier(59, []) }
    exit(0)
}
RunLoop.main.run()
