import Foundation

/// Runs the plugin's installs, updates and removals, one at a time on a queue of their own: each is
/// one or two runs of an agent's command line tool, which take a second or more. Answers come back
/// on the main thread, and every change logs one `[plugin]` line.
///
/// Every folder it reads or changes comes from `home`, `environment` and `personHome`. `init()` gives
/// the app's own; a test names all three.
final class AgentPlugins: @unchecked Sendable {
    private let queue = DispatchQueue(label: "vignette.agent-plugin")
    private let home: URL
    /// Names the agents' folders (`CLAUDE_CONFIG_DIR`, `CODEX_HOME`) and marks a test launch.
    private let environment: [String: String]
    /// The home folder in the user database, whose agent folders a test launch leaves alone.
    private let personHome: URL
    private let template: URL?
    private let skill: URL?
    private let marketplaceFolder: URL
    private let inboxRoot: URL
    private let marketplace: String
    private let appName: String
    private let migrations: LegacySkillMigrations
    /// Makes the host for an agent; tests give one whose tool is a script.
    private let host: (AgentClient, URL) -> PluginHost

    init(home: URL, environment: [String: String], personHome: URL,
         template: URL? = AgentPlugin.bundled, skill: URL? = AgentPlugin.bundledSkill,
         marketplaceFolder: URL = AgentPlugin.marketplaceFolder, inboxRoot: URL = AgentPlugin.inboxRoot,
         marketplace: String = AgentPlugin.marketplace, appName: String = Identity.name,
         migrations: LegacySkillMigrations = LegacySkillMigrations(file: LegacySkillMigrations.standard),
         host: @escaping (AgentClient, URL) -> PluginHost = { PluginHost(client: $0, root: $1) }) {
        self.home = home
        self.environment = environment
        self.personHome = personHome
        self.template = template
        self.skill = skill
        self.marketplaceFolder = marketplaceFolder
        self.inboxRoot = inboxRoot
        self.marketplace = marketplace
        self.appName = appName
        self.migrations = migrations
        self.host = host
    }

    /// The app's: its home folder, which `CFFIXED_USER_HOME` moves, and its own environment.
    convenience init() {
        self.init(home: FileManager.default.homeDirectoryForCurrentUser, environment: ProcessInfo.processInfo.environment,
                  personHome: AgentPlugin.personHome)
    }

    /// The version this copy of the app carries.
    var bundledVersion: String? { template.flatMap { AgentPlugin.version(inMarketplace: $0) } }

