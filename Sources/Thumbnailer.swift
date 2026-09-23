import AppKit
import AVFoundation
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
    /// What a file's header says, by path, valid while the file's date matches; reading a header is a
    /// file open per card, and a recording's is an AVFoundation load.
    nonisolated(unsafe) private static var headers: [String: (modified: Date, header: Header)] = [:]
    private struct Header { let size: NSSize; let duration: TimeInterval? }
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
    /// which is what `NSImage.size` reports for a Retina capture. A recording carries no DPI, so its
    /// size is in pixels; only its shape is used, since a recording never reaches the annotator.
    static func pointSize(of url: URL) -> NSSize? { header(of: url)?.size }

    /// A recording's length in seconds; nil for an image.
    static func duration(of url: URL) -> TimeInterval? { header(of: url)?.duration }

    private static func header(of url: URL) -> Header? {
        let modified = modified(url)
        lock.lock()
        if let hit = headers[url.path], hit.modified == modified { lock.unlock(); return hit.header }
        lock.unlock()
        let read = Screenshot(url: url).kind == .recording ? readRecording(url) : readPointSize(of: url).map { Header(size: $0, duration: nil) }
        guard let header = read else { return nil }
        if let modified { lock.lock(); headers[url.path] = (modified, header); lock.unlock() }
        return header
    }

    /// The first video track's size, turned the way it plays, and the length. The async loads are
    /// waited on here because every caller of `pointSize` expects an answer in the same turn; the
    /// loads finish on AVFoundation's own queues, so waiting on the main thread cannot deadlock.
    /// About 1.4 ms per file, once, since the result is kept (measured on 12 recordings, 2026-09-22).
    private static func readRecording(_ url: URL) -> Header? {
        let asset = AVURLAsset(url: url)
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var header: Header?
        Task.detached {
            defer { done.signal() }
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let (natural, transform) = try? await track.load(.naturalSize, .preferredTransform),
                  let length = try? await asset.load(.duration) else { return }
            let turned = CGRect(origin: .zero, size: natural).applying(transform)
            guard turned.width != 0, turned.height != 0 else { return }
            header = Header(size: NSSize(width: abs(turned.width), height: abs(turned.height)),
                            duration: length.seconds.isFinite ? length.seconds : nil)
        }
        done.wait()
        return header
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

    /// A cached decode of at least `maxPixel` on the longest side, if the file has not changed.
    static func cached(at url: URL, maxPixel: Int) -> NSImage? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = cache[url.path], entry.maxPixel >= maxPixel, entry.modified == modified(url) else { return nil }
        touch(url.path)
        return entry.image
    }

    /// The file's pixels as PNG, whatever format it is stored in. Returns the bytes unchanged when
    /// the file is already a PNG, so the common case costs one read.
    static func png(from url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        if CGImageSourceGetType(source) == "public.png" as CFString { return try? Data(contentsOf: url) }
        guard let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    /// The `maxPixel` for an image drawn at screen size: a card in flight and the screenshot in the
    /// editor. Both ask for it so the cache holds one decode for the two of them; the cache is keyed
    /// on `maxPixel`, so two expressions that drifted apart would silently hold two.
    static func screenPixels(on screen: NSScreen) -> Int {
        Int(ceil(max(screen.visibleFrame.width, screen.visibleFrame.height) * screen.backingScaleFactor))
    }

    /// A decoded copy whose longest side is at most `maxPixel` pixels. Cached. For a recording, its
    /// first frame.
    static func image(at url: URL, maxPixel: Int) -> NSImage? {
        if let hit = cached(at: url, maxPixel: maxPixel) { return hit }
        let decoded = Screenshot(url: url).kind == .recording ? posterFrame(url, maxPixel: maxPixel) : thumbnail(url, maxPixel: maxPixel)
        guard let cg = decoded else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        if let modified = modified(url) {
            lock.lock()
            insert(url.path, Entry(modified: modified, maxPixel: maxPixel, image: image, bytes: cg.width * cg.height * 4))
            lock.unlock()
        }
        return image
    }

    private static func thumbnail(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// About 90 ms, most of it decoding video, so it runs where `image` runs: on `queue` for a card.
    private static func posterFrame(_ url: URL, maxPixel: Int) -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var frame: CGImage?
        generator.generateCGImageAsynchronously(for: .zero) { image, _, _ in
            frame = image
            done.signal()
        }
        done.wait()
        return frame
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
