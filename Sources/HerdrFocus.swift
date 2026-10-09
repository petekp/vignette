import Foundation

/// Where herdr's focus is, as `herdr pane list` reports it: the focused pane, its tab, and every
/// agent herdr runs, of any kind. A fact for `DestinationChoice`, which decides what it marks.
struct HerdrFocus: Equatable, Sendable {
    let pane: String
    let tab: String
    let agents: [AgentPane]

    /// One pane running an agent, of any kind, as `herdr pane list` reports it.
    struct AgentPane: Equatable, Sendable {
        let pane: String
        /// The agent session herdr says this pane is running, when it knows one.
        var session: String? = nil
        /// The tab the pane is in.
        var tab: String = ""
    }

    private static let timeout: TimeInterval = 10

    /// Where herdr may be. The app is launched by LaunchServices, so it inherits no shell PATH.
    private static let paths = ["\(NSHomeDirectory())/.local/bin/herdr", "/opt/homebrew/bin/herdr", "/usr/local/bin/herdr"]

    static func binary() -> String? {
        paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Runs `herdr pane list`. Nil without herdr (a test launch has none unless VIGNETTE_HERDR names
    /// one), or when it fails or exits non-zero. It blocks, so it never runs on the main thread.
    static func read(binary: () -> String? = { AgentTools.forSessions("VIGNETTE_HERDR") { HerdrFocus.binary() } },
                     run: (String, [String], TimeInterval) -> (status: Int32, output: String, timedOut: Bool)? = {
                         Subprocess.run($0, $1, timeout: $2)
                     }) -> HerdrFocus? {
        guard let herdr = binary(), let panes = run(herdr, ["pane", "list"], timeout), panes.status == 0 else { return nil }
        return HerdrFocus(paneList: Data(panes.output.utf8))
    }

    /// herdr's focused pane and its tab, from a `herdr pane list` answer, which lists every pane,
    /// agent or not. Nil when no pane is focused or the answer does not parse.
    static func focus(fromPaneList data: Data) -> (pane: String, tab: String)? {
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let panes = ((root?["result"] as? [String: Any])?["panes"] as? [[String: Any]]) ?? []
        guard let pane = panes.first(where: { $0["focused"] as? Bool == true }),
              let id = pane["pane_id"] as? String else { return nil }
        return (id, pane["tab_id"] as? String ?? "")
    }

    /// The agents in a `herdr pane list` answer. A pane running no agent is left out, and an
    /// unparseable answer is no agents.
    static func agents(in data: Data) -> [AgentPane] {
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let panes = ((root?["result"] as? [String: Any])?["panes"] as? [[String: Any]]) ?? []
        return panes.compactMap { pane in
            guard let id = pane["pane_id"] as? String, pane["agent"] is String else { return nil }
            let session = (pane["agent_session"] as? [String: Any])?["value"] as? String
            return AgentPane(pane: id, session: (session?.isEmpty ?? true) ? nil : session,
                         tab: pane["tab_id"] as? String ?? "")
        }
    }
}

extension HerdrFocus {
    /// Nil when no pane is focused or the answer does not parse.
    init?(paneList data: Data) {
        guard let focus = Self.focus(fromPaneList: data) else { return nil }
        self.init(pane: focus.pane, tab: focus.tab, agents: Self.agents(in: data))
    }
}
