import CoreGraphics
import Foundation

/// The waveform that stands where the note's caret will be while live ink listens. It is a fixed
/// `bars` wide and rolls along the line: the bars sit on a fixed grid, each letter that appears takes
/// the place of the bars at its left end, and new bars come in at its right end. It stays on the line
/// of the last letter shown, centred on the middle of the lowercase letters and never taller than
/// `tallest`, so it never moves up and down and never changes the note's height. At the line's end the
/// bars stop at the edge and the letters take them. When listening ends it folds into a caret.
///
/// A pure value: `tick` moves it on by a frame and `bars` and `caret` say what to draw, in the words'
/// own points, x from the first letter's left edge and y down from the first line's top.
struct VoiceCaret {
    static let bars = 10
    static let pitch: CGFloat = 4
    static var width: CGFloat { CGFloat(bars) * pitch }
    static let barWidth: CGFloat = 2
    static let shortest: CGFloat = 2
    static let tallest: CGFloat = 11
    static let opacity: CGFloat = 0.7
    /// How fast the left end follows the words and the bars follow the voice: the time for a step to
    /// close by 1 - 1/e, at full motion.
    static let follow: TimeInterval = 0.04
    /// How long the bars take to fold into the caret, at full motion.
    static let fold: TimeInterval = 0.35
    /// How strongly the bars show the voice with no motion: a still waveform.
    static let stillLevel: Float = 0.3

    /// Where the last letter shown ends: `x` past its right edge, on the line whose top is `lineTop`,
    /// with the middle of its lowercase letters at `middle` and the line `lineHeight` high.
    struct Edge: Equatable {
        var x: CGFloat
        var lineTop: CGFloat
        var middle: CGFloat
        var lineHeight: CGFloat
    }

    struct Bar: Equatable {
        var x: CGFloat
        var top: CGFloat
        var height: CGFloat
        var opacity: CGFloat
    }

    /// How wide the words wrap: the bars never pass it.
    let lineWidth: CGFloat
    /// The waveform's left end, and the top of the line it is on.
    private(set) var left: CGFloat = 0
    private(set) var lineTop: CGFloat = 0
    private(set) var level: Float = 0
    /// How far the bars have folded into the caret, 0 to 1, once listening has ended.
    private(set) var folded: Double?
    private var edge: Edge

    init(lineWidth: CGFloat, edge: Edge) {
        self.lineWidth = lineWidth
        self.edge = edge
        left = Self.start(at: edge.x, lineWidth: lineWidth)
        lineTop = edge.lineTop
    }

    /// The bars have folded away.
    var isFolded: Bool { (folded ?? 0) >= 1 }

    /// Begins folding into the caret.
    mutating func fold() { if folded == nil { folded = 0 } }

    /// Moves it on by `seconds`, with the words ending at `edge` and the voice at `level`, 0 to 1. The
    /// motion scale `motion` slows nothing it follows, but at 0 it is still and folds at once.
    mutating func tick(_ seconds: TimeInterval, edge: Edge, level: Float, motion: Double) {
        self.edge = edge
        let step = motion > 0 ? CGFloat(1 - exp(-seconds / (Self.follow * motion))) : 1
        let start = Self.start(at: edge.x, lineWidth: lineWidth)
        if edge.lineTop != lineTop {
            lineTop = edge.lineTop
            left = start
        } else {
            left += (start - left) * step
        }
        self.level = motion > 0 ? self.level + (level - self.level) * Float(step) : Self.stillLevel
        if let folded {
            self.folded = motion > 0 ? min(1, folded + seconds / (Self.fold * motion)) : 1
        }
    }

    private static func start(at x: CGFloat, lineWidth: CGFloat) -> CGFloat { max(0, min(x, lineWidth - width)) }

    /// The ease of the fold, 0 listening to 1 folded.
    private var ease: CGFloat { 1 - pow(1 - CGFloat(folded ?? 0), 3) }

    /// The bars to draw, left to right. Each grid slot has its own shape, so neighbouring bars differ,
    /// and all follow the voice's level. Bars taper at both ends, and fold into the caret's place.
    var bars: [Bar] {
        let first = Int((left / Self.pitch).rounded(.up))
        let ease = ease
        return (0..<(Self.bars + 2)).compactMap { k in
            let n = first + k
            let x = CGFloat(n) * Self.pitch
            let into = x - left, past = x - edge.x
            guard into <= Self.width, past >= 0, x + Self.barWidth <= lineWidth else { return nil }
            let lead = min(1, (past + 2) / 5), tail = min(1, (Self.width - into) / 6)
            let height = Self.shortest + (Self.tallest - Self.shortest) * CGFloat(level) * Self.shape(n) * min(lead, tail)
            let opacity = Self.opacity * min(1, tail * 1.5)
            let shown = height * (1 - ease)
            let folding = x + (edge.x + 1 - x) * ease
            return Bar(x: folding, top: edge.middle - shown / 2, height: shown, opacity: opacity * (1 - ease))
        }
    }

