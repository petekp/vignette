import CoreGraphics

extension LiveInkOverlay {
    /// What the pointer did while inking, in global top-left points: from the overlay's own events, or
    /// from `LiveInkTap`, which takes them before the window server delivers them.
    enum Input {
        case pressed(CGPoint)
        case dragged(CGPoint)
        case released(CGPoint)
        case moved(CGPoint)
    }
}

extension LiveMarksLayer {
    /// What a tap where the pointer is would do, shown while the chord is held: a mark it would erase
    /// fades back, and an answer's loop or arrow it would pick takes the person's colour.
    enum Preview: Equatable {
        case erase(Mark.ID)
        case pick(Mark.ID)

        var id: Mark.ID {
            switch self {
            case .erase(let id), .pick(let id): id
            }
        }
    }

    /// How marks leave: done, when the session's turn ended, which turns them green with a check; or
    /// dismissed, which undraws them.
    enum Finish {
        case done, dismissed
    }
}
