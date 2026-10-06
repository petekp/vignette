import AVFoundation
import Speech

/// The first speech engine: Apple's `SFSpeechRecognizer`, on the Mac only. It is the on-device
/// recognizer macOS 14 and 15 have; `SpeechAnalyzer` needs macOS 26.
final class AppleTranscriber: Transcriber, @unchecked Sendable {
    let name = "apple"
    private let recognizer: SFSpeechRecognizer
    /// Guards everything below it: `append` runs on the audio thread, the result handler on the
    /// recognizer's queue, and the rest on the main thread.
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latest: [SpokenWord] = []
    private var final: [SpokenWord]?
    private var waiting: CheckedContinuation<[SpokenWord], Never>?
    private var handler: (@MainActor ([SpokenWord]) -> Void)?

    var onWords: (@MainActor ([SpokenWord]) -> Void)? {
        get { lock.withLock { handler } }
        set { lock.withLock { handler = newValue } }
    }

    /// Nil when macOS has no recognizer for `locale`.
    init?(locale: Locale = .current) {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else { return nil }
        self.recognizer = recognizer
    }

    var format: AVAudioFormat {
        lock.withLock { request?.nativeAudioFormat } ?? SFSpeechAudioBufferRecognitionRequest().nativeAudioFormat
    }

    func begin(hints: [String]) throws {
        // Without an on-device model the request would go to Apple's servers, which speech input
        // never does.
        guard recognizer.supportsOnDeviceRecognition else {
            throw TranscriberFailure(reason: "This Mac can't turn speech into words on its own yet.", detail: "no on-device model for \(recognizer.locale.identifier)")
        }
        guard recognizer.isAvailable else {
            throw TranscriberFailure(reason: "Speech recognition isn't available right now.", detail: "recognizer unavailable")
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.contextualStrings = Array(hints.prefix(Self.hintLimit))
        lock.withLock {
            self.request = request
            latest = []
            final = nil
        }
        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            self?.received(result, error: error)
        }
        lock.withLock { self.task = task }
    }

    /// Apple gives no limit for `contextualStrings`; a window's text can run to hundreds of lines.
    static let hintLimit = 100

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { request }?.append(buffer)
    }

    func finish(timeout: TimeInterval) async -> [SpokenWord] {
        let request = lock.withLock { () -> SFSpeechAudioBufferRecognitionRequest? in
            defer { self.request = nil }
            return self.request
        }
        request?.endAudio()
        let words = await withCheckedContinuation { (continuation: CheckedContinuation<[SpokenWord], Never>) in
            let done: [SpokenWord]? = lock.withLock {
                if let final { return final }
                if task == nil { return latest }
                waiting = continuation
                return nil
            }
            if let done { continuation.resume(returning: done) }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in self?.answer(timedOut: true) }
        }
        lock.withLock { task = nil }
        return words
    }

    func cancel() {
        let task = lock.withLock { () -> SFSpeechRecognitionTask? in
            defer { self.task = nil; self.request = nil }
            return self.task
        }
        task?.cancel()
        answer(timedOut: true)
    }

    private func received(_ result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            let words = result.bestTranscription.segments.map {
                SpokenWord(text: $0.substring, start: $0.timestamp, duration: $0.duration)
            }
            let handler = lock.withLock { () -> (@MainActor ([SpokenWord]) -> Void)? in
                latest = words
                if result.isFinal { final = words }
                return self.handler
            }
            if let handler { DispatchQueue.main.async { MainActor.assumeIsolated { handler(words) } } }
            if result.isFinal { answer(timedOut: false) }
        }
        if let error {
            // "No speech detected" ends a request that heard nothing; it is not a failure.
            Log.write("[speech] \(name) ended: \((error as NSError).domain) \((error as NSError).code)")
            answer(timedOut: false)
        }
    }

    /// Answers a waiting `finish` with the final words, or the latest ones when there are none.
    private func answer(timedOut: Bool) {
        let (waiting, words) = lock.withLock { () -> (CheckedContinuation<[SpokenWord], Never>?, [SpokenWord]) in
            defer { self.waiting = nil }
            return (self.waiting, final ?? latest)
        }
        guard let waiting else { return }
        if timedOut, lock.withLock({ final == nil }) { Log.write("[speech] \(name) final words late, kept \(words.count) partial") }
        waiting.resume(returning: words)
    }
}
