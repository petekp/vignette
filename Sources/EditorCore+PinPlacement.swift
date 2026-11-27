import CoreGraphics
import Foundation

extension EditorCore {
    // MARK: Drawn at one size

    /// A teardrop's side in px at the current zoom: `PinStyle.side` screen pt at every zoom, on a
    /// screenshot of any size.
    var pinSide: CGFloat { geometry.screen(markStyle.pin.side) }

    /// The pins as the editor draws them now. The open pin, the selected ones and a new one never
    /// join a cluster.
    var pinPlacement: PinPlacement {
        var apart = selection
        if let composer { apart.insert(composer.pin) }
        return PinPlacement(drawing, side: pinSide, edge: geometry.pt(markStyle.edgeWidth), apart: apart, style: markStyle.pin)
    }

    /// The pins an area's outline shows for: hovered, selected, being placed or open.
    var outlinedPins: Set<Pin.ID> {
        var ids = Set(drawing.pins.map(\.id)).intersection(selection).union(marchingPins)
        if case .pin(let id)? = hover { ids.insert(id) }
        return ids
    }

    /// The pins whose area's dashes march: the one being placed and the open one.
    var marchingPins: Set<Pin.ID> {
        var ids = Set<Pin.ID>()
        if case .placing(let id)? = gesture?.phase { ids.insert(id) }
        if let composer { ids.insert(composer.pin) }
        return ids
    }

    /// What a press at `point` hits among the pins: a teardrop or a cluster within the hit margin, or
    /// the outline of an area while it shows. Never an area's inside.
    func pinTarget(at point: CGPoint) -> Target? {
        let band = geometry.screen(metrics.hitMargin)
        if let hit = pinPlacement.hit(at: point, band: band) { return hit }
        for id in outlinedPins {
            guard case .area(let frame, _)? = pin(id)?.place else { continue }
            if geometry.hit(Mark(id: id, geometry: .rectangle(frame)), at: point, insideCounts: false) != nil { return .pin(id) }
        }
        return nil
    }

    /// A click on a cluster lists its pins by it.
    mutating func showCluster(_ ids: [Pin.ID]) {
        guard let cluster = pinPlacement.clusters.first(where: { $0.pins == ids }) else { return }
        emit(.showCluster(ids, at: cluster.frame))
    }
}
