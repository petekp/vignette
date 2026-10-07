import AppKit
import ScreenCaptureKit
import XCTest

extension NSWindow {
    /// The window server's own picture of this window: what a person sees, with every layer where
    /// AppKit and Core Animation really put it. One pixel a point, or the screen's own pixels with
    /// `nominal` false. The window is ordered in far off every screen for the capture, and out again
    /// afterwards.
    @MainActor
    func capture(nominal: Bool = true, until ready: (NSBitmapImageRep) -> Bool) throws -> NSBitmapImageRep {
        guard #available(macOS 14.4, *) else { throw XCTSkip("Seeing the test window needs macOS 14.4") }
        setFrameOrigin(NSPoint(x: -30000, y: -30000))
        orderFrontRegardless()
        defer { orderOut(nil) }
        let scale = nominal ? 1 : backingScaleFactor
        let width = Int(frame.width * scale), height = Int(frame.height * scale)
        // The window server composites on its own schedule; wait for the view's picture to arrive.
        let deadline = Date(timeIntervalSinceNow: 5)
        while true {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            if let image = try screenCapture(width: width, height: height, nominal: nominal) {
                // The capture holds the window's own pixel values with no colour space of their own.
                let rep = NSBitmapImageRep(cgImage: colorSpace?.cgColorSpace.flatMap { image.copy(colorSpace: $0) } ?? image)
                if ready(rep) || Date() > deadline { return rep }
            } else if Date() > deadline {
                return try XCTUnwrap(nil, "ScreenCaptureKit gave no picture of the window")
            }
        }
    }

    /// One capture through ScreenCaptureKit, which gives a process its own windows with no
    /// screen-recording permission. `CGWindowListCreateImage` gives no picture of them on macOS 26.
    @available(macOS 14.4, *)
    @MainActor
    private func screenCapture(width: Int, height: Int, nominal: Bool) throws -> CGImage? {
        let id = CGWindowID(windowNumber)
        let answer = CaptureAnswer()
        Task { @MainActor in
            do {
                guard let window = try await SCShareableContent.currentProcess.windows.first(where: { $0.windowID == id }) else {
                    return answer.result = .success(nil)
                }
                let configuration = SCStreamConfiguration()
                configuration.width = width
                configuration.height = height
                configuration.captureResolution = nominal ? .nominal : .best
                configuration.ignoreShadowsSingleWindow = true
                configuration.showsCursor = false
                answer.result = .success(try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window),
                                                                                    configuration: configuration))
            } catch {
                answer.result = .failure(error)
            }
        }
        while answer.result == nil { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005)) }
        return try answer.result!.get()
    }
}

@MainActor
private final class CaptureAnswer {
    var result: Result<CGImage?, Error>?
}
