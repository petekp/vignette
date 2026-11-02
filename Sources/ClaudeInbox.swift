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
