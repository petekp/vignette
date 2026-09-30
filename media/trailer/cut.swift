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
        /// Seconds into the end card, on its frames.
        let outro: Double?
        /// The trailer's first frame dissolving in over the end card, when the trailer loops:
        /// [source, time in the movie, opacity], with the crop it is shown at.
        let after: [Double]?
        let afterCrop: [Double]?
    }
    /// The end card: the app icon rises in, the wordmark writes itself on, then the two lines under
    /// it. Each part leaves in the reverse order from `exit`. Times are seconds into the end card.
    struct Outro: Decodable {
        let icon: String
        let wordmark: String
        let tagline: String
        let footer: String
        let exit: Double
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
    let outro: Outro?
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

// MARK: The end card

func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }

/// Ease in and out, starting and ending at rest.
func smooth(_ x: Double) -> Double { let u = clamp01(x); return u * u * (3 - 2 * u) }

/// A critically damped spring's progress from 0 to 1, 99% there after `length` seconds.
func settle(_ t: Double, from start: Double, over length: Double) -> Double {
    guard t > start else { return 0 }
    let w = 6.64 / length, u = t - start
    return 1 - (1 + w * u) * exp(-w * u)
}

/// How far a part has gone out, from the end card's exit time plus its own delay.
func leaving(_ t: Double, exit: Double, delay: Double) -> Double {
    let u = clamp01((t - exit - delay) / 0.5)
    return u * u * u
}

func loadImage(_ path: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("cut: cannot read \(path)") }
    return image
}

struct EndCard {
    let spec: Plan.Outro
    let icon: CGImage
    let wordmark: CGImage
    let tagline: CTLine
    let footer: CTLine
    let width: Double
    let height: Double

    init(_ spec: Plan.Outro, width: Int, height: Int) {
        self.spec = spec
        icon = loadImage(spec.icon)
        wordmark = loadImage(spec.wordmark)
        func text(_ s: String, size: Double, weight: NSFont.Weight, color: NSColor, kern: Double) -> CTLine {
            CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .kern: kern,
            ]))
        }
        tagline = text(spec.tagline, size: 27, weight: .regular, color: NSColor(srgbRed: 0.84, green: 0.81, blue: 0.77, alpha: 1), kern: -0.1)
        footer = text(spec.footer, size: 18, weight: .medium, color: NSColor(srgbRed: 0.55, green: 0.52, blue: 0.49, alpha: 1), kern: 0.4)
        self.width = Double(width)
        self.height = Double(height)
    }

    /// The card's background: near black, warmed by a faint glow behind the icon.
    func background() -> CIImage {
        let ctx = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
                            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0.043, green: 0.039, blue: 0.035, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let glow = CGGradient(colorsSpace: sRGB, colors: [
            CGColor(srgbRed: 1, green: 0.93, blue: 0.84, alpha: 0.07), CGColor(srgbRed: 1, green: 0.93, blue: 0.84, alpha: 0),
        ] as CFArray, locations: [0, 1])!
        let centre = CGPoint(x: width / 2, y: height * 0.56)
        ctx.drawRadialGradient(glow, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: width * 0.42, options: [])
        return CIImage(cgImage: ctx.makeImage()!)
    }

    /// The icon, the wordmark and the two lines at `t` seconds into the card, on a clear layer.
    func layer(at t: Double) -> CIImage {
        let ctx = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
                            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Top-left coordinates, as the rest of the cut uses.
        ctx.translateBy(x: 0, y: height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        let cx = width / 2
        let exit = spec.exit

        // The icon rises into place and settles, and leaves last.
        let rise = settle(t, from: 0.5, over: 1.1)
        let iconOut = leaving(t, exit: exit, delay: 0.16)
        let iconAlpha = smooth((t - 0.5) / 0.5) * (1 - iconOut)
        if iconAlpha > 0 {
            let size = 248 * (0.88 + 0.12 * rise) * (1 - 0.04 * iconOut)
            let cy = 372 + 34 * (1 - rise) - 10 * iconOut
            ctx.saveGState()
            ctx.setAlpha(iconAlpha)
            ctx.translateBy(x: cx, y: cy)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(icon, in: CGRect(x: -size / 2, y: -size / 2, width: size, height: size))
            ctx.restoreGState()
        }

        // The wordmark writes itself on from the left behind a soft edge.
        let write = smooth((t - 1.0) / 1.0)
        let markOut = leaving(t, exit: exit, delay: 0.08)
        if write > 0 && markOut < 1 {
            let h = 78.0, w = h * Double(wordmark.width) / Double(wordmark.height)
            let rect = CGRect(x: cx - w / 2, y: 560 - h / 2 - 10 * markOut + 8 * (1 - write), width: w, height: h)
            let feather = 90.0
            let edge = rect.minX - feather + (rect.width + feather * 2) * write
            ctx.saveGState()
            ctx.setAlpha(1 - markOut)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            ctx.saveGState()
            ctx.translateBy(x: rect.minX, y: rect.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(wordmark, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
            ctx.restoreGState()
            // What is not written yet is cleared, fading across the feather.
            let clear = CGGradient(colorsSpace: sRGB, colors: [
                CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0), CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
            ] as CFArray, locations: [0, 1])!
            ctx.setBlendMode(.destinationOut)
            ctx.saveGState()
            ctx.clip(to: CGRect(x: edge - feather, y: rect.minY - 20, width: rect.maxX - edge + feather + 20, height: rect.height + 40))
            ctx.drawLinearGradient(clear, start: CGPoint(x: edge - feather, y: 0), end: CGPoint(x: edge, y: 0),
                                   options: [.drawsAfterEndLocation])
            ctx.restoreGState()
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        }

        // The two lines come up after the wordmark and leave first.
        func draw(_ line: CTLine, centreY: Double, start: Double, delay: Double) {
            let inP = smooth((t - start) / 0.6), out = leaving(t, exit: exit, delay: delay)
            let alpha = inP * (1 - out)
            guard alpha > 0 else { return }
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let w = Double(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
            ctx.saveGState()
            ctx.setAlpha(alpha)
            ctx.translateBy(x: cx - w / 2, y: centreY + (ascent - descent) / 2 + 10 * (1 - inP) - 8 * out)
            ctx.scaleBy(x: 1, y: -1)
            ctx.textPosition = .zero
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }
        draw(tagline, centreY: 652, start: 1.9, delay: 0)
        draw(footer, centreY: 700, start: 2.15, delay: 0)
        return CIImage(cgImage: ctx.makeImage()!)
    }
}

/// The film as it leaves for the end card: it eases back, softens and fades into the card's
/// background over the card's first 0.8 s.
func filmLeaving(_ picture: CIImage, at t: Double, over background: CIImage) -> CIImage {
    let p = smooth(t / 0.8)
    guard p < 1 else { return background }
    let extent = picture.extent
    let scale = 1 - 0.05 * p
    let moved = picture.clampedToExtent().applyingGaussianBlur(sigma: 14 * p).cropped(to: extent)
        .transformed(by: CGAffineTransform(translationX: -extent.midX, y: -extent.midY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: extent.midX, y: extent.midY)))
    let faded = moved.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1 - p)])
    return faded.composited(over: background).cropped(to: extent)
}

