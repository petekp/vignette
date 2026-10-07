import AppKit
import CoreImage
import QuartzCore

/// For a live answer's `focus` mark, how the agent pulls focus to its target: the rest of the window
/// goes soft and grey and the target stays sharp (rack focus), or the target is magnified under a
/// lens (the loupe) (docs/live-ink-look-2026-10-07.md, plan step 8). Never written to a file.
struct FocusPlace: Equatable {
    /// What stays sharp, in the mark's coordinates: global top-left points, or the window's own once
    /// the mark is pinned to it (`LiveWindows.translated`).
    var target: CGRect
    var zoom: Bool
    /// The window softened, once it is captured, and where it sits, in the same coordinates as
    /// `target`. A focus mark is shown only with a picture.
    private(set) var picture: FocusPicture?
    private(set) var frame: CGRect = .null

    init(target: CGRect, zoom: Bool) {
        self.target = target
        self.zoom = zoom
    }

    mutating func show(_ picture: FocusPicture) {
        self.picture = picture
        frame = picture.frame
    }

    func moved(by offset: CGVector) -> FocusPlace {
        var moved = self
        moved.target = target.offsetBy(dx: offset.dx, dy: offset.dy)
        moved.frame = frame.offsetBy(dx: offset.dx, dy: offset.dy)
        return moved
    }

    static func == (a: FocusPlace, b: FocusPlace) -> Bool {
        a.target == b.target && a.zoom == b.zoom && a.frame == b.frame && a.picture === b.picture
    }
}

/// The geometry and timing of pulling focus, which the layout and the drawing share. The numbers are
/// the lab's (`.scratch/look-lab`, rendered for Pete on 2026-10-07).
enum Focus {
    /// How far the sharp spot reaches past the target, in points.
    static let pad = CGSize(width: 8, height: 6)
    /// The spot's corner radius, in points.
    static let radius: CGFloat = 9
    /// The softening starts this far inside the spot's edge and is whole this far outside it, in points.
    static let inside: CGFloat = 2
    static let outside: CGFloat = 14
    /// The loupe's magnification.
    static let zoom: CGFloat = 1.7

    /// The sharp spot round `target`.
    static func spot(around target: CGRect) -> CGRect {
        target.insetBy(dx: -pad.width, dy: -pad.height)
    }

    /// The loupe's lens over `target`: the spot round it magnified, centred on it, and moved inside
    /// `room`, the window less a margin.
    static func lens(over target: CGRect, in room: CGRect) -> CGRect {
        let spot = spot(around: target)
        let size = CGSize(width: min(spot.width * zoom, room.width), height: min(spot.height * zoom, room.height))
        var lens = CGRect(x: spot.midX - size.width / 2, y: spot.midY - size.height / 2, width: size.width, height: size.height)
        lens.origin.x = max(room.minX, min(lens.minX, room.maxX - lens.width))
        lens.origin.y = max(room.minY, min(lens.minY, room.maxY - lens.height))
        return lens
    }

    /// How long each of `stops` holds, in seconds. Stop i goes with the reply's sentence i, and the
    /// last with the rest of them, read at `perWord` a word: so the focus follows the reading. Each
    /// holds at least `least`, and the last at least `lastLeast` before the focus lets go.
    static func holds(for say: String, stops: Int) -> [TimeInterval] {
        guard stops > 0 else { return [] }
        var sentences: [String] = []
        say.enumerateSubstrings(in: say.startIndex..., options: .bySentences) { sentence, _, _, _ in
            if let sentence, !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { sentences.append(sentence) }
        }
        return (0..<stops).map { index in
            let last = index == stops - 1
            let read = last ? sentences.dropFirst(index) : sentences.dropFirst(index).prefix(1)
            let words = read.map { $0.split(whereSeparator: \.isWhitespace).count }.reduce(0, +)
            return max(TimeInterval(words) * perWord, last ? lastLeast : least)
        }
    }

    static let perWord: TimeInterval = 0.3
    static let least: TimeInterval = 2
    static let lastLeast: TimeInterval = 2.5
    /// How far the pointer may go from where it was when the focus came in before it lets go, in points.
    static let pointerReach: CGFloat = 120
    /// How long a focus takes to come in, at full motion. A tour's next stop comes in for
    /// `overlap` of that before the last one goes, so the old target blurs before the new one sharpens.
    static let fade: CFTimeInterval = 0.45
    static let overlap: Double = 0.6
}

