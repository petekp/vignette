import CoreGraphics

/// What the view draws over the marks, and what a press can act on.
extension EditorCore {
    enum HandlePosition: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight, top, bottom, left, right

        /// -1 for a handle on the left side, 1 on the right, 0 for one that moves neither.
        var xSide: Int {
            switch self {
            case .topLeft, .bottomLeft, .left: return -1
            case .topRight, .bottomRight, .right: return 1
            case .top, .bottom: return 0
            }
        }

        /// -1 for a handle on the top side, 1 on the bottom, 0 for one that moves neither.
        var ySide: Int {
            switch self {
            case .topLeft, .topRight, .top: return -1
            case .bottomLeft, .bottomRight, .bottom: return 1
            case .left, .right: return 0
            }
        }

        var isCorner: Bool { xSide != 0 && ySide != 0 }
    }

    struct Handle: Equatable {
        let mark: Mark.ID
        let position: HandlePosition
        /// The square drawn at a corner; an edge handle is not drawn.
        let square: CGRect?
        let hitArea: CGRect
    }

    /// A lone selected area pin and its area's corners, in image px, where the pins draw its corner
    /// handles in its gel.
    struct PinCorners: Equatable {
        let pin: Pin
        let corners: [CGPoint]
    }

    enum DotKind: Equatable { case start, end, middle }

    struct Dot: Equatable {
        let mark: Mark.ID
        let kind: DotKind
        let center: CGPoint
        let radius: CGFloat
        let hitRadius: CGFloat
        /// Drawn with its halo.
        let hovered: Bool
    }

    /// The selection and hover as the view draws them, in px at the current zoom.
    struct Overlay: Equatable {
        /// The marks with the selection outline, in drawing order.
        var selected: [Mark.ID] = []
        /// The mark with the hover outline.
        var hovered: Mark.ID?
        /// The frame around several selected marks, or around one selected rectangle, ellipse or text.
        var frame: CGRect?
        var handles: [Handle] = []
        var dots: [Dot] = []
        var brush: CGRect?
        /// The width a Text tool drag is choosing, as the new text's first line.
        var wrap: CGRect?
    }

    /// What a press would act on.
    enum Target: Equatable {
        case handle(Mark.ID, HandlePosition)
        case dot(Mark.ID, DotKind)
        case mark(Mark.ID)
        case pin(Pin.ID)
        /// Pins drawn as one capsule, in number order.
        case cluster([Pin.ID])
    }
}
