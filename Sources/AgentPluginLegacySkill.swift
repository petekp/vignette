import Foundation

extension AgentPlugin {
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

    /// `<home>/.agents/skills/vignette`. Codex reads `<home>/.agents/skills` whatever `CODEX_HOME`
    /// says, so an old skill there reaches every Codex folder of that home.
    static func agentsLegacyEntry(home: URL) -> URL {
        legacyEntry(in: home.appendingPathComponent(".agents"))
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
}

/// The agent folders where the plugin has been put in beside the skill from before the plugin. A
/// launch installs the plugin for an old skill only in a folder not listed here, so a linked skill,
/// which stays, gets the plugin once, and the Agents tab's switch turned off holds after that.
struct LegacySkillMigrations {
    let file: URL

    static let standard = Identity.applicationSupportURL.appendingPathComponent("agent-plugin-migrated.json")

    func contains(_ root: URL) -> Bool { roots().contains(Self.key(root)) }

    func record(_ root: URL) {
        var roots = roots()
        guard roots.insert(Self.key(root)).inserted else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: ["roots": roots.sorted()], options: [.prettyPrinted, .sortedKeys])
            try data.write(to: file, options: .atomic)
            Log.write("[plugin] recorded the old skill's move root=\(root.path)")
        } catch {
            Log.write("[plugin] error cannot record the old skill's move root=\(root.path): \(error.localizedDescription)")
        }
    }

    private func roots() -> Set<String> {
        guard let data = try? Data(contentsOf: file) else { return [] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let roots = object["roots"] as? [String] else {
            Log.write("[plugin] error \(file.path) does not parse; read as no folders")
            return []
        }
        return Set(roots)
    }

    private static func key(_ root: URL) -> String { root.resolvingSymlinksInPath().path }
}
