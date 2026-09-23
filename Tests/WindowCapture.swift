import AppKit
import XCTest

extension NSWindow {
    /// The window server's own picture of this window: what a person sees, with every layer where
    /// AppKit and Core Animation really put it. One pixel a point, or the screen's own pixels with
    /// `nominal` false. The window is ordered in far off every screen for the capture, and out again
    /// afterwards.
    @MainActor
    func capture(nominal: Bool = true, until ready: (NSBitmapImageRep) -> Bool) throws -> NSBitmapImageRep {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        // Swift has not been able to call it since the macOS 15 SDK, but it still answers for the
        // caller's own windows, with no screen-recording permission.
        let symbol = try XCTUnwrap(dlsym(dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW), "CGWindowListCreateImage"),
                                   "CGWindowListCreateImage is gone; this test needs another way to see the window")
        let createImage = unsafeBitCast(symbol, to: CreateImage.self)
        setFrameOrigin(NSPoint(x: -30000, y: -30000))
        orderFrontRegardless()
        defer { orderOut(nil) }
        // The window server composites on its own schedule; wait for the view's picture to arrive.
        let deadline = Date(timeIntervalSinceNow: 5)
        while true {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            let options = CGWindowImageOption.boundsIgnoreFraming.rawValue | (nominal ? CGWindowImageOption.nominalResolution.rawValue : 0)
            if let image = createImage(.null, CGWindowListOption.optionIncludingWindow.rawValue, CGWindowID(windowNumber), options)?.takeRetainedValue() {
                let rep = NSBitmapImageRep(cgImage: image)
                if ready(rep) || Date() > deadline { return rep }
            } else if Date() > deadline {
                return try XCTUnwrap(nil, "the window server gave no picture of the window")
            }
        }
    }
}
