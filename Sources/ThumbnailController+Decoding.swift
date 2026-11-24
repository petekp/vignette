import AppKit

extension ThumbnailController {
    /// What every card and flight image is decoded in, so no first commit has a colour conversion to do.
    var screenSpace: CGColorSpace? { screen.colorSpace?.cgColorSpace }

    /// Decodes thumbnails for `shots` in the background so the stack opens without waiting. A
    /// screenshot that is not downloaded is downloaded here too, for the editor.
    func warm(_ shots: [Screenshot]) {
        let items = shots.compactMap { shot -> (url: URL, maxPixel: Int)? in
            switch Thumbnailer.lookUp(shot.url) {
            case .read(let header):
                return (shot.url, thumbnailPixels(size: layout.cardSize(for: header.size), pointSize: header.size))
            case .notDownloaded:
                if shot.kind == .image { Thumbnailer.download(shot.url) }
                return (shot.url, cloudThumbnailPixels)
            case .unreadable: return nil
            }
        }
        Thumbnailer.warm(items, space: screenSpace)
    }

    /// Pixels on the longest side for iCloud's thumbnail of a file that is not downloaded: enough for a
    /// card of any shape, since the shape is not known until the thumbnail arrives.
    var cloudThumbnailPixels: Int {
        Int(ceil(max(layout.maxCardWidth, layout.maxCardHeight) * screen.backingScaleFactor * 1.5))
    }

    /// Pixels on the longest side for a decode that covers the card at this screen's scale, with margin.
    func thumbnailPixels(size: NSSize, pointSize: NSSize) -> Int {
        let cover = max(size.width / max(pointSize.width, 1), size.height / max(pointSize.height, 1))
        return Int(ceil(max(pointSize.width, pointSize.height) * cover * screen.backingScaleFactor * 1.5))
    }
}
