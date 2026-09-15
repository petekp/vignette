import AppKit
import ImageIO

/// Downsampled copies of screenshots, cached by file and size. Decoding a 3000-pixel PNG for a
/// 220-point card wastes memory and Core Animation's minification shimmers; ImageIO resamples
/// during decode instead. The cache is what makes the stack appear at once: it is warmed at
/// launch and whenever a screenshot lands, so opening the stack rarely decodes anything.
/// `@unchecked Sendable`: every access to the mutable `cache` below is inside `lock`/`unlock`, which
/// is what actually makes the shared state safe across the concurrent `queue`.
enum Thumbnailer: @unchecked Sendable {
    private struct Entry { let modified: Date; let maxPixel: Int; let image: NSImage }
    private static let lock = NSLock()
    // Guarded by `lock`, not by an actor: reads happen inline on the caller's thread (`cached`) as
    // well as after a background decode (`image`), and only the lock's mutual exclusion keeps that safe.
    nonisolated(unsafe) private static var cache: [String: Entry] = [:]
    private static let queue = DispatchQueue(label: "shotnote.thumbnails", qos: .userInitiated, attributes: .concurrent)

    /// The screenshot's size in points, from the file header only.
    static func pointSize(of url: URL) -> NSSize? {
        guard let image = NSImage(contentsOf: url), image.size.width > 0 else { return nil }
        return image.size
    }

    /// A cached decode of at least `maxPixel` on the longest side, if the file has not changed.
    static func cached(at url: URL, maxPixel: Int) -> NSImage? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = cache[url.path], entry.maxPixel >= maxPixel, entry.modified == modified(url) else { return nil }
        return entry.image
    }

    /// A decoded copy whose longest side is at most `maxPixel` pixels. Cached.
    static func image(at url: URL, maxPixel: Int) -> NSImage? {
        if let hit = cached(at: url, maxPixel: maxPixel) { return hit }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        if let modified = modified(url) {
            lock.lock()
            cache[url.path] = Entry(modified: modified, maxPixel: maxPixel, image: image)
            lock.unlock()
        }
        return image
    }

    /// Decodes off the main thread and hands the image back on it.
    static func load(at url: URL, maxPixel: Int, completion: @escaping @MainActor @Sendable (NSImage?) -> Void) {
        queue.async {
            let image = self.image(at: url, maxPixel: maxPixel)
            // Hopping back from this background queue, as documented on `completion`'s callers.
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(image) } }
        }
    }

    /// Fills the cache in the background for files not yet in it.
    static func warm(_ items: [(url: URL, maxPixel: Int)]) {
        for item in items where cached(at: item.url, maxPixel: item.maxPixel) == nil {
            queue.async { _ = image(at: item.url, maxPixel: item.maxPixel) }
        }
    }

    private static func modified(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
