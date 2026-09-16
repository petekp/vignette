import AppKit
import ApplicationServices
import Carbon

// Synthetic input for driving Shotnote from the terminal; run through scripts/input.sh.
// System Events keystrokes do not trigger Carbon hotkeys and only reach the frontmost app;
// CGEvent does both. Coordinates are global Core Graphics points: origin at the top-left of the
// main display, y growing downward, so a display above the main one has negative y.
// Events post only from a process trusted for Accessibility. Launched from a trusted terminal,
// this tool inherits that trust; from anywhere else the events are dropped, so it refuses to run.

@main
struct InputTool {
    static let usage = """
    usage: scripts/input.sh <command>
      key <keycode> [cmd] [shift] [opt] [ctrl]   press and release a key
      hotkey <spec>                              press a settings.json hotkey: cmd+shift+6, double-rshift
      tap <modifier keycode> [count]             tap a modifier key (60 is right shift), twice by default
      holdtap <modifier keycode> [seconds]       tap a modifier key once, then hold a second press (0.7 s)
      move X Y                                   move the mouse
      click X Y                                  click the left button
      drag X1 Y1 X2 Y2                           drag with the left button
      scroll DY [steps]                          scroll; positive DY reveals what is above
      pasteboard                                 print the general pasteboard's item count and types
    """

    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else { fail(usage) }
        let rest = Array(args.dropFirst())
        if command == "pasteboard" { pasteboard(); return }
        guard AXIsProcessTrusted() else {
            fail("input: this process is not trusted for Accessibility, so events would be dropped. Run it from a trusted terminal.")
        }
        switch command {
        case "key":
            guard let code = rest.first.flatMap({ UInt16($0) }) else { fail(usage) }
            key(code, flags: flags(named: rest.dropFirst()))
        case "hotkey":
            guard let spec = rest.first.flatMap(HotKeySpec.parse) else { fail("input: cannot parse hotkey \"\(rest.first ?? "")\"") }
            switch spec {
            case .key(let code, let carbon): key(UInt16(code), flags: flags(carbon: carbon))
            case .doubleTap(let code): tap(code, count: 2)
            }
        case "tap":
            guard let code = rest.first.flatMap({ UInt16($0) }) else { fail(usage) }
            tap(code, count: rest.dropFirst().first.flatMap { Int($0) } ?? 2)
        case "holdtap":
            guard let code = rest.first.flatMap({ UInt16($0) }) else { fail(usage) }
            tap(code, count: 1)
            tap(code, count: 1, hold: rest.dropFirst().first.flatMap { Double($0) } ?? 0.7)
        case "move":
            let p = points(rest, 2); move(p[0].0, p[0].1)
        case "click":
            let p = points(rest, 2); click(p[0].0, p[0].1)
        case "drag":
            let p = points(rest, 4); drag(from: p[0], to: p[1])
        case "scroll":
            guard let dy = rest.first.flatMap({ Double($0) }) else { fail(usage) }
            scroll(dy, steps: rest.dropFirst().first.flatMap { Int($0) } ?? 10)
        default:
            fail(usage)
        }
    }

    // MARK: Events

    static func post(_ event: CGEvent?) { event?.post(tap: .cghidEventTap) }
    static func pause(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }

    static func key(_ code: UInt16, flags: CGEventFlags) {
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
            e?.flags = flags
            post(e); pause(0.03)
        }
    }

    /// A modifier key pressed and released; the down event carries the modifier's flag like a real press.
    static func tap(_ code: UInt16, count: Int, hold: Double = 0.05) {
        let flag: CGEventFlags
        switch code {
        case 56, 60: flag = .maskShift
        case 54, 55: flag = .maskCommand
        case 58, 61: flag = .maskAlternate
        case 59, 62: flag = .maskControl
        default: fail("input: \(code) is not a modifier key code")
        }
        for _ in 0..<count {
            let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)
            down?.flags = flag
            post(down); pause(hold)
            let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)
            up?.flags = []
            post(up); pause(0.12)
        }
    }

    static func mouse(_ type: CGEventType, _ point: CGPoint) {
        post(CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left))
    }

    static func move(_ x: Double, _ y: Double) { mouse(.mouseMoved, CGPoint(x: x, y: y)) }

    static func click(_ x: Double, _ y: Double) {
        let p = CGPoint(x: x, y: y)
        move(x, y); pause(0.1)
        mouse(.leftMouseDown, p); pause(0.05)
        mouse(.leftMouseUp, p)
    }

    static func drag(from: (Double, Double), to: (Double, Double), steps: Int = 12) {
        move(from.0, from.1); pause(0.15)
        mouse(.leftMouseDown, CGPoint(x: from.0, y: from.1)); pause(0.1)
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            mouse(.leftMouseDragged, CGPoint(x: from.0 + (to.0 - from.0) * t, y: from.1 + (to.1 - from.1) * t))
            pause(0.03)
        }
        mouse(.leftMouseUp, CGPoint(x: to.0, y: to.1))
    }

    /// Trackpad-style pixel deltas; positive dy pulls content down (reveals what is above).
    static func scroll(_ dy: Double, steps: Int) {
        for _ in 0..<max(steps, 1) {
            post(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                         wheel1: Int32(dy / Double(max(steps, 1))), wheel2: 0, wheel3: 0))
            pause(0.016)
        }
    }

    static func pasteboard() {
        let items = NSPasteboard.general.pasteboardItems ?? []
        print("items=\(items.count)")
        for (i, item) in items.enumerated() {
            print("\(i): \(item.types.map(\.rawValue).joined(separator: " "))")
        }
    }

    // MARK: Argument parsing

    static func flags(named names: ArraySlice<String>) -> CGEventFlags {
        var flags: CGEventFlags = []
        for name in names {
            switch name {
            case "cmd": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "opt": flags.insert(.maskAlternate)
            case "ctrl": flags.insert(.maskControl)
            default: fail("input: unknown modifier \"\(name)\"")
            }
        }
        return flags
    }

    static func flags(carbon: UInt32) -> CGEventFlags {
        var flags: CGEventFlags = []
        if carbon & UInt32(cmdKey) != 0 { flags.insert(.maskCommand) }
        if carbon & UInt32(shiftKey) != 0 { flags.insert(.maskShift) }
        if carbon & UInt32(optionKey) != 0 { flags.insert(.maskAlternate) }
        if carbon & UInt32(controlKey) != 0 { flags.insert(.maskControl) }
        return flags
    }

    static func points(_ args: [String], _ count: Int) -> [(Double, Double)] {
        let numbers = args.prefix(count).compactMap { Double($0) }
        guard numbers.count == count else { fail(usage) }
        return stride(from: 0, to: count, by: 2).map { (numbers[$0], numbers[$0 + 1]) }
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
        exit(1)
    }
}
