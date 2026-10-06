import Foundation
import QuartzCore

/// When live ink stops listening, from the input's level and the chord: a pure value, so the rule
/// has tests. Times are seconds on one clock, whichever the caller uses.
struct ListeningEnd: Equatable {
    let until: ListenUntil
    /// How long a quiet spell after the chord is let go ends listening, with `until` at `.pause`.
    let pause: TimeInterval
    /// The level under which the input is quiet.
    let quiet: Float
    /// How long listening goes on after the chord is let go, with `until` at `.release`, so the end
    /// of the last word is heard.
    static let tail: TimeInterval = 0.3
    /// Listening never runs longer than this, whatever the level says.
    static let longest: TimeInterval = 60

    private(set) var began: TimeInterval
    private(set) var released: TimeInterval?
    private(set) var lastLoud: TimeInterval?

    init(until: ListenUntil, pause: TimeInterval, quiet: Float, began: TimeInterval) {
        self.until = until
        self.pause = pause
        self.quiet = quiet
        self.began = began
    }

    mutating func heard(level: Float, at time: TimeInterval) {
        if level >= quiet { lastLoud = time }
    }

    /// The chord was let go.
    mutating func release(at time: TimeInterval) { released = time }

    /// The chord was pressed again to draw more: listening goes on until it is let go again.
    mutating func pressAgain() { released = nil }

    func isOver(at time: TimeInterval) -> Bool {
        if time >= began + Self.longest { return true }
        guard let released else { return false }
        switch until {
        case .release: return time >= released + Self.tail
        case .pause: return time >= max(released, lastLoud ?? released) + pause
        }
    }
}

/// Live ink listening to the person while they draw: the microphone into a transcriber, the words
/// as they come, and the end that `ListeningEnd` decides. One listening can span several presses of
/// the chord, so "this" and "that" drawn in two strokes are one note.
@MainActor
final class LiveListening {
    private let microphone = Microphone()
    private let transcriber: Transcriber
    private var end: ListeningEnd
    private var timer: Timer?
    private var finishing = false
    /// When listening began, the time the words' times count from.
    let began = Date()
    private(set) var words: [SpokenWord] = []
    var onWords: (([SpokenWord]) -> Void)?
    /// The final words, once listening has ended by itself or by `finish`.
    var onFinished: (([SpokenWord]) -> Void)?

    var text: String { Self.text(of: words) }

    static func text(of words: [SpokenWord]) -> String { words.map(\.text).joined(separator: " ") }

    init(transcriber: Transcriber, until: ListenUntil, pause: TimeInterval, quiet: Float) {
        self.transcriber = transcriber
        end = ListeningEnd(until: until, pause: pause, quiet: quiet, began: CACurrentMediaTime())
    }

    func start() throws {
        transcriber.onWords = { [weak self] words in
            guard let self, !self.finishing else { return }
            self.words = words
            self.onWords?(words)
        }
        try transcriber.begin(hints: [])
        microphone.onLevel = { [weak self] level in self?.end.heard(level: level, at: CACurrentMediaTime()) }
        do {
            try microphone.start(into: transcriber)
        } catch {
            transcriber.cancel()
            throw error
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.end.isOver(at: CACurrentMediaTime()) else { return }
                self.finish()
            }
        }
        Log.write("[speech] listening engine=\(transcriber.name) until=\(end.until.rawValue)")
    }

    func released() { end.release(at: CACurrentMediaTime()) }

    func pressedAgain() { end.pressAgain() }

    /// Stops the microphone and answers the final words through `onFinished`.
    func finish() {
        guard !finishing else { return }
        finishing = true
        timer?.invalidate()
        microphone.stop()
        let seconds = Date().timeIntervalSince(began)
        Task { @MainActor [weak self, transcriber] in
            let words = await transcriber.finish(timeout: 2)
            guard let self else { return }
            self.words = words
            Log.write("[speech] heard words=\(words.count) seconds=\(String(format: "%.1f", seconds))")
            self.onFinished?(words)
        }
    }

    /// Stops listening and drops what was heard.
    func cancel() {
        guard !finishing else { return }
        finishing = true
        timer?.invalidate()
        microphone.stop()
        transcriber.cancel()
        Log.write("[speech] stopped listening")
    }
}
