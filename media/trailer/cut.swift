// Renders the trailer from a take, one output frame at a time, as cut.py lists them:
//
//   cut <plan.json>
//
// Each frame names one or two times in the take's movie with their opacity, the crop of the screen
// to show, the caption and how far it has turned from the one before, and how lit its key caps
// are. The frame shown at a time is the last one the recorder wrote at or before it, since the
// recorder writes a frame only when the screen changes. The crop is scaled with Lanczos to the
// output size. The caption is a pill over a blur of the frame, as in the storyboard. Writes a
// ProRes master and a PNG of the poster frame.
import AppKit
import AVFoundation
import CoreImage
import CoreText

struct Plan: Decodable {
    struct Frame: Decodable {
        /// [source, time in the movie, opacity], bottom first.
        let layers: [[Double]]
        let crop: [Double]
        let caption: Int
        let previous: Int
        let morph: Double
        let lit: Double
    }
    struct Caption: Decodable {
        let text: String
        let keys: [String]
    }
    struct Style: Decodable {
        let size: Double
        let keySize: Double
        let x: Double
        let y: Double
    }
    let source: String
    /// Where each source starts reading the movie, in seconds.
    let starts: [Double]
    let output: String
    let poster: String
    let posterFrame: Int
    let width: Int
    let height: Int
    let fps: Int
    let style: Style
    let captions: [Caption]
    let frames: [Frame]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
let ci = CIContext(options: [.workingColorSpace: sRGB, .outputColorSpace: sRGB, .cacheIntermediates: false])

// MARK: Reading the take

/// Hands out the frame on screen at a time, reading the movie forward from `start`. A time before
/// the last one asked for starts the reading again.
final class Source {
    let asset: AVURLAsset
    let track: AVAssetTrack
    let start: Double
    var reader: AVAssetReader?
    var output: AVAssetReaderTrackOutput?
    var current: (time: Double, buffer: CVPixelBuffer)?
    var next: (time: Double, buffer: CVPixelBuffer)?
    var last = -Double.infinity

    init(asset: AVURLAsset, track: AVAssetTrack, start: Double) {
        self.asset = asset
        self.track = track
        self.start = start
    }

    func restart() throws {
        reader?.cancelReading()
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        output.alwaysCopiesSampleData = false
        reader.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600_000), end: .positiveInfinity)
        reader.add(output)
        guard reader.startReading() else { fail("cut: \(reader.error?.localizedDescription ?? "cannot read the take")") }
        self.reader = reader
        self.output = output
        current = nil
        next = nil
    }

    func read() -> (time: Double, buffer: CVPixelBuffer)? {
        while let sample = output?.copyNextSampleBuffer() {
            if let buffer = CMSampleBufferGetImageBuffer(sample) {
                return (CMSampleBufferGetPresentationTimeStamp(sample).seconds, buffer)
            }
        }
        return nil
    }

    func frame(at t: Double) throws -> CVPixelBuffer {
        if t < last || reader == nil { try restart() }
        last = t
        if current == nil { current = read() }
        if next == nil { next = read() }
        while let n = next, n.time <= t {
            current = n
            next = read()
        }
        guard let current, current.time <= t + 0.001 else { fail("cut: the take has no frame at \(t) s") }
        return current.buffer
    }
}

// MARK: The caption

struct CaptionLayout {
    let pill: CGRect           // top-left coordinates, output pixels
    let text: CTLine
    let textOrigin: CGPoint
    let keys: [(rect: CGRect, line: CTLine, origin: CGPoint)]
}

func line(_ string: String, size: Double, weight: NSFont.Weight, kern: Double = 0) -> CTLine {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: NSColor.white, .kern: kern,
    ]
    return CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
}

func width(of line: CTLine) -> Double {
    Double(CTLineGetTypographicBounds(line, nil, nil, nil))
}

/// The storyboard's caption: 14 px above and below, 26 px at the ends, 14 px between the words and
/// the keys, 6 px between keys, and key caps at least 38 px wide and 40 px tall.
func layout(_ caption: Plan.Caption, style: Plan.Style) -> CaptionLayout {
    let text = line(caption.text, size: style.size, weight: .semibold, kern: -0.2)
    var ascent: CGFloat = 0, descent: CGFloat = 0
    CTLineGetTypographicBounds(text, &ascent, &descent, nil)
    let keyHeight = 40.0, keyGap = 6.0, padX = 26.0, padY = 14.0, gap = 14.0
    let lineHeight = style.size * 1.2
    let height = max(lineHeight, caption.keys.isEmpty ? 0 : keyHeight) + padY * 2
    var x = style.x + padX
    let textWidth = width(of: text)
    let centreY = style.y + height / 2
    let textOrigin = CGPoint(x: x, y: centreY + (ascent - descent) / 2)
    x += textWidth
    var keys: [(CGRect, CTLine, CGPoint)] = []
    if !caption.keys.isEmpty { x += gap }
    for (i, key) in caption.keys.enumerated() {
        let label = line(key, size: style.keySize, weight: .medium)
        var a: CGFloat = 0, d: CGFloat = 0
        CTLineGetTypographicBounds(label, &a, &d, nil)
        let w = max(38, width(of: label) + 16)
        let rect = CGRect(x: x, y: centreY - keyHeight / 2, width: w, height: keyHeight)
        keys.append((rect, label, CGPoint(x: rect.midX - width(of: label) / 2, y: centreY + (a - d) / 2)))
        x += w + (i < caption.keys.count - 1 ? keyGap : 0)
    }
    let pill = CGRect(x: style.x, y: style.y, width: x + padX - style.x, height: height)
    return CaptionLayout(pill: pill, text: text, textOrigin: textOrigin, keys: keys)
}

