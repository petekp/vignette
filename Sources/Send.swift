import Foundation

/// Hands a screenshot to a coding agent that herdr (Pete's terminal multiplexer) is running in a
/// pane. herdr knows which panes hold an agent and what kind each is (`herdr agent list`), and
/// `herdr agent prompt` submits one line to a named pane, so a send needs no window focus and no
/// synthetic keystrokes. The image travels as a path the agent opens with its own file tool
/// (Claude Code's Read, Codex's view_image); a path the agent is not already allowed to read makes
/// it ask its user for permission first, which herdr then reports as `blocked`.
enum Send {
    /// One agent herdr is running, as `herdr agent list` reports it.
    struct Target: Equatable {
        /// The name herdr answers to: the agent's name, or its pane id when it has none.
        let id: String
        let pane: String
        /// claude, codex, cursor, … whichever herdr recognized.
        let kind: String
        let cwd: String
        /// idle, working, blocked, or unknown.
        let status: String
        /// The pane the herdr UI last focused; the default target.
        let focused: Bool
    }

    /// Where herdr may be. The app is launched by LaunchServices, so it inherits no shell PATH.
    static let binaryPaths = ["\(NSHomeDirectory())/.local/bin/herdr", "/opt/homebrew/bin/herdr", "/usr/local/bin/herdr"]

    static func binary(exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        binaryPaths.first(where: exists)
    }

    /// The agents in a `herdr agent list` answer. An unparseable answer is no agents.
    static func targets(fromAgentList data: Data) -> [Target] {
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let agents = ((root?["result"] as? [String: Any])?["agents"] as? [[String: Any]]) ?? []
        return agents.compactMap { agent in
            guard let pane = agent["pane_id"] as? String, let kind = agent["agent"] as? String else { return nil }
            let name = (agent["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return Target(id: name ?? pane, pane: pane, kind: kind, cwd: agent["cwd"] as? String ?? "",
                          status: agent["agent_status"] as? String ?? "unknown", focused: agent["focused"] as? Bool ?? false)
        }
    }

    /// The target `to` names, by agent name or pane id; without `to`, the focused pane's agent.
    static func choose(_ targets: [Target], to: String?) -> Target? {
        guard let to, !to.isEmpty else { return targets.first { $0.focused } }
        return targets.first { $0.id == to || $0.pane == to }
    }

    /// The line the agent receives. One line: herdr submits it with Return, so an embedded newline
    /// would send half a message. The path is quoted because screenshot names carry spaces.
    static func message(text: String?, file: URL) -> String {
        let words = (text ?? "").components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return "\(words.isEmpty ? "Screenshot:" : words) \"\(file.path)\""
    }

    /// herdr's own words as one short log detail; nil when it said nothing. Its errors are JSON on
    /// stderr, which the log line carries as it is.
    static func detail(_ output: String?) -> String? {
        let text = (output ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(200))
    }

    /// Runs herdr and returns its status and combined output, or nil when it cannot start. Blocks
    /// on a socket round trip, so callers keep it off the main thread.
    static func run(_ binary: String, _ arguments: [String], timeout: TimeInterval = 15) -> (status: Int32, output: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return nil }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
