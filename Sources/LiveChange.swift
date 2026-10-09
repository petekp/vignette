import AppKit

/// Whether a session's turn changed what is under the person's ink: the window under the ink when
/// the ask was sent, against the window when the turn ended (docs/live-ink-overnight-2026-10-07.md,
/// question 5). Both are read on a coarse grid of colour, so a change of a few pixels of anti-aliasing
/// is not one. Colour rather than grey, since a recolour can keep its brightness: a green button
/// turned red reads as no change in grey. Cells that change between two captures of the ended turn, half a second
/// apart, are moving on their own, as a caret or a spinner does, and never count.
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
    /// How far a cell's red, green or blue must move, of 255, to count as changed.
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
        guard let old = colours(before, columns: columns, rows: rows), let new = colours(after, columns: columns, rows: rows) else {
            return .changed(1, around: CGRect(origin: .zero, size: size))
        }
        let later = again.flatMap { colours($0, columns: columns, rows: rows) }
        var inside = 0, changedInside = 0
        var around = CGRect.null
        for row in 0..<rows {
            for column in 0..<columns {
                let index = row * columns + column
                let cell = CGRect(x: CGFloat(column) * side.width, y: CGFloat(row) * side.height, width: side.width, height: side.height)
                let decides = ink.map { $0.contains(CGPoint(x: cell.midX, y: cell.midY)) } ?? true
                if decides { inside += 1 }
                let moved = differ(old, new, at: index)
                let restless = later.map { differ($0, new, at: index) } ?? false
                guard moved && !restless else { continue }
                around = around.union(cell)
                if decides { changedInside += 1 }
            }
        }
        let share = Double(changedInside) / Double(max(inside, 1))
        return changedInside >= fewestCells && share >= changedShare ? .changed(share, around: around) : .unchanged(share)
    }

    /// Whether cell `index` of two grids from `colours` differs by more than `cellThreshold` in any of
    /// red, green and blue.
    private static func differ(_ a: [UInt8], _ b: [UInt8], at index: Int) -> Bool {
        let first = index * 4
        return (first..<first + 3).contains { abs(Int(a[$0]) - Int(b[$0])) > cellThreshold }
    }

    /// `image` drawn into `columns` by `rows` cells of colour, each the average of the pixels it
    /// covers: four bytes a cell, red, green, blue and one unused.
    private static func colours(_ image: CGImage, columns: Int, rows: Int) -> [UInt8]? {
        var cells = [UInt8](repeating: 0, count: columns * rows * 4)
        let drawn = cells.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: columns * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: columns, height: rows))
            return true
        }
        return drawn ? cells : nil
    }
}
