import CoreGraphics
import Foundation

/// A sideways two-finger swipe over the corner: the stack, or the lone thumbnails, follow the
/// fingers toward the screen's edge, and a release far enough or fast enough closes them. Pure:
/// `StackSwipeDriver` turns each scroll event into a `Scroll`, ticks the spring this sets running,
/// and draws `offset`.
///
/// Each gesture locks to one axis once its fingers have moved `lockDistance`, and only a gesture
/// whose start was seen can swipe. A vertical one scrolls the column as before. A mouse wheel has
/// no phases, so it always scrolls. The momentum after a sideways gesture moves nothing: the
/// release decided where the column goes.
struct StackSwipe: Equatable {
    struct Rules: Equatable {
        /// Points toward the edge past which a release closes.
        var distance: CGFloat
        /// Points a second toward the edge at which a release closes wherever it is.
        var speed: CGFloat
        /// The farthest a pull away from the edge moves the column; see `drawn(_:stretch:)`.
        var stretch: CGFloat
        /// How long the column takes to spring back, and to leave.
        var returnDuration: Double
        var exitDuration: Double
    }

    /// One scroll event, as the swipe reads it.
    struct Scroll: Equatable {
        enum Phase: Equatable { case none, mayBegin, began, changed, ended, cancelled }
        /// The fingers' phase, `.none` for a mouse wheel and for momentum.
        var phase: Phase
        var momentum = false
        /// How far the fingers moved sideways, positive toward the screen's edge.
        var dx: CGFloat = 0
        /// The vertical delta as the column's scroll applies it.
        var dy: CGFloat = 0
        /// The event's time, in seconds.
        var time: TimeInterval = 0
    }

    enum Answer: Equatable {
        case none
        /// Scroll the column by this much, as a scroll did before the swipe.
        case scrollColumn(CGFloat)
        /// The fingers moved the column.
        case moved
        /// Close the corner, then call `leave`.
        case close
    }

    enum Phase: Equatable {
        case idle
        /// Fingers rest on the trackpad: a spring in flight is held where it is.
        case touching
        /// The fingers have moved less than `lockDistance`; their movement so far.
        case deciding(dx: CGFloat, dy: CGFloat)
        case vertical
        /// `raw` is where the fingers put the column before the pull away from the edge is resisted.
        case horizontal(raw: CGFloat)
        /// Released to close; `leave` starts the exit.
        case closing
        case leaving
    }

    private struct Sample: Equatable {
        var time: TimeInterval
        var offset: CGFloat
    }

    private struct Spring: Equatable {
        var target: CGFloat
        var omega: Double
        var lastTick: TimeInterval
    }

    /// How far the fingers move before the gesture picks its axis.
    static let lockDistance: CGFloat = 3
    /// The release's speed is the column's movement over the last stretch of this long.
    static let velocityWindow: TimeInterval = 0.08
    /// The slope of the pull away from the edge where it starts, as UIScrollView's rubber band has it.
    static let pullSlope: CGFloat = 0.55

    private(set) var phase: Phase = .idle
    /// How far the column is drawn toward the screen's edge, in points; negative away from it.
    private(set) var offset: CGFloat = 0
    /// The column's speed in points a second: the release's, then the spring's.
    private(set) var velocity: CGFloat = 0
    /// The column leaves, or is coming back from leaving, as one piece: the cards' own slide-out is
    /// off while this holds.
    private(set) var carriesColumn = false
    private var spring: Spring?
    private var samples: [Sample] = []
    /// The axis of the last gesture, which its momentum follows.
    private var lastAxisVertical = true

    var isSpringing: Bool { spring != nil }
    var isSwiping: Bool { if case .horizontal = phase { return true }; return false }

    /// `swipes` is false while the corner may not swipe away, as while a card is in the annotator:
    /// a sideways gesture then moves nothing.
    mutating func scroll(_ event: Scroll, swipes: Bool, rules: Rules, now: TimeInterval) -> Answer {
        if phase == .closing || phase == .leaving { return .none }
        if event.momentum { return lastAxisVertical ? .scrollColumn(event.dy) : .none }
        switch event.phase {
        case .none:
            return .scrollColumn(event.dy)
        case .mayBegin:
            hold()
            phase = .touching
            return .none
        case .began:
            hold()
            phase = .deciding(dx: 0, dy: 0)
            return move(event, swipes: swipes, rules: rules, now: now)
        case .changed:
            return move(event, swipes: swipes, rules: rules, now: now)
        case .ended, .cancelled:
            return end(event, rules: rules, now: now)
        }
    }

    private mutating func move(_ event: Scroll, swipes: Bool, rules: Rules, now: TimeInterval) -> Answer {
        switch phase {
        case .idle, .touching, .vertical:
            // A gesture that began before the corner was there only scrolls.
            return .scrollColumn(event.dy)
        case .deciding(let dx, let dy):
            let x = dx + event.dx, y = dy + event.dy
            guard max(abs(x), abs(y)) >= Self.lockDistance else {
                phase = .deciding(dx: x, dy: y)
                return .none
            }
            guard swipes, abs(x) > abs(y) else {
                phase = .vertical
                if offset != 0 { springBack(rules: rules, now: now) }
                return .scrollColumn(y)
            }
            samples = [Sample(time: event.time, offset: offset)]
            phase = .horizontal(raw: Self.raw(offset, stretch: rules.stretch))
            follow(by: x, at: event.time, rules: rules)
            return .moved
        case .horizontal:
            guard swipes else {
                phase = .vertical
                springBack(rules: rules, now: now)
                return .none
            }
            follow(by: event.dx, at: event.time, rules: rules)
            return .moved
        case .closing, .leaving:
            return .none
        }
    }

