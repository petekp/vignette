import CoreGraphics
import Foundation

/// Pins in the editor: the Comment tool's pins, the popover's composer, and pins among the marks
/// for selection, moving, resizing, deleting and Tab (docs/screenshot-comments-2026-11-24/editor.md).
extension EditorCore {
    /// The pin popover: the pin it is open on, and its composer, the field a comment is written in.
    struct Composer: Equatable {
        let pin: Pin.ID
        /// The comment the composer edits, by its index in the pin's comments, or nil for a new one.
        var editing: Int?
        /// The composer's words as typed.
        var draft: String
    }

    enum ComposerInput: Equatable {
        case changed(String)
        /// Return: posts the words, and the composer stays open on the pin for another comment. In an
        /// empty composer it closes.
        case post
        /// Esc, or the popover closing: posts the words and closes.
        case close
        /// Cmd+Return: posts the words and closes, then finishes as Cmd+Return does.
        case finish
        /// A click on a comment's words: the composer edits that comment.
        case edit(Int)
        /// A pin chosen in the toolbar's list or a cluster's: its popover opens on it.
        case open(Pin.ID)
    }

    func pin(_ id: Pin.ID) -> Pin? { drawing.pins.first { $0.id == id } }

    /// An edit beginning now, for what a gesture, a typing session, the composer or a command changes.
    var newEdit: MarkEdit { MarkEdit(marks: drawing.marks, pins: drawing.pins, selectionBefore: selection) }

    /// Whether what `target` names is still in the drawing.
    func exists(_ target: Target) -> Bool {
        switch target {
        case .handle(let id, _), .dot(let id, _), .mark(let id): return mark(id) != nil || pin(id) != nil
        case .pin(let id): return pin(id) != nil
        case .cluster(let ids): return ids.allSatisfy { pin($0) != nil }
        }
    }

    // MARK: Placing

    /// A new point pin at `point`, kept inside the image, selected, with its composer open. Until its
    /// first comment is posted it holds no number and shows none.
    mutating func placePin(at point: CGPoint) {
        guard drawing.pins.count < Pin.maxCount else { return emit(.beep) }
        let pin = Pin(id: UUID(), number: 0, place: .point(geometry.inside(point)), comments: [])
        edit = newEdit
        drawing.pins.append(pin)
        selection = [pin.id]
        composer = Composer(pin: pin.id, draft: "")
    }

    /// A new point pin at the middle of the part of the picture in view, once a drag, typing or another
    /// pin's popover is put away.
    mutating func placePinInView() {
        if gesture != nil { cancelGesture() }
        if typing != nil { endTyping() }
        if composer != nil { closeComposer() }
        let room = visible.isNull ? geometry.image : visible
        placePin(at: CGPoint(x: room.midX, y: room.midY))
    }

    /// A Comment tool drag: the new pin's area runs from the press to the pointer, by the Rectangle
    /// tool's rules for Shift, Option and the image's edges, and its teardrop's tip follows the pointer's corner.
    mutating func placeArea(_ id: Pin.ID, from start: CGPoint, to pointer: CGPoint) {
        let frame = geometry.newRectangle(from: geometry.inside(start), to: pointer, square: modifiers.contains(.shift),
                                          centred: modifiers.contains(.option))
        let pin = Pin(id: id, number: 0, place: .area(frame, tip: Pin.Corner(from: start, to: pointer)), comments: [])
        if let index = drawing.pins.firstIndex(where: { $0.id == id }) { drawing.pins[index] = pin } else { drawing.pins.append(pin) }
    }

    /// The drag ended. An area smaller than the smallest rectangle is a point pin at the press. Ended by
    /// park, Done or Send rather than a release, the pin goes.
    mutating func finishPlacing(_ id: Pin.ID, at press: CGPoint, released: Bool) {
        guard released, var pin = pin(id) else { return revertEdit() }
        if case .area(let frame, _) = pin.place, min(frame.width, frame.height) * zoom < metrics.smallestRectangle {
            pin.place = .point(geometry.inside(press))
            replacePin(pin)
        }
        selection = [id]
        composer = Composer(pin: id, draft: "")
    }

    // MARK: The composer

