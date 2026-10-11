import AppKit
import AVFoundation
import Speech

/// The microphone, while speech input listens: it starts the transcriber, hands it each buffer in
/// the transcriber's format, and reports how loud the input is, which tells a pause from speech.
/// macOS shows its microphone dot in the menu bar for exactly as long as this runs.
///
/// Starting the transcriber and the engine took 80 to 165 ms on an M4 Max (2026-10-08), and on the
/// main thread it held back the pointer field and the first stroke. So both start on one queue shared by
/// every microphone, which takes starts and stops in order: a stop sent while a start is under way
/// turns the microphone off once it is on, and only then lets the transcriber end, and one
/// listening's stop is done before the next one's start.
final class Microphone: @unchecked Sendable {
    /// Each engine and its `running` are touched only on this queue.
    private static let queue = DispatchQueue(label: "vignette.microphone", qos: .userInitiated)
    private let engine = AVAudioEngine()
    private var running = false

    /// Starts the transcriber and the microphone into it, and answers on the main thread: nil once
    /// both run, or why they could not. `onLevel` gets the input's level, 0 to 1, on the main thread
    /// about ten times a second.
    func start(into transcriber: Transcriber, onLevel: @escaping @MainActor @Sendable (Float) -> Void,
               answer: @escaping @MainActor @Sendable (TranscriberFailure?) -> Void) {
        let report = Self.levelReporter(onLevel)
        Self.queue.async { [self] in
            let failure = begin(transcriber, report: report)
            DispatchQueue.main.async { MainActor.assumeIsolated { answer(failure) } }
        }
    }

    private func begin(_ transcriber: Transcriber, report: @escaping @Sendable (Float) -> Void) -> TranscriberFailure? {
        do {
            try transcriber.begin(hints: [])
        } catch {
            return error as? TranscriberFailure ?? TranscriberFailure(reason: "Vignette couldn't start listening.", detail: "\(error)")
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            transcriber.cancel()
            return TranscriberFailure(reason: "Vignette couldn't find a microphone.", detail: "input has no format")
        }
        let target = transcriber.format
        let converter = AVAudioConverter(from: format, to: target)
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(format.sampleRate / 10), format: format) { buffer, _ in
            if let converted = AudioFeed.convert(buffer, with: converter, to: target) { transcriber.append(converted) }
            report(Self.level(of: buffer))
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            transcriber.cancel()
            return TranscriberFailure(reason: "Vignette couldn't start the microphone.", detail: "\(error)")
        }
        running = true
        return nil
    }

    /// Turns the microphone off, after any start still under way, then runs `then` on the main thread.
    func stop(then: @escaping @MainActor @Sendable () -> Void) {
        Self.queue.async { [self] in
            if running {
                engine.inputNode.removeTap(onBus: 0)
                engine.stop()
                running = false
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { then() } }
        }
    }

    /// A closure the audio thread can call, which hands the level to the main thread.
    private static func levelReporter(_ onLevel: @escaping @MainActor @Sendable (Float) -> Void) -> @Sendable (Float) -> Void {
        { level in DispatchQueue.main.async { MainActor.assumeIsolated { onLevel(level) } } }
    }

    /// The buffer's loudness as a fraction: its RMS in decibels, from -60 dB at 0 to 0 dB at 1.
    static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        let decibels = 20 * log10(max(rms, 1e-6))
        return min(1, max(0, (decibels + 60) / 60))
    }
}

/// The two permissions speech input needs, the microphone's and speech recognition's. Only a switch
/// the person turned on asks for them, as Screen Recording is asked for.
enum SpeechPermission {
    static var granted: Bool { microphone == .authorized && recognition == .authorized }

    static var microphone: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }
    static var recognition: SFSpeechRecognizerAuthorizationStatus { SFSpeechRecognizer.authorizationStatus() }

    /// One of the two has not been asked yet, so macOS will show its alert.
    static var unanswered: Bool { microphone == .notDetermined || recognition == .notDetermined }

    /// Raises whichever of macOS's two alerts have not been answered, one after the other, and answers
    /// whether both are granted.
    @MainActor
    static func request(then done: @escaping @MainActor (Bool) -> Void) {
        Log.write("[speech] asking for the microphone and speech recognition")
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            SFSpeechRecognizer.requestAuthorization { _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { done(granted) } }
            }
        }
    }

    static func openSystemSettings() {
        let pane = microphone == .authorized ? "Privacy_SpeechRecognition" : "Privacy_Microphone"
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }
}
