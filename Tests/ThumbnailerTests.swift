import AppKit
import ImageIO
import XCTest

final class ThumbnailerTests: XCTestCase {
    private var dir: URL!
    private var savedBudget = 0

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("shotnote-thumbs-\(UUID().uuidString)")
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
        XCTAssertNotNil(Thumbnailer.image(at: a, maxPixel: 100))
        XCTAssertNotNil(Thumbnailer.image(at: b, maxPixel: 100))
        XCTAssertNotNil(Thumbnailer.cached(at: a, maxPixel: 100), "touching a makes b the oldest")
        XCTAssertNotNil(Thumbnailer.image(at: c, maxPixel: 100))
        XCTAssertNil(Thumbnailer.cached(at: b, maxPixel: 100), "b was least recently used")
        XCTAssertNotNil(Thumbnailer.cached(at: a, maxPixel: 100))
        XCTAssertNotNil(Thumbnailer.cached(at: c, maxPixel: 100))
        XCTAssertLessThanOrEqual(Thumbnailer.cacheBytes, 90_000)
    }

    func testAnEntryLargerThanTheBudgetStillServesOnce() throws {
        Thumbnailer.budgetBytes = 1_000
        let big = try png("big.png", w: 100, h: 100)
        XCTAssertNotNil(Thumbnailer.image(at: big, maxPixel: 100))
        XCTAssertNotNil(Thumbnailer.cached(at: big, maxPixel: 100), "the newest entry is kept even over budget")
        let next = try png("next.png", w: 10, h: 10)
        XCTAssertNotNil(Thumbnailer.image(at: next, maxPixel: 10))
        XCTAssertNil(Thumbnailer.cached(at: big, maxPixel: 100), "and goes as soon as something newer arrives")
    }

    func testDownsampledPNGKeepsAspectWithinMaxPixel() throws {
        let data = try Data(contentsOf: png("wide.png", w: 3000, h: 1000))
        let small = try XCTUnwrap(Thumbnailer.downsampled(png: data, maxPixel: 1600))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: small))
        XCTAssertEqual(rep.pixelsWide, 1600)
        XCTAssertEqual(rep.pixelsHigh, 533)
        XCTAssertNil(Thumbnailer.downsampled(png: Data("not a png".utf8), maxPixel: 100))
    }
}
