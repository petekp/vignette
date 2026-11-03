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
    /// Starts listening. Throws when the engine cannot transcribe on the Mac.
    func begin() throws
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

/// Audio converted to a transcriber's format as it is heard.
enum AudioFeed {
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
