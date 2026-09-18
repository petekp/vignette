import CoreGraphics

/// Where the annotator's window sits as a zoom scales it, and which point of it stays put.
///
/// The window carries the image's own aspect and the image fills it, so growing the window is
/// growing the image. One point of it keeps its place on screen while the rest grows away from
/// that point: the one under the cursor, so what the cursor is over stays under the cursor, or the
/// middle for a keyboard step. Pure geometry: no view and no settings, so the math stands on its
/// own. An anchor is a fraction of the frame, x from the left and y from the top, which is how the
/// page reports a cursor; frames count y up from the bottom, so the two directions meet here.
enum Zoom {
    /// The middle of the frame: the anchor a keyboard step uses, and the one an image opens with.
    static let center = CGPoint(x: 0.5, y: 0.5)

    /// `fitted` scaled by `scale`, with the point at `anchor` left where it is at scale 1. At
    /// scale 1 the result is `fitted` whatever the anchor, so the window always comes home to
    /// where it opened. `limit` is the screen the window may not leave. An anchor the room allows
    /// (`anchor(_:fitting:within:)`) never reaches that limit, so the clamp here is the last
    /// guard, for a scale past the room or an anchor read off a frame something else placed.
    static func frame(fitted: CGRect, scale: CGFloat, anchor: CGPoint, within limit: CGRect?) -> CGRect {
        let width = fitted.width * scale, height = fitted.height * scale
        var f = CGRect(x: fitted.minX - anchor.x * (width - fitted.width),
                       y: fitted.maxY + anchor.y * (height - fitted.height) - height,
                       width: width, height: height)
        if let limit {
            f.origin.x = min(max(f.minX, limit.minX), max(limit.minX, limit.maxX - f.width))
            f.origin.y = min(max(f.minY, limit.minY), max(limit.minY, limit.maxY - f.height))
        }
        return f
    }

    /// Aims a zoom at `cursor`, a fraction of `shown`, the frame drawn at `scale`: the window ends
    /// up at `target` with the point under the cursor still under it, as far as `limit` allows. The
    /// anchor it starts from reproduces `shown`, so the step begins where the window already is.
    static func aim(at cursor: CGPoint, of shown: CGRect, fitted: CGRect, scale: CGFloat,
                    to target: CGFloat, within limit: CGRect?) -> ZoomAim {
        let wanted = anchor(holding: cursor, of: shown, fitted: fitted, at: target)
        // Below the fitted size the frame only shrinks, and a shrunk frame is inside `fitted`,
        // which the room contains by construction. There is no growth for the room to divide, so
        // it takes nothing: the pull shrinks about the cursor's own anchor, the middle for a key.
        let now = target < 1 ? wanted : anchor(wanted, fitting: fitted, within: limit)
        // At the fitted size the frame is `fitted` whatever the anchor, so there is no growth for
        // an anchor to describe and nothing to blend from: a step from rest starts at `now`.
        // Blending from a made-up starting anchor bows the path instead.
        let was = abs(scale - 1) > 1e-6 ? anchor(holding: cursor, of: shown, fitted: fitted, at: scale) : now
        return ZoomAim(was: was, now: now, from: scale, to: target)
    }

    /// How far the window can grow before it fills the room: the scale at which one side of the
    /// frame reaches the room's own. 1 when the frame already fills the room.
    static func reach(fitted: CGRect, within limit: CGRect?) -> CGFloat {
        guard let limit, fitted.width > 0, fitted.height > 0 else { return 1 }
        return max(1, min(limit.width / fitted.width, limit.height / fitted.height))
    }

