import AppKit
import IOSurface
import QuartzCore

/// A drawing's marks as Core Animation layers, in image px: how the editor, a card and a flight draw
/// them. The owner sets the layer's transform from px to where the image is shown, and says what each
/// text is drawn for.
///
/// A rectangle, an ellipse or an arrow is a shape layer holding the renderer's own paths
/// (`Mark.shape`). Core Animation draws it sharp at any scale with nothing redrawn, and a change to it
/// is a new path, however large the mark.
///
/// A text is a bitmap the renderer draws on a serial queue, because only the renderer draws its
/// outline. Until a new bitmap arrives the old one stays, scaled, and a text that only moved slides
/// it; a text new here may show another picture's bitmap of it meanwhile (`adopt`). A bitmap is
/// shown only if its text is still here, as the same record, and still wants exactly it; after
/// `park` none is.
@MainActor
final class MarkLayers {
    /// Where the editor's and the flights' texts are drawn: apart from the renderings of Done, Copy
    /// Drawing and Send, so a long rendering never delays the screen.
    nonisolated static let textQueue = DispatchQueue(label: "vignette.editor-texts", qos: .userInteractive)
    /// Where the cards' texts are drawn: apart from the editor's, so a stack of long texts never
    /// delays the one being edited.
    nonisolated static let cardQueue = DispatchQueue(label: "vignette.card-texts", qos: .userInitiated)
    /// Units are image px from the top-left corner, y down; the owner sets its transform.
    let layer = CALayer()
    /// The image the marks are drawn on.
    let pixels: PixelSize
    /// A text's bitmap has just arrived and shows the text as it is. Called inside the transaction
    /// that put it on its layer, so whatever covered the text can go in the same frame.
    var onTextDrawn: ((Mark.ID) -> Void)?
    /// What is shown, as of the last `show`.
    private(set) var drawing: Drawing?
    let queue: DispatchQueue
    private var shapes: [Mark.ID: ShapeMarkLayer] = [:]
    var texts: [Mark.ID: Text] = [:]
    private var pins: [Pin.ID: PinLayer] = [:]
    private var clusters: [[Pin.ID]: PinLayer] = [:]
    private var contentsScale: CGFloat = 2
    var shown: Shown?
    /// The scale and the part of the image of the last `show(_:scale:bound:…)`, for `restyle`.
    private var wholeShow: (scale: CGFloat, bound: CGRect)?
    /// After `park`, nothing changes.
    private(set) var isParked = false

    /// Decides what a text wants drawn: sets its `wantWhole` and `wantDetail`, and whether its layers
    /// are hidden. True when the text is in view, which is drawn first.
    typealias Plan = (Text, Mark, Mark.Text) -> Bool

    struct Shown {
        let layout: (Mark.Text, Mark) -> TextLayout
        let plan: Plan
    }


    /// Marks on an image of `pixels`, whose texts are drawn on `queue`.
    init(pixels: PixelSize, queue: DispatchQueue) {
        self.pixels = pixels
        self.queue = queue
        layer.anchorPoint = .zero
        layer.position = .zero
        layer.bounds = pixels.bounds
    }

    /// Keeps what is on screen as it is: no bitmap on its way is shown, and `show` changes nothing.
    func park() {
        isParked = true
        for record in texts.values {
            record.wanted.set([])
            record.pending = nil
        }
    }

    /// Lets every layer and bitmap go, and stops every draw on its way: nothing here is on screen any
    /// more.
    func clear() {
        park()
        layer.sublayers = nil
        shapes = [:]
        texts = [:]
        pins = [:]
        clusters = [:]
    }

    /// Marks shown at one scale over a part of the image, a card's or a flight's, shown again in a
    /// new text style and arrowhead. Each text keeps the bitmap it has until its new one arrives.
    func restyle(_ style: TextStyle, markStyle: MarkStyle) {
        guard let drawing, let wholeShow else { return }
        show(drawing, scale: wholeShow.scale, bound: wholeShow.bound, style: style, markStyle: markStyle)
    }

    /// The device pixels per point of the screen the marks are on, for the shape layers.
    func setScale(_ scale: CGFloat) {
        contentsScale = scale
        for record in shapes.values { record.setScale(scale) }
        for record in Array(pins.values) + Array(clusters.values) { record.setScale(scale) }
    }

