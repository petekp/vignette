import XCTest

extension AgentPluginTests {
    private func launcher(home: URL, calls: @escaping (AgentClient) -> Calls,
                          answer: @escaping ([String]) -> (Int32, String) = { _ in (0, "") }) -> AgentPlugins {
        AgentPlugins(home: home, template: template, skill: skill, marketplaceFolder: staged, inboxRoot: inboxes,
                     marketplace: "vignette", migrations: LegacySkillMigrations(file: dir.appendingPathComponent("support/migrated.json")),
                     host: { client, root in self.host(client, root: root, calls: calls(client), answer: answer) })
    }

    private func launch(_ plugins: AgentPlugins) {
        let done = expectation(description: "launch")
        plugins.launch { _ in done.fulfill() }
        wait(for: [done], timeout: 5)
    }

    private func linkOldSkill(into root: URL) throws {
        let kept = dir.appendingPathComponent("dotfiles/vignette"), link = AgentPlugin.legacyEntry(in: root)
        try write("old", to: kept.appendingPathComponent("SKILL.md"))
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: kept)
    }

    /// Launch installs where the old skill is and nowhere else, takes the old folder away once the
    /// plugin is in, and updates an installed plugin older than the app's.
    func testLaunchMigratesTheOldSkillAndUpdatesOlderPlugins() throws {
        let home = dir.appendingPathComponent("home")
        let claude = home.appendingPathComponent(".claude"), codex = home.appendingPathComponent(".codex")
        try write("{\"enabledPlugins\": {\"vignette@vignette\": true}}", to: claude.appendingPathComponent("settings.json"))
        try write("old", to: AgentPlugin.legacyEntry(in: codex).appendingPathComponent("SKILL.md"))
        let calls: [AgentClient: Calls] = [.claude: Calls(), .codex: Calls()]
        launch(launcher(home: home, calls: { calls[$0]! }) { arguments in
            arguments == ["plugin", "list", "--json"] ? (0, "[{\"id\":\"vignette@vignette\",\"version\":\"5.0.0\"}]") : (0, "")
        })
        XCTAssertEqual(calls[.claude]!.made, [["plugin", "update", "vignette@vignette"]])
        XCTAssertEqual(calls[.codex]!.made.last, ["plugin", "add", "vignette@vignette"])
        XCTAssertEqual(AgentPlugin.legacySkill(at: AgentPlugin.legacyEntry(in: codex)), .none)
    }

    func testLaunchInstallsNothingWhereNothingWas() throws {
        let home = dir.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        let calls = Calls()
        launch(launcher(home: home, calls: { _ in calls }))
        XCTAssertEqual(calls.made, [])
    }

    func testALaunchLeavesThePluginOffAfterTheSwitchTurnedItOffWhereTheOldSkillIsALink() throws {
        let home = dir.appendingPathComponent("home")
        try linkOldSkill(into: home.appendingPathComponent(".claude"))
        let calls = Calls(), plugins = launcher(home: home, calls: { _ in calls })
        launch(plugins)
        XCTAssertEqual(calls.made.last, ["plugin", "install", "vignette@vignette", "--scope", "user"])
        calls.made = []
        launch(plugins)
        XCTAssertEqual(calls.made, [])
        XCTAssertEqual(AgentPlugin.legacySkill(at: AgentPlugin.legacyEntry(in: home.appendingPathComponent(".claude"))), .link)
    }

    func testALaunchThatFindsThePluginBesideALinkedSkillLeavesItOffOnceTheSwitchTurnsItOff() throws {
        let home = dir.appendingPathComponent("home"), claude = home.appendingPathComponent(".claude")
        try linkOldSkill(into: claude)
        try write("{\"enabledPlugins\": {\"vignette@vignette\": true}}", to: claude.appendingPathComponent("settings.json"))
        let calls = Calls(), plugins = launcher(home: home, calls: { _ in calls })
        launch(plugins)
        try write("{}", to: claude.appendingPathComponent("settings.json"))
        calls.made = []
        launch(plugins)
        XCTAssertEqual(calls.made, [])
    }
}
