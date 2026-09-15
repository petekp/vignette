import AppKit

/// Animates one value from wherever it is now, so a new target mid-flight retargets instead of
/// jumping. Used for window alpha, which NSAnimationContext restarts from the model value.
final class Tween {
    private(set) var value: CGFloat
    private var timer: Timer?
    private var start: (time: CFTimeInterval, value: CGFloat, target: CGFloat, duration: Double, curve: String)?
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
        start = (CACurrentMediaTime(), value, target, duration, curve)
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func set(_ target: CGFloat) {
        timer?.invalidate(); timer = nil; start = nil
        value = target
        apply(target)
    }

    private func tick() {
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

    private static func ease(_ t: Double, _ curve: String) -> CGFloat {
        switch curve {
        case "linear": return t
        case "easeInOut": return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        default: return 1 - pow(1 - t, 3)   // easeOut
        }
    }
}