    /// `wanted` moved as little as the room allows, so that the window can grow all the way to the
    /// room about it and the frame still never reaches the room's edge. Each edge of the frame
    /// moves one way as the window grows, so an anchor that fits the whole growth fits every scale
    /// on the way to it: the frame's path from the fitted size to the room is one straight line at
    /// one set of proportions.
    ///
    /// This is where the room gives way, and it gives way once, for the whole growth, rather than
    /// per step. Holding the cursor's point exactly and letting the frame slide when it reaches
    /// the room left the picture still for most of a zoom and then sliding — measured at 2.5 points
    /// in one refresh, out of nothing, with the picture turning around as it went. In the direction
    /// the room binds there is exactly one anchor and the cursor cannot be held; in the other the
    /// room has slack and the cursor is held exactly.
    static func anchor(_ wanted: CGPoint, fitting fitted: CGRect, within limit: CGRect?) -> CGPoint {
        guard let limit, fitted.width > 0, fitted.height > 0 else { return wanted }
        let growth = reach(fitted: fitted, within: limit) - 1
        return CGPoint(x: share(wanted.x, of: fitted.width * growth,
                                near: fitted.minX - limit.minX, far: limit.maxX - fitted.maxX),
                       y: share(wanted.y, of: fitted.height * growth,
                                near: limit.maxY - fitted.maxY, far: fitted.minY - limit.minY))
    }

    /// The share of `growth` an anchor of `wanted` may put on the side it counts from. `near` is
    /// the room on that side and `far` the room on the other; the anchor keeps the growth inside
    /// both. With less room than the growth needs there is no such share, and `wanted` stands.
    private static func share(_ wanted: CGFloat, of growth: CGFloat, near: CGFloat, far: CGFloat) -> CGFloat {
        guard growth > 0 else { return wanted }
        let lowest = 1 - far / growth, highest = near / growth
        guard lowest <= highest else { return wanted }
        return min(max(wanted, lowest), highest)
    }

    /// The anchor that leaves the point at `cursor` on screen where it is when `shown`, the frame
    /// on screen now, is redrawn at `scale`. `cursor` is a fraction of `shown`.
    ///
    /// Read from the frame on screen rather than from the last anchor, so a frame the screen edge
    /// has already nudged does not carry that error into the next step. Reading it at the scale
    /// the frame is already drawn at therefore returns the anchor that reproduces that frame.
    static func anchor(holding cursor: CGPoint, of shown: CGRect, fitted: CGRect, at scale: CGFloat) -> CGPoint {
        guard fitted.width > 0, fitted.height > 0, shown.width > 0, shown.height > 0,
              scale.isFinite, abs(scale - 1) > 1e-6 else { return cursor }
        // Where the cursor's point is on screen now, and where the fitted frame's own copy of that
        // point lands once the frame has grown by `scale`. The anchor is the share of that growth
        // the frame gives back to bring the two together; y runs the other way, hence the swap.
        let held = CGPoint(x: shown.minX + cursor.x * shown.width, y: shown.maxY - cursor.y * shown.height)
        let grown = CGPoint(x: fitted.minX + cursor.x * fitted.width * scale,
                            y: fitted.maxY - cursor.y * fitted.height * scale)
        return CGPoint(x: (grown.x - held.x) / (fitted.width * (scale - 1)),
                       y: (held.y - grown.y) / (fitted.height * (scale - 1)))
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

    /// A point the page or a gesture reported, kept inside the frame it is a fraction of.
    static func clamped(_ cursor: CGPoint) -> CGPoint {
        CGPoint(x: min(max(cursor.x, 0), 1), y: min(max(cursor.y, 0), 1))
    }

    /// A visible middle kept far enough from the image's edges that the image still covers the
    /// frame. At the fitted size the whole image is visible, so the middle is the image's own.
    static func clamped(center: CGPoint, camera: CGFloat) -> CGPoint {
        guard camera.isFinite, camera >= 1 else { return center }
        let half = 0.5 / camera
        return CGPoint(x: min(max(center.x, half), 1 - half), y: min(max(center.y, half), 1 - half))
    }

    /// The part of the image a magnification of `camera` about `center` leaves visible, as
    /// fractions of the image with y from the top. The frame carries the image's own aspect, so
    /// the visible part is the same fraction in both directions.
    static func visible(center: CGPoint, camera: CGFloat) -> CGRect {
        guard camera.isFinite, camera >= 1 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let side = 1 / camera
        let c = clamped(center: center, camera: camera)
        return CGRect(x: c.x - side / 2, y: c.y - side / 2, width: side, height: side)
    }

    /// Where the whole picture sits inside the frame, in the frame's own coordinates, so that the
    /// visible part of it fills the frame: the frame magnified by `camera` and slid under it. The
    /// stand-in is laid out with this and the page is given the same `camera` and `center`, so the
    /// two draw the same picture. y counts up, as a view's frame does.
    static func picture(in bounds: CGRect, camera: CGFloat, center: CGPoint) -> CGRect {
        let v = visible(center: center, camera: camera)
        let scale = max(camera.isFinite ? camera : 1, 1)
        let w = bounds.width * scale, h = bounds.height * scale
        return CGRect(x: bounds.minX - v.minX * w, y: bounds.maxY + v.minY * h - h, width: w, height: h)
    }

    /// How far the image is magnified, divided between the window and the page's camera. The
    /// window grows until it can grow no further and the camera takes what is left, so
    /// `window * camera` is the level asked for and the two sides cannot disagree about it. Below
    /// the fitted size there is nothing to magnify: the window shows `pull` of what was asked and
    /// the camera stays at 1, which is the give a gesture pulls against.
    static func split(level: CGFloat, maxWindow: CGFloat, maxCamera: CGFloat, pull: CGFloat) -> (window: CGFloat, camera: CGFloat) {
        guard level.isFinite, level > 0, maxWindow >= 1, maxCamera >= 1 else { return (1, 1) }
        if level < 1 { return (1 - (1 - level) * pull, 1) }
        let window = min(maxWindow, level)
        return (window, min(maxCamera, level / window))
    }
}

/// The magnification's side of a zoom step in flight: the visible middle when the input arrived,
/// the magnification then, and the point the input named. The middle at any magnification follows
/// from those three, so the point under the cursor stays under it all the way through the spring —
/// what `ZoomAim` does for the window, for the part of the zoom the window cannot take.
struct ZoomPan: Equatable {
    var center: CGPoint
    var camera: CGFloat
    var cursor: CGPoint