    mutating func composerInput(_ input: ComposerInput) {
        switch input {
        case .changed(let words):
            composer?.draft = Self.capped(words)
        case .post:
            guard let composer else { return }
            if composer.editing == nil, Self.blank(composer.draft) { closeComposer() } else { post() }
        case .close:
            closeComposer()
        case .finish:
            closeComposer()
            finish(finishes.commandReturn)
        case .edit(let index):
            guard let composer, let before = pin(composer.pin)?.comments.count, (0..<before).contains(index) else { return }
            post()
            let removed = (pin(composer.pin)?.comments.count ?? 0) < before
            let shifted = removed && (composer.editing ?? index) < index ? index - 1 : index
            if self.composer != nil { openComposer(on: composer.pin, editing: shifted) }
        case .open(let id):
            openComposer(on: id)
        }
    }

    /// Opens the popover on pin `id`, selected, with the caret in a new comment, or in comment
    /// `editing`.
    mutating func openComposer(on id: Pin.ID, editing: Int? = nil) {
        if gesture != nil { cancelGesture() }
        if typing != nil { endTyping() }
        if let open = composer, open.pin != id || editing != open.editing { closeComposer() }
        guard let pin = pin(id) else { return }
        if composer == nil { edit = newEdit }
        selection = [id]
        let index = editing.flatMap { pin.comments.indices.contains($0) ? $0 : nil }
        composer = Composer(pin: id, editing: index, draft: index.map { pin.comments[$0].text } ?? "")
    }

    /// Posts what the composer holds: a new comment on its pin, or the comment it edits, which goes
    /// when emptied, and the pin with its last comment. A pin takes `nextPin` with its first comment.
    /// Each post is one undo step. While the pin is there the composer stays open on it, empty, for
    /// another comment.
    private mutating func post() {
        guard let open = composer, let index = drawing.pins.firstIndex(where: { $0.id == open.pin }) else { return }
        let words = open.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        var pin = drawing.pins[index]
        var name = StepName.comment
        if let editing = open.editing, pin.comments.indices.contains(editing) {
            if words.isEmpty {
                pin.comments.remove(at: editing)
                name = .delete
            } else if words != pin.comments[editing].text {
                // The words are the person's now, as with an agent's note, and written now.
                pin.comments[editing] = Pin.Comment(text: words, at: Date())
                name = .typing
            }
        } else if !words.isEmpty {
            pin.comments.append(Pin.Comment(text: words, at: Date()))
        }
        guard pin != drawing.pins[index] else {
            composer = Composer(pin: pin.id, draft: "")
            return
        }
        let numbered = pin.number == 0 && !pin.comments.isEmpty
        if numbered {
            pin.number = drawing.nextPin
            drawing.nextPin += 1
        }
        if pin.comments.isEmpty, pin.number > 0 {
            drawing.pins.remove(at: index)
            selection.remove(pin.id)
        } else {
            drawing.pins[index] = pin
        }
        commitEdit(named: numbered ? .comment : name)
        if numbered { emit(.announce("Pin \(pin.number) added")) }
        guard self.pin(pin.id) != nil else {
            composer = nil
            return
        }
        edit = newEdit
        composer = Composer(pin: pin.id, draft: "")
    }

    /// A press on a handle of the open pin's area resizes it with the popover still open.
    func keepsComposer(at point: CGPoint) -> Bool {
        guard let open = composer?.pin, case .handle(let id, _)? = target(at: point) else { return false }
        return id == open
    }

    /// A press opens no edit until it drags, so a press put back with the popover open leaves the
    /// composer's edit as it is.
    mutating func revertGestureEdit(_ phase: Phase) {
        let editIsTheComposers = phase == .pressed && composer != nil
        guard !editIsTheComposers else { return }
        revertEdit()
        resumeComposerEdit()
    }

    /// The edit a resize opens. The open popover's edit gives way to it, and the selection that edit
    /// began from is kept for when it begins again.
    mutating func resizeEdit() -> MarkEdit {
        if composer != nil { composerSelectionBefore = edit?.selectionBefore }
        return newEdit
    }

    /// A resize with the popover open ended or was put back: the composer's edit begins again from
    /// the drawing as it is now. A new pin is left out of it, as no step holds a pin before its first
    /// comment, so closing it with nothing posted still takes it away.
    mutating func resumeComposerEdit() {
        guard composer != nil else { return }
        edit = MarkEdit(marks: drawing.marks, pins: drawing.pins.filter { $0.number > 0 },
                        selectionBefore: composerSelectionBefore ?? selection)
        composerSelectionBefore = nil
    }

