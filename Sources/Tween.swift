import AppKit

/// Animates one value from wherever it is now, so a new target mid-flight retargets instead of
/// jumping. Used for window alpha, which NSAnimationContext restarts from the model value.
/// The "spring" curve also keeps its velocity across retargets, so a reversal mid-flight slows
/// and turns instead of restarting from rest.
@MainActor
final class Tween {
    private(set) var value: CGFloat
    private var timer: Timer?
    private var start: (time: CFTimeInterval, value: CGFloat, target: CGFloat, duration: Double, curve: String)?
    /// A critically damped spring: no overshoot, and `omega` sized so it settles within the duration.
    private var spring: (target: CGFloat, omega: Double, lastTick: CFTimeInterval)?
    private var velocity: CGFloat = 0
    private let apply: (CGFloat) -> Void
    private var completion: (() -> Void)?

    init(initial: CGFloat, apply: @escaping (CGFloat) -> Void) {
        value = initial
        self.apply = apply
    }

    func animate(to target: CGFloat, duration: Double, curve: String = "easeOut", completion: (() -> Void)? = nil) {
        timer?.invalidate()
        self.completion = completion
        guard duration > 0, target != value else { set(target); completion?(); return }
        if curve == "spring" {
            // A critically damped step response is within 1% of its target at omega * t = 6.6.
            spring = (target, 6.6 / duration, CACurrentMediaTime())
            start = nil
        } else {
            start = (CACurrentMediaTime(), value, target, duration, curve)
            spring = nil
            velocity = 0
        }
        // Runs on the main run loop (added to it with .common below).
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func set(_ target: CGFloat) {
        timer?.invalidate(); timer = nil; start = nil; spring = nil
        velocity = 0
        value = target
        apply(target)
    }

    private func tick() {
        if let sp = spring { springTick(sp); return }
        guard let s = start else { return }
        let t = min(1, (CACurrentMediaTime() - s.time) / s.duration)
        value = s.value + (s.target - s.value) * Tween.ease(t, s.curve)
        apply(value)
        if t >= 1 {
            timer?.invalidate(); timer = nil; start = nil
            let done = completion; completion = nil
            done?()
        }
    }

    private func springTick(_ sp: (target: CGFloat, omega: Double, lastTick: CFTimeInterval)) {
        let now = CACurrentMediaTime()
        // A stalled run loop would otherwise integrate one huge step; cap it at a few frames.
        let dt = min(0.1, now - sp.lastTick)
        spring?.lastTick = now
        let w = CGFloat(sp.omega)
        let acceleration = -2 * w * velocity - w * w * (value - sp.target)
        velocity += acceleration * dt
        value += velocity * dt
        let settled = abs(value - sp.target) < 0.001 && abs(velocity) < 0.01
        if settled { value = sp.target; velocity = 0 }
        apply(value)
        if settled {
            timer?.invalidate(); timer = nil; spring = nil
            let done = completion; completion = nil
            done?()
        }
    }

    private static func ease(_ t: Double, _ curve: String) -> CGFloat {
        switch curve {
        case "linear": return t
        case "easeInOut": return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        default: return 1 - pow(1 - t, 3)   // easeOut
        }
    }
}
