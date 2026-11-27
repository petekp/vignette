import Foundation

extension AppDelegate {
    /// How long a file the `comments` command wrote is kept.
    static let commentsKept: TimeInterval = 24 * 60 * 60

    /// `vignette://comments?file=<card>`: writes the card's pins and comments, and its sends
    /// (`PinCommentsReport`), to a new JSON file in the app's caches, and answers with its path. It
    /// reads the editor's drawing when the card is open there, and changes nothing. A URL has no
    /// authenticated sender (ADR 0006), so the caller does not choose where the file goes.
    func comments(_ request: CommandRequest) {
        let cmd = "comments"
        guard let file = request.files.first else { Commands.error(cmd, .missingFile, "no file given"); return }
        guard request.files.count == 1 else { Commands.error(cmd, .tooManyFiles, "needs 1 file, got \(request.files.count)"); return }
        let key = ScreenshotKey(naming: file, in: watchFolder)
        if let bad = fileError(key.url) { Commands.error(cmd, bad.code, bad.detail); return }
        guard FileManager.default.fileExists(atPath: key.url.path) else { Commands.error(cmd, .missingFile, key.url.path); return }
        let drawing = drawings.current(of: key, style: settings.data.ui.textStyle)
        let records = requests.requests.values.filter { requests.sourceKey(of: $0) == key }
        let object = PinCommentsReport.object(file: key.url, drawing: drawing, records: Array(records))
        let folder = Identity.cachesURL.appendingPathComponent("comments")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            removeOldComments(in: folder)
            let url = folder.appendingPathComponent("\(UUID().uuidString).json")
            try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                .write(to: url, options: .atomic)
            let pins = drawing?.pins.filter { $0.number > 0 } ?? []
            Commands.ok(cmd, "\(key.name) pins=\(pins.count) comments=\(pins.reduce(0) { $0 + $1.comments.count }) file=\(url.path)")
        } catch {
            Commands.error(cmd, .writeFailed, "\(folder.path): \(error.localizedDescription)")
        }
    }

    private func removeOldComments(in folder: URL, now: Date = Date()) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where file.pathExtension == "json" {
            guard let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  now.timeIntervalSince(modified) > Self.commentsKept else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }
}
