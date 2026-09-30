import XCTest

/// Every folder here is temporary, and no agent's tool runs: the hosts get a `run` that records the
/// command and answers as the tool would. The installer takes its folders as parameters so a test
/// never reaches ~/.claude or ~/.codex.
final class AgentPluginTests: XCTestCase {
    private var dir: URL!
    private var template: URL!
    private var skill: URL!
    private var staged: URL!
    private var inboxes: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-plugin-\(UUID().uuidString)")
        template = dir.appendingPathComponent("bundle/agent-plugin")
        skill = dir.appendingPathComponent("bundle/vignette")
        staged = dir.appendingPathComponent("support/agent-plugin")
        inboxes = dir.appendingPathComponent("support/claude-sessions")
        try write("{\"name\": \"vignette\", \"plugins\": []}", to: template.appendingPathComponent(".claude-plugin/marketplace.json"))
        try write("{\"name\": \"vignette\", \"plugins\": []}", to: template.appendingPathComponent(".agents/plugins/marketplace.json"))
        try write("{\"name\": \"vignette\", \"version\": \"6.0.0\"}",
                  to: template.appendingPathComponent("plugins/vignette/.claude-plugin/plugin.json"))
        try write("#!/bin/sh\n", to: template.appendingPathComponent("plugins/vignette/scripts/inbox.sh"))
        try write("---\nname: vignette\n---\n", to: skill.appendingPathComponent("SKILL.md"))
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    private func stage(marketplace: String = "vignette", appName: String = "Vignette") throws -> Bool {
        try AgentPlugin.stage(template: template, skill: skill, into: staged, inboxRoot: inboxes, marketplace: marketplace, appName: appName)
    }

    // MARK: The marketplace

    /// The scripts find the inboxes through `inbox-root`, and the agents find the skill in the plugin,
    /// so a copy missing either installs a plugin that delivers nothing or teaches nothing.
    func testStageWritesTheSkillAndTheInboxPath() throws {
        XCTAssertTrue(try stage())
        let plugin = AgentPlugin.pluginFolder(in: staged)
        XCTAssertEqual(try read(plugin.appendingPathComponent("skills/vignette/SKILL.md")), "---\nname: vignette\n---\n")
        XCTAssertEqual(try read(plugin.appendingPathComponent("scripts/inbox-root")), inboxes.path + "\n")
        XCTAssertEqual(AgentPlugin.version(inMarketplace: staged), "6.0.0")
    }

