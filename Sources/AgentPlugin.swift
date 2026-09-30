import Foundation

/// The plugin Vignette installs into Claude Code and Codex. It carries the agent skill, and for
/// Claude Code the monitor and hooks that deliver a drawing sent from Vignette into a running
/// session (`ClaudeCodeConnection`, docs/claude-code-without-herdr-2026-09-27.md).
///
/// Each agent installs it with its own command line tool, from a marketplace the app writes into its
/// Application Support folder: the bundled `agent-plugin` folder, the bundled skill, and the path of
/// this app's session inboxes, which the scripts read. A fork writes its own marketplace, named by its
/// URL scheme, with its own inboxes. Claude Code loads a plugin from a folder marketplace in place, so
/// rewriting that folder is what reaches Claude Code's sessions, from their next start or
/// `/reload-plugins`.
enum AgentPlugin {
    static let name = "vignette"
    static var marketplace: String { Identity.urlScheme }
    /// The plugin's id in both agents' commands and settings.
    static var id: String { "\(name)@\(marketplace)" }

    /// The marketplace template in the bundle; nil in a bundle that does not carry it (the test bundle).
    static var bundled: URL? { Bundle.main.url(forResource: "agent-plugin", withExtension: nil) }
    /// The skill, bundled from `skills/vignette`, which stays there in the repo because people link to it.
    static var bundledSkill: URL? { Bundle.main.url(forResource: name, withExtension: nil) }
    /// Where the app writes the marketplace the agents install from.
    static let marketplaceFolder = Identity.applicationSupportURL.appendingPathComponent("agent-plugin")
    /// Where each running Claude Code session's inbox is, one folder per Claude Code process.
    static let inboxRoot = Identity.applicationSupportURL.appendingPathComponent("claude-sessions")

    /// The plugin's folder inside a marketplace.
    static func pluginFolder(in marketplace: URL) -> URL {
        marketplace.appendingPathComponent("plugins").appendingPathComponent(name)
    }

    /// The `version` in the plugin's Claude Code manifest, which the Codex manifest repeats.
    static func version(inMarketplace folder: URL) -> String? {
        let manifest = pluginFolder(in: folder).appendingPathComponent(".claude-plugin/plugin.json")
        guard let data = try? Data(contentsOf: manifest),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["version"] as? String
    }

    // MARK: The marketplace

