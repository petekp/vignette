import CoreGraphics

/// Where the annotator's window sits as a zoom magnifies the image, which part of the image it
/// shows, and where its growth goes.
///
/// One number drives all of it: the level, how far the image is magnified past the frame it opened
/// in. The picture is magnified uniformly by that level, so the image is never stretched; the frame
/// is not, and each side of it grows with the level until that side fills the room. A tall narrow
/// screenshot's frame therefore widens to the room's width while the whole width of the picture is
/// still inside it, and only then is the picture cropped sideways. Pure geometry: no view and no
/// settings, so the math stands on its own. An anchor is a fraction of the frame, x from the left
/// and y from the top, as the editor reports a cursor; frames count y up from the bottom,
/// so the two directions meet here.
enum Zoom {
    /// The middle of the frame: the anchor a keyboard step uses, and the one an image opens with.
    static let center = CGPoint(x: 0.5, y: 0.5)
    /// Neither grown nor magnified: the fitted frame with the whole image in it.
    static let none = CGSize(width: 1, height: 1)

    /// `fitted` with each side scaled by its own half of `scale`, with the point at `anchor` left
    /// where it is at scale 1. At scale 1 the result is `fitted` whatever the anchor, so the window
    /// always comes home to where it opened. `limit` is the room the window may not leave. The
    /// anchor the room allows (`anchor(fitted:within:)`) never reaches that limit, so the clamp
    /// here is the last guard, for a scale past the room or an anchor read off a frame something
    /// else placed.
    static func frame(fitted: CGRect, scale: CGSize, anchor: CGPoint, within limit: CGRect?) -> CGRect {
        let width = fitted.width * scale.width, height = fitted.height * scale.height
        var f = CGRect(x: fitted.minX - anchor.x * (width - fitted.width),
                       y: fitted.maxY + anchor.y * (height - fitted.height) - height,
                       width: width, height: height)
        if let limit {
            f.origin.x = min(max(f.minX, limit.minX), max(limit.minX, limit.maxX - f.width))
            f.origin.y = min(max(f.minY, limit.minY), max(limit.minY, limit.maxY - f.height))
        }
        return f
    }

    /// Aims a zoom at `cursor`, a fraction of `shown`, the frame on screen now: the window ends up
    /// at `target`, where it is drawn at `window`, as far as `limit` allows. The anchor it starts
    /// from reproduces `shown`, so the step begins where the window already is.
    ///
    /// Above the fitted size the room decides the whole growth and the cursor has no say in it —
    /// each side grows into the room that is beside it. What the cursor names is which part of the
    /// image is magnified once a side has filled the room, which is `ZoomPan`'s.
    static func aim(at cursor: CGPoint, of shown: CGRect, fitted: CGRect, window: CGSize,
                    from level: CGFloat, to target: CGFloat, within limit: CGRect?) -> ZoomAim {
        // At the fitted size the frame is `fitted` whatever the anchor, so there is no growth for
        // an anchor to describe and nothing to blend from: a step from rest starts at `now`.
        // Blending from a made-up starting anchor bows the path instead.
        let now: CGPoint
        if target < 1 || level < 1 && target == 1 {
            // Below the fitted size the frame only shrinks, and a shrunk frame is inside `fitted`,
            // which the room contains by construction. There is no growth for the room to divide,
            // so the frame keeps the line it is on: the room's, for a zoom-out that runs on through
            // the fit, or the cursor's, for a pull that starts from rest, and home from a pull is
            // straight back up that line. An anchor worked out to hold the cursor's point instead
            // divided by the shrink, which passes through zero as a zoom-out crosses the fit:
            // measured at 40 points sideways and back in three frames.
            now = anchor(reproducing: shown, fitting: fitted, or: cursor)
        } else {
            now = anchor(fitted: fitted, within: limit)
        }
        return ZoomAim(was: anchor(reproducing: shown, fitting: fitted, or: now), now: now, from: level, to: target)
    }

    /// How far each side of the frame can grow before it fills the room. 1 on a side that already
    /// fills it. The two sides reach the room at different levels, which is the whole of what makes
    /// the frame's shape change: below `min` nothing is cropped, above `max` the frame is the room.
    static func reach(fitted: CGRect, within limit: CGRect?) -> CGSize {
        guard let limit, fitted.width > 0, fitted.height > 0 else { return none }
        return CGSize(width: max(1, limit.width / fitted.width),
                      height: max(1, limit.height / fitted.height))
    }

