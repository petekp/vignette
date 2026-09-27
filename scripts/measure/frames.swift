import AVFoundation
import AppKit

// Reads a screen recording (`screencapture -x -v`) back frame by frame.
//   frames extract <movie> <folder> [start s] [end s] [width px]
//     every frame between start and end as a PNG named f<index>_<seconds>.png, scaled to width
//   frames sheet <movie> <out.png> <x> <y> <w> <h> <start s> <step s> <count> [scale]
//     the frames nearest start, start + step, …, cropped to the rect, four to a row, each
//     labelled with its time
//   frames track <movie> <x> <y> <w> <h> [start s] [end s]
//     one line per frame: its time and the rect's mean red, green and blue, 0 to 255, which is
//     how a fade, a flash or a one-frame step shows as a number
// A rect is in points from the recording's top-left corner, so for a recording of part of a
// screen it is relative to that part. Points become pixels at the main display's
// scale; FRAMES_SCALE=<n> sets it for a recording of a display with another.

let arguments = CommandLine.arguments
func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(2)
}
func number(_ index: Int, _ fallback: Double? = nil) -> Double {
    guard index < arguments.count else {
        if let fallback { return fallback }
        fail("missing argument \(index)")
    }
    guard let value = Double(arguments[index]) else { fail("not a number: \(arguments[index])") }
    return value
}

/// Every frame of the movie in time order, as a CIImage and its time. The frames are read one at a
/// time, so a long recording never sits in memory.
func frames(of path: String, from start: Double = 0, to end: Double = .infinity, _ body: (CIImage, Double) -> Void) {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    // The synchronous accessor, deprecated for the async one, keeps this a plain command line tool.
    guard let track = asset.tracks(withMediaType: .video).first else { fail("no video track in \(path)") }
    guard let reader = try? AVAssetReader(asset: asset) else { fail("can't read \(path)") }
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    reader.add(output)
    reader.startReading()
    while let sample = output.copyNextSampleBuffer() {
        let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        guard time >= start, time <= end, let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
        body(CIImage(cvPixelBuffer: buffer), time)
    }
}

/// The recording's pixels per point. The movie's size does not say it: a region is smaller than the
/// screen whatever its scale.
let pixelsPerPoint: CGFloat = ProcessInfo.processInfo.environment["FRAMES_SCALE"].flatMap(Double.init).map { CGFloat($0) }
    ?? NSScreen.main?.backingScaleFactor ?? 2

/// A rect in top-left points as a rect in the image's bottom-left pixels.
func pixels(_ x: Double, _ y: Double, _ w: Double, _ h: Double, in image: CIImage) -> CGRect {
    let s = pixelsPerPoint
    let rect = CGRect(x: x * s, y: image.extent.height - (y + h) * s, width: w * s, height: h * s).intersection(image.extent)
    if rect.isEmpty { fail("the rect is outside the recording, which is \(image.extent.width / s) by \(image.extent.height / s) points") }
    return rect
}

let context = CIContext()

func png(_ image: CGImage, to path: String) {
    guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
          (try? data.write(to: URL(fileURLWithPath: path))) != nil else { fail("can't write \(path)") }
}

switch arguments.count > 1 ? arguments[1] : "" {
case "extract":
    guard arguments.count > 3 else { fail("usage: frames extract <movie> <folder> [start] [end] [width]") }
    let folder = arguments[3]
    try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    var count = 0
    frames(of: arguments[2], from: number(4, 0), to: number(5, .infinity)) { image, time in
        let scale = arguments.count > 6 ? CGFloat(number(6)) / image.extent.width : 1
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return }
        png(cg, to: String(format: "%@/f%04d_%.3f.png", folder, count, time))
        count += 1
    }
    print("frames \(count)")

case "sheet":
    guard arguments.count > 10 else { fail("usage: frames sheet <movie> <out.png> <x> <y> <w> <h> <start> <step> <count> [scale]") }
    let (x, y, w, h) = (number(4), number(5), number(6), number(7))
    let (start, step, count) = (number(8), number(9), Int(number(10)))
    let scale = number(11, 1)
    guard count > 0 else { fail("count must be at least 1") }
    let wanted = (0..<count).map { start + Double($0) * step }
    // The nearest frame to each wanted time; recordings drop frames, so a time may have none of its own.
    var nearest = [(time: Double, image: CGImage)?](repeating: nil, count: count)
    frames(of: arguments[2], from: max(0, start - 0.1), to: wanted.last! + 0.1) { image, time in
        for (i, t) in wanted.enumerated() where nearest[i].map({ abs($0.time - t) > abs(time - t) }) ?? true {
            let rect = pixels(x, y, w, h, in: image)
            guard let cg = context.createCGImage(image, from: rect) else { continue }
            nearest[i] = (time, cg)
        }
    }
    guard let first = nearest.compactMap({ $0 }).first else { fail("no frames between \(start) and \(wanted.last!) s") }
    let cell = CGSize(width: CGFloat(first.image.width) * scale, height: CGFloat(first.image.height) * scale), label: CGFloat = 22
    let rows = (count + 3) / 4
    let size = CGSize(width: cell.width * 4, height: (cell.height + label) * CGFloat(rows))
    guard let sheet = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fail("can't make the sheet") }
    sheet.setFillColor(.white)
    sheet.fill(CGRect(origin: .zero, size: size))
    NSGraphicsContext.current = NSGraphicsContext(cgContext: sheet, flipped: false)
    for (i, frame) in nearest.enumerated() {
        guard let frame else { continue }
        let left = CGFloat(i % 4) * cell.width
        let top = size.height - CGFloat(i / 4) * (cell.height + label)
        sheet.draw(frame.image, in: CGRect(x: left, y: top - label - cell.height, width: cell.width, height: cell.height))
        (String(format: "%.3f", frame.time) as NSString).draw(at: CGPoint(x: left + 4, y: top - label + 4),
                                                              withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)])
    }
    guard let image = sheet.makeImage() else { fail("can't make the sheet") }
    png(image, to: arguments[3])
    print(arguments[3])

case "track":
    guard arguments.count > 6 else { fail("usage: frames track <movie> <x> <y> <w> <h> [start] [end]") }
    frames(of: arguments[2], from: number(7, 0), to: number(8, .infinity)) { image, time in
        let rect = pixels(number(3), number(4), number(5), number(6), in: image)
        let average = image.cropped(to: rect).applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: rect)])
        var rgba = [UInt8](repeating: 0, count: 4)
        context.render(average, toBitmap: &rgba, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        print(String(format: "%.3f %d %d %d", time, rgba[0], rgba[1], rgba[2]))
    }

default:
    fail("usage: frames extract|sheet|track …; the top of scripts/measure/frames.swift says what each takes")
}
