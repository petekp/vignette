import Foundation

enum EditorCoreTrace {
    static let session = AgentDestination(id: "s1", name: "s1", address: .claudeSession("s1"))

    static func describe(_ input: EditorCore.Input) -> String {
        func at(_ p: EditorCore.Pointer) -> String { String(format: "(%.1f, %.1f)%@", p.location.x, p.location.y, p.modifiers.isEmpty ? "" : " \(p.modifiers.rawValue)") }
        switch input {
        case .open: return "open"
        case .pointerMoved(let p): return "move \(at(p))"
        case .pointerExited: return "exit"
        case .pointerPressed(let p, let count): return "press \(at(p)) count=\(count)"
        case .pointerDragged(let p): return "drag \(at(p))"
        case .pointerReleased(let p): return "release \(at(p))"
        case .modifiersChanged(let m): return "modifiers \(m.rawValue)"
        case .keyDown(let key, let m, let isRepeat): return "key \(key) \(m.rawValue)\(isRepeat ? " repeat" : "")"
        case .keyUp(let key): return "keyUp \(key)"
        case .setTool(let tool): return "tool \(tool)"
        case .enterCanvas(let backward): return "enterCanvas\(backward ? " backward" : "")"
        case .zoomChanged(let zoom): return "zoom \(zoom)"
        case .viewChanged(let visible): return "view visible=\(visible)"
        case .composer(let input): return "composer \(input)"
        case .addPin: return "addPin"
        case .tweaksChanged: return "tweaks"
        case .rescaled(let pointScale, let markScale): return "rescaled \(pointScale) \(markScale)"
        case .typingChanged(let text): return "type \(text.count) characters"
        case .typingEnded: return "typingEnded"
        case .messageChanged(let words, let name): return "message \(name.rawValue) \(words.count) characters"
        case .messageTypingEnded: return "messageTypingEnded"
        case .timerFired: return "timer"
        case .paste(let content):
            switch content {
            case .items(let copied): return "paste \(copied.marks.count) marks @\(copied.pointScale)"
            case .text(let text): return "paste text of \(text.count)"
            case .image: return "paste image"
            case .other: return "paste other"
            }
        case .agentMarks(let marks, let pins, _): return "agent marks \(marks.count) pins \(pins.count)"
        case .sessionNamed: return "sessionNamed"
        case .done: return "done"
        case .send: return "send"
        case .park: return "park"
        }
    }

    static func describe(_ effects: [EditorCore.Effect]) -> String {
        effects.map { effect -> String in
            switch effect {
            case .handOver(let drawing): return "handOver(\(drawing.marks.count))"
            case .done(let drawing): return "done(\(drawing.marks.count))"
            case .send(let drawing, let to): return "send(\(drawing.marks.count)\(to == nil ? "" : " to"))"
            case .copyDrawing(let drawing): return "copyDrawing(\(drawing.marks.count))"
            case .copyItems(let marks, _): return "copyItems(\(marks.marks.count))"
            case .announce: return "announce"
            default: return "\(effect)"
            }
        }.joined(separator: ", ")
    }
}
