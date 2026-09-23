import AppKit

@MainActor
enum Clipboard {
    /// PNG and TIFF, matching what Apple's Copy does, so every paste target accepts it.
    static func copyPNG(_ png: Data) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([imageItem(png: png)])
    }

    /// One pasteboard that works everywhere: a file URL per file (chat apps attach them all),
    /// the paths as text (terminals paste them), and the first file's pixels when it is an image
    /// (single-image targets). A recording goes on as its file only; reading one whole to offer its
    /// bytes would hold the video in memory for a paste target that wants the file anyway.
    static func copyFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        var items: [NSPasteboardItem] = []
        for (i, url) in urls.enumerated() {
            let item: NSPasteboardItem
            if i == 0, Screenshot(url: url).kind == .image, let png = try? Data(contentsOf: url) {
                item = imageItem(png: png)
            } else {
                item = NSPasteboardItem()
            }
            if i == 0 { item.setString(pathsText(urls), forType: .string) }
            item.setString(url.absoluteString, forType: .fileURL)
            items.append(item)
        }
        pb.writeObjects(items)
    }

    /// Done's clipboard, before its rendering exists: the same kinds of data `copyFiles` puts on for
    /// the rendered file. The path goes on as text at once; the PNG, the TIFF and the file's URL are
    /// promised, so a paste that comes before the rendering finishes waits for it. A rendering that
    /// fails takes the whole clipboard back, unless something else was copied since: its path names
    /// a file that never appears.
    static func copyRendering(_ rendering: PendingRendering, file: URL, to pasteboard: NSPasteboard = .general) {
        let item = NSPasteboardItem()
        item.setString(pathsText([file]), forType: .string)
        item.setDataProvider(RenderingProvider(rendering: rendering), forTypes: [.png, .tiff, .fileURL])
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        let written = pasteboard.changeCount
        rendering.whenDone { output in
            guard output.failure != nil, pasteboard.changeCount == written else { return }
            pasteboard.clearContents()
        }
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

    /// The PNG goes on now; the TIFF is a decode and re-encode of the whole image, so it is
    /// rendered only when a paste target asks for it instead of on every copy.
    private static func imageItem(png: Data) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setDataProvider(TIFFProvider(png: png), forTypes: [.tiff])
        return item
    }
}

/// Renders the TIFF of a copied PNG when a paste target asks for it. The item retains it until the
/// pasteboard changes. Immutable, so the callback may arrive on any thread.
private final class TIFFProvider: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
    private let png: Data
    init(png: Data) { self.png = png }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        guard type == .tiff, let tiff = NSImage(data: png)?.tiffRepresentation else { return }
        item.setData(tiff, forType: .tiff)
    }
}

/// Answers a paste of a rendering that may still be running: it waits for it, then gives the PNG,
/// its TIFF, or the written file's URL. A rendering that failed gives nothing. The callback runs on
/// the main thread, which the rendering never needs, so waiting there cannot deadlock, but the app
/// stands still for as long as it waits.
private final class RenderingProvider: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
    private let rendering: PendingRendering
    /// How long a paste waits before it gives up and gets nothing. Done's rendering goes ahead of
    /// any that has not started, so it waits for at most two: one of a 3102 by 6780 image took
    /// 0.6 s, and 1.2 s behind one already running (measured 2026-09-23). This leaves room for a
    /// Mac about four times slower.
    private static let patience: TimeInterval = 5

    init(rendering: PendingRendering) { self.rendering = rendering }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        guard let output = rendering.wait(timeout: Self.patience) else {
            Log.write("[clipboard] error the rendering took longer than \(Int(Self.patience)) s; the paste got nothing")
            return
        }
        switch type {
        case .png: if let png = output.png { item.setData(png, forType: .png) }
        case .tiff: if let tiff = output.png.flatMap({ NSImage(data: $0)?.tiffRepresentation }) { item.setData(tiff, forType: .tiff) }
        case .fileURL: if let file = output.file { item.setString(file.absoluteString, forType: .fileURL) }
        default: break
        }
    }
}