    /// The caret the bars fold into, growing at the words' end as they go.
    var caret: Bar? {
        guard folded != nil else { return nil }
        let height = (edge.lineHeight - 2) * ease
        return Bar(x: edge.x + 1, top: edge.middle - height / 2, height: height, opacity: 1)
    }

    /// A bar's share of the level in grid slot `n`, from 0.45 to 1.
    static func shape(_ n: Int) -> CGFloat {
        let n = Double(n)
        return CGFloat(0.45 + 0.55 * abs(sin(n * 2.7 + sin(n * 0.9))))
    }
}

/// The words heard, shown a letter at a time as they come: each letter fades in over `fade`, one
/// every `interval`, faster when they fall behind, so the words never lag the voice by more than
/// `mostBehind`. A pure value; times are seconds on one clock.
struct HeardLetters {
    static let interval: TimeInterval = 0.032
    static let fade: TimeInterval = 0.16
    static let mostBehind: TimeInterval = 0.4

    private(set) var text = ""
    private var letters: [Character] = []
    /// When each letter shown began to show.
    private var shownAt: [TimeInterval] = []
    /// When the next letter shows, while letters wait.
    private var next: TimeInterval?
    /// The time between letters, set as words arrive so the letters waiting all show within
    /// `mostBehind`.
    private var pace = interval

    /// How many letters show, fully or fading in.
    var shown: Int { shownAt.count }
    var allShown: Bool { shown == letters.count }

    /// The words heard so far replace the last: letters already shown stay shown, so a word the
    /// recognizer corrects changes in place.
    mutating func hear(_ text: String) {
        self.text = text
        letters = Array(text)
        if shownAt.count > letters.count { shownAt.removeLast(shownAt.count - letters.count) }
        pace = min(Self.interval, Self.mostBehind / Double(max(1, letters.count - shownAt.count)))
    }

    /// Shows the letters due by `now`. With no motion, every letter shows at once.
    mutating func tick(at now: TimeInterval, motion: Double) {
        let waiting = letters.count - shownAt.count
        guard waiting > 0 else {
            next = nil
            return
        }
        guard motion > 0 else { return showAll(at: now) }
        let interval = pace * motion
        var at = next ?? now
        while at <= now, shownAt.count < letters.count {
            shownAt.append(at)
            at += interval
        }
        next = at
    }

    /// Shows every letter at once, fully.
    mutating func showAll(at now: TimeInterval) {
        shownAt = shownAt.map { min($0, now - Self.fade) } + Array(repeating: now - Self.fade, count: letters.count - shownAt.count)
    }

    /// How strongly letter `index` shows at `now`, 0 to 1.
    func strength(of index: Int, at now: TimeInterval, motion: Double) -> CGFloat {
        guard index < shownAt.count else { return 0 }
        guard motion > 0 else { return 1 }
        return CGFloat(min(1, max(0, (now - shownAt[index]) / (Self.fade * motion))))
    }

    /// The first letter of the newest word, which the recognizer may still change.
    var newestWord: Int { (letters.lastIndex(of: " ").map { $0 + 1 }) ?? 0 }
}

/// The voice's level from the microphone, played back at the rate it was heard. The microphone hands
/// over a tenth of a second of levels at a time, so the waveform reads them back one `step` apart.
struct VoiceLevels {
    /// The span of the input each level is measured over.
    static let step: TimeInterval = 0.01
    /// The most levels kept waiting, so the bars never trail the voice by more than this many steps.
    static let mostWaiting = 20

    private var waiting: [Float] = []
    private var owed: TimeInterval = 0
    private(set) var current: Float = 0

    mutating func add(_ levels: [Float]) {
        waiting += levels
        if waiting.count > Self.mostWaiting { waiting.removeFirst(waiting.count - Self.mostWaiting) }
    }

    /// The level `seconds` later.
    mutating func advance(_ seconds: TimeInterval) {
        owed += seconds
        while owed >= Self.step, !waiting.isEmpty {
            current = waiting.removeFirst()
            owed -= Self.step
        }
        if waiting.isEmpty { owed = 0 }
    }

    /// A slice of input's loudness, 0 to 1, from its RMS: -50 dB, a quiet room, at 0, and -15 dB,
    /// speaking close to the microphone, at 1.
    static func level(rms: Float) -> Float {
        let decibels = 20 * log10(max(rms, 1e-6))
        return min(1, max(0, (decibels + 50) / 35))
    }
}
