import AppKit

/// Larger decodes for the flight to the annotator, by file path. Filled on hover. They are
/// screen-sized, so they are kept only while the stack is up.
@MainActor
final class FlightImages {
    private var images: [ScreenshotKey: NSImage] = [:]
    private var order: [ScreenshotKey] = []
    private let model: StackModel
    private let flights: TransitionLayer
    private let screen: () -> NSScreen
    private let isVisible: () -> Bool

    init(model: StackModel, flights: TransitionLayer, screen: @escaping () -> NSScreen, isVisible: @escaping () -> Bool) {
        self.model = model
        self.flights = flights
        self.screen = screen
        self.isVisible = isVisible
    }

    func removeAll() {
        images.removeAll()
        order.removeAll()
    }

    func rename(from old: ScreenshotKey, to new: ScreenshotKey) {
        if let image = images.removeValue(forKey: old) { images[new] = image }
        order = order.map { $0 == old ? new : $0 }
    }

    /// The best image for the flight: a larger decode if hovering fetched one, else the thumbnail,
    /// upgraded as soon as a larger decode arrives.
    func image(for card: Card) -> NSImage {
        let key = card.shot.key
        if let image = images[key] { return image }
        // The editor's decode is this one. A lone thumbnail's flight home needs it: the stack hid
        // when the annotator opened, which emptied this cache, and the card's own picture is
        // too small to stand in for the editor's first frame.
        let screen = screen()
        if let image = Thumbnailer.cached(at: card.shot.url, maxPixel: Thumbnailer.screenPixels(on: screen), space: screen.colorSpace?.cgColorSpace) {
            return image
        }
        prefetch(card.id)
        return card.image ?? NSImage(size: card.size)
    }

    func prefetch(_ id: UUID?) {
        // Only an image flies into the editor; a recording's decode at this size is wasted, and one
        // that is not downloaded would be downloaded whole.
        guard let id, let card = model.cards.first(where: { $0.id == id }), card.shot.kind == .image else { return }
        let key = card.shot.key
        guard images[key] == nil else { return }
        let screen = screen()
        Thumbnailer.load(at: card.shot.url, maxPixel: Thumbnailer.screenPixels(on: screen), space: screen.colorSpace?.cgColorSpace) { [weak self] image in
            // `isVisible`: a decode that lands after the stack hid must not refill the cache it cleared.
            guard let self, let image, self.isVisible() else { return }
            self.images[key] = image
            self.order.append(key)
            if self.order.count > 4 { self.images[self.order.removeFirst()] = nil }
            self.flights.setImage(id: id, image)
        }
    }
}
