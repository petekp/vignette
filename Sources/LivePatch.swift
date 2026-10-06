import Accelerate
import AppKit
import ScreenCaptureKit

/// A patch of a window's pixels round a live ink mark, kept so the mark can find its content again
/// when Accessibility gives no anchor, as in Chrome or a terminal (docs/live-ink-step3-2026-10-05.md).
/// It is matched once the content is still, never while it moves. The pixels stay in memory and
/// leave with the mark.
struct LivePatch: Sendable {
    /// The whole patch, then its top and its bottom, each holding the mark's point, for content that
    /// has come to rest against the window's edge with part of the patch cut off.
    private let parts: [Part]
    /// The patch's top-left corner from the window's top-left when it was taken, in points.
    let origin: CGPoint

    /// The size of a patch, in points: wide enough to hold a few words, so one line of text tells
    /// itself apart from the next.
    static let size = CGSize(width: 160, height: 64)
    /// The least a match may score, from -1 to 1, and how close a second place may come before the
    /// one nearer to where the content was expected wins.
    static let leastScore: Float = 0.8
    static let tie: Float = 0.03
    /// The search runs on a copy this many times smaller first.
    private static let coarse = 4

    private struct Part: Sendable {
        let full: Grey
        let small: Grey
        /// Its top edge, from the patch's.
        let top: Int
    }

    /// The patch of `image`, a window at 1 px per pt, centred on `point` from the window's top-left
    /// and kept inside it. Nil when the patch is too plain to tell one place from another.
    init?(_ image: WindowImage, around point: CGPoint) {
        let width = min(Int(Self.size.width), image.grey.width), height = min(Int(Self.size.height), image.grey.height)
        guard width >= 32, height >= 32 else { return nil }
        let x = min(max(0, Int(point.x) - width / 2), image.grey.width - width)
        let y = min(max(0, Int(point.y) - height / 2), image.grey.height - height)
        let spans = [(0, height), (0, height * 5 / 8), (height * 3 / 8, height)]
        var parts: [Part] = []
        for (top, bottom) in spans {
            let crop = image.grey.cropped(x: x, y: y + top, width: width, height: bottom - top)
            // A blank stretch of page matches anywhere.
            guard let full = crop.normalized(least: 6), let small = crop.shrunk(by: Self.coarse).normalized(least: 1) else { continue }
            parts.append(Part(full: full, small: small, top: top))
        }
        guard parts.first?.top == 0, parts.first?.full.height == height else { return nil }
        self.parts = parts
        origin = CGPoint(x: x, y: y)
    }

    /// How far the patch's content moved in `image`, in points, or nil when it is not there. Of the
    /// matches that score within `tie` of the best, the one nearest `expected` wins, so a page of
    /// lines that look alike resolves to the line the scroll brought there. The column the content
    /// was in is searched first, since content mostly scrolls up and down.
    func shift(in image: WindowImage, expected: CGVector) -> CGVector? {
        let field = image.grey.shrunk(by: Self.coarse)
        let column = Int((origin.x + expected.dx) / CGFloat(Self.coarse))
        for part in parts {
            for columns in [column - 12...column + 12, Int.min / 2...Int.max / 2] {
                let partOrigin = CGPoint(x: origin.x, y: origin.y + CGFloat(part.top))
                if let shift = Self.shift(of: part, at: partOrigin, in: image.grey, field: field, columns: columns, expected: expected) {
                    return shift
                }
            }
        }
        return nil
    }

    /// Whether the patch's content is still `shift` from where it was taken, within a point: one
    /// comparison, where `shift(in:expected:)` searches the window.
    func isAt(_ shift: CGVector, in image: WindowImage) -> Bool {
        guard let part = parts.first else { return false }
        let x = Int((origin.x + shift.dx).rounded()), y = Int((origin.y + shift.dy).rounded())
        let score = image.grey.scores(of: part.full, columns: x - 1...x + 1, rows: y - 1...y + 1).best(keep: 1, apart: 1).first?.score
        return (score ?? -1) >= Self.leastScore
    }