// MARK: Rendering

/// A crop of a frame of the take, scaled to the output size with Lanczos.
func scaledCrop(_ buffer: CVPixelBuffer, crop c: [Double], width outW: Double, height outH: Double) -> CIImage {
    let srcH = Double(CVPixelBufferGetHeight(buffer))
    let image = CIImage(cvPixelBuffer: buffer, options: [.colorSpace: sRGB])
    let crop = CGRect(x: c[0], y: srcH - c[1] - c[3], width: c[2], height: c[3])
    let scale = outH / crop.height
    let lanczos = CIFilter(name: "CILanczosScaleTransform", parameters: [
        kCIInputImageKey: image.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY)),
        kCIInputScaleKey: scale,
        kCIInputAspectRatioKey: (outW / crop.width) / scale,
    ])!
    return lanczos.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: outW, height: outH))
}

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

    let card = plan.outro.map { EndCard($0, width: plan.width, height: plan.height) }
    let cardBackground = card?.background()

    for (i, frame) in plan.frames.enumerated() {
        var picture: CIImage?
        for layer in frame.layers {
            let index = Int(layer[0])
            let source = sources[index] ?? Source(asset: asset, track: track, start: plan.starts[index])
            sources[index] = source
            let scaled = scaledCrop(try source.frame(at: layer[1]), crop: frame.crop, width: outW, height: outH)
            if let below = picture {
                picture = below.applyingFilter("CIDissolveTransition", parameters: [
                    kCIInputTargetImageKey: scaled, kCIInputTimeKey: layer[2],
                ]).cropped(to: scaled.extent)
            } else {
                picture = scaled
            }
        }
        // A source no later frame reads is finished with.
        let lowest = (frame.layers.map { Int($0[0]) } + (frame.after.map { [Int($0[0])] } ?? [])).min() ?? 0
        for key in sources.keys where key < lowest { sources[key] = nil }
        guard var picture else { fail("cut: frame \(i) shows nothing") }

        if let t = frame.outro, let card, let cardBackground {
            picture = card.layer(at: t).composited(over: filmLeaving(picture, at: t, over: cardBackground))
                .cropped(to: picture.extent)
        }
        if let after = frame.after, let crop = frame.afterCrop {
            let index = Int(after[0])
            let source = sources[index] ?? Source(asset: asset, track: track, start: plan.starts[index])
            sources[index] = source
            let first = scaledCrop(try source.frame(at: after[1]), crop: crop, width: outW, height: outH)
            picture = picture.applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: first, kCIInputTimeKey: after[2],
            ]).cropped(to: picture.extent)
        }

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
