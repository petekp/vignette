import AppKit
import QuartzCore

/// Whether a session's turn changed what is under the person's ink: the window under the ink when
/// the ask was sent, against the window when the turn ended (docs/live-ink-overnight-2026-10-07.md,
/// question 5). Both are read on a coarse grid of grey, so a change of a few pixels of anti-aliasing
/// is not one. Cells that change between two captures of the ended turn, half a second apart, are
/// moving on their own, as a caret or a spinner does, and never count.
enum LiveChange {
    /// What the comparison saw: the fraction of the cells under the ink that changed, and where
    /// anything in the picture changed, in its points.
    enum Outcome: Equatable {
        case changed(Double, around: CGRect)
        case unchanged(Double)
    }

    /// A grid cell's side, in points.
    static let cell: CGFloat = 3
    /// The most cells a side of the grid has, so a large region is read at the same cost as a small one.
    static let maxCells = 160
    /// How far a cell's grey must move, of 255, to count as changed.
    static let cellThreshold = 24
    /// The share of cells that must change, and the fewest, for the region to have changed.
    static let changedShare = 0.02
    static let fewestCells = 4
    /// How far the part that decides reaches past the ink, in points.
    static let pad: CGFloat = 12
    /// How far the part compared reaches past the ink, in points: a change that spills past the ink,
    /// as a button that grew does, is played back whole.
    static let reach: CGFloat = 64
    /// How long to wait between the two captures at the end of a turn.
    static let settle: TimeInterval = 0.5

    /// The part of the window to look at for ink whose shapes cover `ink`, in global top-left points:
    /// the ink with a margin of `margin`, inside `room`, the window or its web page. Nil when they do
    /// not meet.
    static func region(around ink: CGRect, in room: CGRect, margin: CGFloat = pad) -> CGRect? {
        let region = ink.insetBy(dx: -margin, dy: -margin).intersection(room).integral
        return region.isNull || region.width < 8 || region.height < 8 ? nil : region
    }

    /// The part of `image`, a capture of the window at `frame`, inside `rect`, all in global top-left
    /// points, in pixels of its own: a cropped `CGImage` can keep the whole capture's alive, and a
    /// before picture is kept for as long as the session's turn lasts.
    static func crop(_ image: CGImage, frame: CGRect, to rect: CGRect) -> CGImage? {
        let scale = CGFloat(image.width) / max(frame.width, 1)
        let pixels = CGRect(x: (rect.minX - frame.minX) * scale, y: (rect.minY - frame.minY) * scale,
                            width: rect.width * scale, height: rect.height * scale).integral
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpaceCreateDeviceRGB()
        guard let part = image.cropping(to: pixels),
              let context = CGContext(data: nil, width: part.width, height: part.height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        context.draw(part, in: CGRect(x: 0, y: 0, width: part.width, height: part.height))
        return context.makeImage()
    }

    /// Compares `before` with `after`, two pictures of the same part of the window, `size` points,
    /// ignoring cells that differ between `after` and `again`, a third taken a moment later. Only
    /// the cells inside `ink`, in the pictures' points, decide; all of them say where it changed.
    static func compare(before: CGImage, after: CGImage, again: CGImage?, size: CGSize, ink: CGRect? = nil) -> Outcome {
        let columns = max(1, min(maxCells, Int((size.width / cell).rounded()))), rows = max(1, min(maxCells, Int((size.height / cell).rounded())))
        let side = CGSize(width: size.width / CGFloat(columns), height: size.height / CGFloat(rows))
        guard let old = grey(before, columns: columns, rows: rows), let new = grey(after, columns: columns, rows: rows) else {
            return .changed(1, around: CGRect(origin: .zero, size: size))
        }
        let later = again.flatMap { grey($0, columns: columns, rows: rows) }
        var inside = 0, changedInside = 0
        var around = CGRect.null
        for row in 0..<rows {
            for column in 0..<columns {
                let index = row * columns + column
                let cell = CGRect(x: CGFloat(column) * side.width, y: CGFloat(row) * side.height, width: side.width, height: side.height)
                let decides = ink.map { $0.contains(CGPoint(x: cell.midX, y: cell.midY)) } ?? true
                if decides { inside += 1 }
                let moved = abs(Int(old[index]) - Int(new[index])) > cellThreshold
                let restless = later.map { abs(Int($0[index]) - Int(new[index])) > cellThreshold } ?? false
                guard moved && !restless else { continue }
                around = around.union(cell)
                if decides { changedInside += 1 }
            }
        }
        let share = Double(changedInside) / Double(max(inside, 1))
        return changedInside >= fewestCells && share >= changedShare ? .changed(share, around: around) : .unchanged(share)
    }

    /// `image` drawn into `columns` by `rows` cells of grey, each the average of the pixels it covers.
    private static func grey(_ image: CGImage, columns: Int, rows: Int) -> [UInt8]? {
        var cells = [UInt8](repeating: 0, count: columns * rows)
        let drawn = cells.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: columns,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: columns, height: rows))
            return true
        }
        return drawn ? cells : nil
    }
}

/// How the window looked under the ink when the person asked, which the replay shows over the
/// window before the done animation. Held by reference so a mark carrying it stays cheap to compare.
final class BeforePicture: Equatable, @unchecked Sendable {
    let image: CGImage

    init(_ image: CGImage) { self.image = image }

    static func == (a: BeforePicture, b: BeforePicture) -> Bool { a === b }
}

