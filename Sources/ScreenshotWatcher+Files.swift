import Foundation
import ImageIO

extension ScreenshotWatcher {
    /// True when ImageIO can decode the file. A file still being written fails to decode; ImageIO's
    /// status calls do not tell the two apart (measured: both report complete), so this decodes once.
    /// An image ImageIO can decode, or a recording AVFoundation finds a video track in. The second
    /// also stores the recording's size, so the card made for it next does not read it again.
    static func isComplete(_ url: URL) -> Bool {
        Screenshot.Kind(of: url) == .recording ? Thumbnailer.pointSize(of: url) != nil : isCompleteImage(url)
    }

    static func isCompleteImage(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    }

    /// The formats screencapture can write that the app can show. Outputs of the annotator are not candidates.
    static let candidateExtensions: Set<String> = Set(["png", "jpg", "jpeg", "heic"]).union(Screenshot.recordingExtensions)

    static func isCandidate(_ name: String) -> Bool {
        let lower = name.lowercased()
        guard !lower.hasPrefix("."), !lower.contains(Config.annotatedSuffix) else { return false }
        return candidateExtensions.contains((lower as NSString).pathExtension)
    }

    static func identity(from values: URLResourceValues?) -> FileIdentity? {
        guard let date = values?.contentModificationDate, let file = values?.fileIdentifier,
              let size = values?.fileSize else { return nil }
        return FileIdentity(file: file, size: size, modified: date)
    }

    static func identity(of url: URL) -> FileIdentity? {
        identity(from: try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileIdentifierKey, .fileSizeKey]))
    }

    static func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// The newest `limit` of `files` that `include` takes, newest first, plus the count of `files`.
    /// Ties fall to the name, which carries the capture time for a screenshot. Only the files it
    /// reaches are made keys, since making one costs about 3 µs and a folder can hold thousands.
    static func recent(from files: [String: Date], in folder: URL, limit: Int,
                       include: (ScreenshotKey) -> Bool = { _ in true }) -> (recent: [ScreenshotKey], files: Int) {
        guard limit > 0 else { return ([], files.count) }
        func newer(_ a: (key: String, value: Date), _ b: (key: String, value: Date)) -> Bool {
            a.value != b.value ? a.value > b.value : a.key > b.key
        }
        if limit == 1, let newest = files.max(by: { newer($1, $0) }) {
            let key = ScreenshotKey(folder: folder, name: newest.key)
            if include(key) { return ([key], files.count) }
        }
        var recent: [ScreenshotKey] = []
        for file in files.sorted(by: newer) {
            let key = ScreenshotKey(folder: folder, name: file.key)
            guard include(key) else { continue }
            recent.append(key)
            if recent.count == limit { break }
        }
        return (recent, files.count)
    }
}
