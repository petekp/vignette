import AppKit

enum Clipboard {
    /// PNG and TIFF, matching what Apple's Copy does, so every paste target accepts it.
    static func copyPNG(_ png: Data) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([imageItem(png: png)])
    }

    /// One pasteboard that works everywhere: a file URL per image (chat apps attach them all),
    /// the paths as text (terminals paste them), and the first image's pixels (single-image targets).
    static func copyFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        var items: [NSPasteboardItem] = []
        for (i, url) in urls.enumerated() {
            let item: NSPasteboardItem
            if i == 0, let png = try? Data(contentsOf: url) {
                item = imageItem(png: png)
                item.setString(pathsText(urls), forType: .string)
            } else {
                item = NSPasteboardItem()
            }
            item.setString(url.absoluteString, forType: .fileURL)
            items.append(item)
        }
        pb.writeObjects(items)
    }

    static func copyText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// One path per line, single-quoted when it contains spaces so it survives a shell.
    static func pathsText(_ urls: [URL]) -> String {
        urls.map { url in
            let p = url.path
            return p.contains(" ") ? "'" + p.replacingOccurrences(of: "'", with: "'\\''") + "'" : p
        }.joined(separator: "\n")
    }

    private static func imageItem(png: Data) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let tiff = NSImage(data: png)?.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        return item
    }
}
