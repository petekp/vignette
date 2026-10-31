import AppKit
import SwiftUI

/// Marks where a flight's picture is. SwiftUI lays this view out with the flight, the bow's offset
/// and swell included, so AppKit's own conversion finds a press's place on the picture.
struct FlightSpot: NSViewRepresentable {
    let id: UUID
    let picture: CGSize

    func makeNSView(context: Context) -> FlightSpotView { FlightSpotView(id: id, picture: picture) }
    func updateNSView(_ view: FlightSpotView, context: Context) {
        view.picture = picture
    }
}

final class FlightSpotView: NSView {
    let id: UUID
    /// The picture's shape: the flight fills its frame with it, cropping any excess.
    var picture: CGSize

    init(id: UUID, picture: CGSize) {
        self.id = id
        self.picture = picture
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    /// `point` from the top-left of a frame of `size` that a picture of shape `picture` fills,
    /// cropping any excess, as a fraction of the picture from its top-left corner.
    nonisolated static func fraction(of point: CGPoint, in size: CGSize, picture: CGSize) -> CGPoint? {
        guard picture.width > 0, picture.height > 0, size.width > 0, size.height > 0 else { return nil }
        let scale = max(size.width / picture.width, size.height / picture.height)
        let filled = CGSize(width: picture.width * scale, height: picture.height * scale)
        return CGPoint(x: (point.x - (size.width - filled.width) / 2) / filled.width,
                       y: (point.y - (size.height - filled.height) / 2) / filled.height)
    }
}
