import Foundation

extension StackLayout {
    /// How far past the view, in viewports, the column builds cards (`CardColumn`).
    static let reach: CGFloat = 1

    /// The cards, by index from the newest, whose slots meet `band` once each is drawn `lifts[index]`
    /// below its slot (none past the end of `lifts`): distances up from the column's bottom, as
    /// `cardSpan` measures them.
    func cards(meeting band: ClosedRange<CGFloat>, sizes: [NSSize], lifts: [CGFloat] = []) -> IndexSet {
        var bottom: CGFloat = 0, met = IndexSet()
        for (index, size) in sizes.enumerated() {
            let lift = index < lifts.count ? lifts[index] : 0
            let top = bottom + size.height
            if top - lift >= band.lowerBound && bottom - lift <= band.upperBound { met.insert(index) }
            bottom = top + spacing
        }
        return met
    }
}