    /// The anchor the room allows, per side: the frame grows all the way to the room in each
    /// direction, so the share of that growth on each side is the room that is already there.
    /// There is exactly one such anchor per side, and it holds for every level on the way, so the
    /// frame's path is a straight line in each direction and the clamp in `frame` never bites.
    ///
    /// The frame's growth is therefore not aimed at all. Holding the cursor's point exactly and
    /// letting the frame slide when it reaches the room left the picture still for most of a zoom
    /// and then sliding — measured at 2.5 points in one refresh, out of nothing, with the picture
    /// turning around as it went.
    static func anchor(fitted: CGRect, within limit: CGRect?) -> CGPoint {
        guard let limit else { return center }
        return CGPoint(x: share(near: fitted.minX - limit.minX, far: limit.maxX - fitted.maxX),
                       y: share(near: limit.maxY - fitted.maxY, far: fitted.minY - limit.minY))
    }

    /// The part of the growth that goes on the side `near` counts from. Half when the frame
    /// already fills the room on that axis, where there is no growth to divide.
    private static func share(near: CGFloat, far: CGFloat) -> CGFloat {
        let total = near + far
        guard total > 0, total.isFinite else { return 0.5 }
        return min(max(near / total, 0), 1)
    }

    /// The anchor that redraws `fitted` as `shown`, so a step carries on from the frame that is
    /// really there: one the screen edge has nudged, or one another zoom left mid-spring, does not
    /// carry that difference forward. A side that has not grown has no anchor to read, and takes
    /// `fallback`.
    static func anchor(reproducing shown: CGRect, fitting fitted: CGRect, or fallback: CGPoint) -> CGPoint {
        let growth = CGSize(width: shown.width - fitted.width, height: shown.height - fitted.height)
        return CGPoint(x: abs(growth.width) > 1e-9 ? (fitted.minX - shown.minX) / growth.width : fallback.x,
                       y: abs(growth.height) > 1e-9 ? (shown.maxY - fitted.maxY) / growth.height : fallback.y)
    }

    /// `cursor` pulled towards the edge of the picture it is near, so that magnifying about it
    /// keeps that edge in view. Only the very edge of the window holds the image's own edge with
    /// it: a point one per cent inside the window lets the image's edge slide out as soon as the
    /// picture magnifies at all, so a cursor beside a corner has to be within a few points of it
    /// before the corner survives a zoom.
    ///
    /// `band` is how far from each edge the pull reaches, in points of a picture `size` points
    /// across, so the reach is the same on all four edges of a picture of any shape. As a fraction
    /// of each side it was a short band on the short side: on a wide screenshot the sides held
    /// their edges and the top and bottom did not. The band reaches at most half of a side, so the
    /// middle of the picture is its own anchor whatever the band is set to.
    ///
    /// `pull` is the part of that band in which the edge is taken outright; across the rest the
    /// pull eases off to nothing at the band's inner edge, so the middle of the picture zooms about
    /// itself. The point the zoom then holds is not the one under the cursor but the one the pull
    /// names, which is what keeps the edge from being cropped.
    static func pulledToEdges(_ cursor: CGPoint, in size: CGSize, band: CGFloat, pull: CGFloat) -> CGPoint {
        guard band.isFinite, size.width > 0, size.height > 0 else { return cursor }
        return CGPoint(x: pulledToEdge(cursor.x, band: min(0.5, band / size.width), pull: pull),
                       y: pulledToEdge(cursor.y, band: min(0.5, band / size.height), pull: pull))
    }

    private static func pulledToEdge(_ fraction: CGFloat, band: CGFloat, pull: CGFloat) -> CGFloat {
        guard band > 0, band.isFinite, pull.isFinite, fraction.isFinite else { return fraction }
        let edge: CGFloat = fraction > 0.5 ? 1 : 0
        let depth = (band - abs(fraction - edge)) / band     // 0 at the band's inner edge, 1 at the edge
        guard depth > 0 else { return fraction }
        let taken = pull >= 1 ? 1 : min(1, depth / (1 - pull))
        return fraction + (edge - fraction) * max(0, taken)
    }

    /// A point the editor or a gesture reported, kept inside the frame it is a fraction of.
    static func clamped(_ cursor: CGPoint) -> CGPoint {
        CGPoint(x: min(max(cursor.x, 0), 1), y: min(max(cursor.y, 0), 1))
    }

    /// A visible middle kept far enough from the image's edges that the image still covers the
    /// frame. A direction the whole image is visible in has one middle, the image's own.
    static func clamped(center: CGPoint, camera: CGSize) -> CGPoint {
        let half = CGSize(width: 0.5 / magnification(camera.width), height: 0.5 / magnification(camera.height))
        return CGPoint(x: min(max(center.x, half.width), 1 - half.width),
                       y: min(max(center.y, half.height), 1 - half.height))
    }

    /// A magnification as the picture can really be drawn: at least 1, and never a stray number.
    private static func magnification(_ value: CGFloat) -> CGFloat {
        value.isFinite ? max(value, 1) : 1
    }

