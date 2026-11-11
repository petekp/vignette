import CoreGraphics
import QuartzCore

/// How the ring round the pointer moves, stepped once a refresh. Lengths are in the screen's points,
/// y down from its top-left corner.
struct PointerFieldMotion {
    /// From the arrow's tip, its hotspot, to about the middle of the arrow, so the ring sits round
    /// the arrow rather than round its tip.
    static let ringOffset = CGVector(dx: 4, dy: 6)

    /// The ring's centre, how fast it moves in points a second, and its radius.
    private(set) var centre = CGPoint.zero
    private(set) var velocity = CGVector.zero
    private(set) var radius: CGFloat = 0
    private var radiusVelocity: CGFloat = 0
    /// How fast the pointer itself has moved lately, 0 at rest to 1 at `fastSpeed`; it rises within
    /// about 0.15 s and settles over about 0.6 s.
    private(set) var energy: CGFloat = 0
    /// How loud the person's voice has been lately, 0 to 1, while live ink listens; it rises within
    /// about 0.1 s of a sound and settles over about 0.45 s once the sound stops.
    private(set) var voice: CGFloat = 0
    /// The last level heard, and when.
    private var heard: (level: CGFloat, at: CFTimeInterval)?
    /// Its colour, 0 the ice and 1 the deep blue, eased toward the one that stands out under the pointer.
    private(set) var deepness: CGFloat = 0
    private var deepnessVelocity: CGFloat = 0
    private var lastPointer: CGPoint?
    private var last: CFTimeInterval = 0

    /// A pointer speed, in points a second, that gives the lamp all its energy.
    static let fastSpeed: CGFloat = 1600
    /// How long a level heard counts. The microphone's levels come a buffer at a time, so one level
    /// stands until the next buffer's.
    static let heardFor: CFTimeInterval = 0.15

    /// Starts over round `pointer` at `now`, with no ring, so the ring grows in.
    mutating func reset(at pointer: CGPoint, now: CFTimeInterval, deep: Bool = false) {
        centre = Self.ring(at: pointer)
        velocity = .zero
        (radius, radiusVelocity) = (0, 0)
        energy = 0
        voice = 0
        heard = nil
        (deepness, deepnessVelocity) = (deep ? 1 : 0, 0)
        lastPointer = pointer
        last = now
    }

    /// The input's level, 0 to 1, heard at `time`.
    mutating func hear(_ level: CGFloat, at time: CFTimeInterval) {
        heard = (min(max(level, 0), 1), time)
    }

    /// Moves the ring on to `now`, with the pointer at `pointer`, the button down there or not, and
    /// the deep blue standing out more there or not, and answers whether anything drawn changed. It
    /// follows the pointer over `liveInkFieldFollow`, springs to its size, smaller while pressed, over
    /// `liveInkFieldFade`, and eases to its colour over `colourSettling`.
    mutating func step(to now: CFTimeInterval, pointer: CGPoint, pressed: Bool, deep: Bool = false, ui: UITweaks,
                       colourSettling: CFTimeInterval = 0.3) -> Bool {
        let dt = now - last
        last = now
        guard ui.ringShows else { return false }
        let before = (centre, radius, energy, deepness, voice)
        let travelled = lastPointer.map { hypot(pointer.x - $0.x, pointer.y - $0.y) } ?? 0
        lastPointer = pointer
        let speed = dt > 0 ? travelled / CGFloat(dt) : 0
        let wanted = min(speed / Self.fastSpeed, 1)
        // Quick to rise, slower to settle, so a flick lights it and it dims after: time constants of
        // 0.05 s and 0.2 s, three of which reach the 0.15 s and 0.6 s above.
        let rate: CGFloat = wanted > energy ? 1 / 0.05 : 1 / 0.2
        energy += (wanted - energy) * min(CGFloat(dt) * rate, 1)
        if wanted == 0, energy < 0.002 { energy = 0 }
        // The same shape for the voice, a little quicker, so the light keeps time with the syllables:
        // time constants of 0.03 s and 0.15 s.
        let loud = heard.map { now - $0.at <= Self.heardFor ? $0.level : 0 } ?? 0
        let voiceRate: CGFloat = loud > voice ? 1 / 0.03 : 1 / 0.15
        voice += (loud - voice) * min(CGFloat(dt) * voiceRate, 1)
        if loud == 0, voice < 0.002 { voice = 0 }
        (deepness, deepnessVelocity) = Tween.spring(value: deepness, velocity: deepnessVelocity, target: deep ? 1 : 0,
                                                    settling: colourSettling, dt: dt)
        let target = Self.ring(at: pointer)
        let x = Tween.spring(value: centre.x, velocity: velocity.dx, target: target.x, settling: ui.liveInkFieldFollow, dt: dt)
        let y = Tween.spring(value: centre.y, velocity: velocity.dy, target: target.y, settling: ui.liveInkFieldFollow, dt: dt)
        centre = CGPoint(x: x.value, y: y.value)
        velocity = CGVector(dx: x.velocity, dy: y.velocity)
        let size = CGFloat(ui.liveInkFieldSize) * (pressed ? 0.8 : 1)
        (radius, radiusVelocity) = Tween.spring(value: radius, velocity: radiusVelocity, target: size, settling: ui.liveInkFieldFade, dt: dt)
        return hypot(centre.x - before.0.x, centre.y - before.0.y) > 0.01 || abs(radius - before.1) > 0.01
            || abs(energy - before.2) > 0.001 || abs(deepness - before.3) > 0.001 || abs(voice - before.4) > 0.001
    }

    private static func ring(at pointer: CGPoint) -> CGPoint {
        CGPoint(x: pointer.x + ringOffset.dx, y: pointer.y + ringOffset.dy)
    }
}
