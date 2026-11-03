import AppKit

extension LiveNoteCards {
    /// How the window looked round a note's ink as it went, which `look(again:)` compares, with the
    /// others on its window, when the session's turn ends.
    struct Before {
        /// The part of the window compared, `region`, in points from the window's top-left corner;
        /// `ink`, the part under the ink, which decides; and the window's size then.
        let picture: CGImage
        let region: CGRect
        let ink: CGRect
        let windowSize: CGSize
        let windowID: CGWindowID
    }

    /// The window round `ink`, a rect in global top-left points, as the packet captured it: the
    /// ink's shapes with `LiveChange.reach` round them, inside the web page when there is one. Nil
    /// for a packet of no one window.
    static func before(_ packet: LivePacket, ink: CGRect) -> Before? {
        guard let window = packet.windowID, !ink.isNull else { return nil }
        let room = packet.page.map { $0.intersection(packet.frame) } ?? packet.frame
        guard let under = LiveChange.region(around: ink, in: room),
              let region = LiveChange.region(around: ink, in: room, margin: LiveChange.reach),
              let picture = LiveChange.crop(packet.capture, frame: packet.frame, to: region) else { return nil }
        let origin = CGVector(dx: -packet.frame.minX, dy: -packet.frame.minY)
        return Before(picture: picture, region: region.offsetBy(dx: origin.dx, dy: origin.dy),
                      ink: under.offsetBy(dx: origin.dx, dy: origin.dy), windowSize: packet.frame.size, windowID: window)
    }
}
