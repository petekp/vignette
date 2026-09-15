import AppKit
import ImageIO

/// Downsampled copies of screenshots. Decoding a 3000-pixel PNG for a 220-point card wastes memory
/// and Core Animation's minification shimmers; ImageIO resamples during decode instead.
enum Thumbnailer {
    /// The screenshot's size in points, from the file header only.
    static func pointSize(of url: URL) -> NSSize? {
        guard let image = NSImage(contentsOf: url), image.size.width > 0 else { return nil }
        return image.size
    }

    /// A decoded copy whose longest side is at most `maxPixel` pixels.
    static func image(at url: URL, maxPixel: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
