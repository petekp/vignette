import AppKit

extension EditorView {
    /// Screen pt per image px.
    var zoom: CGFloat {
        let width = CGFloat(core.drawing.pixels.width)
        return width > 0 ? placedPicture.width / width : 0
    }

    var toView: CGAffineTransform {
        CGAffineTransform(a: zoom, b: 0, c: 0, d: zoom, tx: placedPicture.minX, ty: placedPicture.minY)
    }

    func viewPoint(forImagePoint point: CGPoint) -> CGPoint { point.applying(toView) }

    func imagePoint(forViewPoint point: CGPoint) -> CGPoint {
        guard zoom > 0 else { return point }
        return CGPoint(x: (point.x - placedPicture.minX) / zoom, y: (point.y - placedPicture.minY) / zoom)
    }
}
