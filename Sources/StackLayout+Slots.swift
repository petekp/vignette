import Foundation

extension StackLayout {
    /// The cards, by index from the newest, whose slots meet `band`: distances up from the column's
    /// bottom, as `cardSpan` measures them. Slots run up the column in order, so the cards that meet
    /// it are one run.
    func cards(meeting band: ClosedRange<CGFloat>, sizes: [NSSize]) -> Range<Int> {
        var bottom: CGFloat = 0, first: Int?, end = 0
        for (index, size) in sizes.enumerated() {
            if bottom > band.upperBound { break }
            let top = bottom + size.height
            if top >= band.lowerBound {
                if first == nil { first = index }
                end = index + 1
            }
            bottom = top + spacing
        }
        return first.map { $0..<end } ?? 0..<0
    }
}
