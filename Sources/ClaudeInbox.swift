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
    /// How soon after the line is written, and how long, the inbox is looked at for the monitor's
    /// taking it: every `handoverPoll` for the first minute, then every `slowHandoverPoll`, until
    /// `handoverLimit`. The monitor looks every 0.3 s, so a hand-over is seen up to the poll late.
    static let handoverPoll: TimeInterval = 0.5
    static let slowHandoverPoll: TimeInterval = 2
    static let handoverLimit: TimeInterval = 3600

    enum Handover: Equatable {
        case waiting
        /// The monitor printed the line and removed it.
        case handed
        /// The inbox went with the line in it: the session ended first.
        case inboxGone
        case limit

        static func of(lineIsThere: Bool, inboxIsThere: Bool, waited: TimeInterval) -> Handover {
            if !lineIsThere { return inboxIsThere ? .handed : .inboxGone }
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
    /// between turns by printing it and removing the file (inbox.sh). Logs
    /// `[send] handed line=<file> inbox=<pid> after=<ms>` when the file is gone, or
    /// `[send] not handed line=<file> inbox=<pid> after=<ms> reason=inbox-gone|limit` when the
    /// session's inbox went first or the limit passed.
    private func watchHandover(of line: URL, in inbox: Inbox) {
        guard watchesHandover else { return }
        let written = now()
        func look() {
            let waited = now().timeIntervalSince(written)
            let fm = FileManager.default
            let named = "line=\(line.lastPathComponent) inbox=\(inbox.pid) after=\(Int(waited * 1000))ms"
            switch Handover.of(lineIsThere: fm.fileExists(atPath: line.path), inboxIsThere: fm.fileExists(atPath: inbox.folder.path), waited: waited) {
            case .waiting: later(waited < 60 ? Self.handoverPoll : Self.slowHandoverPoll, look)
            case .handed: Log.write("[send] handed \(named)")
            case .inboxGone: Log.write("[send] not handed \(named) reason=inbox-gone")
            case .limit: Log.write("[send] not handed \(named) reason=limit")
            }
        }
        later(Self.handoverPoll, look)
    }
}
