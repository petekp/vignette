import QuartzCore

/// How much of its drift ink left on the screen keeps: all of it for `awake` seconds after the last
/// thing that stirred it, a pointer move or a new mark, then less, to none over `fade`. Still ink
/// draws nothing, so the display link rests until the pointer moves again.
struct InkRest {
    static let awake: CFTimeInterval = 4
    static let fade: CFTimeInterval = 1
    private var stirred: CFTimeInterval

    init(stirredAt now: CFTimeInterval) { stirred = now }

    mutating func stir(at now: CFTimeInterval) { stirred = now }

    /// 1 while awake, then down to 0 along an ease, so the drift slows rather than stops.
    func drift(at now: CFTimeInterval) -> Double {
        let left = min(1, max(0, (Self.awake + Self.fade - (now - stirred)) / Self.fade))
        return left * left * (3 - 2 * left)
    }
}
