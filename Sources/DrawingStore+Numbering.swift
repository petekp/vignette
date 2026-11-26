import CoreGraphics
import Foundation

extension Drawing {
    /// What a drawing's file keeps for the drawing made next, when it holds no marks and no pins: the
    /// number the next pin takes, and where a stitch's pieces wear their numbers.
    struct Numbering: Equatable {
        var nextPin = 1
        var pieceNumbers: [CGRect] = []
    }

    /// A drawing kept by a file that holds a stitch's piece numbers: it is written and swept like one
    /// with marks, though it draws nothing.
    var isFiled: Bool { !isEmpty || !pieceNumbers.isEmpty }

    /// This new drawing, numbered as `numbering` says.
    func numbered(_ numbering: Numbering?) -> Drawing {
        guard let numbering else { return self }
        var drawing = self
        drawing.nextPin = max(drawing.nextPin, numbering.nextPin)
        drawing.pieceNumbers = numbering.pieceNumbers
        return drawing
    }
}

extension DrawingStore {
    /// The numbering the file of the screenshot at `key`, whose size is `pixels`, keeps, or nil with no
    /// file for that image.
    func readNumbering(key: String, pixels: PixelSize) -> Drawing.Numbering? {
        readUnmarked(key: key, pixels: pixels).map { Drawing.Numbering(nextPin: $0.nextPin, pieceNumbers: $0.pieceNumbers) }
    }

    /// The drawing the file of the screenshot at `key`, whose size is `pixels`, keeps with its marks
    /// and pins left out: its scales and its numbering. Nil with no file for that image.
    func readUnmarked(key: String, pixels: PixelSize) -> Drawing? {
        guard case .stored(let stored) = contents(of: url(for: key)), stored.key == key, stored.pixels == pixels else { return nil }
        return Drawing(key: key, pixels: pixels, pointScale: stored.pointScale, markScale: stored.markScale, marks: [],
                       nextPin: Pin.writtenNextPin(stored.nextPin) ?? 1, pieceNumbers: stored.pieceNumbers(in: pixels))
    }
}

extension Drawings {
    /// The numbering stored for the screenshot `key`, whose size as displayed is `pixels`. Only a
    /// screenshot with a file has it read.
    func numbering(of key: ScreenshotKey, pixels: PixelSize) -> Drawing.Numbering? {
        guard keys.contains(key) || messages.contains(key) else { return nil }
        return store.readNumbering(key: key.path, pixels: pixels)
    }
}
