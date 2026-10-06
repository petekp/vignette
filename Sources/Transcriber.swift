import AVFoundation

/// One word heard, with when it was said, in seconds from the start of the audio.
struct SpokenWord: Equatable, Sendable {
    let text: String
    let start: TimeInterval
    let duration: TimeInterval

    var end: TimeInterval { start + duration }
}

/// Turns audio into timed words, on the Mac. Each speech engine conforms to this, so one can
/// replace another; the audio comes from outside, from the microphone or a file
/// (`docs/live-ink-speech-input-2026-10-06.md`).
///
/// `append` is called on the audio thread. `onWords` is called on the main thread.
protocol Transcriber: AnyObject, Sendable {
    /// The engine's name, for the log.
    var name: String { get }
    /// The format `append` takes.
    var format: AVAudioFormat { get }
    /// The words so far, each time they change. Their times may be zero until `finish` answers.
    var onWords: (@MainActor ([SpokenWord]) -> Void)? { get set }
    /// Starts listening. `hints` are words likely to be said, such as the text on the window under
    /// the ink. Throws when the engine cannot transcribe on the Mac.
    func begin(hints: [String]) throws
    func append(_ buffer: AVAudioPCMBuffer)
    /// Ends the audio and answers the final words, or the last partial ones after `timeout`.
    func finish(timeout: TimeInterval) async -> [SpokenWord]
    func cancel()
}

struct TranscriberFailure: Error, Equatable {
    /// For the person, in Vignette's voice.
    let reason: String
    /// For the log.
    let detail: String
}

/// Feeds an audio file to a transcriber as if it were heard, converted to the transcriber's format.
/// It is how an engine is tested and compared without a microphone.
enum AudioFeed {
    /// Feeds the whole file at once, or `paced` at the speed it plays, so partial words arrive as
    /// they would from a voice.
    static func feed(_ url: URL, into transcriber: Transcriber, paced: Bool = false) async throws {
        let file = try AVAudioFile(forReading: url)
        let target = transcriber.format
        let chunk = AVAudioFrameCount(file.processingFormat.sampleRate / 10)
        let converter = AVAudioConverter(from: file.processingFormat, to: target)
        while file.framePosition < file.length {
            guard let read = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk) else { return }
            try file.read(into: read, frameCount: chunk)
            guard read.frameLength > 0 else { break }
            if let converted = convert(read, with: converter, to: target) { transcriber.append(converted) }
            if paced { try await Task.sleep(nanoseconds: UInt64(Double(read.frameLength) / file.processingFormat.sampleRate * 1e9)) }
        }
    }

    /// `buffer` in `format`: as it is when the formats match, or through `converter`.
    static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter?, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        guard let converter else { return nil }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var given = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if given {
                status.pointee = .noDataNow
                return nil
            }
            given = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? out : nil
    }
}

/// The one place that picks the speech engine, so another engine replaces Apple's here.
enum SpeechEngine {
    static func make() -> Transcriber? { AppleTranscriber() }
}
