import CoreGraphics
import Foundation

extension EditorCore {
    // MARK: Pins among the marks

    /// A press on pin `id` changes the selection as one on a mark does, and answers what its release
    /// does. With the Comment tool a click without Shift or Command opens the pin's popover (`.open`),
    /// unless the press closed it. A double-click opens it at once with either tool, and answers nil.
    mutating func pinPress(_ id: Pin.ID, _ modifiers: Modifiers, _ clickCount: Int, wasOpen: Bool) -> Click? {
        if clickCount >= 2 {
            if composer?.pin != id { openComposer(on: id) }
            return nil
        }
        let plain = modifiers.isDisjoint(with: [.shift, .command])
        if tool == .comment, plain, !wasOpen {
            // A drag from one of several selected pins moves them all, as from a mark.
            if !selection.contains(id) { selection = [id] }
            return .open
        }
        if !plain {
            if selection.contains(id) { return .deselect }
            selection.insert(id)
            return .nothing
        }
        if selection.contains(id) { return selection.count > 1 ? .selectOnly : .nothing }
        selection = [id]
        return .nothing
    }

    mutating func replacePin(_ pin: Pin) {
        guard let index = drawing.pins.firstIndex(where: { $0.id == pin.id }) else { return }
        drawing.pins[index] = pin
    }

    mutating func removePin(_ id: Pin.ID) {
        drawing.pins.removeAll { $0.id == id }
        selection.remove(id)
    }

    /// `pins`, as they were, moved by `delta` and kept inside the image.
    mutating func movePins(_ pins: [Pin], by delta: CGVector) {
        for start in pins { replacePin(start.moved(by: delta).placed(in: drawing.pixels) ?? start) }
    }

    /// A handle drag on an area pin resizes its area as a rectangle's. False when `id` is no pin.
    mutating func resizePin(_ id: Pin.ID, by position: HandlePosition, delta: CGVector) -> Bool {
        guard let start = edit?.startPins.first(where: { $0.id == id }) else { return false }
        guard case .area(let frame, let corner) = start.place else { return true }
        let fromCenter = modifiers.contains(.option)
        let resized = geometry.resized(frame, by: position, delta: delta, proportional: modifiers.contains(.shift), fromCenter: fromCenter)
        // A side dragged past the opposite one, or past the centre with `fromCenter`, swaps the area's corners on its axis.
        func flips(_ side: Int, _ low: CGFloat, _ high: CGFloat, _ newLow: CGFloat, _ newHigh: CGFloat, _ move: CGFloat) -> Bool {
            guard side != 0 else { return false }
            if fromCenter { return side > 0 ? move < -(high - low) / 2 : move > (high - low) / 2 }
            return side > 0 ? newLow < low : newHigh > high
        }
        let tip = corner.mirrored(x: flips(position.xSide, frame.minX, frame.maxX, resized.minX, resized.maxX, delta.dx),
                                  y: flips(position.ySide, frame.minY, frame.maxY, resized.minY, resized.maxY, delta.dy))
        var pin = start
        pin.place = .area(resized, tip: tip)
        replacePin(pin.placed(in: drawing.pixels) ?? start)
        return true
    }

    /// What marks and pins move together within, in px, or nil with neither.
    func movingExtent(of marks: [Mark], pins: [Pin]) -> CGRect? {
        var rects = pins.map(\.extent)
        if let marks = geometry.movingExtent(of: marks) { rects.append(marks) }
        guard let first = rects.first else { return nil }
        return rects.dropFirst().reduce(first) { box, rect in
            CGRect(x: min(box.minX, rect.minX), y: min(box.minY, rect.minY),
                   width: max(box.maxX, rect.maxX) - min(box.minX, rect.minX), height: max(box.maxY, rect.maxY) - min(box.minY, rect.minY))
        }
    }

    /// The pins a brush selects: a point inside it, or an area it touches.
    func pins(in brush: CGRect) -> [Pin.ID] {
        drawing.pins.filter { pin in
            switch pin.place {
            case .point(let point): return brush.contains(point)
            case .area(let frame, _): return brush.intersects(frame)
            }
        }.map(\.id)
    }

    /// The marks and the pins, in reading order, for Tab.
    var readingOrder: [Mark.ID] {
        let pins = drawing.pins.filter { $0.number > 0 }.map { Mark(id: $0.id, geometry: .rectangle(CGRect(origin: $0.tip, size: CGSize(width: 1, height: 1)))) }
        return geometry.readingOrder(drawing.marks + pins)
    }

    /// A lone selected area pin's handles, on its area's outline.
    var areaPinHandles: [Handle] {
        guard selection.count == 1, let id = selection.first, case .area(let frame, _)? = pin(id)?.place else { return [] }
        return geometry.handles(around: frame, of: id, markSize: frame.size)
    }

    // MARK: Inspecting

    /// What VoiceOver says for the selection: the kind of one mark, with a text's words, one pin, or how
    /// many.
    var selectionWords: String? {
        let chosen = drawing.marks.filter { selection.contains($0.id) }, pins = drawing.pins.filter { selection.contains($0.id) }
        if chosen.isEmpty, pins.count == 1, let pin = pins.first { return pin.spokenName }
        guard let first = chosen.first else { return pins.isEmpty ? nil : "\(pins.count) pins" }
        guard chosen.count + pins.count == 1 else {
            let marks = chosen.count == 1 ? "1 mark" : "\(chosen.count) marks"
            return pins.isEmpty ? marks : "\(marks) and \(pins.count == 1 ? "1 pin" : "\(pins.count) pins")"
        }
        switch first.geometry {
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .arrow: return "Arrow"
        case .text(let text): return "Text: \(text.text)"
        }
    }
}