    private mutating func follow(by dx: CGFloat, at time: TimeInterval, rules: Rules) {
        guard case .horizontal(let raw) = phase else { return }
        phase = .horizontal(raw: raw + dx)
        offset = Self.drawn(raw + dx, stretch: rules.stretch)
        samples.append(Sample(time: time, offset: offset))
        // One sample at or before the window's start stays, as the speed's starting point.
        while samples.count > 2, samples[1].time <= time - Self.velocityWindow { samples.removeFirst() }
    }

    private mutating func end(_ event: Scroll, rules: Rules, now: TimeInterval) -> Answer {
        let was = phase
        phase = .idle
        switch was {
        case .horizontal:
            lastAxisVertical = false
            let speed = Self.velocity(samples, at: event.time)
            samples = []
            let closes = event.phase == .ended && (speed >= rules.speed || (offset >= rules.distance && speed > -rules.speed))
            velocity = speed
            if closes {
                phase = .closing
                return .close
            }
            springBack(rules: rules, now: now)
            return .none
        case .vertical:
            lastAxisVertical = true
            return .scrollColumn(event.dy)
        default:
            lastAxisVertical = true
            if offset != 0 && spring == nil { springBack(rules: rules, now: now) }
            return .none
        }
    }

    /// The corner is closing: the column leaves `distance` toward the edge, carrying the release's speed.
    mutating func leave(distance: CGFloat, rules: Rules, now: TimeInterval) {
        phase = .leaving
        carriesColumn = true
        samples = []
        start(to: distance, duration: rules.exitDuration, now: now)
    }

    /// A release that was to close did not, so the column comes back.
    mutating func cancelClose(rules: Rules, now: TimeInterval) {
        guard phase == .closing else { return }
        phase = .idle
        springBack(rules: rules, now: now)
    }

    /// The corner came up again while the column left: it turns around and comes back as one piece.
    mutating func presented(rules: Rules, now: TimeInterval) {
        guard phase == .closing || phase == .leaving else { return }
        phase = .idle
        springBack(rules: rules, now: now)
    }

    /// The corner has gone: everything back at rest, for the next time it comes up.
    mutating func reset() {
        self = StackSwipe()
    }

    mutating func tick(at now: TimeInterval) {
        guard let s = spring else { return }
        let dt = now - s.lastTick
        guard dt > 0 else { return }
        (offset, velocity) = Tween.spring(value: offset, velocity: velocity, target: s.target, omega: s.omega, dt: dt)
        spring?.lastTick = now
        if Tween.settled(value: offset, velocity: velocity, target: s.target) { land() }
    }

    private mutating func springBack(rules: Rules, now: TimeInterval) {
        start(to: 0, duration: rules.returnDuration, now: now)
    }

    private mutating func start(to target: CGFloat, duration: Double, now: TimeInterval) {
        guard duration > 0, offset != target else {
            spring = Spring(target: target, omega: 0, lastTick: now)
            land()
            return
        }
        spring = Spring(target: target, omega: Tween.omega(settling: duration), lastTick: now)
    }

    private mutating func land() {
        guard let s = spring else { return }
        offset = s.target
        velocity = 0
        spring = nil
        if s.target == 0 { carriesColumn = false }
    }

    /// Fingers on the trackpad catch a spring coming back where it is. A column leaving is not caught.
    private mutating func hold() {
        guard spring != nil, phase != .leaving else { return }
        spring = nil
        velocity = 0
    }

    /// Where the column is drawn for where the fingers put it. Toward the edge it follows them one to
    /// one; away from it, it follows less and less and never passes `stretch`.
    static func drawn(_ raw: CGFloat, stretch: CGFloat) -> CGFloat {
        guard raw < 0 else { return raw }
        guard stretch > 0 else { return 0 }
        return -stretch * (1 - 1 / (-raw * pullSlope / stretch + 1))
    }

    /// The inverse of `drawn`: where the fingers would have put a column drawn at `drawn`.
    static func raw(_ drawn: CGFloat, stretch: CGFloat) -> CGFloat {
        guard drawn < 0 else { return drawn }
        guard stretch > 0 else { return 0 }
        let pulled = min(-drawn, stretch * 0.999)
        return -pulled / (pullSlope * (1 - pulled / stretch))
    }

    /// The column's speed at `now`, from where it was a `velocityWindow` before.
    private static func velocity(_ samples: [Sample], at now: TimeInterval) -> CGFloat {
        guard let last = samples.last else { return 0 }
        let from = samples.last { $0.time <= now - velocityWindow } ?? samples[0]
        let dt = now - from.time
        guard dt > 0.001 else { return 0 }
        return (last.offset - from.offset) / CGFloat(dt)
    }
}
