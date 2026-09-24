import AppKit
import ImageIO

/// Composes several screenshots into one image with numbered badges, in the order given: the first
/// is at the top left and wears badge 1. The composition is aimed at the model that will read it,
/// which resizes an image before it looks: `docs/stitch-2026-09-17.md` has the rules and why.
enum Stitch {
    /// A screenshot to stitch, and its drawing, which is drawn into the stitch over it.
    struct Piece {
        let url: URL
        let drawing: Drawing?
    }

    /// What a vision model does to an image before reading it, from Anthropic's vision docs
    /// (standard tier, the smallest of the three vendors'): it scales the image to the largest size
    /// whose long edge is at most 1568 px and whose cost, in visual tokens of 28 x 28 px, is at
    /// most 1568. Used to choose the layout and to report what the composition costs; nothing here
    /// sends anything anywhere.
    static let readerLongSide: CGFloat = 1568
    static let readerTokens = 1568
    static let readerPatch: CGFloat = 28

    /// The gap between pieces and the padding around them, as a fraction of the smallest piece's
    /// short side: a fixed number is a hairline on a 5K stitch and a margin on a small crop.
    static let gapFraction: CGFloat = 0.02
    static let gapRange: ClosedRange<CGFloat> = 12...48
    /// A badge's diameter, as a fraction of its own piece's short side, so it stays several times
    /// the height of the UI text beside it however the reader resizes the composition.
    static let badgeFraction: CGFloat = 0.06
    static let badgeRange: ClosedRange<CGFloat> = 32...128
    /// The floor is bigger than a small piece, so the diameter is capped at this share of the
    /// piece's short side as well: a badge is inset by a quarter of itself, and one wider than its
    /// own piece would hang into the gap and land on the neighbouring screenshot.
    static let badgeMaxOfPiece: CGFloat = 0.8

    /// Where every piece goes, at full size. `frames` are in the composition's own space, top-left
    /// origin with y down, in the order the pieces were given.
    struct Layout: Equatable {
        let columns: Int
        let size: CGSize
        let frames: [CGRect]
        let gap: CGFloat
        /// What a reader's resize leaves of the composition: 1 is untouched, 0.45 halves the text.
        let readerScale: CGFloat
    }

    /// The finished image with the numbers a caller reports.
    struct Composition {
        let png: Data
        let size: CGSize
        let columns: Int
        /// How many of the files given are in the picture: one that will not decode is dropped, and
        /// a caller that reported the number it asked for would be reporting a piece nobody can see.
        let pieces: Int
        /// What a reader's resize leaves of the original screenshots, `ui.stitchLongSide` included.
        let readerScale: CGFloat
    }

