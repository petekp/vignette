import AppKit
import CryptoKit
import Darwin

/// A few days' record of what Vignette could see at each capture and each send, to score ways of
/// choosing the session a drawing goes to against where it went
/// (docs/session-detection-exploration-2026-10-08.md, "The shadow log"). It keeps session ids,
/// folders, bundle ids, port numbers, scores, counts, codes and times, and a digest of the
/// screenshot's file name to join a capture to its send; never a window's title, a page's URL, a
/// file's name or the text in a picture, since an agent's push is named for what it shows.
/// Temporary: it is removed before live ink reaches main.
enum SendContext {
    private static let queue = DispatchQueue(label: "send-context", qos: .utility)
    /// Serial, so one Vision reading and one search of edited files run at a time.
    private static let authorQueue = DispatchQueue(label: "send-context.authors", qos: .utility)
    /// Capture and note lines waiting for, or in, the author search. Only `queue` touches it.
    nonisolated(unsafe) private static var searching = 0
    /// A search takes seconds, and a quit loses every line still waiting for one.
    private static let maxSearching = 2
    @MainActor private static var nextSeq = 0
    /// A test launch writes beside its scratch settings file, never into the person's folder.
    static let url: URL = {
        if let path = ProcessInfo.processInfo.environment["VIGNETTE_SETTINGS"], !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath).deletingLastPathComponent()
                .appendingPathComponent("send-context.jsonl")
        }
        return Identity.applicationSupportURL.appendingPathComponent("send-context.jsonl")
    }()
    /// Days of normal use come to well under this; past it the log stops rather than grows.
    private static let maxBytes = 20_000_000

    struct Window: Sendable {
        let id: CGWindowID
        let pid: pid_t
        /// In global top-left points.
        let frame: CGRect
    }

    // MARK: Events

    /// A capture arrived. The window list is read now, before the person moves on; everything that
    /// waits on another app is read on the queue.
    @MainActor
    static func capture(_ shot: URL) {
        let at = Date()
        guard case .read(let header) = Thumbnailer.lookUp(shot), let pixels = header.pixels else { return }
        let seq = nextSeq
        nextSeq += 1
        let mouse = NSEvent.mouseLocation
        let primary = StateReport.primaryHeight
        let cursor = CGPoint(x: mouse.x, y: primary - mouse.y)
        let scale = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }?.backingScaleFactor ?? 2
        let size = CGSize(width: pixels.width / scale, height: pixels.height / scale)
        let displays = NSScreen.screens.map(\.frame.size)
        let maxPixels = NSScreen.screens.map { max($0.frame.width, $0.frame.height) * $0.backingScaleFactor }.max() ?? 0
        let isRecording = Screenshot(url: shot).kind == .recording
        let windows = onScreenWindows()
        let name = shot.lastPathComponent
        queue.async {
            let (how, window) = captured(size: size, cursor: cursor, windows: windows, displays: displays)
            var record: [String: Any] = ["event": "capture", "file": digest(name), "capture": how]
            let seen = facts(of: window, location: nil)
            record.merge(seen.record) { $1 }
            record.merge(shownFields(capture: how, seen: seen, at: at)) { $1 }
            let listed = seen.sessionIDs
            finish(record, at: at, seq: seq, skip: isRecording ? "recording" : nil) { claude in
                guard let image = decoded(shot, maxPixels: maxPixels) else { return ["authorsWhyNot": "unreadable-image"] }
                return authorFields(lines: recognisedLines(image), listed: listed, claudeRoot: claude, now: Date(),
                                    limits: AuthorLimits())
            }
        }
    }

    /// The editor sent `file`'s drawing. `offered` is where the bar's filled button sent before the
    /// person changed it, and whether that was a Reply to the card's own session.
    @MainActor
    static func sent(file: String, request: String, to destination: AgentDestination, offered: (id: String, reply: Bool)?) {
        let at = Date()
        let seq = nextSeq
        nextSeq += 1
        let to = destination.id, client = destination.client.rawValue
        queue.async {
            var record: [String: Any] = ["event": "send", "file": digest(file), "request": request, "to": to, "client": client]
            if let offered { record["offered"] = offered.id; record["reply"] = offered.reply }
            append(record, at: at, seq: seq)
        }
    }

    /// A live ink note was sent: to `to`, a session id or "responder", where the note started on
    /// `offered`. The packet already holds the window and its page.
    @MainActor
    static func note(_ packet: LivePacket, to: String, offered: String?) {
        let at = Date()
        let seq = nextSeq
        nextSeq += 1
        let window = packet.windowID.flatMap { id -> Window? in
            let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]])?.first
            return (info?[kCGWindowOwnerPID as String] as? pid_t).map { Window(id: id, pid: $0, frame: packet.frame) }
        }
        let location = packet.location
        // The window as captured, without the ink: `picture` has the ink drawn in, and `lines` were
        // read with language correction and a confidence floor, unlike Result 9's.
        let image = packet.capture
        queue.async {
            var record: [String: Any] = ["event": "note", "to": to]
            if let offered { record["offered"] = offered }
            let seen = facts(of: window, location: location ?? "")
            record.merge(seen.record) { $1 }
            record.merge(shownFields(capture: nil, seen: seen, at: at)) { $1 }
            let listed = seen.sessionIDs
            finish(record, at: at, seq: seq, skip: nil) { claude in
                authorFields(lines: recognisedLines(image), listed: listed, claudeRoot: claude, now: Date(), limits: AuthorLimits())
            }
        }
    }

    private static func digest(_ name: String) -> String {
        SHA256.hash(data: Data(name.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Live ink's own reads of a window (`LivePacket.build` and `LivePacket.read`). An author search
    /// waits until none has run for `quiet` seconds: started beside a note's look, it made the look
    /// about 0.75 s slower in the VM.
    enum LiveReads {
        private static let lock = NSLock()
        nonisolated(unsafe) private static var running = 0
        nonisolated(unsafe) private static var lastEnd = Date.distantPast
        static let quiet: TimeInterval = 5
        /// A wait longer than this gives up, so a read that never ends cannot hold every search.
        static let longest: TimeInterval = 120

        static func began() { lock.withLock { running += 1 } }
        static func ended() { lock.withLock { running -= 1; lastEnd = Date() } }

        /// Blocks until live ink has been quiet for `quiet` seconds. Answers the ms it waited.
        static func waitForQuiet() -> Int {
            let started = Date()
            while Date().timeIntervalSince(started) < longest {
                let busy = lock.withLock { running > 0 || Date().timeIntervalSince(lastEnd) < quiet }
                guard busy else { break }
                Thread.sleep(forTimeInterval: 0.25)
            }
            return Int(Date().timeIntervalSince(started) * 1000)
        }
    }

    /// A record on its way between the two queues.
    private struct Pending: @unchecked Sendable { let record: [String: Any] }

    /// Adds what `authors` finds under Claude Code's folder, and how long it took, on `authorQueue`,
    /// then appends the record. Runs on `queue`. A `skip` reason, a missing folder, or `maxSearching`
    /// records already waiting (`busy`) write the record at once with `authorsWhyNot`.
    private static func finish(_ record: [String: Any], at: Date, seq: Int, skip: String?,
                               authors: @escaping @Sendable (URL) -> [String: Any]) {
        let claude = skip == nil ? claudeRoot() : nil
        guard let claude, searching < maxSearching else {
            let why = skip ?? (claude == nil ? "no-claude-folder" : "busy")
            append(record.merging(["authorsWhyNot": why]) { $1 }, at: at, seq: seq)
            return
        }
        searching += 1
        let pending = Pending(record: record)
        authorQueue.async {
            let waited = LiveReads.waitForQuiet()
            let started = Date()
            var found = authors(claude)
            found["authorMs"] = Int(Date().timeIntervalSince(started) * 1000)
            if waited > 0 { found["authorWaitMs"] = waited }
            let done = Pending(record: pending.record.merging(found) { $1 })
            queue.async {
                searching -= 1
                append(done.record, at: at, seq: seq)
            }
        }
    }

    /// One line of the file: the record with its time and its place in this launch's order.
    static func line(_ record: [String: Any], at: Date, seq: Int) -> Data? {
        var record = record
        record["t"] = ISO8601DateFormatter().string(from: at)
        record["seq"] = seq
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return nil }
        return data + Data("\n".utf8)
    }

    /// A capture's or a note's line is written once its text search ends, so it can follow a later
    /// line, and a quit before then loses it. Readers order the lines by `t`, then `seq`.
    private static func append(_ record: [String: Any], at: Date, seq: Int) {
        guard let data = line(record, at: at, seq: seq) else { return }
        let manager = FileManager.default
        if let size = (try? manager.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maxBytes { return }
        if !manager.fileExists(atPath: url.path) { manager.createFile(atPath: url.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    // MARK: Which window

    /// Ordinary windows front to back, without Vignette's own, as `LivePacket.window(under:)` filters them.
    @MainActor
    private static func onScreenWindows() -> [Window] {
        let own = ProcessInfo.processInfo.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { info in
            guard let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != own,
                  let level = info[kCGWindowLayer as String] as? Int, level < Int(CGWindowLevelForKey(.dockWindow)),
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds), frame.width > 40, frame.height > 40 else { return nil }
            return Window(id: id, pid: pid, frame: frame)
        }
    }

    /// A window capture is one window's size, or that plus Apple's shadow; a display capture is the
    /// display's. Anything else is taken as a selection, of the window under the pointer.
    private static func captured(size: CGSize, cursor: CGPoint, windows: [Window], displays: [CGSize]) -> (String, Window?) {
        func near(_ other: CGSize) -> Bool { abs(other.width - size.width) <= 1 && abs(other.height - size.height) <= 1 }
        func whole(_ window: Window) -> Bool {
            if near(window.frame.size) { return true }
            for shadow in CaptureRect.shadows {
                let width: CGFloat = window.frame.width + shadow.left + shadow.right
                let height: CGFloat = window.frame.height + shadow.top + shadow.bottom
                if near(CGSize(width: width, height: height)) { return true }
            }
            return false
        }
        let under = windows.first { $0.frame.contains(cursor) }
        if let under, whole(under) { return ("window", under) }
        if let window = windows.first(where: whole) { return ("window", window) }
        return (displays.contains(where: near) ? "display" : "selection", under)
    }

    // MARK: What the window says

    /// What `facts` wrote, and what it read on the way that the `shown` and author fields use.
    struct Seen {
        /// The record's fields.
        let record: [String: Any]
        /// The sessions listed, in Send's order.
        let sessionIDs: [String]
        /// The sessions with a live Claude Code inbox.
        let live: Set<String>
        /// herdr's answer to the listing's read; nil when the listing did not read it.
        let herdr: HerdrAnswer?
        /// The window's app.
        let pid: pid_t?
        let bundle: String
        /// As written to the record.
        let kind: String
        let launched: Date?
    }

    /// What the window gives about where its content lives, and the live sessions beside it.
    /// `location` is the page or document the note already read, "" for none; nil reads it here.
    private static func facts(of window: Window?, location given: String?) -> Seen {
        let listing = liveSessions()
        let sessions = listing.sessions
        var out: [String: Any] = ["sessions": sessions.map(\.record)]
        guard let window, let app = NSRunningApplication(processIdentifier: window.pid) else {
            out["kind"] = "none"
            return Seen(record: out, sessionIDs: sessions.map(\.id), live: listing.live, herdr: listing.herdr,
                        pid: nil, bundle: "", kind: "none", launched: nil)
        }
        let bundle = app.bundleIdentifier ?? ""
        let kind = kind(of: bundle)
        out["app"] = bundle
        out["kind"] = kind
        if let path = app.bundleURL?.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path,
           FileManager.default.fileExists(atPath: path) { out["electron"] = true }
        if let built = app.executableURL.flatMap({ checkout(ofExecutable: $0.path) }) { out["built"] = built }
        let started = Date()
        let location = given.map { $0.isEmpty ? nil : $0 } ?? LivePacket.page(pid: window.pid, frame: window.frame)?.location
        var page = kind == "browser" ? "unread" : "none"
        if let location, let url = URL(string: location), let scheme = url.scheme?.lowercased() {
            if scheme == "file" {
                page = "file"
                out["folder"] = url.deletingLastPathComponent().path
            } else if scheme == "http" || scheme == "https" {
                let local = ["localhost", "127.0.0.1", "::1", "[::1]", "0.0.0.0"].contains(url.host?.lowercased() ?? "")
                page = local ? "local" : "web"
                if local {
                    let port = url.port ?? (scheme == "https" ? 443 : 80)
                    out["port"] = port
                    if let server = server(listeningOn: port) { out["server"] = server }
                }
            } else {
                page = "other"
            }
        }
        out["page"] = page
        let element = axWindow(pid: window.pid, frame: window.frame)
        if out["folder"] == nil, kind == "finder", let element, let folder = finderFolder(element) { out["folder"] = folder }
        if let title = element.flatMap({ attribute($0, kAXTitleAttribute) as? String }), !title.isEmpty {
            let named = sessions.filter { !$0.name.isEmpty && title.contains($0.name) }.map(\.id)
            let foldered = sessions.filter { session in
                let last = (session.folder as NSString).lastPathComponent
                return !last.isEmpty && title.contains(last)
            }.map(\.id)
            if !named.isEmpty { out["titleNames"] = named }
            if !foldered.isEmpty { out["titleFolders"] = foldered }
            // How often a title gives a reader anything to go on: its own words counted, and each
            // session sharing some with it, by how many. Never the words themselves.
            let titleWords = words(title)
            out["titleWords"] = titleWords.count
            var overlap: [String: Int] = [:]
            for session in sessions {
                let shared = titleWords.intersection(words(session.name + " " + (session.folder as NSString).lastPathComponent)).count
                if shared > 0 { overlap[session.id] = shared }
            }
            if !overlap.isEmpty { out["titleOverlap"] = overlap }
        }
        out["readMs"] = Int(Date().timeIntervalSince(started) * 1000)
        return Seen(record: out, sessionIDs: sessions.map(\.id), live: listing.live, herdr: listing.herdr,
                    pid: window.pid, bundle: bundle, kind: kind, launched: app.launchDate)
    }

    /// The words in a title or a session's name and folder that could tie the two together:
    /// lowercased, three letters or more, a plural's "s" dropped, without the words most titles or
    /// session names carry whatever they are about.
    static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.compactMap { part -> String? in
            var word = String(part)
            if word.count > 4, word.hasSuffix("s"), !word.hasSuffix("ss") { word.removeLast() }
            return word.count >= 3 && !commonWords.contains(word) ? word : nil
        })
    }

    private static let commonWords: Set<String> = [
        "the", "and", "for", "with", "from", "into", "this", "that", "new", "session", "project", "untitled",
        "google", "chrome", "safari", "dia", "figma", "slack", "notion", "linear", "github", "app", "www", "com",
        "http", "https", "html", "index", "home", "page", "tab", "window", "add", "fix", "make", "use", "code",
    ]

    private static func kind(of bundle: String) -> String {
        switch bundle {
        case "com.mitchellh.ghostty", "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable",
             "net.kovidgoyal.kitty", "org.alacritty", "com.github.wez.wezterm": "terminal"
        case "com.openai.codex", "com.anthropic.claudefordesktop": "agent-app"
        case "com.google.Chrome", "company.thebrowser.dia", "company.thebrowser.Browser", "com.apple.Safari",
             "org.mozilla.firefox", "com.brave.Browser", "com.microsoft.edgemac", "com.google.Chrome.canary": "browser"
        case "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed", "com.apple.dt.Xcode": "editor"
        case "com.apple.finder": "finder"
        default: "other"
        }
    }

    /// The checkout an app being built runs from: a folder holding `.derived-data` or `build`, or the
    /// workspace Xcode's own DerivedData records for it.
    static func checkout(ofExecutable path: String) -> String? {
        for marker in ["/.derived-data/", "/build/Build/Products/"] {
            if let range = path.range(of: marker) { return String(path[..<range.lowerBound]) }
        }
        guard let range = path.range(of: "/Library/Developer/Xcode/DerivedData/") else { return nil }
        let rest = path[range.upperBound...]
        guard let project = rest.split(separator: "/").first else { return nil }
        let info = String(path[..<range.upperBound]) + project + "/info.plist"
        let workspace = (NSDictionary(contentsOfFile: info)?["WorkspacePath"] as? String).map { ($0 as NSString).deletingLastPathComponent }
        return workspace
    }

    // MARK: Sessions

    private struct Session {
        let id: String
        let name: String
        let folder: String
        let focus: String?
        let lastUsed: Date?

        var record: [String: Any] {
            var out: [String: Any] = ["id": id, "folder": folder]
            if let focus { out["focus"] = focus }
            if let lastUsed { out["idle"] = Int(Date().timeIntervalSince(lastUsed)) }
            return out
        }
    }

    /// The Claude Code sessions Send would list now, with herdr's focus, and each one's folder; the
    /// sessions with a live inbox; and herdr's answer, when it was read.
    private static func liveSessions() -> (sessions: [Session], live: Set<String>, herdr: HerdrAnswer?) {
        let claude = ClaudeCodeConnection()
        var folders: [String: String] = [:]
        for inbox in claude.liveInboxes() {
            if let session = inbox.session, folders[session] == nil { folders[session] = inbox.cwd ?? "" }
        }
        let listed = claude.destinations()
        let herdr = DestinationChoice.readsHerdr(beside: .claude, listed: listed) ? readHerdr() : nil
        let candidates = DestinationChoice.Candidates(destinations: listed, complete: true, fresh: true, herdr: herdr?.focus)
        let sessions = DestinationChoice.choose(candidates, for: .send(cameFrom: nil)).list.map {
            Session(id: $0.id, name: $0.name, folder: folders[$0.id] ?? "", focus: $0.focus?.rawValue, lastUsed: $0.lastUsed)
        }
        return (sessions, Set(folders.keys), herdr?.answer)
    }

    // MARK: Accessibility

    private static func axWindow(pid: pid_t, frame: CGRect) -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        return windows.first { window in
            guard let position = attribute(window, kAXPositionAttribute), let size = attribute(window, kAXSizeAttribute) else { return false }
            var origin = CGPoint.zero, extent = CGSize.zero
            AXValueGetValue(position as! AXValue, .cgPoint, &origin)
            AXValueGetValue(size as! AXValue, .cgSize, &extent)
            return abs(origin.x - frame.minX) < 2 && abs(origin.y - frame.minY) < 2 && abs(extent.width - frame.width) < 2
        }
    }

    /// Finder's folder, from the files it lists: the parent most of them share. The sidebar's items
    /// each have a parent of their own, so they never outvote the window's content.
    private static func finderFolder(_ window: AXUIElement) -> String? {
        var parents: [String: Int] = [:]
        var queue: [(AXUIElement, Int)] = [(window, 0)], visited = 0
        while !queue.isEmpty, visited < 300 {
            let (element, depth) = queue.removeFirst()
            visited += 1
            if let url = attribute(element, kAXURLAttribute) as? URL, url.isFileURL {
                parents[url.deletingLastPathComponent().path, default: 0] += 1
            }
            guard depth < 10, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { continue }
            queue += children.map { ($0, depth + 1) }
        }
        return parents.filter { $0.value >= 2 }.max { $0.value < $1.value }?.key
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    // MARK: A local page's server

    /// The process listening on `port` among this user's, with the agent session its environment
    /// names and its working folder. An app launched from an agent's shell carries that session in
    /// its environment too, and an app's working folder is `/`, so the session counts only beside a
    /// project folder (`trusted`).
    private static func server(listeningOn port: Int) -> [String: Any]? {
        guard let pid = listener(on: port) else { return nil }
        var out: [String: Any] = [:]
        let folder = workingFolder(pid)
        if let folder { out["folder"] = folder }
        let names = environmentSessions(pid)
        if let session = names.claude { out["session"] = session }
        if let thread = names.codex { out["thread"] = thread }
        out["trusted"] = folder.map { $0 != "/" } ?? false
        return out
    }

    private static func listener(on port: Int) -> pid_t? {
        let count = proc_listpids(UInt32(PROC_UID_ONLY), getuid(), nil, 0)
        guard count > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: Int(count) / MemoryLayout<pid_t>.size + 64)
        let got = pids.withUnsafeMutableBytes { proc_listpids(UInt32(PROC_UID_ONLY), getuid(), $0.baseAddress, Int32($0.count)) }
        let stride = MemoryLayout<proc_fdinfo>.stride
        for pid in pids.prefix(Int(got) / MemoryLayout<pid_t>.size) where pid > 0 {
            let need = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
            guard need > 0 else { continue }
            var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(need) / stride + 32)
            let read = fds.withUnsafeMutableBytes { proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count)) }
            guard read > 0 else { continue }
            for fd in fds.prefix(Int(read) / stride) where fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
                var info = socket_fdinfo()
                let size = Int32(MemoryLayout<socket_fdinfo>.size)
                guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, size) == size,
                      Int(info.psi.soi_kind) == Int(SOCKINFO_TCP) else { continue }
                let tcp = info.psi.soi_proto.pri_tcp
                guard tcp.tcpsi_state == TSI_S_LISTEN else { continue }
                if Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport))) == port { return pid }
            }
        }
        return nil
    }

    private static func workingFolder(_ pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafeBytes(of: info.pvi_cdir.vip_path) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    /// `CLAUDE_CODE_SESSION_ID` and `CODEX_THREAD_ID` from the process's environment, when they are
    /// UUIDs. Nothing else in the environment is kept: it holds tokens.
    private static func environmentSessions(_ pid: pid_t) -> (claude: String?, codex: String?) {
        var argmax: Int32 = 0
        var size = MemoryLayout<Int32>.size
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&mib, 2, &argmax, &size, nil, 0) == 0, argmax > 0 else { return (nil, nil) }
        var buffer = [UInt8](repeating: 0, count: Int(argmax))
        size = buffer.count
        mib = [CTL_KERN, KERN_PROCARGS2, pid]
        guard buffer.withUnsafeMutableBytes({ sysctl(&mib, 3, $0.baseAddress, &size, nil, 0) }) == 0, size > 4 else { return (nil, nil) }
        let argc = Int(buffer.withUnsafeBytes { $0.load(as: Int32.self) })
        var i = 4
        while i < size, buffer[i] != 0 { i += 1 }   // the executable's path
        while i < size, buffer[i] == 0 { i += 1 }   // its padding
        var skipped = 0
        while i < size, skipped < argc {            // the arguments, not read
            while i < size, buffer[i] != 0 { i += 1 }
            i += 1
            skipped += 1
        }
        var claude: String?, codex: String?
        while i < size, buffer[i] != 0 {
            let start = i
            while i < size, buffer[i] != 0 { i += 1 }
            let entry = buffer[start..<i]
            i += 1
            for (name, keep) in [("CLAUDE_CODE_SESSION_ID=", 0), ("CODEX_THREAD_ID=", 1)] where entry.starts(with: Array(name.utf8)) {
                let value = String(decoding: entry.dropFirst(name.utf8.count), as: UTF8.self)
                guard UUID(uuidString: value) != nil else { continue }
                if keep == 0 { claude = value } else { codex = value }
            }
        }
        return (claude, codex)
    }
}
