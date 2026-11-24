import AppKit
import SwiftUI

// MARK: The message field's box as one outline, and the bar's blurs of what is behind it

/// The message field's box. One line high, it is a rounded rectangle. Grown, its leading end stays
/// one line high around the target, as a tab, and its trailing `tallWidth` grows with the words. One
/// outline wraps both: under the tab it turns down into the tall part through a concave corner, and
/// every corner is a curve. The box's height comes from the rect, which `GrowingField` springs, so
/// the outline changes on the same spring as the box.
struct FieldOutline: Shape, Equatable {
    /// From the box's trailing edge to the tall part's leading edge.
    let tallWidth: CGFloat
    static let lineHeight: CGFloat = 30
    static let radius: CGFloat = 7

    func path(in rect: CGRect) -> Path {
        let drop = rect.height - Self.lineHeight
        let joinX = rect.maxX - tallWidth
        // Two corners on the tab's bottom edge, and two on the tall part's leading edge.
        let cornersReach = 2 * Self.cornerReach * Self.radius
        guard drop > 0, joinX - rect.minX >= cornersReach else {
            return RoundedRectangle(cornerRadius: Self.radius, style: .continuous).path(in: rect)
        }
        // A drop shorter than the two corners on the tall part's leading edge shrinks both, so the
        // outline flattens into the one-line box as the box shrinks to one line.
        let fit = min(1, drop / cornersReach)
        let tabBottom = rect.minY + Self.lineHeight
        let up = CGVector(dx: 0, dy: -1), down = CGVector(dx: 0, dy: 1)
        let left = CGVector(dx: -1, dy: 0), right = CGVector(dx: 1, dy: 0)
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY + Self.lineHeight / 2))
        addCorner(to: &path, at: CGPoint(x: rect.maxX, y: rect.maxY), from: down, to: left, radius: Self.radius)
        addCorner(to: &path, at: CGPoint(x: joinX, y: rect.maxY), from: left, to: up, radius: Self.radius * fit)
        addCorner(to: &path, at: CGPoint(x: joinX, y: tabBottom), from: up, to: left, radius: Self.radius * fit)
        addCorner(to: &path, at: CGPoint(x: rect.minX, y: tabBottom), from: left, to: up, radius: Self.radius)
        addCorner(to: &path, at: CGPoint(x: rect.minX, y: rect.minY), from: up, to: right, radius: Self.radius)
        addCorner(to: &path, at: CGPoint(x: rect.maxX, y: rect.minY), from: right, to: down, radius: Self.radius)
        path.closeSubpath()
        return path
    }

    /// The corner of `RoundedRectangle(style: .continuous)`, read from the path SwiftUI draws, as
    /// points measured from the corner in radii: back along the edge that comes in, then on along the
    /// edge that goes out. Three curves, each its two control points and its end.
    private static let cornerReach: CGFloat = 1.528665
    private static let cornerCurves: [[(back: CGFloat, on: CGFloat)]] = [
        [(1.088492, 0), (0.868407, 0), (0.631494, 0.074911)],
        [(0.372824, 0.169060), (0.169060, 0.372824), (0.074911, 0.631494)],
        [(0, 0.868407), (0, 1.088492), (0, cornerReach)],
    ]

    /// A convex and a concave corner are drawn the same way, from the edge that comes in to the one
    /// that goes out.
    private func addCorner(to path: inout Path, at corner: CGPoint, from incoming: CGVector, to outgoing: CGVector, radius: CGFloat) {
        func point(_ p: (back: CGFloat, on: CGFloat)) -> CGPoint {
            CGPoint(x: corner.x + (outgoing.dx * p.on - incoming.dx * p.back) * radius,
                    y: corner.y + (outgoing.dy * p.on - incoming.dy * p.back) * radius)
        }
        path.addLine(to: point((Self.cornerReach, 0)))
        guard radius > 0 else { return }
        for curve in Self.cornerCurves {
            path.addCurve(to: point(curve[2]), control1: point(curve[0]), control2: point(curve[1]))
        }
    }
}

/// A blur of what is behind the window, as a popover has. SwiftUI's materials blend only with the
/// window's own content, so over the bar's panel they show the bar's edge through them. With an
/// `outline`, grown past one line, it is cut to the message field's box by a mask image redrawn at
/// each new size; otherwise by the layer's rounded corners.
struct BehindWindowBlur: NSViewRepresentable {
    let cornerRadius: CGFloat
    var material: NSVisualEffectView.Material = .popover
    var outline: FieldOutline?

    func makeNSView(context: Context) -> OutlinedEffectView {
        let view = OutlinedEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        // The bar's panel is seldom key, and an inactive effect view draws flat.
        view.state = .active
        view.wantsLayer = true
        view.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: OutlinedEffectView, context: Context) {
        view.outline = outline
    }
}

final class OutlinedEffectView: NSVisualEffectView {
    var cornerRadius: CGFloat = 0 {
        didSet { layer?.cornerRadius = cornerRadius }
    }
    var outline: FieldOutline? {
        didSet {
            if outline != oldValue { cutSize = nil }
            cut()
        }
    }
    /// The size the current cut was made for.
    private var cutSize: CGSize?

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        cut()
    }

    private func cut() {
        let size = bounds.size
        guard let outline, size != cutSize else { return }
        cutSize = size
        let grown = size.height > FieldOutline.lineHeight
        layer?.cornerRadius = grown ? 0 : cornerRadius
        layer?.masksToBounds = !grown
        guard grown else {
            maskImage = nil
            return
        }
        let path = outline.path(in: CGRect(origin: .zero, size: size)).cgPath
        maskImage = NSImage(size: size, flipped: true) { _ in
            NSColor.black.setFill()
            NSBezierPath(cgPath: path).fill()
            return true
        }
    }
}