    /// The whole image, centred: what an image opens at and what a keyboard step comes home to.
    static let centered = ZoomPan(center: Zoom.center, camera: 1, cursor: Zoom.center)

    /// The middle of the visible part of the image once the magnification is `camera`.
    func center(at camera: CGFloat) -> CGPoint {
        guard self.camera.isFinite, camera.isFinite, self.camera >= 1, camera >= 1 else { return Zoom.center }
        let was = 1 / self.camera, now = 1 / camera
        let from = Zoom.clamped(center: center, camera: self.camera)
        // The image's point under the cursor, and the middle that leaves it there once the
        // visible part has shrunk (or grown) to `now`.
        let held = CGPoint(x: from.x - was / 2 + cursor.x * was, y: from.y - was / 2 + cursor.y * was)
        return Zoom.clamped(center: CGPoint(x: held.x - cursor.x * now + now / 2,
                                            y: held.y - cursor.y * now + now / 2), camera: camera)
    }
}

/// A zoom step in flight: the anchor the window is growing away from, the one it is aimed at, and
/// the scales those belong to. In between the anchor blends, so a zoom aimed at another point
/// mid-spring bends the path instead of stepping sideways. A step that lands at once is drawn at
/// its target scale and uses the new anchor outright.
struct ZoomAim: Equatable {
    var was: CGPoint
    var now: CGPoint
    var from: CGFloat
    var to: CGFloat

    /// The window at rest, growing away from its middle.
    static let fitted = ZoomAim(was: Zoom.center, now: Zoom.center, from: 1, to: 1)

    /// The anchor at `scale`. Past either end of the step it is that end's anchor, so a spring
    /// carried further than the step asked for, or turned back from it, still moves smoothly.
    func anchor(at scale: CGFloat) -> CGPoint {
        guard abs(to - from) > 1e-6, scale.isFinite else { return now }
        let t = min(1, max(0, (scale - from) / (to - from)))
        return CGPoint(x: was.x + (now.x - was.x) * t, y: was.y + (now.y - was.y) * t)
    }
}
