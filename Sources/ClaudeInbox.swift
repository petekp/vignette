import Foundation

/// The plugin's inboxes, read from disk: one folder per Claude Code process.
extension ClaudeCodeConnection {
    /// One inbox, as the plugin's scripts wrote it.
    struct Inbox: Equatable {
        let folder: URL
        let pid: Int32
        /// The session the process runs now.
        var session: String?
        /// The folder Claude Code runs in, which is the session's project.
        var cwd: String?
        /// The session's transcript, from the last hook that ran.
        var transcript: String?
        /// The sessions the process ran before this one, which `/clear` and `/resume` leave.
        var past: [String] = []
        /// When the monitor last said it was running.
        var alive: Date?
        /// When the `session` file was created and last written: when the session started in this
        /// process, and a time to order it by when its transcript has no message yet.
        var started: Date?
        var written: Date?
    }

    /// Every inbox under `root`. Nothing is read beyond the few short files in each.
    static func inboxes(in root: URL) -> [Inbox] {
        folders(in: root).compactMap(inbox(at:))
    }

    /// The folders under `root`, each an inbox when it is named by a process id.
    static func folders(in root: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
    }

    /// The inbox in `folder`, or nil when the folder is not named by a process id. A folder that has
    /// gone reads as an inbox with nothing in it.
    static func inbox(at folder: URL) -> Inbox? {
        guard let pid = Int32(folder.lastPathComponent), pid > 0 else { return nil }
        func text(_ name: String) -> String {
            (try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)) ?? ""
        }
        func line(_ name: String) -> String? {
            let line = text(name).trimmingCharacters(in: .whitespacesAndNewlines)
            return line.isEmpty ? nil : line
        }
        let alive = (try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent("alive").path))?[.modificationDate] as? Date
        let session = try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent("session").path)
        return Inbox(folder: folder, pid: pid, session: line("session"), cwd: line("cwd"), transcript: line("transcript"),
                     past: text("past").split(whereSeparator: \.isNewline).map(String.init), alive: alive,
                     started: session?[.creationDate] as? Date, written: session?[.modificationDate] as? Date)
    }
}

// MARK: Writing a request, and watching the monitor take it

extension ClaudeCodeConnection {
    /// How long a line is watched for the monitor's taking it.
    static let handoverLimit: TimeInterval = 3600

    enum Handover: Equatable {
        case waiting
        /// The monitor printed the line and removed it while the session's Claude Code process ran.
        case handed
        /// The line went after the process exited, with the inbox or before it: the session ended first.
        case inboxGone
        case limit

        /// Both ways an inbox is removed, the monitor's as it stops and `liveInboxes`'s, start only once
        /// the process has exited, and delete the line before the folder. So a line gone while the
        /// folder is still there was handed only if the process still runs.
        static func of(lineIsThere: Bool, inboxIsThere: Bool, processIsRunning: Bool, waited: TimeInterval) -> Handover {
            if !lineIsThere { return inboxIsThere && processIsRunning ? .handed : .inboxGone }
            return waited >= ClaudeCodeConnection.handoverLimit ? .limit : .waiting
        }
    }

    /// Only the person's own inboxes are watched: a test names an inbox folder of its own.
    private var watchesHandover: Bool { inboxes == AgentPlugin.inboxRoot }

    /// Writes the request into `inbox`, aside and then renamed in, so the monitor never prints half
    /// of one. It is accepted once it is there: a session in a turn reads it when the turn ends, as a
    /// Codex thread does a queued message. The `ok` line names the file, which `watchHandover` logs.
    func write(_ line: String, into inbox: Inbox, session: String) -> SubmissionOutcome {
        let name = "\(Int64(now().timeIntervalSince1970 * 1000))-\(UUID().uuidString).line"
        let aside = inbox.folder.appendingPathComponent(".\(name).tmp")
        let file = inbox.folder.appendingPathComponent(name)
        do {
            try Data((line + "\n").utf8).write(to: aside)
            try FileManager.default.moveItem(at: aside, to: file)
        } catch {
            try? FileManager.default.removeItem(at: aside)
            return .notSubmitted(code: .sendFailed, detail: "\(inbox.folder.path): \(error.localizedDescription)",
                                 reason: SubmissionOutcome.internalReason)
        }
        watchHandover(of: file, in: inbox)
        return .accepted(detail: "inbox=\(inbox.pid) session=\(session) line=\(name)")
    }

    /// Watches `line`, a file written into `inbox`, until the plugin's monitor takes it, which it does
    /// between turns by printing it and removing the file (inbox.sh). The inbox folder is watched
    /// through the file system, so nothing runs until the folder changes. Logs
    /// `[send] handed line=<file> inbox=<pid> after=<ms>` when the file is gone while the inbox's
    /// process runs, or `[send] not handed line=<file> inbox=<pid> after=<ms> reason=inbox-gone|limit`
    /// when the process exited first or `handoverLimit` passed. The monitor looks every 0.3 s, so a
    /// hand-over is logged up to that late.
    private func watchHandover(of line: URL, in inbox: Inbox) {
        guard watchesHandover else { return }
        let fd = open(inbox.folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let written = now(), now = self.now, isRunning = self.isRunning
        let queue = DispatchQueue(label: "vignette.handover")
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .revoke], queue: queue)
        var finished = false
        func look(timedOut: Bool) {
            guard !finished else { return }
            let waited = now().timeIntervalSince(written)
            let fm = FileManager.default
            let lineIsThere = fm.fileExists(atPath: line.path)
            let state = Handover.of(lineIsThere: lineIsThere, inboxIsThere: fm.fileExists(atPath: inbox.folder.path),
                                    processIsRunning: isRunning(inbox.pid), waited: timedOut ? max(waited, Self.handoverLimit) : waited)
            let named = "line=\(line.lastPathComponent) inbox=\(inbox.pid) after=\(Int(waited * 1000))ms"
            switch state {
            case .waiting: return
            case .handed: Log.write("[send] handed \(named)")
            case .inboxGone: Log.write("[send] not handed \(named) reason=inbox-gone")
            case .limit: Log.write("[send] not handed \(named) reason=limit")
            }
            finished = true
            source.cancel()
        }
        source.setEventHandler { look(timedOut: false) }
        source.setCancelHandler { close(fd) }
        source.resume()
        queue.async { look(timedOut: false) }
        queue.asyncAfter(deadline: .now() + Self.handoverLimit) { look(timedOut: true) }
    }
}