    private static func shift(of part: Part, at origin: CGPoint, in image: Grey, field: Grey, columns: ClosedRange<Int>,
                              expected: CGVector) -> CGVector? {
        let peaks = field.scores(of: part.small, columns: columns, rows: Int.min / 2...Int.max / 2).best(keep: 8, apart: 4)
        // Each coarse peak, found again at full detail round its place.
        let found = peaks.compactMap { peak -> (x: Int, y: Int, score: Float)? in
            let reach = coarse + 2
            return image.scores(of: part.full, columns: peak.x * coarse - reach...peak.x * coarse + reach,
                                rows: peak.y * coarse - reach...peak.y * coarse + reach).best(keep: 1, apart: 1).first
        }
        guard let top = found.map(\.score).max(), top >= leastScore else { return nil }
        let shifts = found.filter { $0.score >= top - tie }.map { CGVector(dx: CGFloat($0.x) - origin.x, dy: CGFloat($0.y) - origin.y) }
        return shifts.min { a, b in hypot(a.dx - expected.dx, a.dy - expected.dy) < hypot(b.dx - expected.dx, b.dy - expected.dy) }
    }
}

/// Grey levels, row by row.
struct Grey: Sendable {
    let pixels: [Float]
    let width: Int, height: Int

    func cropped(x: Int, y: Int, width w: Int, height h: Int) -> Grey {
        var out = [Float](repeating: 0, count: w * h)
        pixels.withUnsafeBufferPointer { source in
            out.withUnsafeMutableBufferPointer { target in
                for row in 0..<h {
                    (target.baseAddress! + row * w).update(from: source.baseAddress! + (y + row) * width + x, count: w)
                }
            }
        }
        return Grey(pixels: out, width: w, height: h)
    }

    /// Moved to mean 0 and deviation 1, or nil when the deviation is under `least`.
    func normalized(least: Float) -> Grey? {
        var mean: Float = 0, deviation: Float = 0
        var out = [Float](repeating: 0, count: pixels.count)
        vDSP_normalize(pixels, 1, &out, 1, &mean, &deviation, vDSP_Length(pixels.count))
        return deviation >= least ? Grey(pixels: out, width: width, height: height) : nil
    }

