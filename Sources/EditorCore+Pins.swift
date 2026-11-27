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
        /// The popover takes the keys as it opens. False for the one the editor opens on its own, which
        /// leaves them with the editor until the person clicks into it.
        var takesKeys = true
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
        /// A comment's Delete: it goes, and its pin with it when it was the only one, as one undo step.
        case delete(Int)
        /// The editor came up on its screenshot: the popover opens on the pin with the lowest number,
        /// leaving the keys and the selection as they are.
        case openFirst
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
        case .delete(let index):
            composerInput(.edit(index))
            guard composer?.editing != nil else { return }
            composer?.draft = ""
            post()
        case .openFirst:
            guard composer == nil, gesture == nil, typing == nil,
                  let first = drawing.pins.filter({ $0.number > 0 }).min(by: { $0.number < $1.number }) else { return }
            edit = newEdit
            composer = Composer(pin: first.id, draft: "", takesKeys: false)
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
                pin.comments[editing] = Pin.Comment(id: pin.comments[editing].id, text: words, at: Date())
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

    /// A press on a handle of the open pin's area resizes it with the popover still open, and a
    /// double-click's second press on the open pin leaves the popover its first click opened.
    func keepsComposer(at point: CGPoint, _ clickCount: Int) -> Bool {
        guard let open = composer?.pin else { return false }
        switch target(at: point) {
        case .handle(let id, _)?: return id == open
        case .pin(let id)?: return clickCount >= 2 && id == open && composer?.takesKeys == true
        default: return false
        }
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
    /// Tells the view when the pin popover opens, changes or closes.
    mutating func reportComposer() {
        guard composer != reportedComposer else { return }
        reportedComposer = composer
        emit(.composer(composer))
    }

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