    /// Shows `drawing`'s marks in order, the newest on top, and its pins above them, clustered by the
    /// editor's rule at the size they are drawn (`PinPlacement`). `plan` says what each text wants drawn,
    /// here and again whenever one of its bitmaps arrives, in the style of `layout`, the text's
    /// layout, which a text that only moved sideways is checked against. A text new here shows the
    /// bitmap one of `sources` has of the same words in the same place and style, until its own
    /// arrives.
    func show(_ drawing: Drawing, markStyle: MarkStyle, layout: @escaping (Mark.Text, Mark) -> TextLayout,
              adopting sources: [MarkLayers] = [], plan: @escaping Plan) {
        guard !isParked, drawing.pixels == pixels else { return }
        self.drawing = drawing
        shown = Shown(layout: layout, plan: plan)
        var layers: [CALayer] = []
        var seen = Set<Mark.ID>()
        var inView: [Text] = [], outOfView: [Text] = []
        let ids = Set(drawing.marks.map(\.id))
        var gone = texts.filter { !ids.contains($0.key) }
        for mark in drawing.marks {
            seen.insert(mark.id)
            if case .text(let text) = mark.geometry {
                let record: Text
                if let kept = texts[mark.id] ?? renamed(mark, from: &gone) {
                    record = kept
                } else {
                    record = Text()
                    // What it wants first, so it takes the bitmap nearest that.
                    update(record, mark, text)
                    for source in sources { take(from: source, into: record, mark) }
                }
                texts[mark.id] = record
                if update(record, mark, text) { inView.append(record) } else { outOfView.append(record) }
                layers.append(record.whole)
                layers.append(record.detail)
            } else {
                let record = shapes[mark.id] ?? ShapeMarkLayer(scale: contentsScale)
                record.show(mark, pointScale: drawing.pointScale, markStyle: markStyle)
                shapes[mark.id] = record
                layers.append(record.root)
            }
        }
        let pointScale = drawing.pointScale
        let placement = PinPlacement(drawing, side: markStyle.pin.side * pointScale, edge: markStyle.edgeWidth * pointScale, apart: [],
                                     style: markStyle.pin)
        let alone = Set(placement.drops.map(\.id))
        pins = pins.filter { alone.contains($0.key) }
        for pin in drawing.pins where alone.contains(pin.id) {
            let record = pins[pin.id] ?? PinLayer(scale: contentsScale)
            record.show(pin, on: drawing, markStyle: markStyle)
            pins[pin.id] = record
            layers.append(record.root)
        }
        let grouped = Set(placement.clusters.map(\.pins))
        clusters = clusters.filter { grouped.contains($0.key) }
        for cluster in placement.clusters {
            let record = clusters[cluster.pins] ?? PinLayer(scale: contentsScale)
            record.show(PinTeardrop(label: cluster.label, agent: cluster.agent, orientation: cluster.orientation, frame: cluster.frame, style: markStyle.pin),
                        color: cluster.agent ? .agent : .person, pointScale: pointScale, markStyle: markStyle)
            clusters[cluster.pins] = record
            layers.append(record.root)
        }
        for id in shapes.keys where !seen.contains(id) {
            shapes[id]?.root.removeFromSuperlayer()
            shapes[id] = nil
        }
        for id in texts.keys where !seen.contains(id) {
            texts[id]?.wanted.set([])
            texts[id]?.whole.removeFromSuperlayer()
            texts[id]?.detail.removeFromSuperlayer()
            texts[id] = nil
        }
        if (layer.sublayers ?? []).map(ObjectIdentifier.init) != layers.map(ObjectIdentifier.init) {
            layer.sublayers = layers
        }
        // The texts in view are drawn first.
        for record in inView + outOfView { schedule(record) }
    }

    /// Shows `drawing` with every text drawn whole at `scale` device px to a px, over the part of
    /// `bound` its letters may touch: the plan for a picture that does not zoom.
    func show(_ drawing: Drawing, scale: CGFloat, bound: CGRect, style: TextStyle, markStyle: MarkStyle, adopting sources: [MarkLayers] = []) {
        guard !isParked else { return }
        wholeShow = (scale, bound)
        let imageWidth = CGFloat(drawing.pixels.width), pointScale = drawing.pointScale
        let styles = Styles(text: style, paint: markStyle, pointScale: pointScale)
        show(drawing, markStyle: markStyle, layout: { TextLayout($0, imageWidth: imageWidth, pointScale: pointScale, style: style.forMark($1)) },
             adopting: sources) { record, mark, _ in
            record.wantWhole = Target(mark: mark, region: bound, scale: scale, style: styles)
            return true
        }
    }

    /// Every text that has not got the bitmap it wants takes the one `source` has of the same words
    /// in the same place, when that is nearer what it wants than its own, until its own arrives.
    func adopt(from source: MarkLayers) {
        guard !isParked, let drawing else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for mark in drawing.marks {
            guard case .text(let text) = mark.geometry, let record = texts[mark.id], record.drawn != record.wantWhole,
                  take(from: source, into: record, mark) else { continue }
            update(record, mark, text)
        }
        CATransaction.commit()
    }

    /// The pixels in the text bitmaps held now, for the memory they take.
    var bitmapPixels: Int {
        texts.values.reduce(0) { sum, record in
            sum + [record.whole, record.detail].reduce(0) { sum, bitmap in
                guard let surface = bitmap.contents as? IOSurface else { return sum }
                return sum + surface.width * surface.height
            }
        }
    }

    /// Whether the text's bitmap on screen shows it as it is now.
    func isDrawn(_ id: Mark.ID) -> Bool {
        guard let record = texts[id] else { return false }
        return record.drawn == record.wantWhole
    }

}

