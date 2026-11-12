import AppKit

/// Where the note is on the screen: its words, and where it hangs by the pointer before any ink.
extension LiveNotePopover {
    /// The words, in global top-left points: where the drawn note's tag goes once they are asked.
    var tagFrame: CGRect? {
        guard let window = content.window else { return nil }
        return StateReport.flipped(window.convertToScreen(content.convert(content.wordsFrame, to: nil)))
    }

    /// Where a note of `size` hangs by the pointer at `pointer`, on `screen`'s visible frame, all in
    /// global top-left points: from a square round the pointer's ring, `clearance` from its middle to
    /// each side, to the right first, then the left, below and above, on the first side where it fits.
    /// A side in `kept` comes first, so a note that moves keeps its side while it fits.
    nonisolated static func pointerPlace(_ size: CGSize, at pointer: CGPoint, clearance: CGFloat, screen: CGRect,
                             keeping kept: PopoverPlace.Edge? = nil) -> PopoverPlace {
        let ring = CGPoint(x: pointer.x + PointerFieldMotion.ringOffset.dx, y: pointer.y + PointerFieldMotion.ringOffset.dy)
        let reach = max(clearance, 1)
        let at = CGRect(x: ring.x - reach, y: ring.y - reach, width: reach * 2, height: reach * 2)
        let room = screen.insetBy(dx: PopoverPlace.windowMargin, dy: PopoverPlace.windowMargin)
        let sides = (kept.map { [$0] } ?? []) + [PopoverPlace.Edge.right, .left, .below, .above]
        let places = sides.map { edge in
            PopoverPlace(anchor: nil, at: at, edge: edge, body: PopoverPlace.body(size, hungFrom: at, edge: edge, on: screen),
                         foot: .zero, screen: screen)
        }
        return places.first { room.contains($0.body) } ?? places[0]
    }

    /// The pointer a note by the pointer was placed at by `pointerPlace`.
    nonisolated static func pointer(hungFrom place: PopoverPlace) -> CGPoint {
        CGPoint(x: place.at.midX - PointerFieldMotion.ringOffset.dx, y: place.at.midY - PointerFieldMotion.ringOffset.dy)
    }

    /// Whether `pointer` has come within half of `clearance` of a note whose body is `body`, so the
    /// note moves out of its way.
    nonisolated static func pointer(_ pointer: CGPoint, crowds body: CGRect, clearance: CGFloat) -> Bool {
        body.insetBy(dx: -clearance / 2, dy: -clearance / 2).contains(pointer)
    }
}
