import AppKit

/// Which cards of a long column hold their pictures. Chunks of older screenshots can make the
/// column as long as the folder, and a card's picture is about 0.8 MB, so a card far from the view
/// lets its picture go and takes it back as the view comes near: from `Thumbnailer`'s cache when it
/// is still there, decoded off the main thread when it is not. A column no longer than the largest
/// `recentCount` holds every picture, as it always has.
@MainActor
final class CardPictures {
    static let keptAlways = 100
    /// How near the view, in viewports, a card takes its picture back.
    static let near: CGFloat = 2
    /// How far from the view, in viewports, a card's picture may go.
    static let far: CGFloat = 4
    /// Pictures go only this many at a time, since every change to the column's cards lays the
    /// whole column out again.
    static let batch = 30

    /// The cards to let go of their pictures and the cards to give theirs back, by index.
    /// `heights` are the cards' drawn heights from the newest, `view` is the scroll's range, and
    /// `holding` says which cards hold a picture now. A card `keeps` holds its own whatever the
    /// distance.
    static func plan(heights: [CGFloat], spacing: CGFloat, view: ClosedRange<CGFloat>, holding: [Bool],
                     keeps: (Int) -> Bool) -> (drop: [Int], want: [Int]) {
        guard heights.count > keptAlways else { return ([], []) }
        let viewport = max(view.upperBound - view.lowerBound, 1)
        var drop: [Int] = [], want: [Int] = [], bottom: CGFloat = 0
        for (index, height) in heights.enumerated() {
            let top = bottom + height
            let distance = max(0, bottom - view.upperBound, view.lowerBound - top) / viewport
            if holding[index], distance > far, !keeps(index) { drop.append(index) }
            if !holding[index], distance < near { want.append(index) }
            bottom = top + spacing
        }
        return (drop.count >= batch ? drop : [], want)
    }

    /// Cards whose picture is being decoded, so the next plan does not ask again.
    var asked: Set<UUID> = []
    /// Pictures decoded since the column last changed, given to the cards in one change.
    var arrived: [UUID: NSImage] = [:]

    func reset() {
        asked = []
        arrived = [:]
    }
}