/// Plays a change back where the person drew: the window as it was under their ink comes in over
/// the window as it is now, with a "Before" tag, holds, and then wipes away from left to right,
/// so the change happens again in front of them. Everything is in the marks layer's coordinates.
@MainActor
final class BeforeLayer {
    let root = CALayer()
    /// Clipped by a moving gradient for the wipe; the picture inside it has soft edges.
    private let wiper = CALayer()
    private let wipe = CAGradientLayer()
    private let picture = CALayer()
    private let edge = CALayer()
    private let tag = CATextLayer()
    private let scale: CGFloat

    /// How long each part of the replay takes at full motion: coming in, holding, and the wipe.
    static let appear: CFTimeInterval = 0.2
    static let hold: CFTimeInterval = 0.8
    static let wipeDuration: CFTimeInterval = 0.9
    /// The whole replay at the current motion scale.
    static var duration: TimeInterval { (appear + hold + wipeDuration) * Settings.shared.motionScale }
    /// How far the picture's edge softens into the window, in points.
    static let feather: CGFloat = 6

    init(scale: CGFloat) {
        self.scale = scale
        for layer in [root, wiper, wipe, picture, edge, tag] as [CALayer] { layer.anchorPoint = .zero }
        picture.contentsGravity = .resize
        edge.contents = Self.pillow
        edge.contentsScale = Self.pillowScale
        edge.contentsCenter = Self.pillowCenter
        picture.mask = edge
        wipe.startPoint = CGPoint(x: 0, y: 0.5)
        wipe.endPoint = CGPoint(x: 1, y: 0.5)
        wipe.colors = [CGColor(gray: 1, alpha: 0), CGColor(gray: 1, alpha: 1)]
        wipe.locations = [-0.2, -0.05]
        wiper.mask = wipe
        wiper.addSublayer(picture)
        root.addSublayer(wiper)
        tag.string = NSAttributedString(string: "Before", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
        ])
        tag.alignmentMode = .center
        tag.contentsScale = scale
        tag.backgroundColor = CGColor(gray: 0, alpha: 0.6)
        tag.cornerRadius = 7
        root.addSublayer(tag)
    }

    /// Shows `before` filling `rect`.
    func show(_ before: BeforePicture, in rect: CGRect) {
        root.frame = rect
        wiper.frame = CGRect(origin: .zero, size: rect.size)
        wipe.frame = wiper.bounds
        picture.frame = wiper.bounds
        picture.contents = before.image
        edge.frame = picture.bounds
        // Inside the picture's top-left corner, or above it when the picture is too short to hold it.
        let size = CGSize(width: 50, height: 16)
        let inside = rect.height >= size.height + 12 && rect.width >= size.width + 12
        tag.frame = CGRect(origin: inside ? CGPoint(x: 6, y: 6) : CGPoint(x: 0, y: -size.height - 4), size: size)
    }

    /// Plays the replay once: in, hold, wipe. It ends invisible.
    func play() {
        let motion = Settings.shared.motionScale
        guard motion > 0 else { root.opacity = 0; return }
        let now = root.convertTime(CACurrentMediaTime(), from: nil)
        let appear = Self.appear * motion, hold = Self.hold * motion, wipeDuration = Self.wipeDuration * motion
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = appear
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        root.add(fade, forKey: "appear")
        let sweep = CABasicAnimation(keyPath: "locations")
        sweep.fromValue = [-0.2, -0.05]
        sweep.toValue = [1.05, 1.2]
        sweep.beginTime = now + appear + hold
        sweep.duration = wipeDuration
        sweep.fillMode = .both
        sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        sweep.isRemovedOnCompletion = false
        wipe.add(sweep, forKey: "wipe")
        let tagOut = CABasicAnimation(keyPath: "opacity")
        tagOut.fromValue = 1
        tagOut.toValue = 0
        tagOut.beginTime = now + appear + hold
        tagOut.duration = wipeDuration * 0.4
        tagOut.fillMode = .both
        tagOut.isRemovedOnCompletion = false
        tag.add(tagOut, forKey: "out")
    }

    /// White inside, fading to clear over the last `feather` points before its rounded edge, with one
    /// stretchable point in the middle: `FocusLayer`'s hole drawn the other way round.
    private static let pillowScale: CGFloat = 2
    private static let pillowRadius: CGFloat = 6
    private static let pillowSide = Int(((feather + pillowRadius) * 2 + 1) * pillowScale)
    private static let pillowCenter: CGRect = {
        let side = CGFloat(pillowSide), middle = (feather + pillowRadius) * pillowScale
        return CGRect(x: middle / side, y: middle / side, width: pillowScale / side, height: pillowScale / side)
    }()

    private static let pillow: CGImage? = {
        let side = pillowSide
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let s = pillowScale, radius = pillowRadius * s
        let box = CGRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side))
        for y in 0..<side {
            for x in 0..<side {
                let px = CGFloat(x) + 0.5, py = CGFloat(y) + 0.5
                let qx = abs(px - box.midX) - (box.width / 2 - radius), qy = abs(py - box.midY) - (box.height / 2 - radius)
                let outer = hypot(max(qx, 0), max(qy, 0)), inner = min(max(qx, qy), 0)
                // Signed distance to the rounded rect, in points: negative inside.
                let distance = (outer + inner - radius) / s
                let t: CGFloat = min(max((distance + feather) / feather, 0), 1)
                let faded: CGFloat = t * t * (3 - 2 * t)
                let alpha = UInt8(((1 - faded) * 255).rounded())
                let i = (y * side + x) * 4
                pixels[i] = alpha; pixels[i + 1] = alpha; pixels[i + 2] = alpha; pixels[i + 3] = alpha
            }
        }
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }()
}
