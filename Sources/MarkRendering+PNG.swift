import AppKit
import ImageIO

// MARK: - A full rendering

extension PixelSize {
    /// The size an image file's header gives, turned by its orientation flag: the size as displayed.
    init?(imageProperties properties: [CFString: Any]) {
        guard let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        let turned = (5...8).contains(properties[kCGImagePropertyOrientation] as? Int ?? 1)
        self.init(width: turned ? height : width, height: turned ? width : height)
    }

    /// The size as displayed of the image file at `url`, from its header alone.
    init?(imageAt url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        self.init(imageProperties: properties)
    }
}

/// A screenshot with its drawing's marks and pins, as PNG: what Done, Send and Copy Drawing hand on. It
/// is the screenshot as displayed, at its exact pixel size and in its own colour space, so every pixel
/// the marks leave alone is the screenshot's own, with the pins' comments beside it in a `withComments`
/// layout. Safe off the main thread.
enum Rendering {
    enum Failure: Error, CustomStringConvertible {
        /// The file is not an image, or not the one the drawing was made on.
        case unreadableImage(String)
        /// The bitmap could not be made, or the PNG could not be written.
        case writeFailed(String)

        var code: CommandError {
            switch self {
            case .unreadableImage: return .unreadableImage
            case .writeFailed: return .writeFailed
            }
        }

        var description: String {
            switch self {
            case .unreadableImage(let detail), .writeFailed(let detail): return detail
            }
        }

        /// What a card says, short enough for its mark; `description` has the detail for the log.
        var reason: String {
            switch self {
            case .unreadableImage: return "Vignette couldn't read the screenshot."
            case .writeFailed: return "Vignette couldn't save the drawing."
            }
        }
    }

    /// The image at `url` with `drawing` over it, laid out as `layout` says. Throws a `Failure`.
    static func png(of drawing: Drawing, imageAt url: URL, style: TextStyle, markStyle: MarkStyle, layout: Layout = .picture) throws -> Data {
        let name = url.lastPathComponent
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixels = PixelSize(imageProperties: properties),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw Failure.unreadableImage("\(name) is not an image this Mac can read")
        }
        guard pixels == drawing.pixels else {
            throw Failure.unreadableImage("\(name) is \(pixels.width)x\(pixels.height); the drawing was made on \(drawing.pixels.width)x\(drawing.pixels.height)")
        }
        var list: CommentList?
        if case .withComments(let textSize) = layout { list = CommentList(drawing, textSize: textSize, style: style, markStyle: markStyle) }
        let canvas = list?.canvas(for: pixels) ?? pixels
        guard let ctx = context(for: image, pixels: canvas) else {
            throw Failure.writeFailed("could not make a \(canvas.width)x\(canvas.height) bitmap for \(name)")
        }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        // From here on the context's units are the image's px as displayed, from the top-left, y down.
        ctx.translateBy(x: 0, y: CGFloat(canvas.height))
        ctx.scaleBy(x: 1, y: -1)
        if list != nil {
            ctx.setFillColor(CommentList.background)
            ctx.fill(CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
        }

        ctx.saveGState()
        // Each orientation turns or mirrors whole pixels onto whole pixels, so nothing is resampled.
        ctx.interpolationQuality = .none
        ctx.setBlendMode(.copy)
        ctx.concatenate(displayed(orientation: orientation, width: CGFloat(image.width), height: CGFloat(image.height)))
        // `draw` puts an image's first row at the top of a y-up rect; these units run y down.
        ctx.translateBy(x: 0, y: CGFloat(image.height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.restoreGState()

        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height))
        drawing.draw(in: ctx, style: style, markStyle: markStyle, pins: .rendered)
        ctx.restoreGState()
        list?.draw(in: ctx, at: list?.origin(for: pixels) ?? .zero, pointScale: drawing.pointScale, markStyle: markStyle)

        guard let rendered = ctx.makeImage() else {
            throw Failure.writeFailed("could not finish the \(canvas.width)x\(canvas.height) bitmap for \(name)")
        }
        let png = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(png, "public.png" as CFString, 1, nil) else {
            throw Failure.writeFailed("could not start a PNG for \(name)")
        }
        // The screenshot's own DPI, so the rendering pastes at the size the screenshot does.
        var dpi = [kCGImagePropertyDPIWidth: properties[kCGImagePropertyDPIWidth], kCGImagePropertyDPIHeight: properties[kCGImagePropertyDPIHeight]]
        if (5...8).contains(orientation) {
            (dpi[kCGImagePropertyDPIWidth], dpi[kCGImagePropertyDPIHeight]) = (dpi[kCGImagePropertyDPIHeight], dpi[kCGImagePropertyDPIWidth])
        }
        CGImageDestinationAddImage(destination, rendered, dpi.compactMapValues { $0 } as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw Failure.writeFailed("could not write the PNG for \(name)")
        }
        return png as Data
    }

    /// A bitmap for the image's pixels as displayed, in the image's own colour space and depth, with
    /// alpha only when the image has it. A colour space a bitmap cannot be drawn in, or one that
    /// cannot hold coloured marks (grey, CMYK), gives way to sRGB.
    private static func context(for image: CGImage, pixels: PixelSize) -> CGContext? {
        var space = image.colorSpace
        if space?.model == .indexed { space = space?.baseColorSpace }
        let own = space.flatMap { $0.model == .rgb && $0.supportsOutput ? $0 : nil }
        guard let space = own ?? CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let opaque = [.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        return CGContext(data: nil, width: pixels.width, height: pixels.height, bitsPerComponent: image.bitsPerComponent > 8 ? 16 : 8,
                         bytesPerRow: 0, space: space,
                         bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue)
    }

    /// Maps the file's pixels, from its top-left with y down, to where they are displayed, for the
    /// EXIF orientation flag (1 to 8). `width` and `height` are the file's own, before turning.
    private static func displayed(orientation: Int, width w: CGFloat, height h: CGFloat) -> CGAffineTransform {
        switch orientation {
        case 2: return CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0)
        case 3: return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h)
        case 4: return CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h)
        case 5: return CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        case 6: return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0)
        case 7: return CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: h, ty: w)
        case 8: return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w)
        default: return .identity
        }
    }
}
