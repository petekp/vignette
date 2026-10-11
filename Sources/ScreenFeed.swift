import AppKit
import CoreMedia
import CoreVideo
import ScreenCaptureKit

/// A live picture of one display without live ink's overlay, for the pointer field, which bends the
/// screen's own pixels. ScreenCaptureKit sends a frame only when something on the display changed,
/// so a still screen costs nothing after the first. Frames are kept, not announced: whoever draws
/// takes the newest one at its own pace.
final class ScreenFeed: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    enum Failure: Error { case noPermission, noDisplay }

    private let queue = DispatchQueue(label: "vignette.screen-feed", qos: .userInteractive)
    private let lock = NSLock()
    private var stream: SCStream?
    private var latest: CVPixelBuffer?
    private var fresh = false
    private var frames = 0
    /// Runs on the main thread when the stream stops on its own.
    var onStopped: ((Error) -> Void)?

    /// Starts the stream of `display` at `pixels`, leaving out the windows `excluding` names.
    func start(display: CGDirectDisplayID, pixels: CGSize, excluding: [CGWindowID]) async throws {
        guard CGPreflightScreenCaptureAccess() else { throw Failure.noPermission }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let screen = content.displays.first(where: { $0.displayID == display }) else { throw Failure.noDisplay }
        let left = content.windows.filter { excluding.contains($0.windowID) }
        let filter = SCContentFilter(display: screen, excludingWindows: left)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(pixels.width)
        configuration.height = Int(pixels.height)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.displayP3
        configuration.showsCursor = false
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 4
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        // A new stream starts with no picture, and only its own frames are kept, so a frame of an
        // earlier stream, still on its way when that one stopped, is never drawn as the screen now.
        lock.withLock { self.stream = stream; latest = nil; fresh = false; frames = 0 }
        do {
            try await stream.startCapture()
        } catch {
            detach(stream)
            throw error
        }
    }

    func stop() {
        detach()?.stopCapture { _ in }
    }

    /// Forgets the stream and its last picture, about 24 MB on a 3024 by 1964 display, and answers
    /// the stream it forgot. Given a stream, forgets only that one, so a stream this feed already
    /// stopped or replaced changes nothing.
    @discardableResult
    private func detach(_ stream: SCStream? = nil) -> SCStream? {
        lock.withLock {
            guard let current = self.stream, stream.map({ $0 === current }) ?? true else { return nil }
            self.stream = nil
            latest = nil
            fresh = false
            return current
        }
    }

    /// The newest frame, and whether it arrived since the last time this was asked.
    func take() -> (frame: CVPixelBuffer, fresh: Bool)? {
        lock.withLock {
            guard let latest else { return nil }
            defer { fresh = false }
            return (latest, fresh)
        }
    }

    var frameCount: Int { lock.withLock { frames } }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: status) == .complete,
              let buffer = sampleBuffer.imageBuffer else { return }
        lock.withLock {
            guard stream === self.stream else { return }
            latest = buffer
            fresh = true
            frames += 1
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // A stream this feed already stopped or replaced says nothing.
        guard detach(stream) != nil else { return }
        DispatchQueue.main.async { [weak self] in self?.onStopped?(error) }
    }
}
