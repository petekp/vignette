import AppKit

/// Composes several screenshots into one tall image with numbered badges, oldest at the top.
enum Stitch {
    static let gap = 24
    static let pad = 24

    static func compose(_ urls: [URL]) -> Data? {
        let reps = urls.compactMap { url -> NSBitmapImageRep? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return NSBitmapImageRep(data: data)
        }
        guard !reps.isEmpty else { return nil }
        let width = reps.map(\.pixelsWide).max()! + pad * 2
        let height = reps.reduce(0) { $0 + $1.pixelsHigh } + gap * (reps.count - 1) + pad * 2

        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        var top = height - pad
        for (i, rep) in reps.enumerated() {
            guard let cg = rep.cgImage else { continue }
            let rect = CGRect(x: pad, y: top - rep.pixelsHigh, width: rep.pixelsWide, height: rep.pixelsHigh)
            ctx.draw(cg, in: rect)
            drawBadge(number: i + 1, at: CGPoint(x: rect.minX + 12, y: rect.maxY - 12), in: ctx)
            top -= rep.pixelsHigh + gap
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let image = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    private static func drawBadge(number: Int, at corner: CGPoint, in ctx: CGContext) {
        let d: CGFloat = 44
        let circle = CGRect(x: corner.x, y: corner.y - d, width: d, height: d)
        ctx.setFillColor(CGColor(red: 0.88, green: 0.19, blue: 0.19, alpha: 1))
        ctx.fillEllipse(in: circle)
        let text = NSAttributedString(string: "\(number)", attributes: [
            .font: NSFont.systemFont(ofSize: 26, weight: .bold), .foregroundColor: NSColor.white])
        let size = text.size()
        text.draw(at: CGPoint(x: circle.midX - size.width / 2, y: circle.midY - size.height / 2))
    }
}
