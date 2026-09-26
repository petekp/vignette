import AppKit
import AVFoundation
import ImageIO
import QuickLookThumbnailing

/// Downsampled copies of screenshots, cached by file and size. Decoding a 3000-pixel PNG for a
/// 220-point card wastes memory and Core Animation's minification shimmers; ImageIO resamples
/// during decode instead. The cache is what makes the stack appear at once: it is warmed at
/// launch and whenever a screenshot lands, so opening the stack rarely decodes anything. The cache
/// is bounded by `budgetBytes`, least recently used first, so a long session stays flat.
/// `@unchecked Sendable`: every access to the mutable state below is inside `lock`/`unlock`, which
/// is what actually makes it safe across the concurrent `queue`.
enum Thumbnailer: @unchecked Sendable {
    /// `space` is the colour space the decode was asked for, nil for the file's own.
    private struct Entry { let modified: Date; let maxPixel: Int; let space: CGColorSpace?; let image: NSImage; let bytes: Int }
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
    /// A file's size in points and, for a recording, its length. `exact` is false for a shape taken
    /// from iCloud's thumbnail of a file that is not downloaded: right in proportion only.
    struct Header { let size: NSSize; let duration: TimeInterval?; var exact = true }
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
    /// Reads the file, so a file that is not downloaded is downloaded first: the main thread asks
    /// `lookUp` instead.
    static func pointSize(of url: URL) -> NSSize? { header(of: url)?.size }

    /// A recording's length in seconds; nil for an image. Reads the file, as `pointSize` does.
    static func duration(of url: URL) -> TimeInterval? { header(of: url)?.duration }

    /// True when iCloud Drive has taken the file's bytes off this Mac (Optimize Mac Storage) and left
    /// a placeholder. Any read of such a file, ImageIO's header read and AVFoundation's included,
    /// downloads all of it and waits: two such files held launch for 1.5 s, and a 333 MB recording
    /// held the stack's opening for 14 s (measured 2026-09-25). `lstat` reads the flag without that.
    static func isDataless(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && info.st_flags & UInt32(SF_DATALESS) != 0
    }

    /// A file as the main thread may know it, which never reads a file that is not downloaded.
    enum Lookup {
        case read(Header)
        /// The file's bytes are in iCloud only. The header kept from an earlier read, or the shape of
        /// iCloud's thumbnail once `cardImage` has fetched it; nil before either.
        case notDownloaded(Header?)
        case unreadable
    }

    static func lookUp(_ url: URL) -> Lookup {
        if isDataless(url) { return .notDownloaded(kept(url)) }
        return header(of: url).map { .read($0) } ?? .unreadable
    }

    private static func kept(_ url: URL) -> Header? {
        let modified = modified(url)
        lock.lock(); defer { lock.unlock() }
        guard let hit = headers[url.path], hit.modified == modified else { return nil }
        return hit.header
    }