    /// Shrunk `factor` times, with vImage, so a capture's whole window takes a few milliseconds.
    func shrunk(by factor: Int) -> Grey {
        let w = width / factor, h = height / factor
        var out = [Float](repeating: 0, count: w * h)
        guard w > 0, h > 0 else { return Grey(pixels: out, width: w, height: h) }
        var source = pixels
        source.withUnsafeMutableBytes { source in
            out.withUnsafeMutableBytes { target in
                var from = vImage_Buffer(data: source.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width),
                                         rowBytes: width * MemoryLayout<Float>.size)
                var to = vImage_Buffer(data: target.baseAddress, height: vImagePixelCount(h), width: vImagePixelCount(w),
                                       rowBytes: w * MemoryLayout<Float>.size)
                vImageScale_PlanarF(&from, &to, nil, vImage_Flags(kvImageNoFlags))
            }
        }
        return Grey(pixels: out, width: w, height: h)
    }

    /// The normalised cross-correlation of `patch`, normalised itself, at every place whose top-left
    /// corner is in `columns` and `rows`, cut to the places where it fits: 1 for the same pixels,
    /// whatever their brightness and contrast. Each row of the patch is correlated with an image row
    /// across all the columns in one call, and each window's mean and deviation come from running
    /// sums.
    func scores(of patch: Grey, columns: ClosedRange<Int>, rows: ClosedRange<Int>) -> Scores {
        let x0 = max(0, columns.lowerBound), x1 = min(width - patch.width, columns.upperBound)
        let y0 = max(0, rows.lowerBound), y1 = min(height - patch.height, rows.upperBound)
        guard x1 >= x0, y1 >= y0 else { return Scores(values: [], width: 0, x0: 0, y0: 0) }
        let w = x1 - x0 + 1, h = y1 - y0 + 1
        var dots = [Float](repeating: 0, count: w * h)
        var row = [Float](repeating: 0, count: w)
        pixels.withUnsafeBufferPointer { image in
            patch.pixels.withUnsafeBufferPointer { p in
                dots.withUnsafeMutableBufferPointer { d in
                    for y in 0..<h {
                        for r in 0..<patch.height {
                            vDSP_conv(image.baseAddress! + (y0 + y + r) * width + x0, 1, p.baseAddress! + r * patch.width, 1,
                                      &row, 1, vDSP_Length(w), vDSP_Length(patch.width))
                            vDSP_vadd(d.baseAddress! + y * w, 1, row, 1, d.baseAddress! + y * w, 1, vDSP_Length(w))
                        }
                    }
                }
            }
        }
        let n = Double(patch.width * patch.height)
        var values = [Float](repeating: -1, count: w * h)
        let integral = Integral(self, columns: x0...(x1 + patch.width), rows: y0...(y1 + patch.height))
        for y in 0..<h {
            for x in 0..<w {
                let (sum, squares) = integral.sums(x: x, y: y, width: patch.width, height: patch.height)
                let variance = squares / n - (sum / n) * (sum / n)
                guard variance > 1 else { continue }
                values[y * w + x] = Float(Double(dots[y * w + x]) / (n * variance.squareRoot()))
            }
        }
        return Scores(values: values, width: w, x0: x0, y0: y0)
    }

    /// Running sums of the pixels and of their squares over a part of the image, in Double, since a
    /// window's sum of squares outgrows a Float's precision.
    private struct Integral {
        let sum: [Double], squares: [Double]
        let stride: Int

        init(_ grey: Grey, columns: ClosedRange<Int>, rows: ClosedRange<Int>) {
            let x0 = columns.lowerBound, y0 = rows.lowerBound
            let w = min(grey.width, columns.upperBound) - x0, h = min(grey.height, rows.upperBound) - y0
            stride = w + 1
            var sum = [Double](repeating: 0, count: stride * (h + 1))
            var squares = sum
            for y in 0..<h {
                var rowSum = 0.0, rowSquares = 0.0
                for x in 0..<w {
                    let v = Double(grey.pixels[(y0 + y) * grey.width + x0 + x])
                    rowSum += v
                    rowSquares += v * v
                    sum[(y + 1) * stride + x + 1] = sum[y * stride + x + 1] + rowSum
                    squares[(y + 1) * stride + x + 1] = squares[y * stride + x + 1] + rowSquares
                }
            }
            self.sum = sum
            self.squares = squares
        }

        /// Over the box at `x`, `y` from the part's top-left.
        func sums(x: Int, y: Int, width: Int, height: Int) -> (Double, Double) {
            func box(_ table: [Double]) -> Double {
                table[(y + height) * stride + x + width] - table[y * stride + x + width] - table[(y + height) * stride + x] + table[y * stride + x]
            }
            return (box(sum), box(squares))
        }
    }

    struct Scores {
        let values: [Float]
        let width: Int, x0: Int, y0: Int

        /// The best `keep` places, each at least `apart` from a better one, in the image's coordinates.
        func best(keep: Int, apart: Int) -> [(x: Int, y: Int, score: Float)] {
            guard width > 0 else { return [] }
            var found: [(x: Int, y: Int, score: Float)] = []
            for index in values.indices.sorted(by: { values[$0] > values[$1] }) {
                guard values[index] > -1 else { break }
                let x = x0 + index % width, y = y0 + index / width
                guard !found.contains(where: { abs($0.x - x) < apart && abs($0.y - y) < apart }) else { continue }
                found.append((x, y, values[index]))
                if found.count == keep { break }
            }
            return found
        }
    }
}

/// One capture of a window, in grey levels at 1 px per pt, from its top-left.
struct WindowImage: Sendable {
    let grey: Grey

    /// Captures the window `id` alone, as ScreenCaptureKit draws it, without Vignette's overlays. The
    /// window's `SCWindow` is kept, since listing the shareable content took longer than the capture.
    static func capture(_ id: CGWindowID, size: CGSize) async -> WindowImage? {
        guard CGPreflightScreenCaptureAccess() else { return nil }
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(size.width.rounded()))
        configuration.height = max(1, Int(size.height.rounded()))
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        for fresh in [false, true] {
            guard let window = await Shareable.window(id, fresh: fresh) else { continue }
            if let image = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window),
                                                                      configuration: configuration) {
                return WindowImage(image)
            }
        }
        return nil
    }

    /// The `SCWindow` of each window captured, listed again when it is missing or did not capture.
    private actor Shareable {
        static let shared = Shareable()
        private var windows: [CGWindowID: SCWindow] = [:]

        static func window(_ id: CGWindowID, fresh: Bool) async -> SCWindow? { await shared.window(id, fresh: fresh) }

        private func window(_ id: CGWindowID, fresh: Bool) async -> SCWindow? {
            if !fresh, let window = windows[id] { return window }
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return nil }
            windows = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
            return windows[id]
        }
    }

    init?(_ image: CGImage) {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var pixels = [Float](repeating: 0, count: bytes.count)
        vDSP_vfltu8(bytes, 1, &pixels, 1, vDSP_Length(bytes.count))
        grey = Grey(pixels: pixels, width: width, height: height)
    }
}
