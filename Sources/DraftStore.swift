import Foundation

/// Annotations in progress, owned by the app: one JSON file per screenshot under Application
/// Support, keyed by the screenshot's path, with a preview PNG under Caches. The page holds only
/// the draft it is editing, so drafts survive relaunches and a restarted web process.
final class DraftStore {
    let directory: URL
    let previewDirectory: URL
    private(set) var keys: Set<String> = []

    init(directory: URL, previewDirectory: URL) {
        self.directory = directory
        self.previewDirectory = previewDirectory
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try? fm.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
        for file in (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] where file.pathExtension == "json" {
            if let key = Self.read(file)?.key { keys.insert(key) }
        }
    }

    func snapshotURL(for key: String) -> URL { directory.appendingPathComponent(DrawingStore.id(for: key) + ".json") }
    func previewURL(for key: String) -> URL { previewDirectory.appendingPathComponent(DrawingStore.id(for: key) + ".png") }

    /// The stored snapshot as JSON, ready to hand to the page.
    func snapshot(for key: String) -> Data? {
        guard keys.contains(key), let stored = Self.read(snapshotURL(for: key)), stored.key == key else { return nil }
        return try? JSONSerialization.data(withJSONObject: stored.snapshot)
    }

    /// `snapshot` is the JSON object the page sent.
    func save(key: String, snapshot: Any) throws {
        let data = try JSONSerialization.data(withJSONObject: ["key": key, "snapshot": snapshot])
        try data.write(to: snapshotURL(for: key), options: .atomic)
        keys.insert(key)
    }

    func savePreview(key: String, png: Data) throws {
        try png.write(to: previewURL(for: key), options: .atomic)
    }

    func preview(for key: String) -> Data? {
        guard keys.contains(key) else { return nil }
        return try? Data(contentsOf: previewURL(for: key))
    }

    /// Drafts with no preview file. Caches is the system's to clear, and without the preview the
    /// card shows the plain screenshot with no sign of the annotations.
    func keysWithoutPreview() -> [String] {
        keys.filter { !FileManager.default.fileExists(atPath: previewURL(for: $0).path) }.sorted()
    }

    /// Removes the snapshot and preview for each key. Keys without a draft are ignored.
    func forget(_ removed: some Sequence<String>) {
        for key in removed {
            try? FileManager.default.removeItem(at: snapshotURL(for: key))
            try? FileManager.default.removeItem(at: previewURL(for: key))
            keys.remove(key)
        }
    }

    /// Forgets every draft whose key `exists` rejects; returns what was removed.
    @discardableResult
    func sweep(keeping exists: (String) -> Bool) -> [String] {
        let gone = keys.filter { !exists($0) }.sorted()
        forget(gone)
        return gone
    }

    private static func read(_ file: URL) -> (key: String, snapshot: Any)? {
        guard let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = object["key"] as? String, let snapshot = object["snapshot"] else { return nil }
        return (key, snapshot)
    }
}
