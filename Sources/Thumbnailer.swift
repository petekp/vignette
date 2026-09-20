import AppKit
import ImageIO

/// Downsampled copies of screenshots, cached by file and size. Decoding a 3000-pixel PNG for a
/// 220-point card wastes memory and Core Animation's minification shimmers; ImageIO resamples
/// during decode instead. The cache is what makes the stack appear at once: it is warmed at
/// launch and whenever a screenshot lands, so opening the stack rarely decodes anything. The cache
/// is bounded by `budgetBytes`, least recently used first, so a long session stays flat.
/// `@unchecked Sendable`: every access to the mutable state below is inside `lock`/`unlock`, which
/// is what actually makes it safe across the concurrent `queue`.
enum Thumbnailer: @unchecked Sendable {
    private struct Entry { let modified: Date; let maxPixel: Int; let image: NSImage; let bytes: Int }
    private static let lock = NSLock()
    // Guarded by `lock`, not by an actor: reads happen inline on the caller's thread (`cached`) as
    // well as after a background decode (`image`), and only the lock's mutual exclusion keeps that safe.
    nonisolated(unsafe) private static var cache: [String: Entry] = [:]
    /// Keys from least to most recently used.
    nonisolated(unsafe) private static var order: [String] = []
    nonisolated(unsafe) private static var bytes = 0
    /// Point sizes by path, valid while the file's date matches; reading a header is a file open per card.
    nonisolated(unsafe) private static var sizes: [String: (modified: Date, size: NSSize)] = [:]
    /// Decoded pixels the cache may hold, as RGBA bytes. About 30 cards at Retina card size plus a few
    /// screen-size flight decodes fit; beyond that the oldest go.
    nonisolated(unsafe) private static var budget = 96 << 20
    private static let queue = DispatchQueue(label: "vignette.thumbnails", qos: .userInitiated, attributes: .concurrent)

    static var budgetBytes: Int {
        get { lock.lock(); defer { lock.unlock() }; return budget }
        set { lock.lock(); budget = newValue; evict(); lock.unlock() }
    }

    /// Decoded bytes held right now.
    static var cacheBytes: Int { lock.lock(); defer { lock.unlock() }; return bytes }

    /// The screenshot's size in points, from the file header only: pixels scaled by the file's DPI,
    /// which is what `NSImage.size` reports for a Retina capture.
    static func pointSize(of url: URL) -> NSSize? {
        let modified = modified(url)
        lock.lock()
        if let hit = sizes[url.path], hit.modified == modified { lock.unlock(); return hit.size }
        lock.unlock()
        guard let size = readPointSize(of: url) else { return nil }
        if let modified { lock.lock(); sizes[url.path] = (modified, size); lock.unlock() }
        return size
    }

    private static func readPointSize(of url: URL) -> NSSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Double, let h = props[kCGImagePropertyPixelHeight] as? Double,
              w > 0, h > 0 else { return nil }
        let dpiX = props[kCGImagePropertyDPIWidth] as? Double ?? 72
        let dpiY = props[kCGImagePropertyDPIHeight] as? Double ?? 72
        return NSSize(width: w * 72 / (dpiX > 0 ? dpiX : 72), height: h * 72 / (dpiY > 0 ? dpiY : 72))
    }

    /// The screenshot's size in pixels, from the file header only.
    static func pixelSize(of url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0 else { return nil }
        return (w, h)
    }

    /// A fully decoded image from PNG bytes, sized in points like `pointSize`. `NSImage(data:)` would
    /// defer the decode to Core Animation's first commit of the layer, on the main thread.
    static func decode(png: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let dpiX = props[kCGImagePropertyDPIWidth] as? Double ?? 72
        let dpiY = props[kCGImagePropertyDPIHeight] as? Double ?? 72
        let size = NSSize(width: Double(cg.width) * 72 / (dpiX > 0 ? dpiX : 72), height: Double(cg.height) * 72 / (dpiY > 0 ? dpiY : 72))
        return NSImage(cgImage: cg, size: size)
    }

    /// `decode(png:)` off the main thread, handed back on it.
    static func decode(png: Data, completion: @escaping @MainActor @Sendable (NSImage?) -> Void) {
        queue.async {
            let image = decode(png: png)
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(image) } }
        }
    }

    /// A cached decode of at least `maxPixel` on the longest side, if the file has not changed.
    static func cached(at url: URL, maxPixel: Int) -> NSImage? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = cache[url.path], entry.maxPixel >= maxPixel, entry.modified == modified(url) else { return nil }
        touch(url.path)
        return entry.image
    }

    /// PNG bytes of the image in `png`, downscaled so its longest side is at most `maxPixel`. Used for
    /// the Done rendering, so a card preview never holds a full-resolution decode.
    static func downsampled(png: Data, maxPixel: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    /// The `maxPixel` for an image drawn at screen size: a card in flight and the zoom stand-in's
    /// screenshot. Both ask for it so the cache holds one decode for the two of them; the cache is
    /// keyed on `maxPixel`, so two expressions that drifted apart would silently hold two.
    static func screenPixels(on screen: NSScreen) -> Int {
        Int(ceil(max(screen.visibleFrame.width, screen.visibleFrame.height) * screen.backingScaleFactor))
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
            insert(url.path, Entry(modified: modified, maxPixel: maxPixel, image: image, bytes: cg.width * cg.height * 4))
            lock.unlock()
        }
        return image
    }

    // MARK: Cache bookkeeping, all under `lock`

    private static func insert(_ key: String, _ entry: Entry) {
        if let old = cache[key] { bytes -= old.bytes }
        cache[key] = entry
        bytes += entry.bytes
        touch(key)
        evict()
    }

    private static func touch(_ key: String) {
        if let i = order.firstIndex(of: key) { order.remove(at: i) }
        order.append(key)
    }

    /// Drops least recently used entries until the cache fits the budget. The newest entry stays
    /// even if it alone exceeds the budget, so a request is never answered from nothing.
    private static func evict() {
        while bytes > budget, order.count > 1, let key = order.first {
            order.removeFirst()
            if let entry = cache.removeValue(forKey: key) { bytes -= entry.bytes }
        }
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