    /// Writes the marketplace the agents install from: `template` with `skill` in it, the inbox path
    /// the scripts read, and `marketplace` as both lists' name. It is assembled beside `folder` and
    /// swapped in whole, so an agent never reads half of it. Returns whether anything changed.
    @discardableResult
    static func stage(template: URL, skill: URL, into folder: URL, inboxRoot: URL, marketplace: String) throws -> Bool {
        let fileManager = FileManager.default
        let parent = folder.deletingLastPathComponent()
        let staging = parent.appendingPathComponent(".\(folder.lastPathComponent)-incoming")
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        try? fileManager.removeItem(at: staging)
        do {
            try fileManager.copyItem(at: template, to: staging)
            let plugin = pluginFolder(in: staging)
            let skills = plugin.appendingPathComponent("skills")
            try fileManager.createDirectory(at: skills, withIntermediateDirectories: true)
            try fileManager.copyItem(at: skill, to: skills.appendingPathComponent(name))
            try Data((inboxRoot.path + "\n").utf8).write(to: plugin.appendingPathComponent("scripts/inbox-root"))
            for list in [".claude-plugin/marketplace.json", ".agents/plugins/marketplace.json"] {
                try rename(list: staging.appendingPathComponent(list), to: marketplace)
            }
            if SkillFiles.matches(source: staging, installed: folder) {
                try fileManager.removeItem(at: staging)
                return false
            }
            if fileManager.fileExists(atPath: folder.path) {
                _ = try fileManager.replaceItemAt(folder, withItemAt: staging)
            } else {
                try fileManager.moveItem(at: staging, to: folder)
            }
            return true
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    /// Sets a marketplace list's top-level `name`, leaving the rest as written.
    private static func rename(list: URL, to marketplace: String) throws {
        let data = try Data(contentsOf: list)
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        guard object["name"] as? String != marketplace else { return }
        object["name"] = marketplace
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: list)
    }

    // MARK: The agents

    /// The agents' config folders on this Mac that exist, Claude Code's then Codex's: `~/.claude`
    /// and `~/.codex`, or where `CLAUDE_CONFIG_DIR` and `CODEX_HOME` point. A test launch never gets
    /// the person's own (`guarded`), so the launch, setup and the Agents tab cannot reach them.
    static func roots(home: URL, environment: [String: String] = ProcessInfo.processInfo.environment,
                      personHome: URL = AgentPlugin.personHome) -> [URL] {
        existingRoots(home: home, environment: environment).filter { !isGuarded($0, environment: environment, personHome: personHome) }
    }

    /// The folders `roots` leaves out: the person's own agent folders, in a test launch.
    static func guarded(home: URL, environment: [String: String] = ProcessInfo.processInfo.environment,
                        personHome: URL = AgentPlugin.personHome) -> [URL] {
        existingRoots(home: home, environment: environment).filter { isGuarded($0, environment: environment, personHome: personHome) }
    }

    /// The home folder in the user database. `CFFIXED_USER_HOME` moves `NSHomeDirectory` for a test
    /// launch but not this, so it always names the person's own folders.
    static let personHome: URL = {
        guard let entry = getpwuid(getuid()), let path = entry.pointee.pw_dir else { return FileManager.default.homeDirectoryForCurrentUser }
        return URL(fileURLWithPath: String(cString: path))
    }()

    private static func existingRoots(home: URL, environment: [String: String]) -> [URL] {
        AgentClient.allCases.map { root(of: $0, home: home, environment: environment) }.filter { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    /// Whether `folder` is one of the person's own agent folders and this is a test launch, which
    /// `VIGNETTE_SETTINGS` marks. A test copy that must install the plugin moves the home folder
    /// with `CFFIXED_USER_HOME`, or names scratch folders with `CLAUDE_CONFIG_DIR` and `CODEX_HOME`.
    private static func isGuarded(_ folder: URL, environment: [String: String], personHome: URL) -> Bool {
        guard environment["VIGNETTE_SETTINGS"].map({ !$0.isEmpty }) ?? false else { return false }
        let own = AgentClient.allCases.map { root(of: $0, home: personHome, environment: [:]).resolvingSymlinksInPath().path }
        return own.contains(folder.resolvingSymlinksInPath().path)
    }

    static func root(of client: AgentClient, home: URL, environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        switch client {
        case .claude: return environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".claude")
        case .codex: return environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".codex")
        }
    }

    /// Which agent a config folder belongs to: `.claude` and `.codex` by name, and a folder
    /// `CLAUDE_CONFIG_DIR` or `CODEX_HOME` names by that.
    static func client(of root: URL, environment: [String: String] = ProcessInfo.processInfo.environment) -> AgentClient? {
        let path = root.standardizedFileURL.path
        if environment["CLAUDE_CONFIG_DIR"].map({ URL(fileURLWithPath: $0).standardizedFileURL.path }) == path { return .claude }
        if environment["CODEX_HOME"].map({ URL(fileURLWithPath: $0).standardizedFileURL.path }) == path { return .codex }
        switch root.lastPathComponent {
        case ".claude": return .claude
        case ".codex": return .codex
        default: return nil
        }
    }

    /// Whether the agent's own settings have the plugin enabled. These are the files the command line
    /// tools write, read here so a window can ask without running one: Claude Code's `enabledPlugins`
    /// in `settings.json`, and Codex's `[plugins."<id>"]` table in `config.toml`.
    static func isInstalled(in root: URL, client: AgentClient, id: String = AgentPlugin.id) -> Bool {
        switch client {
        case .claude:
            guard let data = try? Data(contentsOf: root.appendingPathComponent("settings.json")),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let enabled = object["enabledPlugins"] as? [String: Any] else { return false }
            return enabled[id] as? Bool == true
        case .codex:
            guard let text = try? String(contentsOf: root.appendingPathComponent("config.toml"), encoding: .utf8) else { return false }
            return codexEnabled(id: id, config: text)
        }
    }

    /// `enabled = true` in the `[plugins."<id>"]` table of a Codex `config.toml`.
    static func codexEnabled(id: String, config: String) -> Bool {
        var inTable = false
        for raw in config.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inTable = line == "[plugins.\"\(id)\"]"
                continue
            }
            guard inTable else { continue }
            let pair = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if pair.count == 2, pair[0] == "enabled" { return pair[1] == "true" }
        }
        return false
    }

    static func status(of root: URL, client: AgentClient) -> AgentPluginStatus {
        AgentPluginStatus(root: root, client: client, installed: isInstalled(in: root, client: client),
                          hasTool: PluginHost(client: client, root: root).binary() != nil)
    }

    /// One row per agent on this Mac, in the order `roots` lists them.
    static func statuses(home: URL) -> [AgentPluginStatus] {
        roots(home: home).compactMap { root in client(of: root).map { status(of: root, client: $0) } }
    }

    // MARK: The skill before the plugin

    /// The skill Vignette installed before the plugin, at `<root>/skills/vignette`. With the plugin
    /// there too, the agent would see the skill twice.
    enum LegacySkill: Equatable {
        case none
        /// A folder, which is what Vignette wrote.
        case folder
        /// A link, which the person made. It is theirs to remove.
        case link
    }

    static func legacySkill(at entry: URL) -> LegacySkill {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: entry.path) else { return .none }
        return attributes[.type] as? FileAttributeType == .typeSymbolicLink ? .link : .folder
    }

    /// `<root>/skills/vignette`.
    static func legacyEntry(in root: URL) -> URL {
        root.appendingPathComponent("skills").appendingPathComponent(name)
    }

    /// Removes an old skill folder. A link stays. `root` is the agent the result is reported for.
    static func removeLegacySkill(at entry: URL, root: URL) -> Result {
        switch legacySkill(at: entry) {
        case .none: return Result(root: root, outcome: .absent)
        case .link: return Result(root: root, outcome: .kept, detail: "\(entry.path) is a link, so it stays")
        case .folder:
            do {
                try FileManager.default.removeItem(at: entry)
                return Result(root: root, outcome: .removed, detail: "old skill \(entry.path)")
            } catch {
                return Result(root: root, outcome: .failed, detail: "old skill \(entry.path): \(error.localizedDescription)")
            }
        }
    }

    // MARK: Outcomes

    enum Outcome: String {
        case installed, updated, unchanged, removed
        case absent                 // nothing to remove
        case kept                   // an old skill left where it was, because it is a link
        case noTool = "no-tool"     // the agent's command line tool is not on this Mac
        case failed
    }

    struct Result: Equatable {
        let root: URL
        let outcome: Outcome
        var detail = ""
    }
}