    /// `longSideLimit` caps the composition's long side; the app passes `ui.stitchLongSide`. Each
    /// piece's drawing is drawn as Done draws it, scaled with the piece, so its marks sit on the
    /// pixels they were drawn on. The app calls this off the main thread.
    static func compose(_ pieces: [Piece], style: TextStyle, arrowhead: ArrowheadStyle, longSideLimit: CGFloat) -> Composition? {
        // Sizes come from the files' headers, so the layout is chosen without decoding anything and
        // only the piece being drawn is ever in memory: six 5K screenshots held at once as bitmaps
        // is several hundred megabytes.
        let sources = pieces.compactMap { piece -> (url: URL, size: CGSize, drawing: Drawing?)? in
            guard let size = pixelSize(of: piece.url) else { return nil }
            return (piece.url, size, piece.drawing)
        }
        guard !sources.isEmpty else { return nil }
        let sizes = sources.map(\.size)
        let plan = layout(sizes)

        // The composition is drawn at the output size rather than drawn full size and resampled: a
        // six-piece 5K stitch would otherwise need a buffer of several hundred megabytes.
        let longSide = max(plan.size.width, plan.size.height)
        let scale = min(1, longSideLimit / longSide)
        let width = max(1, Int((plan.size.width * scale).rounded()))
        let height = max(1, Int((plan.size.height * scale).rounded()))

        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        var drawn = 0
        for (i, source) in sources.enumerated() {
            guard let cg = decode(source.url) else { continue }
            drawn += 1
            let frame = plan.frames[i]
            // CGContext draws from the bottom left; the layout counts from the top left.
            let rect = CGRect(x: frame.minX * scale, y: (plan.size.height - frame.maxY) * scale,
                              width: frame.width * scale, height: frame.height * scale)
            ctx.draw(cg, in: rect)
            if let drawing = source.drawing, drawing.pixels == PixelSize(width: cg.width, height: cg.height) {
                ctx.saveGState()
                // The drawing's px, from the piece's top-left with y down, onto the piece's rect.
                ctx.translateBy(x: rect.minX, y: rect.maxY)
                ctx.scaleBy(x: rect.width / CGFloat(cg.width), y: -rect.height / CGFloat(cg.height))
                drawing.draw(in: ctx, style: style, arrowhead: arrowhead)
                ctx.restoreGState()
            }
            drawBadge(number: i + 1, on: rect, diameter: badgeDiameter(for: sizes[i]) * scale, in: ctx)
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let image = ctx.makeImage(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return nil }
        let size = CGSize(width: width, height: height)
        // What the reader's resize leaves of the screenshots themselves, which is what the layout
        // was chosen for: the cap this drawing applied and then the reader's own resize of it.
        // Reporting the second alone said a six-piece 5K stitch arrived at 0.38 when it arrived at
        // 0.29, because the cap had already taken a quarter of it.
        return Composition(png: png, size: size, columns: plan.columns, pieces: drawn,
                           readerScale: scale * readerScale(size))
    }

    /// The image's size in pixels, read from its header. Nil when the file is not an image this Mac
    /// can read, which is what drops it from the composition.
    private static func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    private static func decode(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// The layout that survives a reader's resize best: every column count is tried and the one
    /// whose composition keeps the most of itself wins, fewest columns first. A tall stack loses
    /// because the long edge is capped before the pixel count is used up; a wide one loses the
    /// same way, and a grid with a hole in it loses the area the hole takes.
    static func layout(_ sizes: [CGSize]) -> Layout {
        guard !sizes.isEmpty else { return Layout(columns: 1, size: .zero, frames: [], gap: 0, readerScale: 1) }
        let gap = gap(for: sizes)
        var best = layout(sizes, columns: 1, gap: gap)
        guard sizes.count > 1 else { return best }
        for columns in 2...sizes.count {
            let plan = layout(sizes, columns: columns, gap: gap)
            if plan.readerScale > best.readerScale + 0.001 { best = plan }
        }
        return best
    }

    /// How much of a composition a vision model keeps when it resizes it to read it. The token cost
    /// counts whole patches, so the area estimate can land a patch over the budget; the scale comes
    /// down until it fits, which reproduces the sizes the vision docs tabulate (1920 x 1080 ->
    /// 1456 x 819).
    static func readerScale(_ size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 1 }
        let budget = CGFloat(readerTokens) * readerPatch * readerPatch
        var scale = min(1, readerLongSide / max(size.width, size.height), sqrt(budget / (size.width * size.height)))
        while scale > 0.01 && visualTokens(size, scale) > readerTokens { scale *= 0.995 }
        return scale
    }

    /// What an image of this size costs a reader: whole 28 x 28 px patches, rounded up each way.
    static func visualTokens(_ size: CGSize, _ scale: CGFloat) -> Int {
        Int(ceil((size.width * scale).rounded() / readerPatch)) * Int(ceil((size.height * scale).rounded() / readerPatch))
    }

    static func gap(for sizes: [CGSize]) -> CGFloat {
        let shortest = sizes.map { min($0.width, $0.height) }.min() ?? 0
        return clamp((gapFraction * shortest).rounded(), to: gapRange)
    }

    static func badgeDiameter(for size: CGSize) -> CGFloat {
        let short = min(size.width, size.height)
        return min(clamp((badgeFraction * short).rounded(), to: badgeRange), (badgeMaxOfPiece * short).rounded())
    }

    /// Pieces in reading order, row by row. A column is as wide as its widest piece and a row as
    /// tall as its tallest, and a piece sits in the middle of its cell.
    static func layout(_ sizes: [CGSize], columns: Int, gap: CGFloat) -> Layout {
        let rows = Int(ceil(Double(sizes.count) / Double(columns)))
        var columnWidths = [CGFloat](repeating: 0, count: columns)
        var rowHeights = [CGFloat](repeating: 0, count: rows)
        for (i, size) in sizes.enumerated() {
            columnWidths[i % columns] = max(columnWidths[i % columns], size.width)
            rowHeights[i / columns] = max(rowHeights[i / columns], size.height)
        }
        let size = CGSize(width: gap * 2 + columnWidths.reduce(0, +) + gap * CGFloat(columns - 1),
                          height: gap * 2 + rowHeights.reduce(0, +) + gap * CGFloat(rows - 1))
        let frames = sizes.enumerated().map { i, piece -> CGRect in
            let column = i % columns, row = i / columns
            let x = gap + columnWidths[..<column].reduce(0, +) + gap * CGFloat(column) + (columnWidths[column] - piece.width) / 2
            let y = gap + rowHeights[..<row].reduce(0, +) + gap * CGFloat(row) + (rowHeights[row] - piece.height) / 2
            return CGRect(x: x, y: y, width: piece.width, height: piece.height)
        }
        return Layout(columns: columns, size: size, frames: frames, gap: gap, readerScale: readerScale(size))
    }

    private static func clamp(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// The piece's number, in its top-left corner, inset by a quarter of the badge.
    private static func drawBadge(number: Int, on piece: CGRect, diameter: CGFloat, in ctx: CGContext) {
        let inset = diameter / 4
        let circle = CGRect(x: piece.minX + inset, y: piece.maxY - inset - diameter, width: diameter, height: diameter)
        ctx.setFillColor(CGColor(red: 0.88, green: 0.19, blue: 0.19, alpha: 1))
        ctx.fillEllipse(in: circle)
        let text = NSAttributedString(string: "\(number)", attributes: [
            .font: NSFont.systemFont(ofSize: diameter * 0.6, weight: .bold), .foregroundColor: NSColor.white])
        let size = text.size()
        text.draw(at: CGPoint(x: circle.midX - size.width / 2, y: circle.midY - size.height / 2))
    }
}
