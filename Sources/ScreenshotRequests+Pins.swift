import Foundation

// MARK: A reply on the person's pins

extension ScreenshotRequests {
    /// The picture a reply's card shows: its own image, or the request's `base.png` when the request
    /// kept one, else the request's `image.png`.
    func picture(of reply: Reply, ownImage: URL) -> URL {
        if reply.hasImage { return ownImage }
        let directory = ReplyProtocol.requestDirectory(root: root, requestID: reply.requestID)
        let base = ReplyProtocol.baseImageURL(in: directory)
        let onPins = reply.answer == nil && FileManager.default.fileExists(atPath: base.path)
        return onPins ? base : directory.appendingPathComponent("image.png")
    }

    /// The person's pins a reply drawn on `base.png` holds, each with the reply's answer to it added.
    /// None for a reply on any other picture.
    func cardPins(of reply: Reply, on picture: URL, at destination: URL) -> [Pin] {
        let directory = ReplyProtocol.requestDirectory(root: root, requestID: reply.requestID)
        guard picture == ReplyProtocol.baseImageURL(in: directory), let pixels = PixelSize(imageAt: destination) else { return [] }
        let agent = requests[reply.requestID]?.address.client.rawValue
        return ReplyProtocol.requestPins(in: directory, image: pixels).map {
            $0.answered(by: reply.comments ?? [], from: agent, at: reply.accepted)
        }
    }
}
