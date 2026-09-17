import Foundation
import ImageIO

/// Codes a command can end with: `[<cmd>] error <code> <detail>`. The vocabulary is fixed so an
/// agent can match on it; add a case here before using a new code anywhere.
enum CommandError: String, CaseIterable {
    case unknownCommand = "unknown-command"
    case missingFile = "missing-file"
    case outsideWatchFolder = "outside-watch-folder"
    case notEnoughFiles = "not-enough-files"
    case unreadableImage = "unreadable-image"
    case pageNotReady = "page-not-ready"
    case exportTimeout = "export-timeout"
    case exportFailed = "export-failed"
    case settingsInvalid = "settings-invalid"
    case debugDisabled = "debug-disabled"
    case noAppleOriginal = "no-apple-original"
    case evalFailed = "eval-failed"
    case writeFailed = "write-failed"
    case unsupportedType = "unsupported-type"
}

/// A `shotnote://<name>?file=…&file=…` URL, decoded once.
struct CommandRequest: Equatable {
    let name: String
    let files: [URL]
    /// The decoded query, for `eval`, which carries JavaScript instead of files.
    let query: String?
    /// `tag=` from the query, echoed in the `[state]` line so a script can find its own answer.
    let tag: String?
    /// `annotate` in the query: `add` opens the image in the annotator instead of showing its thumbnail.
    let annotate: Bool
    /// `agent=` from the query: which agent is pushing the image. Empty when the parameter carried
    /// no name, which still marks the card; nil when it was not given at all.
    let agent: String?
}

/// The URL command surface: what exists, how a URL parses, and which files a command may touch.
/// Dispatch lives in AppDelegate. Every command ends with one `[<cmd>] ok …` or `[<cmd>] error …` line.
enum Commands {
    struct Fixed {
        let name: String
        let summary: String
        var needsDebug = false
    }

    /// Commands that are not actions on screenshots. Actions come from `Config.actions`.
    static let fixed: [Fixed] = [
        Fixed(name: "help", summary: "list every command and action in the log"),
        Fixed(name: "state", summary: "dump app and page state to the log"),
        Fixed(name: "last", summary: "show the thumbnail for the newest screenshot"),
        Fixed(name: "add", summary: "copy an image from anywhere into the watch folder and show its thumbnail; &annotate opens it in the annotator instead; &agent=<name> marks the card as an agent's; ignores copyOnCapture and annotateOnCapture"),
        Fixed(name: "recent", summary: "toggle the recent stack"),
        Fixed(name: "dismiss", summary: "close the thumbnail or the stack"),
        Fixed(name: "cancel", summary: "close the annotator without exporting, as Esc would"),
        Fixed(name: "settings", summary: "open the Settings window"),
        Fixed(name: "restore-apple-defaults", summary: "put Apple's screencapture defaults back to what Shotnote first recorded"),
        Fixed(name: "tweaks", summary: "toggle the live UI tweaks panel", needsDebug: true),
        Fixed(name: "show-editor", summary: "open the editor window without an image", needsDebug: true),
        Fixed(name: "eval", summary: "run JavaScript in the editor page: \(Identity.urlScheme)://eval?<code>", needsDebug: true),
    ]

    /// URLComponents decodes each query value once; `open` does not encode again, so nothing else may.
    static func parse(_ url: URL) -> CommandRequest {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let files = items.filter { $0.name == "file" }.compactMap(\.value)
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        let annotate = items.first { $0.name == "annotate" }.map { !["0", "false"].contains($0.value ?? "") } ?? false
        return CommandRequest(name: url.host ?? "", files: files, query: url.query?.removingPercentEncoding,
                              tag: items.first { $0.name == "tag" }?.value, annotate: annotate,
                              agent: Agent.clean(items.first { $0.name == "agent" }.map { $0.value ?? "" }))
    }

    /// Where `add` copies `source` inside `folder`: its own name, or the name with a counter when
    /// that is taken (`x.png`, `x 2.png`, `x 3.png`), so a push never overwrites a screenshot.
    static func destination(for source: URL, in folder: URL, exists: (URL) -> Bool) -> URL {
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var candidate = folder.appendingPathComponent(source.lastPathComponent)
        var n = 2
        while exists(candidate) {
            candidate = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }

    static func isKnown(_ name: String) -> Bool {
        fixed.contains { $0.name == name } || Config.action(id: name) != nil
    }

    static func needsDebug(_ name: String) -> Bool {
        fixed.first { $0.name == name }?.needsDebug ?? false
    }

    /// nil when a command may act on `file`. Both paths are compared after resolving symlinks, so a
    /// folder reached through a link still counts as inside. `debug` lifts the restriction.
    static func policyError(for file: URL, watchFolder: URL, debug: Bool) -> CommandError? {
        if debug { return nil }
        var folder = realPath(watchFolder)
        if !folder.hasSuffix("/") { folder += "/" }
        return realPath(file).hasPrefix(folder) ? nil : .outsideWatchFolder
    }

    /// `realpath` of the longest existing prefix, with the rest appended, so a file that does not
    /// exist yet is still placed by the real location of its folder. (`resolvingSymlinksInPath`
    /// leaves a path alone when any component is missing.)
    static func realPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path
        var rest: [String] = []
        while path != "/" {
            if let real = realpath(path, nil) {
                var resolved = String(cString: real)
                free(real)
                for component in rest.reversed() { resolved = (resolved as NSString).appendingPathComponent(component) }
                return resolved
            }
            rest.append((path as NSString).lastPathComponent)
            path = (path as NSString).deletingLastPathComponent
        }
        return url.standardizedFileURL.path
    }

    /// True when ImageIO can open the file as an image; false for a missing or undecodable file.
    static func isReadableImage(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return CGImageSourceGetType(source) != nil && CGImageSourceGetCount(source) > 0
    }

    /// One line per command, for `shotnote://help`.
    static func helpLines() -> [String] {
        let commands = fixed.map { "\($0.name): \($0.summary)\($0.needsDebug ? " (needs \"debug\": true in settings.json)" : "")" }
        let actions = Config.actions.map { action -> String in
            var line = "\(action.id): \(action.label); \(Identity.urlScheme)://\(action.id)?file=<path>&file=<path>, the newest screenshot when no file is given"
            if action.minimumCount > 1 { line += "; needs \(action.minimumCount) files" }
            return line
        }
        return commands + actions
    }

    static func ok(_ command: String, _ detail: String = "") {
        Log.write(detail.isEmpty ? "[\(command)] ok" : "[\(command)] ok \(detail)")
    }

    static func error(_ command: String, _ code: CommandError, _ detail: String) {
        Log.write("[\(command)] error \(code.rawValue) \(detail)")
    }
}