/// A window captured when the agent pulls focus, and what the focus shows over it, made off the main
/// thread from one capture for every stop of a tour.
final class FocusPicture: @unchecked Sendable {
    /// The window when it was captured, in global top-left points.
    let frame: CGRect
    /// The window blurred, greyed and dimmed, for rack focus.
    let soft: CGImage?
    /// The window lightly blurred and dimmed, round the loupe.
    let rest: CGImage?
    /// The capture itself, which the loupe magnifies, and its pixels per point.
    let sharp: CGImage?
    let scale: CGFloat
    /// The window is dark, which darkens the lens's shadow.
    let dark: Bool

    private init(frame: CGRect, soft: CGImage?, rest: CGImage?, sharp: CGImage?, scale: CGFloat, dark: Bool) {
        self.frame = frame
        self.soft = soft
        self.rest = rest
        self.sharp = sharp
        self.scale = scale
        self.dark = dark
    }

    /// `capture`, the window at `frame`, softened for rack focus with `rack` and for the loupe with
    /// `loupe`, as the lab softened it. Nil when Core Image cannot render it.
    static func make(_ capture: CGImage, frame: CGRect, rack: Bool, loupe: Bool) -> FocusPicture? {
        let scale = CGFloat(capture.width) / max(frame.width, 1)
        let dark = (LivePacket.Luminance(capture, frame: frame)?.mean(in: frame) ?? 1) <= LivePacket.Luminance.dark
        // A quarter of the pixels each way: the blur takes out the detail, and it is a sixteenth of the work.
        let small = CIImage(cgImage: capture).applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: 0.25])
        let extent = small.extent.integral
        let blurred = small.clampedToExtent().applyingGaussianBlur(sigma: Double(5 * scale * 0.25)).cropped(to: extent)
        func dimmed(_ image: CIImage, by amount: CGFloat) -> CIImage {
            let k = 1 - amount
            return image.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: k, y: 0, z: 0, w: 0),
                                                                      "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0),
                                                                      "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0)])
        }
        let context = CIContext(options: [.cacheIntermediates: false])
        let space = capture.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        func render(_ image: CIImage) -> CGImage? { context.createCGImage(image, from: extent, format: .RGBA8, colorSpace: space) }
        var soft: CGImage?, rest: CGImage?
        if rack {
            // Most of the colour goes, so a light page reads as out of focus rather than as a grey sheet.
            soft = render(dimmed(blurred.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.2]), by: dark ? 0.35 : 0.1))
            guard soft != nil else { return nil }
        }
        if loupe {
            let mixed = blurred.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.4)]).composited(over: small)
            rest = render(dimmed(mixed, by: dark ? 0.45 : 0.22))
            guard rest != nil else { return nil }
        }
        return FocusPicture(frame: frame, soft: soft, rest: rest, sharp: loupe ? capture : nil, scale: scale, dark: dark)
    }
}

/// Draws a focus mark on the overlay, under the other marks: the softened window with the sharp spot
/// cut out for rack focus, or the lightly softened window with the lens over the target for the loupe.
/// Everything is in the marks layer's coordinates, global top-left points.
@MainActor
final class FocusLayer {
    let root = CALayer()
    private let picture = CALayer()
    /// The rack focus's mask: four white rects round the hole, and the hole's soft edge, stretched
    /// from one small picture (`hole`), so the spot can be any size.
    private let mask = CALayer()
    private let edges = (0..<4).map { _ in CALayer() }
    private let hole = CALayer()
    private let shadow = CALayer()
    private let lens = CALayer()

    init() {
        root.anchorPoint = .zero
        for layer in [picture, mask, hole, shadow, lens] + edges {
            layer.anchorPoint = .zero
        }
        picture.contentsGravity = .resize
        for edge in edges {
            edge.backgroundColor = CGColor(gray: 1, alpha: 1)
            mask.addSublayer(edge)
        }
        hole.contents = Self.hole
        hole.contentsScale = Self.holeScale
        hole.contentsCenter = Self.holeCenter
        mask.addSublayer(hole)
        lens.contentsGravity = .resize
        lens.masksToBounds = true
        lens.borderWidth = 1
        lens.borderColor = CGColor(gray: 1, alpha: 0.55)
        shadow.shadowColor = CGColor(gray: 0, alpha: 1)
        shadow.shadowRadius = 10
        shadow.shadowOffset = CGSize(width: 0, height: 6)
        root.addSublayer(picture)
        root.addSublayer(shadow)
        root.addSublayer(lens)
    }