/// One agent's command line tool, as the installer runs it. Each step is one call, so a failure
/// names the step and the tool's own words.
struct PluginHost {
    let client: AgentClient
    /// The agent's config folder.
    let root: URL
    var binary: () -> String?
    var run: (String, [String], TimeInterval, [String: String]) -> (status: Int32, output: String, timedOut: Bool)? = {
        Subprocess.run($0, $1, timeout: $2, environment: $3)
    }
    var id = AgentPlugin.id
    var marketplace = AgentPlugin.marketplace

    static let timeout: TimeInterval = 60

    init(client: AgentClient, root: URL, binary: (() -> String?)? = nil) {
        self.client = client
        self.root = root
        self.binary = binary ?? { PluginHost.binary(for: client) }
    }

    /// Where Claude Code's tool may be. The app is launched by LaunchServices, so it inherits no shell PATH.
    static let claudePaths = [
        "\(NSHomeDirectory())/.local/bin/claude", "\(NSHomeDirectory())/.claude/local/claude",
        "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
    ]

    static func binary(for client: AgentClient, exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        switch client {
        case .claude: return claudePaths.first(where: exists)
        case .codex: return CodexConnection.binary(exists: exists)
        }
    }

    /// `HOME` is the app's, which `CFFIXED_USER_HOME` moves for a test copy; the tool would read
    /// the real one from the environment. The config folder is passed only when it is not the
    /// default in that home: `CLAUDE_CONFIG_DIR` also moves Claude Code's `.claude.json` into it.
    var environment: [String: String] {
        let home = NSHomeDirectory()
        let defaultRoot = AgentPlugin.root(of: client, home: URL(fileURLWithPath: home), environment: [:])
        guard root.standardizedFileURL.path != defaultRoot.standardizedFileURL.path else { return ["HOME": home] }
        return ["HOME": home, client == .claude ? "CLAUDE_CONFIG_DIR" : "CODEX_HOME": root.path]
    }

