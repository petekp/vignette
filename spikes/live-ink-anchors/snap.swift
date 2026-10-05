// snap <out.png> <pid>...: a screenshot of these processes' windows alone
import AppKit
import ScreenCaptureKit
let args = CommandLine.arguments
let pids = Set(args.dropFirst(2).compactMap { pid_t($0) })
let sem = DispatchSemaphore(value: 0)
Task {
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    let d = content.displays[0]
    let filter = SCContentFilter(display: d, including: content.applications.filter { pids.contains($0.processID) }, exceptingWindows: [])
    let config = SCStreamConfiguration()
    config.width = d.width; config.height = d.height; config.colorSpaceName = CGColorSpace.sRGB
    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    let rep = NSBitmapImageRep(cgImage: image)
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[1]))
    sem.signal()
}
sem.wait()
