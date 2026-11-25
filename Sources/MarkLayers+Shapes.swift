import QuartzCore

/// A rectangle's, an ellipse's or an arrow's layers, as the renderer draws it (`Mark.draw`): its
/// white edge once for each shadow the edge casts, and over them the stroke and the arrowhead's
/// fill. Each edge is a stroke and a head in one container, so the two cast one shadow together.
@MainActor
final class ShapeMarkLayer {
    let root = CALayer()
    private let edges: [(container: CALayer, stroke: CAShapeLayer, fill: CAShapeLayer)]
    private let stroke = CAShapeLayer()
    private let fill = CAShapeLayer()
    /// The mark drawn, or nil for a shape that is not one.
    private var mark: Mark?
    private var markStyle: MarkStyle?
    private var pointScale: CGFloat?

    init(scale: CGFloat) {
        edges = NoteTag.shadows.map { _ in (CALayer(), CAShapeLayer(), CAShapeLayer()) }
        root.anchorPoint = .zero
        for edge in edges {
            edge.container.anchorPoint = .zero
            edge.container.addSublayer(edge.stroke)
            edge.container.addSublayer(edge.fill)
            root.addSublayer(edge.container)
        }
        root.addSublayer(stroke)
        root.addSublayer(fill)
        for shape in shapeLayers {
            shape.anchorPoint = .zero
            shape.lineCap = .round
            shape.lineJoin = .round
        }
        setScale(scale)
    }

    private var shapeLayers: [CAShapeLayer] { edges.flatMap { [$0.stroke, $0.fill] } + [stroke, fill] }

    func setScale(_ scale: CGFloat) {
        for shape in shapeLayers { shape.contentsScale = scale }
        for edge in edges { edge.container.contentsScale = scale }
    }

    /// Draws `mark`, unless it is drawn already as it is, in this style and at this point scale.
    func show(_ mark: Mark, pointScale: CGFloat, markStyle: MarkStyle) {
        guard mark != self.mark || markStyle != self.markStyle || pointScale != self.pointScale,
              let shape = mark.shape(pointScale: pointScale, markStyle: markStyle) else { return }
        show(shape, color: mark.color, pointScale: pointScale, markStyle: markStyle)
        self.mark = mark
    }

    /// Draws itself on after `delay`, as a hand draws: the stroke grows from its start over
    /// `duration`, and the arrowhead appears as the stroke reaches it.
    func drawOn(after delay: CFTimeInterval, duration: CFTimeInterval) {
        guard duration > 0 else { return }
        let begin = CACurrentMediaTime() + delay
        for layer in edges.map(\.stroke) + [stroke] {
            let grow = CABasicAnimation(keyPath: "strokeEnd")
            grow.fromValue = 0
            grow.toValue = 1
            grow.beginTime = begin
            grow.duration = duration
            grow.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0, 0.2, 1)
            grow.fillMode = .backwards
            layer.add(grow, forKey: "drawOn")
        }
        for layer in edges.map(\.fill) + [fill] {
            let appear = CABasicAnimation(keyPath: "opacity")
            appear.fromValue = 0
            appear.toValue = 1
            appear.beginTime = begin + duration * 0.85
            appear.duration = duration * 0.25
            appear.fillMode = .backwards
            layer.add(appear, forKey: "drawOn")
        }
    }

    /// A shape that is not a mark yet, such as a live ink stroke being drawn, drawn as a mark is.
    func show(_ shape: MarkShape, color markColor: MarkColor, pointScale: CGFloat, markStyle: MarkStyle) {
        let edge = markStyle.edgeWidth * pointScale
        let size = Mark.shadowSize * pointScale
        let edgeColor = markStyle.edgeColor.cgColor, color = markStyle.color(markColor)
        for (layers, shadow) in zip(edges, NoteTag.shadows) {
            layers.stroke.path = shape.stroked
            layers.stroke.lineWidth = shape.lineWidth + 2 * edge
            layers.stroke.strokeColor = edgeColor
            layers.stroke.fillColor = nil
            layers.fill.path = shape.filled
            layers.fill.lineWidth = 2 * edge
            layers.fill.strokeColor = edgeColor
            layers.fill.fillColor = edgeColor
            // Core Animation's radius is about half the blur Core Graphics takes for the same shadow.
            layers.container.shadowColor = CGColor(gray: 0, alpha: 1)
            layers.container.shadowOpacity = Float(min(1, shadow.alpha * markStyle.shadowOpacity))
            layers.container.shadowOffset = CGSize(width: 0, height: shadow.y * size)
            layers.container.shadowRadius = shadow.blur * size / 2
        }
        stroke.path = shape.stroked
        stroke.lineWidth = shape.lineWidth
        stroke.strokeColor = color
        stroke.fillColor = nil
        fill.path = shape.filled
        fill.fillColor = color
        fill.strokeColor = nil
        mark = nil
        self.markStyle = markStyle
        self.pointScale = pointScale
    }
}
