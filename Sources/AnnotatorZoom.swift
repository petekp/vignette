import CoreGraphics

/// The annotator's zoom: what each input does to the level, where the frame grows, and which part
/// of the image is in view. `AnnotationController` turns events into inputs, runs the spring the
/// zoom asks for, sends back each of its ticks, and puts the frame and the picture where the
/// effects say. `Zoom` is the geometry.
///
/// The zoom moves only between the landing and the close: before the flight has landed, the window
/// would grow under a flight image still at the fitted frame, and once the card is on its way home
/// the window has to be at the frame the flight starts from.
struct AnnotatorZoom: Equatable {
    enum Input: Equatable {
        case prepare(fitted: CGRect, room: CGRect)   // an image opens in `fitted`; the frame grows within `room`
        case landed                                    // the flight put the image down
        case zoomIn, zoomOut, fit                      // Cmd+Plus, Cmd+Minus, Cmd+0
        case smart(at: CGPoint?)                       // a two-finger double tap, or a double-click on empty space
        case pinch(by: CGFloat, at: CGPoint?)          // a pinch's magnification
        case wheel(points: CGFloat, at: CGPoint?, fingers: Bool)   // a scroll with Cmd or Ctrl held
        case lift                                      // the fingers left the trackpad
        case pan(by: CGVector)                         // a plain scroll, in points
        case reveal(CGRect, image: CGSize)             // the caret, in image px
        case tick(CGFloat)                             // the spring's level now
        case arrived                                   // the spring reached its target
        case close                                     // the card is about to fly home
    }

    enum Effect: Equatable {
        /// Carry the level to `to` on a spring of this many seconds, before the motion scale.
        case spring(to: CGFloat, seconds: Double)
        /// A tick: the frame on screen, and the picture in the editor's coordinates, which run down
        /// from the top of the frame. Both are set in one turn of the run loop.
        case place(frame: CGRect, picture: CGRect)
        /// A pan: the picture moves and the frame stays.
        case movePicture(CGRect)
    }

    enum Phase: Equatable {
        case closed, flying, landed, closing
    }

    /// How far from each edge of the picture a zoom holds that edge, in points, and the part of that
    /// band where it holds it exactly (`Zoom.pulledToEdges`).
    struct EdgePull: Equatable {
        var band: CGFloat
        var pull: CGFloat
    }

    var edge = EdgePull(band: 0, pull: 0)

    private(set) var phase = Phase.closed
    /// The frame the image opened in; the zoom grows the frame from here.
    private(set) var fitted = CGRect.zero
    /// The rect the frame may grow within: the visible screen, less the strip the recent stack keeps.
    private(set) var room = CGRect.zero
    /// How far the image is magnified past the fitted frame, as the spring has carried it. One
    /// number: `Zoom.split` divides it between the frame's growth and the magnification inside it,
    /// one division per side, so those two can never disagree about it.
    private(set) var level: CGFloat = 1
    /// Where the level is heading. Every input moves this; one spring carries the level to it, so a
    /// gesture, a key and a fit bend into each other instead of stepping.
    private var target: CGFloat = 1
    /// The point the frame grows away from, as a fraction of it. See `ZoomAim`.
    private var aim = ZoomAim.fitted
    /// The same for the magnification inside a frame that can grow no further. See `ZoomPan`.
    private var pan = ZoomPan.centered
    /// Magnification inside a frame that can grow no further, per side; 1 by 1 shows the whole image.
    private(set) var camera = Zoom.none
    /// The middle of the visible part of the image, as a fraction of it, y from the top.
    private(set) var center = Zoom.center
    /// The frame on screen, as the last tick placed it.
    private(set) var frame = CGRect.zero

    /// How far each side of the frame has grown past the fitted frame. 1 by 1 is the fitted frame.
    var window: CGSize { split(level).window }
    /// The anchor in effect at the level on screen.
    var anchor: CGPoint { aim.anchor(at: level) }

    /// Where the whole picture sits in the frame: magnified by `camera` and slid so that the part of
    /// the image `center` names fills it. In the editor's coordinates, which run down from the top.
    var picture: CGRect {
        let bounds = CGRect(origin: .zero, size: frame.size)
        let up = Zoom.picture(in: bounds, camera: camera, center: center)
        return CGRect(x: up.minX, y: bounds.height - up.maxY, width: up.width, height: up.height)
    }

