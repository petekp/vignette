import AppKit

/// Animates one value from wherever it is now, so a new target mid-flight retargets instead of
/// jumping. Used for window alpha, which NSAnimationContext restarts from the model value.
/// The "spring" curve also keeps its velocity across retargets, so a reversal mid-flight slows
/// and turns instead of restarting from rest. Ticks come from the screen's display link, so a
/// 120 Hz display gets a step per refresh; a fixed timer would step at 60 Hz on it.
@MainActor
final class Tween: NSObject {
    private(set) var value: CGFloat
    private var link: CADisplayLink?
    private var timer: Timer?   // only when no screen can provide a display link
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

    private func startTicking() {
        stopTicking()
        if let screen = NSScreen.main {
            let link = screen.displayLink(target: self, selector: #selector(linkTick))
            link.add(to: .main, forMode: .common)
            self.link = link
        } else {
            // Runs on the main run loop (added to it with .common below).
            timer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(timer!, forMode: .common)
        }
    }

    private func stopTicking() {
        link?.invalidate(); link = nil
        timer?.invalidate(); timer = nil
    }

    @objc private func linkTick(_ link: CADisplayLink) { tick() }

    func animate(to target: CGFloat, duration: Double, curve: String = "easeOut", completion: (() -> Void)? = nil) {
        stopTicking()
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
        startTicking()
    }

    func set(_ target: CGFloat) {
        stopTicking(); start = nil; spring = nil
        velocity = 0
        value = target
        apply(target)
    }

    /// Stops where it is, without a tick and without its completion: what it animates has gone, so
    /// applying the value again would drive a view that is no longer on screen.
    func stop() {
        stopTicking(); start = nil; spring = nil
        velocity = 0
        completion = nil
    }

    private func tick() {
        if let sp = spring { springTick(sp); return }
        guard let s = start else { return }
        let t = min(1, (CACurrentMediaTime() - s.time) / s.duration)
        value = s.value + (s.target - s.value) * Tween.ease(t, s.curve)
        apply(value)
        if t >= 1 {
            stopTicking(); start = nil
            let done = completion; completion = nil
            done?()
        }
    }

    private func springTick(_ sp: (target: CGFloat, omega: Double, lastTick: CFTimeInterval)) {
        let now = CACurrentMediaTime()
        let step = Tween.spring(value: value, velocity: velocity, target: sp.target, omega: sp.omega, dt: now - sp.lastTick)
        spring?.lastTick = now
        value = step.value
        velocity = step.velocity
        let settled = abs(value - sp.target) < 0.001 && abs(velocity) < 0.01
        if settled { value = sp.target; velocity = 0 }
        apply(value)
        if settled {
            stopTicking(); spring = nil
            let done = completion; completion = nil
            done?()
        }
    }

    /// Where a critically damped spring is `dt` after this point, in closed form. Stepping the
    /// acceleration instead multiplies the value by about (omega * dt)^2 when a tick is late, so a
    /// run loop that stalled for 50 ms threw the backdrop most of a screen past its target and it
    /// swept back into place; this lands where the spring really is, however late the tick, and a
    /// long stall simply finds it settled.
    static func spring(value: CGFloat, velocity: CGFloat, target: CGFloat, omega: Double, dt: Double) -> (value: CGFloat, velocity: CGFloat) {
        guard dt > 0, omega > 0 else { return (value, velocity) }
        // Measured from the target, a critically damped spring is (offset + slope t) e^(-omega t).
        let offset = Double(value - target)
        let slope = Double(velocity) + omega * offset
        let decay = exp(-omega * dt)
        let next = (offset + slope * dt) * decay
        return (CGFloat(Double(target) + next), CGFloat((slope - omega * (offset + slope * dt)) * decay))
    }

    private static func ease(_ t: Double, _ curve: String) -> CGFloat {
        switch curve {
        case "linear": return t
        case "easeInOut": return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        default: return 1 - pow(1 - t, 3)   // easeOut
        }
    }
}