    /// A fork's marketplace carries its own name, so its plugin id never collides with Vignette's.
    func testStageNamesBothListsForTheMarketplace() throws {
        XCTAssertTrue(try stage(marketplace: "vignette-fork"))
        for list in [".claude-plugin/marketplace.json", ".agents/plugins/marketplace.json"] {
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: staged.appendingPathComponent(list))) as? [String: Any]
            XCTAssertEqual(object?["name"] as? String, "vignette-fork", list)
        }
    }

    /// A test copy's or a fork's skill names its own URL scheme and log; left as written, its agent
    /// would drive the real Vignette.
    func testStageNamesThisCopyOfTheAppInTheSkill() throws {
        try write("---\nname: vignette\n---\nRun `open -g vignette://help` and read `~/Library/Logs/Vignette.log`.\n",
                  to: skill.appendingPathComponent("SKILL.md"))
        XCTAssertTrue(try stage(marketplace: "vignette-e2e", appName: "Vignette E2E"))
        XCTAssertEqual(try read(AgentPlugin.pluginFolder(in: staged).appendingPathComponent("skills/vignette/SKILL.md")),
                       "---\nname: vignette\n---\nRun `open -g vignette-e2e://help` and read `~/Library/Logs/Vignette E2E.log`.\n")
    }

    /// Launch updates the agents only when the copy changed, so an unchanged one has to say so.
    func testStageReportsWhetherAnythingChanged() throws {
        XCTAssertTrue(try stage())
        XCTAssertFalse(try stage())
        try write("---\nname: vignette\n---\nMore.\n", to: skill.appendingPathComponent("SKILL.md"))
        XCTAssertTrue(try stage())
        XCTAssertEqual(try read(AgentPlugin.pluginFolder(in: staged).appendingPathComponent("skills/vignette/SKILL.md")),
                       "---\nname: vignette\n---\nMore.\n")
    }

    // MARK: What the agents' settings say

    func testClaudeCodeSettingsSayWhetherThePluginIsOn() throws {
        let root = dir.appendingPathComponent(".claude")
        XCTAssertFalse(AgentPlugin.isInstalled(in: root, client: .claude, id: "vignette@vignette"))
        try write("{\"enabledPlugins\": {\"vignette@vignette\": true, \"other@x\": false}}", to: root.appendingPathComponent("settings.json"))
        XCTAssertTrue(AgentPlugin.isInstalled(in: root, client: .claude, id: "vignette@vignette"))
        try write("{\"enabledPlugins\": {\"vignette@vignette\": false}}", to: root.appendingPathComponent("settings.json"))
        XCTAssertFalse(AgentPlugin.isInstalled(in: root, client: .claude, id: "vignette@vignette"))
    }

    /// The table has to be the plugin's own: another plugin's `enabled = true` says nothing about it.
    func testCodexConfigSaysWhetherThePluginIsOn() {
        let config = """
        [marketplaces.vignette]
        source = "/x"

        [plugins."other@vignette"]
        enabled = true

        [plugins."vignette@vignette"]
        enabled = true
        """
        XCTAssertTrue(AgentPlugin.codexEnabled(id: "vignette@vignette", config: config))
        XCTAssertFalse(AgentPlugin.codexEnabled(id: "vignette@fork", config: config))
        XCTAssertFalse(AgentPlugin.codexEnabled(id: "vignette@vignette",
                                                config: "[plugins.\"vignette@vignette\"]\nenabled = false\n"))
    }

    // MARK: The skill from before the plugin

    /// A folder is what an older Vignette wrote and goes. A link is the person's own and stays, with
    /// its target untouched.
    func testOldSkillFolderGoesAndALinkStays() throws {
        let claude = dir.appendingPathComponent(".claude"), codex = dir.appendingPathComponent(".codex")
        try write("old", to: AgentPlugin.legacyEntry(in: claude).appendingPathComponent("SKILL.md"))
        try FileManager.default.createDirectory(at: codex.appendingPathComponent("skills"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: AgentPlugin.legacyEntry(in: codex), withDestinationURL: skill)

        XCTAssertEqual(AgentPlugin.removeLegacySkill(at: AgentPlugin.legacyEntry(in: claude), root: claude).outcome, .removed)
        XCTAssertEqual(AgentPlugin.legacySkill(at: AgentPlugin.legacyEntry(in: claude)), .none)
        XCTAssertEqual(AgentPlugin.removeLegacySkill(at: AgentPlugin.legacyEntry(in: codex), root: codex).outcome, .kept)
        XCTAssertEqual(AgentPlugin.legacySkill(at: AgentPlugin.legacyEntry(in: codex)), .link)
        XCTAssertTrue(FileManager.default.fileExists(atPath: skill.appendingPathComponent("SKILL.md").path))
    }

    // MARK: The agents' tools

    private final class Calls: @unchecked Sendable {
        var made: [[String]] = []
        var environments: [[String: String]] = []
    }

    private func host(_ client: AgentClient, root: URL, calls: Calls, tool: String? = "/bin/tool",
                      answer: @escaping ([String]) -> (Int32, String) = { _ in (0, "") }) -> PluginHost {
        var host = PluginHost(client: client, root: root, binary: { tool })
        host.run = { _, arguments, _, environment in
            calls.made.append(arguments)
            calls.environments.append(environment)
            let (status, output) = answer(arguments)
            return (status, output, false)
        }
        return host
    }

    func testInstallRunsEachAgentsCommands() {
        let folder = URL(fileURLWithPath: "/m")
        let claude = Calls(), codex = Calls()
        XCTAssertEqual(host(.claude, root: dir.appendingPathComponent(".claude"), calls: claude).install(from: folder).outcome, .installed)
        XCTAssertEqual(claude.made, [["plugin", "marketplace", "add", "/m"], ["plugin", "install", "vignette@vignette", "--scope", "user"]])
        XCTAssertEqual(host(.codex, root: dir.appendingPathComponent(".codex"), calls: codex).install(from: folder).outcome, .installed)
        XCTAssertEqual(codex.made, [["plugin", "marketplace", "add", "/m"], ["plugin", "add", "vignette@vignette"]])
    }

    /// A config folder other than the default is named to the tool, and HOME is always the app's, so
    /// a test copy on a scratch home never installs into the real one.
    func testTheToolIsToldWhichConfigFolder() {
        let calls = Calls()
        let root = dir.appendingPathComponent("elsewhere/.claude")
        _ = host(.claude, root: root, calls: calls).update()
        XCTAssertEqual(calls.environments.first?["CLAUDE_CONFIG_DIR"], root.path)
        XCTAssertEqual(calls.environments.first?["HOME"], NSHomeDirectory())
    }

    /// A failure stops at that step and carries the tool's own words.
    func testAFailedStepStopsAndSaysWhy() {
        let calls = Calls()
        let result = host(.codex, root: dir, calls: calls) { $0[1] == "marketplace" ? (1, "marketplace is broken") : (0, "") }
            .install(from: dir)
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertTrue(result.detail.contains("marketplace is broken"), result.detail)
        XCTAssertEqual(calls.made.count, 1)
    }

    /// Removing a plugin that is already gone is the state asked for.
    func testRemovingWhatIsGoneSucceeds() {
        let calls = Calls()
        let result = host(.claude, root: dir, calls: calls) { _ in (1, "Plugin \"vignette@vignette\" not found in installed plugins") }.remove()
        XCTAssertEqual(result.outcome, .removed)
        XCTAssertEqual(calls.made.count, 2)
    }

    func testNoToolIsItsOwnOutcome() {
        XCTAssertEqual(host(.claude, root: dir, calls: Calls(), tool: nil).install(from: dir).outcome, .noTool)
    }

    /// The two tools list their plugins in different shapes, and may print a notice first.
    func testInstalledVersionFromEachList() {
        let claude = Data("[{\"id\":\"other@x\",\"version\":\"1\"},{\"id\":\"vignette@vignette\",\"version\":\"6.0.0\"}]".utf8)
        XCTAssertEqual(PluginHost.version(of: "vignette@vignette", inList: claude, client: .claude), "6.0.0")
        let codex = Data("A notice\n{\"installed\":[{\"pluginId\":\"vignette@vignette\",\"version\":\"5.0.0\"}],\"available\":[]}".utf8)
        XCTAssertEqual(PluginHost.version(of: "vignette@vignette", inList: codex, client: .codex), "5.0.0")
        XCTAssertNil(PluginHost.version(of: "vignette@vignette", inList: Data("[]".utf8), client: .claude))
    }

    // MARK: Launch

    /// Launch installs where the old skill is and nowhere else, takes the old folder away once the
    /// plugin is in, and updates an installed plugin older than the app's.
    func testLaunchMigratesTheOldSkillAndUpdatesOlderPlugins() throws {
        let home = dir.appendingPathComponent("home")
        let claude = home.appendingPathComponent(".claude"), codex = home.appendingPathComponent(".codex")
        try write("{\"enabledPlugins\": {\"vignette@vignette\": true}}", to: claude.appendingPathComponent("settings.json"))
        try write("old", to: AgentPlugin.legacyEntry(in: codex).appendingPathComponent("SKILL.md"))
        let calls: [AgentClient: Calls] = [.claude: Calls(), .codex: Calls()]
        let plugins = AgentPlugins(home: home, template: template, skill: skill, marketplaceFolder: staged, inboxRoot: inboxes,
                                   marketplace: "vignette", host: { client, root in
            self.host(client, root: root, calls: calls[client]!) { arguments in
                arguments == ["plugin", "list", "--json"] ? (0, "[{\"id\":\"vignette@vignette\",\"version\":\"5.0.0\"}]") : (0, "")
            }
        })
        let done = expectation(description: "launch")
        plugins.launch { _ in done.fulfill() }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(calls[.claude]!.made, [["plugin", "update", "vignette@vignette"]])
        XCTAssertEqual(calls[.codex]!.made.last, ["plugin", "add", "vignette@vignette"])
        XCTAssertEqual(AgentPlugin.legacySkill(at: AgentPlugin.legacyEntry(in: codex)), .none)
    }

    func testAToolIsFoundUnderTheNewestNodeAndInTheShellsAnswer() throws {
        let home = dir.appendingPathComponent("home")
        for version in ["v9.11.2", "v22.1.0", "v18.20.4"] {
            try FileManager.default.createDirectory(at: home.appendingPathComponent(".nvm/versions/node/\(version)/bin"), withIntermediateDirectories: true)
        }
        let everywhere = AgentTools.path("claude", fixed: [], home: home.path) { $0.contains("/.nvm/") }
        XCTAssertEqual(everywhere, home.appendingPathComponent(".nvm/versions/node/v22.1.0/bin/claude").path, "the newest Node's, not the first listed")
        let shell = "Last login: Tue\nnvm: using node v22\n/Users/x/.nvm/versions/node/v22.1.0/bin/claude\n  /opt/tools/codex  \nclaude not found\n"
        XCTAssertEqual(AgentTools.parse(shell, names: ["claude", "codex"]),
                       ["claude": "/Users/x/.nvm/versions/node/v22.1.0/bin/claude", "codex": "/opt/tools/codex"])
    }

    func testATestLaunchNeverGetsThePersonsOwnAgentFolders() throws {
        let person = dir.appendingPathComponent("person"), scratch = dir.appendingPathComponent("scratch")
        for folder in [person, scratch] {
            for name in [".claude", ".codex"] {
                try FileManager.default.createDirectory(at: folder.appendingPathComponent(name), withIntermediateDirectories: true)
            }
        }
        let own = [person.appendingPathComponent(".claude"), person.appendingPathComponent(".codex")]
        let test = ["VIGNETTE_SETTINGS": "/tmp/x/settings.json"]
        XCTAssertEqual(AgentPlugin.roots(home: person, environment: [:], personHome: person), own, "an ordinary launch")
        XCTAssertEqual(AgentPlugin.roots(home: person, environment: test, personHome: person), [])
        XCTAssertEqual(AgentPlugin.guarded(home: person, environment: test, personHome: person), own)
        XCTAssertEqual(AgentPlugin.roots(home: scratch, environment: test, personHome: person),
                       [scratch.appendingPathComponent(".claude"), scratch.appendingPathComponent(".codex")], "with CFFIXED_USER_HOME")
        XCTAssertEqual(AgentPlugin.roots(home: scratch, environment: test.merging(["CLAUDE_CONFIG_DIR": own[0].path]) { $1 }, personHome: person),
                       [scratch.appendingPathComponent(".codex")], "a config folder named in the environment is still the person's")
    }

    func testLaunchInstallsNothingWhereNothingWas() throws {
        let home = dir.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        let calls = Calls()
        let plugins = AgentPlugins(home: home, template: template, skill: skill, marketplaceFolder: staged, inboxRoot: inboxes,
                                   marketplace: "vignette", host: { client, root in self.host(client, root: root, calls: calls) })
        let done = expectation(description: "launch")
        plugins.launch { _ in done.fulfill() }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(calls.made, [])
    }
}
