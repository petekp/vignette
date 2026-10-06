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
    case debugDisabled = "debug-disabled"
    case noAppleOriginal = "no-apple-original"
    case writeFailed = "write-failed"
    case unsupportedType = "unsupported-type"
    case invalidMarks = "invalid-marks"
    case noAgent = "no-agent"
    case sendFailed = "send-failed"
    /// An agent's reply was not taken. The detail names which ReplyProtocol.Refusal it was, and
    /// the receipt the helper reads carries the same word.
    case replyRefused = "reply-refused"
    /// Live ink is turned off in settings.json (`liveInk`).
    case liveInkOff = "live-ink-off"
    /// `points=` is missing, or is not `x,y` pairs of finite numbers joined by `;`.
    case invalidPoints = "invalid-points"
    /// `live-ink-ask` found no ink to ask about, or an ask under way. The detail says which.
    case liveInkNotAsked = "live-ink-not-asked"
    /// `section=` names no section of the `[state]` report.
    case unknownSection = "unknown-section"
}

/// A `vignette://<name>?file=…&file=…` URL, decoded once.
struct CommandRequest: Equatable {
    let name: String
    let files: [URL]
    /// `tag=` from the query, echoed in the `[state]` line so a script can find its own answer.
    let tag: String?
    /// `annotate` in the query: `add` opens the image in the annotator instead of showing its thumbnail.
    let annotate: Bool
    /// `agent=` from the query: which agent is pushing the image. Empty when the parameter carried
    /// no name, which still marks the card; nil when it was not given at all.
    let agent: String?
    /// `session=` from the query, as given: the agent session `add` is pushing from. `Agent.cleanSession`
    /// decides whether it is one.
    var session: String? = nil
    /// `marks=` from the query, as given: a path to a JSON file, or the JSON itself. See `AgentMark.parse`.
    let marks: String?
    /// `root=` from the query: the one directory `install-skill` writes into instead of the agent
    /// directories. Needs `debug`, so a live check points it at a scratch directory.
    let root: URL?
    /// `clear=` from the query: which screenshot request `requests` closes, or `all`.
    let clear: String?
    /// `points=` from the query, as given: a stroke for `live-ink-stroke`. See `Commands.points`.
    var points: String? = nil
    /// `message=` from the query: what `live-ink-ask` asks, as the note's words.
    var message: String? = nil
    /// `section=` from the query: the one section `state` reports beside `app`.
    var section: String? = nil
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
        Fixed(name: "state", summary: "dump app state to the log; &section=<name> reports only that section and app"),
        Fixed(name: "last", summary: "show the thumbnail for the newest screenshot"),
        Fixed(name: "add", summary: "copy an image from anywhere into the watch folder and show its thumbnail; &annotate opens it in the annotator instead; &agent=<name> marks the card as an agent's; &session=<id> names the Claude Code session it came from, which Reply on the card goes back to; &marks=<json file> draws on it, as marks the user can edit; ignores copyOnCapture and annotateOnCapture"),
        Fixed(name: "recent", summary: "toggle the recent stack"),
        Fixed(name: "dismiss", summary: "close the thumbnail or the stack"),
        Fixed(name: "cancel", summary: "close the annotator without copying, as Esc would"),
        Fixed(name: "settings", summary: "open the Settings window"),
        Fixed(name: "install-skill", summary: "install the Vignette plugin, which carries the agent skill, into Claude Code and Codex; &root=<dir> installs into that one config folder, named .claude or .codex (needs \"debug\": true)"),
        Fixed(name: "reply", summary: "an agent's reply to a screenshot request: \(Identity.urlScheme)://reply?file=<attempt envelope>; the bundled reply helper writes that envelope and waits for the receipt Vignette writes back"),
        Fixed(name: "requests", summary: "list the open screenshot requests; &clear=<id or all> stops one taking replies, cancels its unpublished imports, and removes the files Vignette owns"),
        Fixed(name: "restore-apple-defaults", summary: "put Apple's screencapture defaults back to what Vignette first recorded"),
        Fixed(name: "live-ink-clear", summary: "erase every live ink mark from the screen"),
        Fixed(name: "live-ink-ask", summary: "ask about the live ink on the screen, as Return in its note does: &message=<the note's words>; with no new ink it asks again about the ink asked about last. The answer is drawn on the screen and logged as [live-ink] lines. &session=<id> sends the picture to that agent session instead, as picking it in the note's target does", needsDebug: true),
        Fixed(name: "live-ink-stroke", summary: "draw a live ink stroke as if by hand: &points=x,y;x,y;… in global top-left points, the [state] convention; a loop draws an ellipse, another stroke an arrow, a tap erases the mark under it, or makes an answer's loop or arrow the person's", needsDebug: true),
        Fixed(name: "tweaks", summary: "toggle the live UI tweaks panel", needsDebug: true),
        Fixed(name: "intro-lab", summary: "open the Intro Lab, for tuning how setup's window goes into the menu bar icon", needsDebug: true),
    ]

    /// URLComponents decodes each query value once; `open` does not encode again, so nothing else may.
    /// A file in `watchFolder` is spelled as the folder is (`inWatchFolder`).
    static func parse(_ url: URL, watchFolder: URL? = nil) -> CommandRequest {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let files = items.filter { $0.name == "file" }.compactMap(\.value)
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            .map { file in watchFolder.map { inWatchFolder(file, watchFolder: $0) } ?? file }
        let annotate = items.first { $0.name == "annotate" }.map { !["0", "false"].contains($0.value ?? "") } ?? false
        return CommandRequest(name: url.host ?? "", files: files,
                              tag: items.first { $0.name == "tag" }?.value, annotate: annotate,
                              agent: Agent.clean(items.first { $0.name == "agent" }.map { $0.value ?? "" }),
                              session: items.first { $0.name == "session" }?.value,
                              marks: items.first { $0.name == "marks" }?.value,
                              root: items.first { $0.name == "root" }?.value.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) },
                              clear: items.first { $0.name == "clear" }?.value,
                              points: items.first { $0.name == "points" }?.value,
                              message: items.first { $0.name == "message" }?.value,
                              section: items.first { $0.name == "section" }?.value)
    }

    /// `points=` as a stroke: `x,y` pairs joined by `;`. Nil when it holds none, or any pair is not
    /// two finite numbers.
    static func points(_ text: String) -> [CGPoint]? {
        let pairs = text.split(separator: ";", omittingEmptySubsequences: true)
        guard !pairs.isEmpty else { return nil }
        var points: [CGPoint] = []
        for pair in pairs {
            let parts = pair.split(separator: ",", omittingEmptySubsequences: false).map { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 2, let x = parts[0], let y = parts[1], x.isFinite, y.isFinite else { return nil }
            points.append(CGPoint(x: x, y: y))
        }
        return points
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

    /// `file` by the watch folder's own spelling when it is inside the folder, and as given when it
    /// is not. A drawing is keyed by the path, and a capture arrives by the folder's spelling, so
    /// `/tmp/x.png` would reach another drawing than `/private/tmp/x.png`, the same file.
    static func inWatchFolder(_ file: URL, watchFolder: URL) -> URL {
        var folder = realPath(watchFolder)
        if !folder.hasSuffix("/") { folder += "/" }
        let real = realPath(file)
        guard real.hasPrefix(folder) else { return file }
        return watchFolder.standardizedFileURL.appendingPathComponent(String(real.dropFirst(folder.count)))
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

    /// One line per command, for `vignette://help`.
    static func helpLines() -> [String] {
        let commands = fixed.map { "\($0.name): \($0.summary)\($0.needsDebug ? " (needs \"debug\": true in settings.json)" : "")" }
        let actions = Config.actions.map { action -> String in
            var line = "\(action.id): \(action.label); \(Identity.urlScheme)://\(action.id)?file=<path>&file=<path>, the newest file it applies to when no file is given"
            if action.minimumCount > 1 { line += "; needs \(action.minimumCount) files" }
            if !action.kinds.contains(.recording) { line += "; screenshots only" }
            else if !action.kinds.contains(.image) { line += "; recordings only" }
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
