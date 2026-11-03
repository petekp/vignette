import AppKit
import ScreenCaptureKit
import Vision

extension LivePacket {
    /// A capture's luminance averaged over a grid of cells about 1/64 of its width across, so an
    /// answer's mark can be drawn for what is behind it.
    struct Luminance: Sendable {
        /// The capture's frame, in global top-left points.
        let frame: CGRect
        let columns: Int
        let rows: Int
        /// Row by row from the top, 0 for black and 255 for white.
        let cells: [UInt8]
        /// The mean luminance at or below which a window counts as dark behind what is drawn over it.
        static let dark: CGFloat = 0.45

        /// `image` drawn down to `columns` cells across, each the mean of the pixels under it.
        init?(_ image: CGImage, frame: CGRect, columns: Int = 64) {
            let rows = max(1, Int((CGFloat(columns) * CGFloat(image.height) / CGFloat(max(image.width, 1))).rounded()))
            var cells = [UInt8](repeating: 0, count: columns * rows)
            let drawn = cells.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: columns,
                                              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(x: 0, y: 0, width: columns, height: rows))
                return true
            }
            guard drawn else { return nil }
            self.frame = frame
            self.columns = columns
            self.rows = rows
            self.cells = cells
        }

        /// The luminance, 0 to 1, of the cell under `point`, in global top-left points, or nil when
        /// it is outside the capture.
        func value(at point: CGPoint) -> CGFloat? {
            guard frame.contains(point), frame.width > 0, frame.height > 0 else { return nil }
            let column = min(Int((point.x - frame.minX) / frame.width * CGFloat(columns)), columns - 1)
            let row = min(Int((point.y - frame.minY) / frame.height * CGFloat(rows)), rows - 1)
            return CGFloat(cells[row * columns + column]) / 255
        }

        /// The mean luminance, 0 to 1, of the cells under `rect`, in global top-left points, or nil
        /// when it is outside the capture.
        func mean(in rect: CGRect) -> CGFloat? {
            let part = rect.intersection(frame)
            guard !part.isNull, frame.width > 0, frame.height > 0 else { return nil }
            let x0 = Int(((part.minX - frame.minX) / frame.width * CGFloat(columns)).rounded(.down))
            let x1 = Int(((part.maxX - frame.minX) / frame.width * CGFloat(columns)).rounded(.up))
            let y0 = Int(((part.minY - frame.minY) / frame.height * CGFloat(rows)).rounded(.down))
            let y1 = Int(((part.maxY - frame.minY) / frame.height * CGFloat(rows)).rounded(.up))
            var sum = 0, count = 0
            for row in max(0, y0)..<min(rows, max(y1, y0 + 1)) {
                for column in max(0, x0)..<min(columns, max(x1, x0 + 1)) {
                    sum += Int(cells[row * columns + column])
                    count += 1
                }
            }
            return count > 0 ? CGFloat(sum) / CGFloat(count * 255) : nil
        }
    }
}
