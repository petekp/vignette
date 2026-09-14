import AppKit

enum Clipboard {
    /// Puts PNG and TIFF on the pasteboard, matching what Apple's Copy does, so every paste target accepts it.
    static func copyPNG(_ png: Data) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let tiff = NSImage(data: png)?.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        pb.writeObjects([item])
    }
}
