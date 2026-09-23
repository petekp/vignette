import Foundation
import ImageIO

/// The screenshot as the colour pass measures it: drawn into an sRGB bitmap `longSide` px on its
/// long side, once per image. At that size the text in a screenshot blends into its background,
/// which is what a mark is drawn across. `docs/annotation-colour-2026-09-17.md` has the numbers.
struct ColorSample {
    static let longSide = 320

    /// The image's size as displayed, in px: what a mark's geometry is measured in.
    let pixels: PixelSize
    let width: Int
    let height: Int
    /// RGBA, premultiplied, so a transparent pixel reads as black.
    private let bytes: [UInt8]

    /// Nil when the file is not an image this Mac can read.
    init?(imageAt url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixels = PixelSize(imageProperties: properties) else { return nil }
        let scale = min(1, CGFloat(Self.longSide) / CGFloat(max(pixels.width, pixels.height)))
        let width = max(1, Int((CGFloat(pixels.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(pixels.height) * scale).rounded()))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.pixels = pixels
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    // MARK: The pick

    /// How far a colour must be from what it covers, as a CIE76 distance in CIELAB.
    private static let minDistance: CGFloat = 55
    /// The share of the sampled pixels allowed to be nearer a colour than `minDistance`, so a few
    /// stray pixels do not decide the pick.
    private static let tolerance: CGFloat = 0.1
    /// At most this many sample points across a frame or a text's line, each way.
    private static let grid = 20
    /// A rectangle or an ellipse is drawn on its outline, so only the points this near an edge
    /// count, as a share of the frame's shorter side.
    private static let borderBand: CGFloat = 0.15
    /// How far an arrow's side points are from its body, as a share of the sample's long side.
    private static let lineBand: CGFloat = 0.01
    /// Steps along an arrow's body, so it is sampled at one more point than this.
    private static let lineSteps = 40

    /// The colour `mark` gets from the pixels it covers: the first in the colour pass's order whose
    /// distance from them is at least `minDistance`, else the furthest. A mark of a drawing at
    /// `pointScale`; `style` sets a text's lines.
    func pick(for mark: Mark, pointScale: CGFloat, style: TextStyle) -> MarkColor {
        let under: [Lab]
        switch mark.geometry {
        case .rectangle(let frame), .ellipse(let frame):
            under = labs(in: frame, borderOnly: true)
        case .arrow(let arrow):
            under = labs(along: arrow.body(pointScale: pointScale))
        case .text(let text):
            let lines = TextLayout(text, imageWidth: CGFloat(pixels.width), pointScale: pointScale, style: style).lines
            // An empty line has no letters to cover anything.
            let inked = lines.filter { $0.rect.width > 0 }
            under = (inked.isEmpty ? lines : inked).flatMap { labs(in: $0.rect, borderOnly: false) }
        }
        var furthest = (color: MarkColor.start, distance: -CGFloat.infinity)
        for color in MarkColor.allCases {
            let (red, green, blue) = color.sRGB
            let distance = Self.distance(from: Lab(red, green, blue), to: under)
            if distance >= Self.minDistance { return color }
            if distance > furthest.distance { furthest = (color, distance) }
        }
        return furthest.color
    }

    /// The distance the nearest `tolerance` of the pixels are within: a mean would be no use, since
    /// black and white average to a grey that is nothing like either.
    private static func distance(from color: Lab, to pixels: [Lab]) -> CGFloat {
        let distances = pixels.map { color.distance(to: $0) }.sorted()
        guard !distances.isEmpty else { return .infinity }
        return distances[min(distances.count - 1, Int(tolerance * CGFloat(distances.count)))]
    }

    /// A grid of points over `rect`, in px, or its border band alone. A rect too small for a band
    /// keeps the whole grid.
    private func labs(in rect: CGRect, borderOnly: Bool) -> [Lab] {
        let scaleX = CGFloat(width) / CGFloat(pixels.width), scaleY = CGFloat(height) / CGFloat(pixels.height)
        let left = index((rect.minX * scaleX).rounded(.down), width)
        let top = index((rect.minY * scaleY).rounded(.down), height)
        let right = max(left, index((rect.maxX * scaleX).rounded(.up) - 1, width))
        let bottom = max(top, index((rect.maxY * scaleY).rounded(.up) - 1, height))
        let columns = min(Self.grid, right - left + 1), rows = min(Self.grid, bottom - top + 1)
        let band = max(1, Int((Self.borderBand * CGFloat(min(right - left, bottom - top))).rounded()))
        var all: [Lab] = [], border: [Lab] = []
        for row in 0..<rows {
            let y = rows == 1 ? top : top + Int((CGFloat(row * (bottom - top)) / CGFloat(rows - 1)).rounded())
            for column in 0..<columns {
                let x = columns == 1 ? left : left + Int((CGFloat(column * (right - left)) / CGFloat(columns - 1)).rounded())
                let lab = self.lab(x: CGFloat(x), y: CGFloat(y))
                all.append(lab)
                if x - left <= band || right - x <= band || y - top <= band || bottom - y <= band { border.append(lab) }
            }
        }
        return borderOnly && !border.isEmpty ? border : all
    }

    /// Points along the body as drawn, arc included, each with one to either side of it.
    private func labs(along body: ArrowBody) -> [Lab] {
        let scaleX = CGFloat(width) / CGFloat(pixels.width), scaleY = CGFloat(height) / CGFloat(pixels.height)
        let band = CGFloat(max(1, Int((Self.lineBand * CGFloat(max(width, height))).rounded())))
        let chord = hypot(body.end.x - body.start.x, body.end.y - body.start.y)
        var labs: [Lab] = []
        for step in 0...Self.lineSteps {
            let point = body.point(at: CGFloat(step) / CGFloat(Self.lineSteps))
            // The body's normal at this point: the radius on an arc, the perpendicular on a line.
            var normal = CGVector(dx: 0, dy: 0)
            if let arc = body.arc, arc.radius > 0 {
                normal = CGVector(dx: (point.x - arc.center.x) / arc.radius, dy: (point.y - arc.center.y) / arc.radius)
            } else if chord > 0 {
                normal = CGVector(dx: -(body.end.y - body.start.y) / chord, dy: (body.end.x - body.start.x) / chord)
            }
            for side: CGFloat in [-1, 0, 1] {
                labs.append(lab(x: point.x * scaleX + normal.dx * band * side, y: point.y * scaleY + normal.dy * band * side))
            }
        }
        return labs
    }

    /// The sample pixel nearest a point in the sample's own px, clamped to the sample.
    private func lab(x: CGFloat, y: CGFloat) -> Lab {
        let i = (index(y.rounded(), height) * width + index(x.rounded(), width)) * 4
        return Lab(CGFloat(bytes[i]) / 255, CGFloat(bytes[i + 1]) / 255, CGFloat(bytes[i + 2]) / 255)
    }

    /// A column or a row, clamped to the sample before it becomes an integer.
    private func index(_ value: CGFloat, _ count: Int) -> Int {
        value.isFinite ? Int(min(max(value, 0), CGFloat(count - 1))) : 0
    }
}

/// A colour in CIELAB, where equal steps look about equally different.
private struct Lab {
    let l: CGFloat
    let a: CGFloat
    let b: CGFloat

    /// From sRGB components from 0 to 1, with the D65 white point.
    init(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) {
        func linear(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        func f(_ t: CGFloat) -> CGFloat { t > 0.008856 ? cbrt(t) : 7.787 * t + 16 / 116 }
        let r = linear(red), g = linear(green), b = linear(blue)
        let x = f((0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047)
        let y = f(0.2126 * r + 0.7152 * g + 0.0722 * b)
        let z = f((0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883)
        l = 116 * y - 16
        a = 500 * (x - y)
        self.b = 200 * (y - z)
    }

    /// CIE76: the straight line between two colours.
    func distance(to other: Lab) -> CGFloat {
        (pow(l - other.l, 2) + pow(a - other.a, 2) + pow(b - other.b, 2)).squareRoot()
    }
}
