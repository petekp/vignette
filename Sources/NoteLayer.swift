import AppKit
import QuartzCore

/// A note on the live screen: its tag, badge and words drawn by the renderer into one bitmap at the
/// screen's scale, as `Mark.draw` draws a note on a screenshot. A few short notes, so on the main thread.
@MainActor
final class NoteLayer: CALayer {
    private var shown: (mark: Mark, textStyle: TextStyle, markStyle: MarkStyle)?

    init(scale: CGFloat) {
        super.init()
        contentsScale = scale
    }

    override init(layer: Any) { super.init(layer: layer) }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ mark: Mark, textStyle: TextStyle, markStyle: MarkStyle) {
        guard case .text(let text) = mark.geometry else { return }
        if let shown, shown.mark == mark, shown.textStyle == textStyle, shown.markStyle == markStyle { return }
        shown = (mark, textStyle, markStyle)
        // The notes wrap at their own width, so no image edge bounds them.
        let layout = TextLayout(text, imageWidth: .greatestFiniteMagnitude, pointScale: 1, style: textStyle.forMark(mark))
        let region = MarkLayers.aligned(MarkLayers.padded(text, box: layout.box, pointScale: 1, markStyle: markStyle), scale: contentsScale)
        let width = Int((region.width * contentsScale).rounded()), height = Int((region.height * contentsScale).rounded())
        guard width > 0, height > 0, let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                             bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: contentsScale, y: -contentsScale)
        context.translateBy(x: -region.minX, y: -region.minY)
        mark.draw(in: context, pointScale: 1, imageWidth: .greatestFiniteMagnitude, style: textStyle, markStyle: markStyle)
        frame = region
        contents = context.makeImage()
    }

    /// Springs in from its centre after `delay`.
    func springIn(after delay: CFTimeInterval, duration: CFTimeInterval) {
        guard duration > 0 else { return }
        let begin = CACurrentMediaTime() + delay
        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.6
        pop.toValue = 1
        pop.damping = 14
        pop.stiffness = 240
        pop.beginTime = begin
        pop.duration = pop.settlingDuration
        pop.fillMode = .backwards
        let appear = CABasicAnimation(keyPath: "opacity")
        appear.fromValue = 0
        appear.toValue = opacity
        appear.beginTime = begin
        appear.duration = duration * 0.3
        appear.fillMode = .backwards
        add(pop, forKey: "pop")
        add(appear, forKey: "appear")
    }
}

