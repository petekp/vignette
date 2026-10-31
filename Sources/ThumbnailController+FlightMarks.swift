import AppKit

extension ThumbnailController {
    /// The marks a flight carries: `drawing` with every text drawn at `scale` device px to a px, the
    /// larger of the flight's two ends, over the whole image, and showing the bitmaps `sources` have
    /// until its own arrive. Nil for a drawing with no marks.
    func flightMarks(_ drawing: Drawing?, scale: CGFloat, adopting sources: [MarkLayers?]) -> MarkLayers? {
        guard let drawing, !drawing.marks.isEmpty else { return nil }
        let marks = MarkLayers(pixels: drawing.pixels, queue: MarkLayers.textQueue)
        marks.setScale(screen.backingScaleFactor)
        marks.show(drawing, scale: scale, bound: drawing.pixels.bounds, style: ui.textStyle, markStyle: ui.markStyle, adopting: sources.compactMap { $0 })
        return marks
    }

    /// Device px per image px of the editor's texts in the annotator at `frame`, fitted: the editor's
    /// own sum, so a flight's texts and the editor's are the same bitmaps.
    func annotatorTextScale(_ frame: NSRect, _ pixels: PixelSize) -> CGFloat {
        pixels.width > 0 ? frame.width / CGFloat(pixels.width) * screen.backingScaleFactor : 0
    }

    /// Device px per image px of a card's texts, at the card's `size` at rest.
    func cardTextScale(_ size: NSSize, _ pixels: PixelSize) -> CGFloat {
        guard pixels.width > 0, pixels.height > 0 else { return 0 }
        return max(size.width / CGFloat(pixels.width), size.height / CGFloat(pixels.height)) * screen.backingScaleFactor
    }
}