/// A mask of the pill, in Core Image's bottom-left coordinates, white where it is fully up.
func pillMask(_ pill: CGRect, alpha: Double, width: Int, height: Int) -> CIImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    let flipped = CGRect(x: pill.minX, y: Double(height) - pill.maxY, width: pill.width, height: pill.height)
    ctx.setFillColor(gray: alpha, alpha: 1)
    ctx.addPath(CGPath(roundedRect: flipped, cornerWidth: pill.height / 2, cornerHeight: pill.height / 2, transform: nil))
    ctx.fillPath()
    return CIImage(cgImage: ctx.makeImage()!)
}

func mix(_ a: CGRect, _ b: CGRect, _ e: Double) -> CGRect {
    CGRect(x: a.minX + (b.minX - a.minX) * e, y: a.minY + (b.minY - a.minY) * e,
           width: a.width + (b.width - a.width) * e, height: a.height + (b.height - a.height) * e)
}

/// The caption on one frame: the pill's rect and how much of it is up, and each caption's words at
/// their own opacity. While one caption turns into the next, the pill changes width and the words
/// cross-fade inside it.
struct CaptionFrame {
    let pill: CGRect
    let alpha: Double
    let contents: [(layout: CaptionLayout, alpha: Double, lit: Double)]

    init?(_ frame: Plan.Frame, layouts: [CaptionLayout]) {
        guard frame.caption >= 0 else { return nil }
        let now = layouts[frame.caption]
        let m = frame.morph
        guard frame.previous >= 0, m < 1 else {
            // A caption with none before it fades in where it is.
            let alpha = frame.previous < 0 ? m : 1
            pill = now.pill
            self.alpha = alpha
            contents = [(now, alpha, frame.lit)]
            return
        }
        let before = layouts[frame.previous]
        pill = mix(before.pill, now.pill, m)
        alpha = 1
        // The old words are gone before the new ones start, so the two never overlap.
        let out = 1 - min(m / 0.4, 1)
        let into = max((m - 0.45) / 0.55, 0)
        contents = [(before, out, 0), (now, into, frame.lit)].filter { $0.1 > 0 }
    }
}

/// Draws the words, the key caps and the pill's hairline into a context whose origin is top left.
func drawCaption(_ c: CaptionFrame, in ctx: CGContext) {
    let r = c.pill.height / 2
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.1 * c.alpha))
    ctx.setLineWidth(1)
    ctx.addPath(CGPath(roundedRect: c.pill.insetBy(dx: -0.5, dy: -0.5), cornerWidth: r + 0.5, cornerHeight: r + 0.5, transform: nil))
    ctx.strokePath()
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: c.pill, cornerWidth: r, cornerHeight: r, transform: nil))
    ctx.clip()
    for (l, alpha, lit) in c.contents {
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        for key in l.keys {
            let path = CGPath(roundedRect: key.rect, cornerWidth: 9, cornerHeight: 9, transform: nil)
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.14 + 0.28 * lit))
            ctx.addPath(path)
            ctx.fillPath()
            // The key's lower lip, then its hairline.
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35))
            ctx.fill(CGRect(x: key.rect.minX, y: key.rect.maxY - 2, width: key.rect.width, height: 2))
            ctx.restoreGState()
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.2))
            ctx.addPath(CGPath(roundedRect: key.rect.insetBy(dx: -0.5, dy: -0.5), cornerWidth: 9.5, cornerHeight: 9.5, transform: nil))
            ctx.strokePath()
        }
        // Core Text draws with y up, so each line is drawn in a context flipped back around its baseline.
        func draw(_ line: CTLine, at origin: CGPoint) {
            ctx.saveGState()
            ctx.translateBy(x: origin.x, y: origin.y)
            ctx.scaleBy(x: 1, y: -1)
            ctx.textPosition = .zero
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }
        draw(l.text, at: l.textOrigin)
        for key in l.keys { draw(key.line, at: key.origin) }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
    ctx.restoreGState()
}

// MARK: Rendering