    func installArguments(marketplaceFolder: URL) -> [[String]] {
        switch client {
        case .claude: return [["plugin", "marketplace", "add", marketplaceFolder.path], ["plugin", "install", id, "--scope", "user"]]
        case .codex: return [["plugin", "marketplace", "add", marketplaceFolder.path], ["plugin", "add", id]]
        }
    }

    /// Claude Code reads a folder marketplace in place, so an update only records the new version.
    /// Codex copies the plugin into its cache, and adding it again copies the new one.
    var updateArguments: [[String]] {
        switch client {
        case .claude: return [["plugin", "update", id]]
        case .codex: return [["plugin", "add", id]]
        }
    }

    var removeArguments: [[String]] {
        switch client {
        case .claude: return [["plugin", "uninstall", id, "--scope", "user"], ["plugin", "marketplace", "remove", marketplace]]
        case .codex: return [["plugin", "remove", id], ["plugin", "marketplace", "remove", marketplace]]
        }
    }

    func install(from marketplaceFolder: URL) -> AgentPlugin.Result {
        steps(installArguments(marketplaceFolder: marketplaceFolder), done: .installed)
    }

    func update() -> AgentPlugin.Result { steps(updateArguments, done: .updated) }

    /// A second uninstall fails in Claude Code with "not found in installed plugins", which is the
    /// state asked for, so it counts as done. So does a marketplace already gone.
    func remove() -> AgentPlugin.Result {
        steps(removeArguments, done: .removed) { output in
            let lower = output.lowercased()
            return lower.contains("not found") || lower.contains("not installed") || lower.contains("no marketplace")
        }
    }

    /// The installed version, from the tool's own list: Claude Code's `plugin list --json` is an
    /// array of `{id, version}`, Codex's an `installed` array of `{pluginId, version}`.
    func installedVersion() -> String? {
        guard let tool = binary(), let listed = run(tool, ["plugin", "list", "--json"], Self.timeout, environment),
              listed.status == 0 else { return nil }
        return Self.version(of: id, inList: Data(listed.output.utf8), client: client)
    }

    static func version(of id: String, inList data: Data, client: AgentClient) -> String? {
        let text = String(decoding: data, as: UTF8.self)
        // A tool may print a notice before the JSON.
        guard let start = text.firstIndex(where: { $0 == "[" || $0 == "{" }),
              let object = try? JSONSerialization.jsonObject(with: Data(text[start...].utf8)) else { return nil }
        switch client {
        case .claude:
            return (object as? [[String: Any]])?.first { $0["id"] as? String == id }?["version"] as? String
        case .codex:
            let installed = (object as? [String: Any])?["installed"] as? [[String: Any]]
            return installed?.first { $0["pluginId"] as? String == id }?["version"] as? String
        }
    }

    private func steps(_ commands: [[String]], done: AgentPlugin.Outcome,
                       tolerated: (String) -> Bool = { _ in false }) -> AgentPlugin.Result {
        guard let tool = binary() else {
            return AgentPlugin.Result(root: root, outcome: .noTool, detail: "no \(client == .claude ? "claude" : "codex") at \(Self.paths(for: client).joined(separator: " "))")
        }
        for arguments in commands {
            guard let result = run(tool, arguments, Self.timeout, environment) else {
                return AgentPlugin.Result(root: root, outcome: .failed, detail: "\(arguments.prefix(3).joined(separator: " ")) did not run")
            }
            if result.timedOut {
                return AgentPlugin.Result(root: root, outcome: .failed, detail: "\(arguments.prefix(3).joined(separator: " ")) did not answer in \(Int(Self.timeout)) s")
            }
            if result.status != 0 && !tolerated(result.output) {
                return AgentPlugin.Result(root: root, outcome: .failed,
                                          detail: "\(arguments.prefix(3).joined(separator: " ")): \(Subprocess.detail(result.output) ?? "exit \(result.status)")")
            }
        }
        return AgentPlugin.Result(root: root, outcome: done)
    }