    /// How far a pinch may pull below the fitted size before the level stops following it.
    static let minLevel: CGFloat = 0.5
    /// How much of a pull below the fitted size the frame shows before springing back.
    static let overpull: CGFloat = 0.3
    /// The level stops where the side that fills the room first has been magnified this far past it.
    static let maxCanvasZoom: CGFloat = 8
    /// How far a two-finger double tap zooms in. Preview picks a level from the content; one step of
    /// twice the fitted size is the same gesture without guessing at what is under the cursor.
    static let smartFactor: CGFloat = 2
    /// How far Cmd+Plus and Cmd+Minus magnify, as a multiple of the level.
    static let keyStep: CGFloat = 1.25
    /// How much one point of wheel travel zooms: a factor of e to this per point, so 100 points of
    /// scroll is a zoom of e (2.7 times) in either direction.
    static let wheelRate: CGFloat = 0.01
    /// A gesture's spring. Short enough to follow the fingers; long enough that the frame still moves
    /// once per display refresh when events arrive unevenly.
    static let trackingSeconds = 0.1
    /// A step's spring: a key, a two-finger double tap, or a fit is a movement the eye follows.
    static let stepSeconds = 0.3
    /// The fit the frame makes on its way out, before the card flies back. Shorter than a step: it is
    /// the start of the card leaving rather than a zoom the person asked for.
    static let fitToCloseSeconds = 0.2

    /// What asked for a zoom: the fingers on a trackpad, or a key, a mouse wheel's notch, a two-finger
    /// double tap, or a fit.
    private enum Source { case hand, step }

    mutating func reduce(_ input: Input) -> Effect? {
        switch input {
        case .prepare(let fitted, let room):
            self = AnnotatorZoom(edge: edge, phase: .flying, fitted: fitted, room: room, frame: fitted)
            return nil
        case .landed:
            if phase == .flying { phase = .landed }
            return nil
        case .tick(let level):
            return tick(level)
        case .close:
            return close()
        default:
            break
        }
        guard phase == .landed else { return nil }
        switch input {
        case .zoomIn: return zoom(by: Self.keyStep, at: nil, from: .step)
        case .zoomOut: return zoom(by: 1 / Self.keyStep, at: nil, from: .step)
        case .fit: return zoom(by: nil, at: nil, from: .step)
        case .smart(let cursor):
            // In on the point named, or back to the fitted size from anywhere above it, as Preview
            // and Safari do.
            let zoomedIn = target > 1.001
            return zoom(by: zoomedIn ? nil : Self.smartFactor, at: zoomedIn ? nil : cursor, from: .step)
        case .pinch(let magnification, let cursor):
            return zoom(by: 1 + magnification, at: cursor, from: .hand)
        case .wheel(let points, let cursor, let fingers):
            guard points != 0, points.isFinite else { return nil }
            return zoom(by: exp(points * Self.wheelRate), at: cursor, from: fingers ? .hand : .step)
        case .lift, .arrived:
            // A pull below the fitted size lets go when the fingers lift, or when the spring has
            // caught up with a hand that stopped without lifting.
            return target < 1 ? zoom(by: nil, at: nil, from: .step) : nil
        case .pan(let delta):
            return panPicture(by: delta)
        case .reveal(let rect, let image):
            return reveal(rect, image: image)
        case .prepare, .landed, .tick, .close:
            return nil
        }
    }

    /// `factor` multiplies the target; nil asks for the fitted size. `cursor` is the point to keep in
    /// place; nil means the middle, which is where a key zooms. The frame grows away from it, and
    /// past that the picture is magnified about it.
    private mutating func zoom(by factor: CGFloat?, at cursor: CGPoint?, from source: Source) -> Effect? {
        guard fitted.width > 0 else { return nil }
        let cursor = cursor.map(Zoom.clamped) ?? Zoom.center
        let next: CGFloat
        if let factor, factor.isFinite, factor > 0 {
            // Only a hand pulls below the fit: a key or a mouse wheel's notch stops at it, as it
            // does in Preview, since there is no gesture to let go of.
            let floor = source == .hand ? Self.minLevel : 1
            next = min(maxLevel, max(floor, target * factor))
        } else {
            next = 1
        }
        // An input that moves nothing (a notch out at the fit, Cmd+0 at rest) is over here.
        guard next != target || level != target else { return nil }
        target = next
        aimFrame(at: cursor)
        aimPan(at: cursor)
        return .spring(to: target, seconds: source == .hand ? Self.trackingSeconds : Self.stepSeconds)
    }

    /// Springs the level back to the fitted size, about the middle, so the frame the flight home
    /// starts from is the one the image opened in. Nil when it is there already.
    private mutating func close() -> Effect? {
        phase = .closing
        guard fitted.width > 0, abs(level - 1) > 0.001 || abs(target - 1) > 0.001 else { return nil }
        target = 1
        aimFrame(at: Zoom.center)
        aimPan(at: Zoom.center)
        return .spring(to: 1, seconds: Self.fitToCloseSeconds)
    }

    /// The frame's rect and the picture inside it both come from the level: each side of the frame
    /// grows until it fills the room and the magnification takes the rest.
    private mutating func tick(_ level: CGFloat) -> Effect? {
        guard fitted.width > 0, level.isFinite else { return nil }
        self.level = level
        let step = split(level)
        camera = step.camera
        center = pan.center(at: step.camera)
        // Kept in the room: a frame grown to the screen's height slides rather than clips.
        frame = Zoom.frame(fitted: fitted, scale: step.window, anchor: aim.anchor(at: level), within: room)
        return .place(frame: frame, picture: picture)
    }