func render(_ plan: Plan) async throws {
    let asset = AVURLAsset(url: URL(fileURLWithPath: plan.source))
    guard let track = try await asset.loadTracks(withMediaType: .video).first else { fail("cut: no video in \(plan.source)") }
    var sources: [Int: Source] = [:]
    let outURL = URL(fileURLWithPath: plan.output)
    try? FileManager.default.removeItem(at: outURL)
    let writer = try AVAssetWriter(outputURL: outURL, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.proRes422,
        AVVideoWidthKey: plan.width,
        AVVideoHeightKey: plan.height,
        AVVideoColorPropertiesKey: [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ],
    ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: plan.width,
        kCVPixelBufferHeightKey as String: plan.height,
    ])
    writer.add(input)
    guard writer.startWriting() else { fail("cut: \(writer.error?.localizedDescription ?? "cannot write")") }
    writer.startSession(atSourceTime: .zero)

    let layouts = plan.captions.map { layout($0, style: plan.style) }
    let masks = layouts.map { pillMask($0.pill, alpha: 1, width: plan.width, height: plan.height) }
    let outW = Double(plan.width), outH = Double(plan.height)
    let tint = CIImage(color: CIColor(red: 14 / 255, green: 10 / 255, blue: 16 / 255, alpha: 0.74))

    for (i, frame) in plan.frames.enumerated() {
        let c = frame.crop
        var picture: CIImage?
        for layer in frame.layers {
            let index = Int(layer[0])
            let source = sources[index] ?? Source(asset: asset, track: track, start: plan.starts[index])
            sources[index] = source
            let buffer = try source.frame(at: layer[1])
            let srcH = Double(CVPixelBufferGetHeight(buffer))
            let image = CIImage(cvPixelBuffer: buffer, options: [.colorSpace: sRGB])
            let crop = CGRect(x: c[0], y: srcH - c[1] - c[3], width: c[2], height: c[3])
            let scale = outH / crop.height
            let lanczos = CIFilter(name: "CILanczosScaleTransform", parameters: [
                kCIInputImageKey: image.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY)),
                kCIInputScaleKey: scale,
                kCIInputAspectRatioKey: (outW / crop.width) / scale,
            ])!
            let scaled = lanczos.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: outW, height: outH))
            if let below = picture {
                picture = below.applyingFilter("CIDissolveTransition", parameters: [
                    kCIInputTargetImageKey: scaled, kCIInputTimeKey: layer[2],
                ]).cropped(to: scaled.extent)
            } else {
                picture = scaled
            }
        }
        // A source no later frame reads is finished with.
        let lowest = frame.layers.map { Int($0[0]) }.min() ?? 0
        for key in sources.keys where key < lowest { sources[key] = nil }
        guard var picture else { fail("cut: frame \(i) shows nothing") }

        let caption = CaptionFrame(frame, layouts: layouts)
        if let caption {
            let mask = caption.alpha >= 1 && caption.pill == layouts[frame.caption].pill
                ? masks[frame.caption]
                : pillMask(caption.pill, alpha: caption.alpha, width: plan.width, height: plan.height)
            let blurred = tint.composited(over: picture.clampedToExtent().applyingGaussianBlur(sigma: 14))
                .cropped(to: picture.extent)
            picture = blurred.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: picture, kCIInputMaskImageKey: mask,
            ])
        }

        while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
        guard let pool = adaptor.pixelBufferPool else { fail("cut: no pixel buffer pool") }
        var out: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out)
        guard let out else { fail("cut: no pixel buffer") }
        ci.render(picture, to: out, bounds: picture.extent, colorSpace: sRGB)
        if let caption {
            CVPixelBufferLockBaseAddress(out, [])
            let ctx = CGContext(data: CVPixelBufferGetBaseAddress(out), width: plan.width, height: plan.height,
                                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(out), space: sRGB,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
            ctx.translateBy(x: 0, y: outH)
            ctx.scaleBy(x: 1, y: -1)
            drawCaption(caption, in: ctx)
            CVPixelBufferUnlockBaseAddress(out, [])
        }
        if i == plan.posterFrame { writePoster(out, to: plan.poster) }
        adaptor.append(out, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(plan.fps)))
        if i % 60 == 0 { print("frame \(i) of \(plan.frames.count)"); fflush(stdout) }
    }
    input.markAsFinished()
    await writer.finishWriting()
    if writer.status != .completed { fail("cut: \(writer.error?.localizedDescription ?? "writing failed")") }
    print("wrote \(plan.output)")
}

func writePoster(_ buffer: CVPixelBuffer, to path: String) {
    let image = CIImage(cvPixelBuffer: buffer, options: [.colorSpace: sRGB])
    guard let cg = ci.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: sRGB) else { fail("cut: no poster") }
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let data = rep.representation(using: .png, properties: [:]) else { fail("cut: no poster") }
    do { try data.write(to: URL(fileURLWithPath: path)) } catch { fail("cut: \(error)") }
}

guard CommandLine.arguments.count == 2 else { fail("usage: cut <plan.json>") }
do {
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let plan = try decoder.decode(Plan.self, from: data)
    let done = DispatchSemaphore(value: 0)
    Task {
        do { try await render(plan) } catch { fail("cut: \(error)") }
        done.signal()
    }
    done.wait()
} catch {
    fail("cut: \(error)")
}