    static func paths(for client: AgentClient) -> [String] {
        client == .claude ? claudePaths : CodexConnection.binaryPaths
    }
}

/// One agent's line in the Agents tab and on setup's last page.
struct AgentPluginStatus: Equatable, Identifiable {
    let root: URL
    let client: AgentClient
    let installed: Bool
    /// Whether the agent's command line tool is on this Mac. Without it the plugin can't be installed.
    let hasTool: Bool

    var name: String { client.label }
    /// The name its logo has under `Resources/agents`.
    var logoKey: String { client.rawValue }
    var id: String { root.path }
}

/// Comparing two folders file by file, for the marketplace copy the app writes.
enum SkillFiles {
    /// True when `installed` holds exactly the files `source` does, byte for byte. .DS_Store is
    /// skipped on both sides: macOS leaves it behind. A file that will not read matches
    /// nothing, so the copy is written again rather than taken on trust.
    static func matches(source: URL, installed: URL) -> Bool {
        let wanted = files(under: source), found = files(under: installed)
        guard Set(wanted.keys) == Set(found.keys) else { return false }
        return wanted.allSatisfy { name, data in
            guard let data, let other = found[name] ?? nil else { return false }
            return data == other
        }
    }

    /// Every regular file under `folder`, keyed by its path inside it, the marketplace's lists in
    /// their dot folders included.
    static func files(under folder: URL) -> [String: Data?] {
        guard let walk = FileManager.default.enumerator(atPath: folder.path) else { return [:] }
        var out: [String: Data?] = [:]
        for case let path as String in walk where (path as NSString).lastPathComponent != ".DS_Store" {
            guard walk.fileAttributes?[.type] as? FileAttributeType == .typeRegular else { continue }
            out.updateValue(try? Data(contentsOf: folder.appendingPathComponent(path)), forKey: path)
        }
        return out
    }
}