    /// Points the frame's growth at `cursor`. The anchor it starts from is read off the frame on
    /// screen, so the step carries on from where the frame is: a frame the room's edge has nudged
    /// does not carry that error forward, and a step aimed elsewhere mid-spring bends rather than
    /// stepping sideways. The anchor it ends at is the one the room allows, so the room gives way
    /// once, here, rather than the frame sliding part way through the spring. A frame at rest has
    /// nothing to aim.
    private mutating func aimFrame(at cursor: CGPoint) {
        guard target != level else { return }
        aim = Zoom.aim(at: cursor, of: frame, fitted: fitted, window: split(target).window,
                       from: level, to: target, within: room)
    }

    /// Points the magnification at `cursor`, from the part of the image that is visible now. Like
    /// `aimFrame`, it starts from what is on screen, so a step aimed elsewhere mid-spring bends.
    ///
    /// A cursor near an edge of the picture is pulled onto it first (`edge`): only the frame's own
    /// edge holds the image's edge with it, so without the pull the corner the cursor is beside is
    /// cropped by the first bit of magnification. The band is measured in points of the frame the
    /// cursor is over, so its reach is the same on all four edges however wide the screenshot is.
    ///
    /// Each side reaches the room at its own level, so the picture is already cropped in the side
    /// that got there first while the other is still growing. The pull is applied in both
    /// directions on every input for that reason. A side that is still growing shows the whole
    /// image in that direction, so the pull has nothing to hold there and
    /// `Zoom.clamped(center:camera:)` pins it.
    private mutating func aimPan(at cursor: CGPoint) {
        let aimed = Zoom.pulledToEdges(cursor, in: frame.size, band: edge.band, pull: edge.pull)
        let camera = split(level).camera
        pan = ZoomPan(center: pan.center(at: camera), camera: camera, cursor: aimed)
    }

    /// A plain scroll over a picture magnified past its frame moves the part in view, with the
    /// fingers, as Preview does. At the fitted size, or on a side that is still growing, there is
    /// nothing hidden to bring into view.
    private mutating func panPicture(by delta: CGVector) -> Effect? {
        guard camera.width > 1 || camera.height > 1 else { return nil }
        let picture = self.picture
        guard picture.width > 0, picture.height > 0, delta.dx.isFinite, delta.dy.isFinite,
              delta.dx != 0 || delta.dy != 0 else { return nil }
        // The content follows the fingers, so the middle of what is in view moves the other way.
        return show(CGPoint(x: center.x - delta.dx / picture.width, y: center.y - delta.dy / picture.height))
    }

    /// Moves the part of a magnified picture in view just far enough to show `rect`, in image px,
    /// with a line's height of room around it: the caret while typing. A text wraps at the image's
    /// edge, not the frame's, so without this the words typed past the frame ran on out of sight.
    private mutating func reveal(_ rect: CGRect, image: CGSize) -> Effect? {
        guard camera.width > 1 || camera.height > 1 else { return nil }
        let w = image.width, h = image.height
        guard w > 0, h > 0, [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite) else { return nil }
        let visible = Zoom.visible(center: center, camera: camera)
        // As fractions of the image, y from the top, as `center` is.
        let pad = CGSize(width: min(rect.height / w, visible.width / 4), height: min(rect.height / h, visible.height / 4))
        let want = CGRect(x: rect.minX / w - pad.width, y: rect.minY / h - pad.height,
                          width: rect.width / w + 2 * pad.width, height: rect.height / h + 2 * pad.height)
        var c = center
        if want.minX < visible.minX { c.x -= visible.minX - want.minX } else if want.maxX > visible.maxX { c.x += want.maxX - visible.maxX }
        if want.minY < visible.minY { c.y -= visible.minY - want.minY } else if want.maxY > visible.maxY { c.y += want.maxY - visible.maxY }
        return show(c)
    }

    /// Puts the visible middle at `center`, as far as the image allows, with the frame where it is.
    private mutating func show(_ wanted: CGPoint) -> Effect? {
        let c = Zoom.clamped(center: wanted, camera: camera)
        guard c != center else { return nil }
        pan = ZoomPan(center: c, camera: camera, cursor: Zoom.center)
        center = c
        return .movePicture(picture)
    }

    /// How a level divides between the frame's growth and the magnification inside it, per side.
    private func split(_ level: CGFloat) -> (window: CGSize, camera: CGSize) {
        Zoom.split(level: level, reach: reach, pull: Self.overpull)
    }

    /// How far each side of the frame may grow: to the whole of the room.
    private var reach: CGSize { Zoom.reach(fitted: fitted, within: room) }

    /// The side that fills the room first is the one magnified most, so its cap is the whole
    /// picture's.
    private var maxLevel: CGFloat { min(reach.width, reach.height) * Self.maxCanvasZoom }
}

extension AnnotatorZoom.Phase: CustomStringConvertible {
    var description: String {
        switch self {
        case .closed: return "closed"
        case .flying: return "flying"
        case .landed: return "landed"
        case .closing: return "closing"
        }
    }
}
