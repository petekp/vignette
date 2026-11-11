import AppKit

/// What the cards in a drag out of the stack drop, one item per card. A card with a drawing drops
/// the drawing, written beside its screenshot as the drag begins, through the item Done's clipboard
/// uses (`Clipboard.renderingItem`). A card without one drops its file. The drawing is the one now,
/// with the card's own as the stored one, since every write and removal reaches it at once
/// (`onChange`) and the drag needs no read from disk.
///
/// A drop target can ask for the PNG as soon as the pointer reaches it, and the answer waits on the
/// main thread, which also moves the drag image. So the PNG is rendered before the drag: `prepare`
/// starts it when a card is hovered or pressed, one card at a time, and the PNGs are kept for the
/// drags to come. The drag then only writes the file.
@MainActor
final class DragItems {
    private struct Key: Equatable {
        let url: URL
        let drawing: Drawing
        let style: TextStyle
        let markStyle: MarkStyle
    }

    private let drawings: Drawings
    /// Every PNG rendered for a drag, newest last, finished or not.
    private var kept: [(key: Key, rendering: PendingRendering)] = []
    /// The rendering `prepare` started that has not finished. Only one runs ahead at a time, so a
    /// pointer moving over many cards renders only the last one it rests on.
    private var ahead: PendingRendering?
    /// The cards `prepare` named last.
    private var wanted: [Card] = []
    /// How many finished PNGs' bytes are kept. A full-screen capture with a drawing is 1 to 10 MB.
    private static let keptBytes = 32 << 20

    init(drawings: Drawings) { self.drawings = drawings }

    /// Renders the drawings of `cards` ahead of a drag, in the order given, unless they are kept
    /// already. An empty list renders nothing more after the one already running.
    func prepare(_ cards: [Card]) {
        wanted = cards
        startAhead()
    }

    /// The items the drag of `cards` carries. Asks nothing that waits.
    func items(for cards: [Card]) -> [NSPasteboardWriting] {
        var drawn = 0, ready = 0
        let items = cards.map { card -> NSPasteboardWriting in
            let shot = card.shot, name = shot.url.lastPathComponent
            guard let key = key(for: card) else { return shot.url as NSURL }
            drawn += 1
            let bytes = rendering(for: key)
            if bytes.isDone { ready += 1 }
            let file = RenderingQueue.shared.file(from: bytes, beside: shot.url)
            file.whenDone { output in
                if let failure = output.failure {
                    Log.write("[drag] error \(failure.code.rawValue) \(name): \(failure); the drop gets no image for it")
                } else if let file = output.file, let png = output.png {
                    Log.write("[drag] rendered files=\(RenderingQueue.paths([file])) \(png.count) bytes")
                }
            }
            return Clipboard.renderingItem(file, loggedAs: "drag")
        }
        Log.write("[drag] cards=\(cards.count) drawings=\(drawn) ready=\(ready)")
        return items
    }

    private func key(for card: Card) -> Key? {
        guard let drawing = drawings.current(of: card.shot.key, stored: { card.marks?.drawing }), !drawing.marks.isEmpty else { return nil }
        let ui = Settings.shared.data.ui
        return Key(url: card.shot.url, drawing: drawing, style: ui.textStyle, markStyle: ui.markStyle)
    }

    /// The kept rendering for `key`, else a new one. A kept rendering that failed is made again, since
    /// a failure can pass: the file can come back from iCloud, or a rename back.
    private func rendering(for key: Key) -> PendingRendering {
        if let index = kept.firstIndex(where: { $0.key == key }) {
            let entry = kept.remove(at: index)
            if !(entry.rendering.isDone && entry.rendering.wait(timeout: 0)?.failure != nil) {
                kept.append(entry)
                return entry.rendering
            }
        }
        // In turn, so Done's promise keeps its bound: a drop comes after the pointer has travelled,
        // which is time a paste does not have.
        let rendering = RenderingQueue.shared.render(key.drawing, imageAt: key.url, output: .bytes, style: key.style, markStyle: key.markStyle)
        kept.append((key, rendering))
        trim()
        return rendering
    }

    private func startAhead() {
        guard ahead?.isDone ?? true else { return }
        ahead = nil
        let keys = wanted.compactMap(key(for:))
        guard let next = keys.first(where: { key in !kept.contains { $0.key == key } }) else { return }
        let rendering = rendering(for: next)
        ahead = rendering
        rendering.whenDone { [weak self] _ in
            self?.trim()
            self?.startAhead()
        }
    }

    /// Lets the oldest finished PNGs go once their bytes pass `keptBytes`.
    private func trim() {
        var total = kept.reduce(0) { $0 + ($1.rendering.wait(timeout: 0)?.png?.count ?? 0) }
        while total > Self.keptBytes, let index = kept.firstIndex(where: { $0.rendering.isDone }) {
            total -= kept[index].rendering.wait(timeout: 0)?.png?.count ?? 0
            kept.remove(at: index)
        }
    }
}
