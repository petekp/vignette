import Foundation

extension LivePacket {
    /// The JSON of an ask, sent after its pictures and text lines: `freshPicture` false for a
    /// follow-up that sends no picture, about the picture and text lines sent before. `pointer`, for
    /// an ask about the window under it with no ink, is where it was, in thousandths of the picture.
    func message(note: String, ink: [Mark], new: Set<Mark.ID>, freshPicture: Bool, pointer: CGPoint? = nil) -> String {
        var json: [String: Any] = [:]
        if let app { json["app"] = app }
        if let title, !title.isEmpty { json["window"] = title }
        if let location { json["location"] = location }
        if !windows.isEmpty {
            json["windows"] = windows.map { window -> [String: Any] in
                var item: [String: Any] = ["box": thousandths(of: window.frame.intersection(frame))]
                if let app = window.app { item["app"] = app }
                if let title = window.title, !title.isEmpty { item["window"] = title }
                return item
            }
        }
        json["note"] = note
        if let pointer, frame.contains(pointer) { json["pointer"] = thousandths(of: pointer) }
        json["ink"] = ink.compactMap { mark -> [String: Any]? in
            guard let extent = mark.shapeExtent else { return nil }
            var item: [String: Any] = ["kind": mark.kind == .ellipse ? "circle" : mark.kind.rawValue, "new": new.contains(mark.id)]
            if let number = numbers[mark.id] { item["n"] = number }
            // Ink past the area's picture has a box only in its window's own picture.
            guard extent.intersects(frame) else { return item }
            item["box"] = thousandths(of: extent)
            if case .arrow(let arrow) = mark.geometry {
                item["from"] = thousandths(of: arrow.start)
                item["to"] = thousandths(of: arrow.end)
            }
            return item
        }
        if freshPicture, let detail { json["detail"] = Self.thousandths(detail.box) }
        if freshPicture, !alone.isEmpty {
            let numbered = { (ids: [Mark.ID]) in ids.compactMap { numbers[$0] }.sorted() }
            json["alone"] = alone.map { window -> [String: Any] in
                var item: [String: Any] = ["ink": numbered(window.ink)]
                if let app = window.app { item["app"] = app }
                if let title = window.title, !title.isEmpty { item["window"] = title }
                if !window.covered.isEmpty { item["covered"] = numbered(window.covered) }
                if !window.outside.isEmpty { item["outside"] = numbered(window.outside) }
                return item
            }
        }
        let data = (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// The message a session is sent with a live ink note: the person's words, `numbered` when they
    /// carry the ink's `[n]`, then where they drew. For an ask with no ink, `pointer` is where they
    /// asked, given in whole percentages of the picture when it is on it.
    func sessionLine(note: String, numbered: Bool, pointer: CGPoint?) -> String {
        var place = [app, title.map { "\"\($0)\"" }, location].compactMap { $0 }.joined(separator: ", ")
        if !windows.isEmpty {
            place = "the screen, across " + windows.map { window in
                [window.app, window.title.flatMap { $0.isEmpty ? nil : "\"\($0)\"" }].compactMap { $0 }.joined(separator: " ")
            }.joined(separator: " and ")
        }
        if place.isEmpty { place = "the screen" }
        // One line: the plugin's monitor makes each line it prints a message of its own.
        var said = note.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        if let last = said.last, !".?!]".contains(last) { said += "." }
        let how = pointer == nil ? "Drawn with Vignette's live ink on" : "Asked with Vignette's live ink, without drawing, about"
        var message = (said.isEmpty ? "" : said + " ") + "\(how) \(place)."
        if let pointer, frame.contains(pointer) {
            let percent = { (fraction: CGFloat) in Int((fraction * 100).rounded()) }
            let across = percent((pointer.x - frame.minX) / frame.width), down = percent((pointer.y - frame.minY) / frame.height)
            message += " The pointer was at \(across)% across and \(down)% down the picture."
        }
        if numbered { message += " Each [n] in the words is where the ink numbered n in the picture was drawn as they were said." }
        let covered = alone.flatMap(\.covered).compactMap { numbers[$0] }.sorted()
        if !covered.isEmpty {
            message += " On the screen, a window in front covers the ink numbered \(covered.map(String.init).joined(separator: ", "))."
        }
        return message
    }
}
