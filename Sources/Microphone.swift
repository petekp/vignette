import AppKit
import AVFoundation
import Speech

/// The microphone, while speech input listens: it hands each buffer to the transcriber, in the
/// transcriber's format, and reports how loud the input is, which tells a pause from speech.
/// macOS shows its microphone dot in the menu bar for exactly as long as this runs.
@MainActor
final class Microphone {
    private let engine = AVAudioEngine()
    private(set) var running = false
    /// The input's level, 0 to 1, about ten times a second.
    var onLevel: ((Float) -> Void)?

    func start(into transcriber: Transcriber) throws {
        guard !running else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw TranscriberFailure(reason: "Vignette couldn't find a microphone.", detail: "input has no format")
        }
        let target = transcriber.format
        let converter = AVAudioConverter(from: format, to: target)
        let report = Self.levelReporter { [weak self] level in self?.onLevel?(level) }
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(format.sampleRate / 10), format: format) { buffer, _ in
            if let converted = AudioFeed.convert(buffer, with: converter, to: target) { transcriber.append(converted) }
            report(Self.level(of: buffer))
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw TranscriberFailure(reason: "Vignette couldn't start the microphone.", detail: "\(error)")
        }
        running = true
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
    }

    /// A closure the audio thread can call, which hands the level to the main thread.
    private nonisolated static func levelReporter(_ onLevel: @escaping @MainActor (Float) -> Void) -> @Sendable (Float) -> Void {
        { level in DispatchQueue.main.async { MainActor.assumeIsolated { onLevel(level) } } }
    }

    /// The buffer's loudness as a fraction: its RMS in decibels, from -60 dB at 0 to 0 dB at 1.
    nonisolated static func level(of buffer: AVAudioPCMBuffer) -> Float {
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