    /// Posts what was typed and closes the popover. The pin stays selected; a new one with nothing
    /// posted goes, and took no number.
    mutating func closeComposer() {
        guard let open = composer else { return }
        if gesture != nil { cancelGesture() }
        post()
        composer = nil
        if let pin = pin(open.pin), pin.number == 0 {
            revertEdit()
            selection.remove(open.pin)
        } else {
            edit = nil
        }
    }

    private static func blank(_ words: String) -> Bool { words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: Pins among the marks

    /// A press on pin `id` changes the selection as one on a mark does, and answers what its release does.
    mutating func pinClick(_ id: Pin.ID, _ modifiers: Modifiers) -> Click {
        if !modifiers.isDisjoint(with: [.shift, .command]) {
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

    // MARK: Drawn at one size

    /// A teardrop's side in px at the current zoom: the size it has in the picture when the picture fits
    /// the frame, kept on screen at every zoom.
    var pinSide: CGFloat { geometry.screen(markStyle.pin.side * drawing.pointScale * fitZoom) }

    /// The pins as the editor draws them now. The open pin, the selected ones and a new one never
    /// join a cluster.
    var pinPlacement: PinPlacement {
        var apart = selection
        if let composer { apart.insert(composer.pin) }
        return PinPlacement(drawing, side: pinSide, edge: geometry.pt(markStyle.edgeWidth), apart: apart, style: markStyle.pin)
    }

    /// The pins an area's outline shows for: hovered, selected, being placed or open.
    var outlinedPins: Set<Pin.ID> {
        var ids = Set(drawing.pins.map(\.id)).intersection(selection).union(marchingPins)
        if case .pin(let id)? = hover { ids.insert(id) }
        return ids
    }

    /// The pins whose area's dashes march: the one being placed and the open one.
    var marchingPins: Set<Pin.ID> {
        var ids = Set<Pin.ID>()
        if case .placing(let id)? = gesture?.phase { ids.insert(id) }
        if let composer { ids.insert(composer.pin) }
        return ids
    }

    /// What a press at `point` hits among the pins: a teardrop or a cluster within the hit margin, or
    /// the outline of an area while it shows. Never an area's inside.
    func pinTarget(at point: CGPoint) -> Target? {
        let band = geometry.screen(metrics.hitMargin)
        if let hit = pinPlacement.hit(at: point, band: band) { return hit }
        for id in outlinedPins {
            guard case .area(let frame, _)? = pin(id)?.place else { continue }
            if geometry.hit(Mark(id: id, geometry: .rectangle(frame)), at: point, insideCounts: false) != nil { return .pin(id) }
        }
        return nil
    }

    /// A click on a cluster lists its pins by it.
    mutating func showCluster(_ ids: [Pin.ID]) {
        guard let cluster = pinPlacement.clusters.first(where: { $0.pins == ids }) else { return }
        emit(.showCluster(ids, at: cluster.frame))
    }
}

extension Pin {
    /// Where the pin is, as a rect in px: its area, or a point's empty rect.
    var extent: CGRect {
        switch place {
        case .point(let point): return CGRect(origin: point, size: .zero)
        case .area(let frame, _): return frame
        }
    }

    /// What VoiceOver calls the pin: "Pin 3, area, 2 comments".
    var spokenName: String {
        guard number > 0 else { return "New pin" }
        let kind: String
        switch place {
        case .point: kind = "point"
        case .area: kind = "area"
        }
        return "Pin \(number), \(kind), \(comments.count == 1 ? "1 comment" : "\(comments.count) comments")"
    }
}

extension MarkEdit {
    /// The undo step named `name` from where this edit began to `drawing`: the marks it touched and
    /// every pin that changed, or nil when nothing did. A pin before its first comment is left out.
    func step(named name: StepName, ending drawing: Drawing, selection: Set<Mark.ID>) -> EditStep? {
        let before = Dictionary(startPins.filter { $0.number > 0 }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let after = Dictionary(drawing.pins.filter { $0.number > 0 }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ids = startPins.map(\.id) + drawing.pins.map(\.id).filter { !startPins.map(\.id).contains($0) }
        let pins = ids.compactMap { id in before[id] == after[id] ? nil : EditStep.PinChange(id: id, before: before[id], after: after[id]) }
        let marks = step(named: name, ending: drawing.marks, selection: selection)
        guard marks != nil || !pins.isEmpty else { return nil }
        var step = marks ?? EditStep(name: name, changes: [], selectionBefore: selectionBefore, selectionAfter: selection)
        step.pins = pins
        return step
    }
}