    /// Launch. Writes the marketplace, then for each agent on this Mac: installs the plugin where the
    /// skill from before the plugin is (that person chose the skill, and the plugin is what carries it
    /// now), once per agent folder, takes that skill's folders away once the plugin is in, and updates
    /// a plugin older than this app's. Nothing is installed where neither is.
    func launch(completion: @escaping @MainActor @Sendable ([AgentPlugin.Result]) -> Void = { _ in }) {
        queue.async { [self] in
            var results: [AgentPlugin.Result] = []
            let changed: Bool
            do { changed = try stageNow() } catch {
                Log.write("[plugin] error \(error.localizedDescription)")
                return
            }
            let guardedAgents = agentsFolderIsGuarded ? [home.appendingPathComponent(".agents")] : []
            for folder in AgentPlugin.guarded(home: home, environment: environment, personHome: personHome) + guardedAgents {
                Log.write("[plugin] test launch: left \(folder.path) alone; launch with CFFIXED_USER_HOME to test the plugin")
            }
            for root in AgentPlugin.roots(home: home, environment: environment, personHome: personHome) {
                guard let client = AgentPlugin.client(of: root, environment: environment) else { continue }
                let host = host(client, root)
                if !AgentPlugin.isInstalled(in: root, client: client, id: host.id) {
                    guard hasLegacySkill(client, root), !migrations.contains(root) else { continue }
                    let installed = host.install(from: marketplaceFolder)
                    results.append(log(installed, "for the skill already there"))
                    guard installed.outcome == .installed else { continue }
                } else if changed || host.installedVersion() != bundledVersion {
                    results.append(log(host.update()))
                }
                results += retireLegacySkill(client, root)
            }
            let found = results
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(found) } }
        }
    }

    /// The Agents tab's switch, setup's last page and `install-skill`.
    func install(into roots: [URL], completion: @escaping @MainActor @Sendable ([AgentPlugin.Result]) -> Void) {
        queue.async { [self] in
            var results: [AgentPlugin.Result] = []
            do { try stageNow() } catch {
                results = roots.map { AgentPlugin.Result(root: $0, outcome: .failed, detail: error.localizedDescription) }
            }
            if results.isEmpty {
                for root in roots {
                    if let refused = refusal(root) {
                        results.append(log(refused))
                        continue
                    }
                    guard let client = AgentPlugin.client(of: root, environment: environment) else {
                        results.append(log(AgentPlugin.Result(root: root, outcome: .failed, detail: "not a Claude Code or Codex folder")))
                        continue
                    }
                    let result = log(host(client, root).install(from: marketplaceFolder))
                    results.append(result)
                    if result.outcome == .installed { results += retireLegacySkill(client, root) }
                }
            }
            let found = results
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(found) } }
        }
    }

    /// The Agents tab's switch, turned off.
    func remove(from root: URL, completion: @escaping @MainActor @Sendable (AgentPlugin.Result) -> Void) {
        queue.async { [self] in
            let result: AgentPlugin.Result
            if let refused = refusal(root) {
                result = log(refused)
            } else if let client = AgentPlugin.client(of: root, environment: environment) {
                result = log(host(client, root).remove())
            } else {
                result = AgentPlugin.Result(root: root, outcome: .failed, detail: "not a Claude Code or Codex folder")
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(result) } }
        }
    }

    /// A test launch's answer for one of the person's own agent folders, which `install-skill?root=`
    /// can name: the Agents tab and setup only list the folders `roots` gives.
    private func refusal(_ root: URL) -> AgentPlugin.Result? {
        guard AgentPlugin.isGuarded(root, environment: environment, personHome: personHome) else { return nil }
        return AgentPlugin.Result(root: root, outcome: .failed, detail: "a test launch leaves this folder alone; launch with CFFIXED_USER_HOME to test the plugin")
    }

    /// Where the skill from before the plugin may be for an agent: `<root>/skills/vignette`, and for
    /// the Codex folder this launch's environment names, `<home>/.agents/skills/vignette` too. Every
    /// Codex folder of this home reads that one, and the person's Codex is the one their environment
    /// names, so an install into another folder leaves it in place for theirs. A test launch never
    /// gets the person's own.
    func legacyEntries(for client: AgentClient, root: URL) -> [URL] {
        var entries = [AgentPlugin.legacyEntry(in: root)]
        let ownsAgentsSkill = client == .codex && root.resolvingSymlinksInPath().path
            == AgentPlugin.root(of: .codex, home: home, environment: environment).resolvingSymlinksInPath().path
        if ownsAgentsSkill && !agentsFolderIsGuarded { entries.append(AgentPlugin.agentsLegacyEntry(home: home)) }
        return entries
    }

    private var agentsFolderIsGuarded: Bool {
        AgentPlugin.isGuardedAgentsFolder(home: home, environment: environment, personHome: personHome)
    }

    private func hasLegacySkill(_ client: AgentClient, _ root: URL) -> Bool {
        legacyEntries(for: client, root: root).contains { AgentPlugin.legacySkill(at: $0) != .none }
    }

    /// With the plugin in: records the move, then removes the old skill's folders.
    private func retireLegacySkill(_ client: AgentClient, _ root: URL) -> [AgentPlugin.Result] {
        if hasLegacySkill(client, root) { migrations.record(root) }
        return legacyEntries(for: client, root: root).map { log(AgentPlugin.removeLegacySkill(at: $0, root: root)) }
    }

    @discardableResult
    private func stageNow() throws -> Bool {
        guard let template, let skill else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "the plugin is missing from this copy of \(Identity.name)"])
        }
        let changed = try AgentPlugin.stage(template: template, skill: skill, into: marketplaceFolder,
                                            inboxRoot: inboxRoot, marketplace: marketplace, appName: appName, app: Bundle.main.bundleURL)
        if changed { Log.write("[plugin] staged \(marketplaceFolder.path) version=\(bundledVersion ?? "?")") }
        return changed
    }

    private func log(_ result: AgentPlugin.Result, _ reason: String = "") -> AgentPlugin.Result {
        if result.outcome != .absent {
            let words = [result.outcome.rawValue, result.root.path, reason, result.detail].filter { !$0.isEmpty }
            Log.write("[plugin] \(words.joined(separator: " "))")
        }
        return result
    }
}