    /// How much of the image a magnification of `camera` leaves visible, as fractions of it. The
    /// frame no longer carries the image's shape, so the two directions are magnified by different
    /// amounts and this is a different fraction in each: a tall image in a frame that has widened
    /// to the room shows all of its width and a band of its height.
    static func visibleSize(camera: CGSize) -> CGSize {
        CGSize(width: 1 / magnification(camera.width), height: 1 / magnification(camera.height))
    }

    /// The part of the image `camera` about `center` leaves visible, with y from the top.
    static func visible(center: CGPoint, camera: CGSize) -> CGRect {
        let side = visibleSize(camera: camera)
        let c = clamped(center: center, camera: camera)
        return CGRect(x: c.x - side.width / 2, y: c.y - side.height / 2, width: side.width, height: side.height)
    }

    /// Where the whole picture sits inside the frame, in the frame's own coordinates, so that the
    /// visible part of it fills the frame. The editor draws its picture in this rect. y counts up, as
    /// a view's frame does.
    static func picture(in bounds: CGRect, camera: CGSize, center: CGPoint) -> CGRect {
        let v = visible(center: center, camera: camera)
        let w = bounds.width / v.width, h = bounds.height / v.height
        return CGRect(x: bounds.minX - v.minX * w, y: bounds.maxY + v.minY * h - h, width: w, height: h)
    }

    /// How far the image is magnified, divided between the frame's growth and the magnification
    /// inside it, one division per side. The frame grows until that side fills the room and the
    /// magnification takes what is left, so `window * camera` is the level asked for in each
    /// direction and the two sides cannot disagree about it. The picture itself is magnified
    /// uniformly by the level: the frame changes shape, the image does not.
    ///
    /// Below the fitted size there is nothing to magnify: the frame shrinks evenly and shows `pull`
    /// of what was asked, which is the give a gesture pulls against.
    static func split(level: CGFloat, reach: CGSize, pull: CGFloat) -> (window: CGSize, camera: CGSize) {
        guard level.isFinite, level > 0, reach.width >= 1, reach.height >= 1 else { return (none, none) }
        if level < 1 {
            let shrunk = 1 - (1 - level) * pull
            return (CGSize(width: shrunk, height: shrunk), none)
        }
        let window = CGSize(width: min(reach.width, level), height: min(reach.height, level))
        return (window, CGSize(width: level / window.width, height: level / window.height))
    }

}

/// The magnification's side of a zoom step in flight: the visible middle when the input arrived,
/// the magnification then, and the point the input named. The middle at any magnification follows
/// from those three, so the point under the cursor stays under it all the way through the spring —
/// what `ZoomAim` does for the window, for the part of the zoom the window cannot take.
struct ZoomPan: Equatable {
    var center: CGPoint
    var camera: CGSize
    var cursor: CGPoint

    /// The whole image, centred: what an image opens at and what a keyboard step comes home to.
    static let centered = ZoomPan(center: Zoom.center, camera: Zoom.none, cursor: Zoom.center)

    /// The middle of the visible part of the image once the magnification is `camera`.
    func center(at camera: CGSize) -> CGPoint {
        let was = Zoom.visible(center: center, camera: self.camera)
        let now = Zoom.visibleSize(camera: camera)
        // The image's point under the cursor, and the middle that leaves it there once the
        // visible part has shrunk (or grown) to `now`.
        let held = CGPoint(x: was.minX + cursor.x * was.width, y: was.minY + cursor.y * was.height)
        return Zoom.clamped(center: CGPoint(x: held.x - cursor.x * now.width + now.width / 2,
                                            y: held.y - cursor.y * now.height + now.height / 2),
                            camera: camera)
    }
}

/// A zoom step in flight: the anchor the window is growing away from, the one it is aimed at, and
/// the levels those belong to. In between the anchor blends, so a zoom aimed at another point
/// mid-spring bends the path instead of stepping sideways. A step that lands at once is drawn at
/// its target level and uses the new anchor outright.
struct ZoomAim: Equatable {
    var was: CGPoint
    var now: CGPoint
    var from: CGFloat
    var to: CGFloat

    /// The window at rest, growing away from its middle.
    static let fitted = ZoomAim(was: Zoom.center, now: Zoom.center, from: 1, to: 1)

    /// The anchor at `level`. Past either end of the step it is that end's anchor, so a spring
    /// carried further than the step asked for, or turned back from it, still moves smoothly.
    func anchor(at level: CGFloat) -> CGPoint {
        guard abs(to - from) > 1e-6, level.isFinite else { return now }
        let t = min(1, max(0, (level - from) / (to - from)))
        return CGPoint(x: was.x + (now.x - was.x) * t, y: was.y + (now.y - was.y) * t)
    }
}
