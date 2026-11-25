import CoreGraphics
import CoreText
import Foundation

/// Where the editor draws each pin's teardrop, at one size on screen whatever the zoom, and which
/// pins it draws together as clusters. Two pins cluster when their bodies overlap by more than
/// `overlap` of their width at the zoom on screen, and a cluster takes in every pin that overlaps one
/// of its pins. A pin kept apart, such as the open or a selected one, never joins a cluster.
struct PinPlacement: Equatable {
    /// A pin drawn on its own.
    struct Drop: Equatable {
        let id: Pin.ID
        /// 0 for a pin before its first comment, which shows no number.
        let number: Int
        let agent: Bool
        let tip: CGPoint
        let orientation: PinTeardrop.Orientation
        /// The square the teardrop fits in, in px.
        let square: CGRect
    }

    /// Pins drawn as one capsule that names them, such as "3 · 4", or "3 · 4 · 7 +2" past three.
    struct Cluster: Equatable {
        /// In number order.
        let pins: [Pin.ID]
        let label: String
        /// Every pin in it is an agent's.
        let agent: Bool
        /// The tip of its lowest-numbered pin.
        let tip: CGPoint
        let orientation: PinTeardrop.Orientation
        /// The capsule, in px: a teardrop's height, and as wide as its label needs.
        let frame: CGRect
    }

    /// A teardrop's side, in px.
    let side: CGFloat
    let drops: [Drop]
    let clusters: [Cluster]

    /// The pins of `drawing`, each teardrop `side` px across, turned by the edge rule at the size the
    /// renderer draws them, inside an edge `edge` px wide, so each faces the way it does on a card.
    init(_ drawing: Drawing, side: CGFloat, edge: CGFloat, apart: Set<Pin.ID>, overlap: CGFloat) {
        self.side = side
        let fitSide = PinTeardrop.side * drawing.pointScale
        let pins = drawing.pins.sorted { $0.number < $1.number }
        let drops = pins.map { pin -> Drop in
            let orientation = PinTeardrop.facing(tip: pin.tip, side: fitSide, edge: edge, in: drawing.pixels, avoiding: drawing.pieceNumbers)
            return Drop(id: pin.id, number: pin.number, agent: pin.color == .agent, tip: pin.tip, orientation: orientation,
                        square: PinTeardrop.square(tip: pin.tip, orientation: orientation, side: side))
        }
        let reach = side * (1 - min(max(overlap, 0), 1))
        var group = Array(drops.indices)
        func root(_ i: Int) -> Int {
            var i = i
            while group[i] != i { i = group[i] }
            return i
        }
        let joinable = drops.indices.filter { !apart.contains(drops[$0].id) && drops[$0].number > 0 }
        for (n, i) in joinable.enumerated() {
            for j in joinable[(n + 1)...] {
                let a = drops[i].square, b = drops[j].square
                guard hypot(a.midX - b.midX, a.midY - b.midY) < reach else { continue }
                group[root(j)] = root(i)
            }
        }
        var members: [Int: [Int]] = [:]
        for i in joinable { members[root(i), default: []].append(i) }
        let clustered = members.values.filter { $0.count > 1 }
        let inCluster = Set(clustered.joined())
        self.drops = drops.indices.filter { !inCluster.contains($0) }.map { drops[$0] }
        clusters = clustered.map { indices in
            let chosen = indices.sorted().map { drops[$0] }
            let label = Self.label(chosen.map(\.number))
            let width = max(side, Self.width(of: label, side: side) + side * Self.labelPadding)
            let first = chosen[0]
            let up = first.tip.y - side - edge >= 0, right = first.tip.x + width + edge <= CGFloat(drawing.pixels.width)
            let frame = CGRect(x: right ? first.tip.x : first.tip.x - width, y: up ? first.tip.y - side : first.tip.y, width: width, height: side)
            return Cluster(pins: chosen.map(\.id), label: label, agent: chosen.allSatisfy(\.agent), tip: first.tip, orientation: PinTeardrop.orientation(up: up, right: right),
                           frame: frame)
        }.sorted { $0.label < $1.label }
    }

    /// The room beside a cluster's label, as a share of the teardrop's side.
    static let labelPadding: CGFloat = 0.7

    /// "3 · 4", or past three numbers "3 · 4 · 7 +2".
    static func label(_ numbers: [Int]) -> String {
        let shown = numbers.prefix(3).map(String.init).joined(separator: " · ")
        return numbers.count > 3 ? "\(shown) +\(numbers.count - 3)" : shown
    }

    /// How wide `label` is set in a teardrop's number size.
    static func width(of label: String, side: CGFloat) -> CGFloat {
        let font = CTFontCreateUIFontForLanguage(.system, side * PinTeardrop.numberSize, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, side * PinTeardrop.numberSize, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: label, attributes: [.font: font]))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// What a press at `point` lands on, within `band` px of a cluster or a teardrop: a cluster, then
    /// the teardrops from the newest number down.
    func hit(at point: CGPoint, band: CGFloat) -> EditorCore.Target? {
        if let cluster = clusters.first(where: { $0.frame.insetBy(dx: -band, dy: -band).contains(point) }) { return .cluster(cluster.pins) }
        let drop = drops.reversed().first { drop in
            let body = drop.square
            if hypot(point.x - body.midX, point.y - body.midY) <= side / 2 + band { return true }
            let right = drop.orientation == .upRight || drop.orientation == .downRight
            let up = drop.orientation == .upRight || drop.orientation == .upLeft
            let corner = CGRect(x: right ? drop.tip.x : drop.tip.x - side / 2, y: up ? drop.tip.y - side / 2 : drop.tip.y, width: side / 2, height: side / 2)
            return corner.insetBy(dx: -band, dy: -band).contains(point)
        }
        return drop.map { .pin($0.id) }
    }
}
