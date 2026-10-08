import AppKit
import CryptoKit
import Darwin

/// A few days' record of what Vignette could see at each capture and each send, to score ways of
/// choosing the session a drawing goes to against where it went
/// (docs/session-detection-exploration-2026-10-08.md, "The shadow log"). It keeps session ids,
/// folders, bundle ids and port numbers, and a digest of the screenshot's file name to join a capture
/// to its send; never a window's title, a page's URL or a file's name, since an agent's push is named
/// for what it shows. Temporary: it is removed before live ink reaches main.
enum SendContext {
    private static let queue = DispatchQueue(label: "send-context", qos: .utility)
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
        let mouse = NSEvent.mouseLocation
        let primary = StateReport.primaryHeight
        let cursor = CGPoint(x: mouse.x, y: primary - mouse.y)
        let scale = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }?.backingScaleFactor ?? 2
        let size = CGSize(width: pixels.width / scale, height: pixels.height / scale)
        let displays = NSScreen.screens.map(\.frame.size)
        let windows = onScreenWindows()
        let name = shot.lastPathComponent
        queue.async {
            let (how, window) = captured(size: size, cursor: cursor, windows: windows, displays: displays)
            var record: [String: Any] = ["event": "capture", "file": digest(name), "capture": how]
            record.merge(facts(of: window, location: nil)) { $1 }
            append(record, at: at)
        }
    }

    /// The editor sent `file`'s drawing. `offered` is where the bar's filled button sent before the
    /// person changed it, and whether that was a Reply to the card's own session.
    @MainActor
    static func sent(file: String, request: String, to destination: AgentDestination, offered: (id: String, reply: Bool)?) {
        let at = Date()
        let to = destination.id, client = destination.client.rawValue
        queue.async {
            var record: [String: Any] = ["event": "send", "file": digest(file), "request": request, "to": to, "client": client]
            if let offered { record["offered"] = offered.id; record["reply"] = offered.reply }
            append(record, at: at)
        }
    }

    /// A live ink note was sent: to `to`, a session id or "responder", where the note started on
    /// `offered`. The packet already holds the window and its page.
    @MainActor
    static func note(_ packet: LivePacket, to: String, offered: String?) {
        let at = Date()
        let window = packet.windowID.flatMap { id -> Window? in
            let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]])?.first
            return (info?[kCGWindowOwnerPID as String] as? pid_t).map { Window(id: id, pid: $0, frame: packet.frame) }
        }
        let location = packet.location
        queue.async {
            var record: [String: Any] = ["event": "note", "to": to]
            if let offered { record["offered"] = offered }
            record.merge(facts(of: window, location: location ?? "")) { $1 }
            append(record, at: at)
        }
    }

    private static func digest(_ name: String) -> String {
        SHA256.hash(data: Data(name.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private static func append(_ record: [String: Any], at: Date) {
        var record = record
        record["t"] = ISO8601DateFormatter().string(from: at)
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
        let manager = FileManager.default
        if let size = (try? manager.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maxBytes { return }
        if !manager.fileExists(atPath: url.path) { manager.createFile(atPath: url.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data + Data("\n".utf8))
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

    /// What the window gives about where its content lives, and the live sessions beside it.
    /// `location` is the page or document the note already read, "" for none; nil reads it here.
    private static func facts(of window: Window?, location given: String?) -> [String: Any] {
        let sessions = liveSessions()
        var out: [String: Any] = ["sessions": sessions.map(\.record)]
        guard let window, let app = NSRunningApplication(processIdentifier: window.pid) else {
            out["kind"] = "none"
            return out
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
        }
        out["readMs"] = Int(Date().timeIntervalSince(started) * 1000)
        return out
    }

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

    /// The Claude Code sessions Send would list now, with herdr's focus, and each one's folder.
    private static func liveSessions() -> [Session] {
        let claude = ClaudeCodeConnection()
        var folders: [String: String] = [:]
        for inbox in claude.liveInboxes() {
            if let session = inbox.session, folders[session] == nil { folders[session] = inbox.cwd ?? "" }
        }
        return claude.destinations().map {
            Session(id: $0.id, name: $0.name, folder: folders[$0.id] ?? "", focus: $0.focus?.rawValue, lastUsed: $0.lastUsed)
        }
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
