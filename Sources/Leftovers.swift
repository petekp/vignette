import Foundation

/// What earlier builds left on disk that nothing reads now. Every launch asks; once an item is gone
/// that is one lookup.
enum Leftovers {
    /// The web editor's drafts, which are not carried over, and WebKit's data.
    static var webEditorData: [URL] {
        [Identity.applicationSupportURL.appendingPathComponent("drafts"),
         Identity.cachesURL.appendingPathComponent("drafts"),
         Identity.cachesURL.appendingPathComponent("WebKit"),
         Identity.webKitURL]
    }

    /// The shadow log a live-ink build kept of what it saw at each capture and send.
    static var shadowLog: URL { Identity.applicationSupportURL.appendingPathComponent("send-context.jsonl") }

    static func removeAtLaunch() {
        remove(webEditorData, what: "web editor data")
        remove([shadowLog], what: "shadow log")
    }

    /// Removes each of `items` that is there, with one `[app] removed <what> <path>` line each.
    static func remove(_ items: [URL], what: String) {
        for item in items where FileManager.default.fileExists(atPath: item.path) {
            do {
                try FileManager.default.removeItem(at: item)
                Log.write("[app] removed \(what) \(item.path)")
            } catch {
                Log.write("[app] error write-failed could not remove \(what) \(item.path): \(error.localizedDescription)")
            }
        }
    }
}
