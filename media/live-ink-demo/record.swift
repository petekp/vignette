// Records the main display with ScreenCaptureKit, pointer included, into an H.264 movie, and writes
// the host time of the movie's first frame beside it. Only the windows of the processes it is given
// are in the movie, so the demo's windows and Vignette's ink show and nothing else on the Mac does.
// The trailer's recorder (media/trailer/record.swift), filtered.
//
//   record <out.mov> <seconds, or 0 for no limit> <pid>...   stops then, or on SIGINT or SIGTERM
//
// Frames arrive only when the screen changes, so the movie has a variable frame rate; the cut
// resamples it to 60 frames a second.
import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

// Its state is touched only on `queue`, where ScreenCaptureKit delivers the frames.
final class Recorder: NSObject, SCStreamOutput, @unchecked Sendable {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let sidecar: URL
    private var started = false
    private let queue = DispatchQueue(label: "record")

    init(url: URL, width: Int, height: Int) throws {
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            // The stream delivers sRGB, and video on the web is read as BT.709, whose primaries match.
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 60_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: 60,
            ],
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        sidecar = url.deletingPathExtension().appendingPathExtension("json")
        super.init()
    }

    var sampleQueue: DispatchQueue { queue }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(buffer)
        if !started {
            started = true
            writer.startWriting()
            writer.startSession(atSourceTime: time)
            let info = ["firstFrameHostTime": time.seconds]
            try? JSONSerialization.data(withJSONObject: info).write(to: sidecar)
        }
        if input.isReadyForMoreMediaData { input.append(buffer) }
    }

    func finish() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async {
                guard self.started else { done.resume(); return }
                self.input.markAsFinished()
                self.writer.finishWriting { done.resume() }
            }
        }
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 4 else { fail("usage: record <out.mov> <seconds> <pid>...") }
let out = URL(fileURLWithPath: args[1])
let limit = Double(args[2]).flatMap { $0 > 0 ? $0 : nil }
let pids = Set(args.dropFirst(3).compactMap { pid_t($0) })

let stop = DispatchSemaphore(value: 0)
for sig in [SIGINT, SIGTERM] {
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler { stop.signal() }
    source.resume()
    // Kept alive for the life of the process.
    _ = Unmanaged.passRetained(source)
}

Task {
    do {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first,
              let mode = CGDisplayCopyDisplayMode(display.displayID) else { fail("record: no display") }
        let config = SCStreamConfiguration()
        config.width = mode.pixelWidth
        config.height = mode.pixelHeight
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = true
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.queueDepth = 8
        let recorder = try Recorder(url: out, width: mode.pixelWidth, height: mode.pixelHeight)
        let stream = SCStream(filter: SCContentFilter(display: display, including: content.applications.filter { pids.contains($0.processID) }, exceptingWindows: []), configuration: config, delegate: nil)
        try stream.addStreamOutput(recorder, type: .screen, sampleHandlerQueue: recorder.sampleQueue)
        try await stream.startCapture()
        print("recording \(mode.pixelWidth)x\(mode.pixelHeight)")
        fflush(stdout)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                if let limit { _ = stop.wait(timeout: .now() + limit) } else { stop.wait() }
                done.resume()
            }
        }
        try await stream.stopCapture()
        await recorder.finish()
        print("wrote \(out.path)")
        exit(0)
    } catch {
        fail("record: \(error.localizedDescription)")
    }
}
dispatchMain()
