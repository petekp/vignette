import Foundation

extension AgentPlugin {
    // MARK: The app's own folders

    /// The app's home folder, which `CFFIXED_USER_HOME` moves, and its environment, for the app's own
    /// entry points below and `AgentPlugins.init()`. The other functions take them as arguments, and
    /// `scripts/check-agent-folders.py` fails a default for them, so a test names its own.
    static var appHome: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var appEnvironment: [String: String] { ProcessInfo.processInfo.environment }

    /// The app's agent folders, for setup, the Agents tab, the offer and `install-skill`.
    static func appRoots() -> [URL] { roots(home: appHome, environment: appEnvironment, personHome: personHome) }

    static func appStatuses() -> [AgentPluginStatus] { statuses(home: appHome, environment: appEnvironment, personHome: personHome) }

    static func appClient(of root: URL) -> AgentClient? { client(of: root, environment: appEnvironment) }

    /// The app's Claude Code folder: `~/.claude`, or where `CLAUDE_CONFIG_DIR` points. None in a test
    /// launch where that is the person's own, so Send neither lists nor reads their sessions there.
    static let claudeRoot: URL? = claudeRoot(home: appHome, environment: appEnvironment, personHome: personHome)

    static func claudeRoot(home: URL, environment: [String: String], personHome: URL) -> URL? {
        let root = root(of: .claude, home: home, environment: environment)
        guard isPersons(root, environment: environment, personHome: personHome) else { return root }
        Log.write("[plugin] test launch: left \(root.path) alone, so Send lists no Claude Code session from it; launch with CFFIXED_USER_HOME to test Send")
        return nil
    }

    // MARK: The person's own folders in a test launch

    /// Whether this is a test launch and `folder` is one of the person's own agent folders (`.claude`,
    /// `.codex` and `.agents` of `personHome`) or inside one. Both sides are compared by their paths
    /// with every link resolved, and without case, as APFS compares names by default.
    static func isPersons(_ folder: URL, environment: [String: String], personHome: URL) -> Bool {
        guard Launch.isTest(in: environment) else { return false }
        let path = realPath(folder)
        return [".claude", ".codex", ".agents"].contains { name in
            let own = realPath(personHome.appendingPathComponent(name))
            return path == own || path.hasPrefix(own + "/")
        }
    }

    /// Whether this is a test launch on the person's own home folder, one without `CFFIXED_USER_HOME`.
    /// An agent's tool run there gets the person's `HOME`, and Codex reads `$HOME/.agents/skills`
    /// whatever folder it is pointed at, so such a launch runs no tool.
    static func isPersonsHome(_ home: URL, environment: [String: String], personHome: URL) -> Bool {
        Launch.isTest(in: environment) && realPath(home) == realPath(personHome)
    }

    private static func realPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path.lowercased()
    }
}