    /// Shows `place` with `spot`, the mark's rect: the sharp spot, or the lens.
    func show(_ place: FocusPlace, spot: CGRect) {
        guard let shown = place.picture else { root.isHidden = true; return }
        root.isHidden = false
        picture.frame = place.frame
        if place.zoom {
            picture.contents = shown.rest
            picture.mask = nil
            let radius = Focus.radius * Focus.zoom
            lens.frame = spot
            lens.cornerRadius = radius
            shadow.frame = spot
            shadow.shadowPath = CGPath(roundedRect: CGRect(origin: .zero, size: spot.size), cornerWidth: radius, cornerHeight: radius, transform: nil)
            shadow.shadowOpacity = shown.dark ? 0.6 : 0.3
            lens.contents = Self.magnified(place, lens: spot)
            shadow.isHidden = false
            lens.isHidden = false
        } else {
            picture.contents = shown.soft
            shadow.isHidden = true
            lens.isHidden = true
            cut(Focus.spot(around: place.target), from: place.frame)
            picture.mask = mask
        }
    }

    /// Brings it in over `duration`: it fades in, and a lens grows from the target's own size.
    func appear(duration: CFTimeInterval) {
        guard duration > 0 else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        root.add(fade, forKey: "appear")
        guard !lens.isHidden else { return }
        for layer in [lens, shadow] {
            let grow = CASpringAnimation(keyPath: "transform.scale")
            grow.fromValue = 1 / Focus.zoom
            grow.toValue = 1
            grow.stiffness = 260
            grow.damping = 26
            grow.duration = grow.settlingDuration
            layer.add(grow, forKey: "grow")
        }
    }

    /// Cuts `spot` out of the mask over the picture at `frame`.
    private func cut(_ spot: CGRect, from frame: CGRect) {
        mask.frame = CGRect(origin: .zero, size: frame.size)
        let edge = spot.offsetBy(dx: -frame.minX, dy: -frame.minY).insetBy(dx: -Focus.outside, dy: -Focus.outside)
        hole.frame = edge
        let w = frame.width, h = frame.height
        edges[0].frame = CGRect(x: 0, y: 0, width: w, height: max(0, edge.minY))
        edges[1].frame = CGRect(x: 0, y: edge.maxY, width: w, height: max(0, h - edge.maxY))
        edges[2].frame = CGRect(x: 0, y: edge.minY, width: max(0, edge.minX), height: edge.height)
        edges[3].frame = CGRect(x: edge.maxX, y: edge.minY, width: max(0, w - edge.maxX), height: edge.height)
    }

    /// The part of the capture the lens shows, the target's spot magnified about its centre.
    private static func magnified(_ place: FocusPlace, lens: CGRect) -> CGImage? {
        guard let picture = place.picture, let sharp = picture.sharp else { return nil }
        let spot = Focus.spot(around: place.target)
        let source = CGRect(x: spot.midX + (lens.minX - spot.midX) / Focus.zoom, y: spot.midY + (lens.minY - spot.midY) / Focus.zoom,
                            width: lens.width / Focus.zoom, height: lens.height / Focus.zoom)
        let pixels = CGRect(x: (source.minX - place.frame.minX) * picture.scale, y: (source.minY - place.frame.minY) * picture.scale,
                            width: source.width * picture.scale, height: source.height * picture.scale)
        return sharp.cropping(to: pixels.integral)
    }

    /// The hole's soft edge, drawn once at `holeScale`: clear inside a rounded rect of radius
    /// `Focus.radius`, white `Focus.outside` past its edge, and a smoothstep between, with one
    /// stretchable point in the middle (`holeCenter`).
    private static let holeScale: CGFloat = 2
    private static let holeSide = Int(((Focus.outside + Focus.radius) * 2 + 1) * holeScale)
    private static let holeCenter: CGRect = {
        let side = CGFloat(holeSide), middle = (Focus.outside + Focus.radius) * holeScale
        return CGRect(x: middle / side, y: middle / side, width: holeScale / side, height: holeScale / side)
    }()

    private static let hole: CGImage? = {
        let side = holeSide
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let s = holeScale, margin = Focus.outside * s, radius = Focus.radius * s
        let box = CGRect(x: margin, y: margin, width: CGFloat(side) - 2 * margin, height: CGFloat(side) - 2 * margin)
        for y in 0..<side {
            for x in 0..<side {
                // The signed distance from the pixel's centre to the rounded rect, in points.
                let px = CGFloat(x) + 0.5, py = CGFloat(y) + 0.5
                let qx = abs(px - box.midX) - (box.width / 2 - radius), qy = abs(py - box.midY) - (box.height / 2 - radius)
                let outer = hypot(max(qx, 0), max(qy, 0)), inner = min(max(qx, qy), 0)
                let distance = (outer + inner - radius) / s
                let t = min(max((distance + Focus.inside) / (Focus.inside + Focus.outside), 0), 1)
                let alpha = UInt8((t * t * (3 - 2 * t) * 255).rounded())
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