/// Runs the plugin's installs, updates and removals, one at a time on a queue of their own: each is
/// one or two runs of an agent's command line tool, which take a second or more. Answers come back
/// on the main thread, and every change logs one `[plugin]` line.
final class AgentPlugins: @unchecked Sendable {
    private let queue = DispatchQueue(label: "vignette.agent-plugin")
    private let home: URL
    private let template: URL?
    private let skill: URL?
    private let marketplaceFolder: URL
    private let inboxRoot: URL
    private let marketplace: String
    /// Makes the host for an agent; tests give one whose tool is a script.
    private let host: (AgentClient, URL) -> PluginHost

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         template: URL? = AgentPlugin.bundled, skill: URL? = AgentPlugin.bundledSkill,
         marketplaceFolder: URL = AgentPlugin.marketplaceFolder, inboxRoot: URL = AgentPlugin.inboxRoot,
         marketplace: String = AgentPlugin.marketplace,
         host: @escaping (AgentClient, URL) -> PluginHost = { PluginHost(client: $0, root: $1) }) {
        self.home = home
        self.template = template
        self.skill = skill
        self.marketplaceFolder = marketplaceFolder
        self.inboxRoot = inboxRoot
        self.marketplace = marketplace
        self.host = host
    }

    /// The version this copy of the app carries.
    var bundledVersion: String? { template.flatMap { AgentPlugin.version(inMarketplace: $0) } }

    /// Launch. Writes the marketplace, then for each agent on this Mac: installs the plugin where the
    /// skill from before the plugin is (that person chose the skill, and the plugin is what carries it
    /// now), takes that skill's folders away once the plugin is in, and updates a plugin older than
    /// this app's. Nothing is installed where neither is.
    func launch(completion: @escaping ([AgentPlugin.Result]) -> Void = { _ in }) {
        queue.async { [self] in
            var results: [AgentPlugin.Result] = []
            let changed: Bool
            do { changed = try stageNow() } catch {
                Log.write("[plugin] error \(error.localizedDescription)")
                return
            }
            for root in AgentPlugin.guarded(home: home) {
                Log.write("[plugin] test launch: left \(root.path) alone; launch with CFFIXED_USER_HOME to test the plugin")
            }
            for root in AgentPlugin.roots(home: home) {
                guard let client = AgentPlugin.client(of: root) else { continue }
                let host = host(client, root)
                let legacy = legacyEntries(for: client, root: root)
                if !AgentPlugin.isInstalled(in: root, client: client, id: host.id) {
                    guard legacy.contains(where: { AgentPlugin.legacySkill(at: $0) != .none }) else { continue }
                    let installed = host.install(from: marketplaceFolder)
                    results.append(log(installed, "for the skill already there"))
                    guard installed.outcome == .installed else { continue }
                } else if changed || host.installedVersion() != bundledVersion {
                    results.append(log(host.update()))
                }
                results += legacy.map { log(AgentPlugin.removeLegacySkill(at: $0, root: root)) }
            }
            DispatchQueue.main.async { completion(results) }
        }
    }

    /// The Agents tab's switch, setup's last page and `install-skill`.
    func install(into roots: [URL], completion: @escaping ([AgentPlugin.Result]) -> Void) {
        queue.async { [self] in
            var results: [AgentPlugin.Result] = []
            do { try stageNow() } catch {
                results = roots.map { AgentPlugin.Result(root: $0, outcome: .failed, detail: error.localizedDescription) }
            }
            if results.isEmpty {
                for root in roots {
                    guard let client = AgentPlugin.client(of: root) else {
                        results.append(log(AgentPlugin.Result(root: root, outcome: .failed, detail: "not a Claude Code or Codex folder")))
                        continue
                    }
                    let result = log(host(client, root).install(from: marketplaceFolder))
                    results.append(result)
                    if result.outcome == .installed {
                        results += legacyEntries(for: client, root: root).map { log(AgentPlugin.removeLegacySkill(at: $0, root: root)) }
                    }
                }
            }
            DispatchQueue.main.async { completion(results) }
        }
    }

    /// The Agents tab's switch, turned off.
    func remove(from root: URL, completion: @escaping (AgentPlugin.Result) -> Void) {
        queue.async { [self] in
            let result: AgentPlugin.Result
            if let client = AgentPlugin.client(of: root) {
                result = log(host(client, root).remove())
            } else {
                result = AgentPlugin.Result(root: root, outcome: .failed, detail: "not a Claude Code or Codex folder")
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Where the skill from before the plugin may be for an agent. Codex also reads `~/.agents/skills`.
    func legacyEntries(for client: AgentClient, root: URL) -> [URL] {
        var entries = [AgentPlugin.legacyEntry(in: root)]
        if client == .codex { entries.append(AgentPlugin.legacyEntry(in: home.appendingPathComponent(".agents"))) }
        return entries
    }

    @discardableResult
    private func stageNow() throws -> Bool {
        guard let template, let skill else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "the plugin is missing from this copy of \(Identity.name)"])
        }
        let changed = try AgentPlugin.stage(template: template, skill: skill, into: marketplaceFolder,
                                            inboxRoot: inboxRoot, marketplace: marketplace)
        if changed { Log.write("[plugin] staged \(marketplaceFolder.path) version=\(bundledVersion ?? "?")") }
        return changed
    }

    private func log(_ result: AgentPlugin.Result, _ reason: String = "") -> AgentPlugin.Result {
        if ![.unchanged, .absent].contains(result.outcome) {
            let words = [result.outcome.rawValue, result.root.path, reason, result.detail].filter { !$0.isEmpty }
            Log.write("[plugin] \(words.joined(separator: " "))")
        }
        return result
    }
}