    /// Downloads a file that is not downloaded by reading its header on the thumbnail queue, so the
    /// editor, which reads the file on the main thread when it opens, finds its bytes here.
    static func download(_ url: URL, completion: @escaping @MainActor @Sendable (Header?) -> Void = { _ in }) {
        queue.async {
            let header = self.read(url)
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(header) } }
        }
    }

    private static func header(of url: URL) -> Header? {
        if let hit = kept(url), hit.exact { return hit }
        return read(url)
    }

    /// Reads the header from the file, whatever is kept, and keeps it.
    private static func read(_ url: URL) -> Header? {
        let modified = modified(url)
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

    /// A cached decode of at least `maxPixel` on the longest side in `space`, if the file has not changed.
    static func cached(at url: URL, maxPixel: Int, space: CGColorSpace?) -> NSImage? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = cache[url.path], entry.maxPixel >= maxPixel, entry.space == space,
              entry.modified == modified(url) else { return nil }
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
    /// on `maxPixel` and the colour space, so two expressions that drifted apart would silently hold two.
    static func screenPixels(on screen: NSScreen) -> Int {
        Int(ceil(max(screen.visibleFrame.width, screen.visibleFrame.height) * screen.backingScaleFactor))
    }

    /// A decoded copy whose longest side is at most `maxPixel` pixels, in `space`: the colour space
    /// of the screen it will be shown on (`NSScreen.colorSpace`), or nil for the file's own. Cached.
    /// For a recording, its first frame.
    static func image(at url: URL, maxPixel: Int, space: CGColorSpace?) -> NSImage? {
        if let hit = cached(at: url, maxPixel: maxPixel, space: space) { return hit }
        let decoded = Screenshot(url: url).kind == .recording ? posterFrame(url, maxPixel: maxPixel) : thumbnail(url, maxPixel: maxPixel)
        guard let cg = decoded.map({ converted($0, to: space) }) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        if let modified = modified(url) {
            lock.lock()
            insert(url.path, Entry(modified: modified, maxPixel: maxPixel, space: space, image: image, bytes: cg.width * cg.height * 4))
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

    /// The image redrawn in `space`. Core Animation converts an image in any other space at the first
    /// commit that shows it, on the main thread: 21 ms for a 3024x1964 sRGB image, against 0.05 ms
    /// once redrawn here (measured 2026-09-23). The redraw is 8-bit, so a deeper image is left as it is.
    private static func converted(_ image: CGImage, to space: CGColorSpace?) -> CGImage {
        guard let space, image.colorSpace != space, image.bitsPerComponent == 8 else { return image }
        let opaque = [.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let info = CGBitmapInfo.byteOrder32Little.rawValue
            | (opaque ? CGImageAlphaInfo.noneSkipFirst : .premultipliedFirst).rawValue
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: info) else { return image }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage() ?? image
    }

    /// A card's picture. A file that is not downloaded gets iCloud's thumbnail instead of a decode of
    /// its pixels, which would download it; the thumbnail's shape is kept as the file's header until
    /// the file's own is read.
    static func cardImage(at url: URL, maxPixel: Int, space: CGColorSpace?) -> NSImage? {
        guard isDataless(url) else { return image(at: url, maxPixel: maxPixel, space: space) }
        if let hit = cached(at: url, maxPixel: maxPixel, space: space) { return hit }
        guard let cg = cloudThumbnail(url, maxPixel: maxPixel).map({ converted($0, to: space) }) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        guard let modified = modified(url) else { return image }
        lock.lock()
        insert(url.path, Entry(modified: modified, maxPixel: maxPixel, space: space, image: image, bytes: cg.width * cg.height * 4))
        if headers[url.path]?.modified != modified {
            headers[url.path] = (modified, Header(size: NSSize(width: cg.width, height: cg.height), duration: nil, exact: false))
        }
        lock.unlock()
        return image
    }

    /// Quick Look answers for a file that is not downloaded from iCloud's own thumbnail, without
    /// downloading it: 0.3 to 0.9 s, and the file stayed a placeholder (measured 2026-09-25).
    private static func cloudThumbnail(_ url: URL, maxPixel: Int) -> CGImage? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: maxPixel, height: maxPixel),
                                                   scale: 1, representationTypes: .thumbnail)
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var thumbnail: CGImage?
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            thumbnail = representation?.cgImage
            done.signal()
        }
        // Offline, iCloud may not answer at all; the card then keeps its matte.
        if done.wait(timeout: .now() + 20) == .timedOut { QLThumbnailGenerator.shared.cancel(request) }
        return thumbnail
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
    static func load(at url: URL, maxPixel: Int, space: CGColorSpace?, completion: @escaping @MainActor @Sendable (NSImage?) -> Void) {
        queue.async {
            let image = self.image(at: url, maxPixel: maxPixel, space: space)
            // Hopping back from this background queue, as documented on `completion`'s callers.
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(image) } }
        }
    }

    /// A card's picture, off the main thread, with the file's header as it stands once the picture
    /// is in: for a file that is not downloaded, the shape of iCloud's thumbnail if nothing better was kept.
    static func loadCard(at url: URL, maxPixel: Int, space: CGColorSpace?,
                         completion: @escaping @MainActor @Sendable (NSImage?, Header?) -> Void) {
        queue.async {
            let image = self.cardImage(at: url, maxPixel: maxPixel, space: space)
            let header = self.kept(url)
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(image, header) } }
        }
    }

    /// Fills the cache with cards' pictures in the background for files not yet in it.
    static func warm(_ items: [(url: URL, maxPixel: Int)], space: CGColorSpace?) {
        for item in items where cached(at: item.url, maxPixel: item.maxPixel, space: space) == nil {
            queue.async { _ = cardImage(at: item.url, maxPixel: item.maxPixel, space: space) }
        }
    }

    private static func modified(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
