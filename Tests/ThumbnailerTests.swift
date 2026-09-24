import AppKit
import ImageIO
import XCTest

final class ThumbnailerTests: XCTestCase {
    private var dir: URL!
    private var savedBudget = 0

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-thumbs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        savedBudget = Thumbnailer.budgetBytes
    }

    override func tearDownWithError() throws {
        Thumbnailer.budgetBytes = savedBudget
        try FileManager.default.removeItem(at: dir)
    }

    /// A PNG of `w`x`h` pixels; `dpi` sets the resolution metadata a Retina capture carries.
    private func png(_ name: String, w: Int, h: Int, dpi: Double = 72) throws -> URL {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let url = dir.appendingPathComponent(name)
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, rep.cgImage!, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    func testPointSizeFollowsTheFileDPI() throws {
        let plain = try png("plain.png", w: 300, h: 200)
        XCTAssertEqual(Thumbnailer.pointSize(of: plain), NSSize(width: 300, height: 200))
        let retina = try png("retina.png", w: 300, h: 200, dpi: 144)
        XCTAssertEqual(Thumbnailer.pointSize(of: retina), NSSize(width: 150, height: 100))
        XCTAssertEqual(Thumbnailer.pointSize(of: retina), NSImage(contentsOf: retina)?.size, "must agree with what AppKit reports")
        XCTAssertNil(Thumbnailer.pointSize(of: dir.appendingPathComponent("missing.png")))
    }

    func testCacheEvictsLeastRecentlyUsedWithinTheBudget() throws {
        // Each decode is 100x100 RGBA = 40 000 bytes; room for two.
        Thumbnailer.budgetBytes = 90_000
        let a = try png("a.png", w: 100, h: 100), b = try png("b.png", w: 100, h: 100), c = try png("c.png", w: 100, h: 100)
        XCTAssertNotNil(Thumbnailer.image(at: a, maxPixel: 100, space: nil))
        XCTAssertNotNil(Thumbnailer.image(at: b, maxPixel: 100, space: nil))
        XCTAssertNotNil(Thumbnailer.cached(at: a, maxPixel: 100, space: nil), "touching a makes b the oldest")
        XCTAssertNotNil(Thumbnailer.image(at: c, maxPixel: 100, space: nil))
        XCTAssertNil(Thumbnailer.cached(at: b, maxPixel: 100, space: nil), "b was least recently used")
        XCTAssertNotNil(Thumbnailer.cached(at: a, maxPixel: 100, space: nil))
        XCTAssertNotNil(Thumbnailer.cached(at: c, maxPixel: 100, space: nil))
        XCTAssertLessThanOrEqual(Thumbnailer.cacheBytes, 90_000)
    }

    func testAnEntryLargerThanTheBudgetStillServesOnce() throws {
        Thumbnailer.budgetBytes = 1_000
        let big = try png("big.png", w: 100, h: 100)
        XCTAssertNotNil(Thumbnailer.image(at: big, maxPixel: 100, space: nil))
        XCTAssertNotNil(Thumbnailer.cached(at: big, maxPixel: 100, space: nil), "the newest entry is kept even over budget")
        let next = try png("next.png", w: 10, h: 10)
        XCTAssertNotNil(Thumbnailer.image(at: next, maxPixel: 10, space: nil))
        XCTAssertNil(Thumbnailer.cached(at: big, maxPixel: 100, space: nil), "and goes as soon as something newer arrives")
    }

    /// Core Animation converts an image in any other colour space at the first commit that shows it,
    /// on the main thread, so a decode for a screen comes back in that screen's space and is cached
    /// under it.
    func testADecodeForAScreenIsInThatScreensColorSpace() throws {
        let file = try png("space.png", w: 40, h: 20)
        let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let image = try XCTUnwrap(Thumbnailer.image(at: file, maxPixel: 40, space: p3))
        XCTAssertEqual(image.cgImage(forProposedRect: nil, context: nil, hints: nil)?.colorSpace, p3)
        XCTAssertNotNil(Thumbnailer.cached(at: file, maxPixel: 40, space: p3))
        XCTAssertNil(Thumbnailer.cached(at: file, maxPixel: 40, space: nil), "a decode for another space is another decode")
    }

    /// A drawing sent to an agent is stored as `image.png`, and a reply copies those bytes to a
    /// `.png` card. A jpg or heic capture sent with nothing drawn on it would otherwise put the
    /// capture's own bytes under a name that says PNG.
    func testAnyCaptureFormatIsSentAsRealPNGBytes() throws {
        let source = dir.appendingPathComponent("capture.jpg")
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 20, bitsPerSample: 8,
                                                 samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        try XCTUnwrap(rep.representation(using: .jpeg, properties: [:])).write(to: source)

        let converted = try XCTUnwrap(Thumbnailer.png(from: source))
        XCTAssertEqual(converted.prefix(8), Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        let decoded = try XCTUnwrap(NSBitmapImageRep(data: converted))
        XCTAssertEqual(decoded.pixelsWide, 40)
        XCTAssertEqual(decoded.pixelsHigh, 20)

        // A PNG is handed back as it is, so the common case costs one read and no re-encode.
        let png = try self.png("already.png", w: 8, h: 8)
        XCTAssertEqual(Thumbnailer.png(from: png), try Data(contentsOf: png))
        XCTAssertNil(Thumbnailer.png(from: dir.appendingPathComponent("nothing.png")))
    }
}
