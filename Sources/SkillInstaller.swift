import Foundation

/// The agent skill the app ships, and the copies of it under a coding agent's own directory.
/// A root is an agent's directory (`~/.claude`, `~/.codex`); the skill lands in
/// `<root>/skills/<skillName>`. Roots are parameters everywhere, so a test never reaches the
/// real ones.
///
/// Links are resolved all the way, so a skill the user keeps in a repository of theirs and links
/// into both agents is one folder: it is updated where it lives, and each agent that reaches it
/// reads as installed. Installing overwrites whatever is at that folder; removing takes the entry
/// under `skills` away, which for a link is the link and not what it points at.
enum SkillInstaller {
    /// The skill's folder, in the bundle and under `<root>/skills`.
    static let skillName = "vignette"
    /// Where Claude Code and Codex keep their skills. A directory that is not there means that
    /// agent is not installed on this Mac.
    static let agentDirectories = [".claude", ".codex"]

    /// Whether the skill is at `<root>/skills/<skillName>`.
    enum State {
        case none, installed
    }

    /// What one root's install or remove did.
    enum Outcome: String {
        case installed              // written where there was nothing
        case updated                // something was there, and now holds this build's copy
        case unchanged              // already the files the bundle carries
        case kept                   // a launch left a copy of the bundle's version or a later one as it was
        case removed
        case absent                 // nothing to remove
        case failed
    }

    struct Result: Equatable {
        let root: URL
        let path: URL
        let outcome: Outcome
        var detail = ""
    }

    /// The skill folder in the app bundle; nil in a bundle that does not carry it (the test bundle).
    static var bundled: URL? { Bundle.main.url(forResource: skillName, withExtension: nil) }

    /// The entry under `skills` that the skill is reached through: the links on the way there are
    /// resolved, a link at the skill folder itself is not. Removing takes this away.
    static func entry(in root: URL) -> URL {
        root.appendingPathComponent("skills").resolvingSymlinksInPath().appendingPathComponent(skillName)
    }

    /// Where the skill's files live: `entry` with a link at the skill folder followed too, so an
    /// install rewrites the user's own folder in place instead of replacing their link with a copy.
    static func destination(in root: URL) -> URL {
        let entry = entry(in: root)
        return present(entry) ? entry.resolvingSymlinksInPath() : entry
    }

    /// The agent directories this Mac has, in a fixed order. `fileExists` follows a link, so a root
    /// that is itself a link is listed, and the skill is written through it.
    static func roots(home: URL) -> [URL] {
        agentDirectories.map { home.appendingPathComponent($0) }.filter { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    /// The skill is its `SKILL.md`, at the end of whatever links lead there.
    static func state(of root: URL) -> State {
        let skill = destination(in: root).appendingPathComponent("SKILL.md")
        return FileManager.default.fileExists(atPath: skill.path) ? .installed : .none
    }

    /// The agent's name as the user knows it.
    static func agentName(of root: URL) -> String {
        switch root.lastPathComponent {
        case ".claude": return "Claude Code"
        case ".codex": return "Codex"
        default: return root.lastPathComponent
        }
    }

    /// What one root looks like to a reader: the agent's name and whether the skill is there.
    static func status(of root: URL) -> AgentSkillStatus {
        AgentSkillStatus(root: root, name: agentName(of: root), installed: state(of: root) == .installed)
    }

    /// One row per agent directory on this Mac, in the order `roots` lists them.
    static func statuses(home: URL) -> [AgentSkillStatus] {
        roots(home: home).map(status(of:))
    }

    /// Copies `source` to each root's destination, replacing whatever is there. `onlyNewer`, for a
    /// launch, replaces a copy only when `source` is a later version (`version(of:)`) or the copy has
    /// none: an older build must not replace a newer skill, and a copy that is the checkout the skill
    /// is written in differs from the bundle whenever it has edits the build does not.
    static func install(source: URL, into roots: [URL], onlyNewer: Bool = false) -> [Result] {
        each(of: roots, at: destination(in:)) { destination in
            if matches(source: source, installed: destination) { return (.unchanged, "") }
            if onlyNewer, let found = version(of: destination), let wanted = version(of: source), found >= wanted {
                return (.kept, "version \(found); this build's is \(wanted)")
            }
            // Staged beside the destination and moved into place in one step, so a copy that failed
            // part way leaves the old one where it was. Both paths are inside one directory, so the
            // move is a rename.
            let parent = destination.deletingLastPathComponent()
            let staging = parent.appendingPathComponent(".\(skillName)-incoming")
            let replacing = present(destination)
            do {
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: staging)
                try FileManager.default.copyItem(at: source, to: staging)
                if replacing { try FileManager.default.removeItem(at: destination) }
                try FileManager.default.moveItem(at: staging, to: destination)
                return (replacing ? .updated : .installed, "")
            } catch {
                try? FileManager.default.removeItem(at: staging)
                return (.failed, error.localizedDescription)
            }
        }
    }

    /// Takes each root's entry under `skills` away. A link goes and what it points at stays.
    static func remove(from roots: [URL]) -> [Result] {
        each(of: roots, at: entry(in:)) { entry in
            guard present(entry) else { return (.absent, "") }
            do {
                try FileManager.default.removeItem(at: entry)
                return (.removed, "")
            } catch {
                return (.failed, error.localizedDescription)
            }
        }
    }

    /// Runs `work` once for each distinct path the roots lead to, and gives every root that shares
    /// a path the same answer: two agents linked to one folder are one copy on disk, and both rows
    /// say what happened to it.
    private static func each(of roots: [URL], at path: (URL) -> URL,
                             work: (URL) -> (outcome: Outcome, detail: String)) -> [Result] {
        var done: [String: (outcome: Outcome, detail: String)] = [:]
        return roots.map { root in
            let path = path(root)
            let answer = done[path.path] ?? work(path)
            done[path.path] = answer
            return Result(root: root, path: path, outcome: answer.outcome, detail: answer.detail)
        }
    }

    /// True when `installed` holds exactly the files `source` does, byte for byte. Hidden files are
    /// skipped on both sides: macOS leaves .DS_Store behind. A file that will not read matches
    /// nothing, so the copy is written again rather than taken on trust for a file nobody could
    /// compare.
    static func matches(source: URL, installed: URL) -> Bool {
        let wanted = files(under: source), found = files(under: installed)
        guard Set(wanted.keys) == Set(found.keys) else { return false }
        return wanted.allSatisfy { name, data in
            guard let data, let other = found[name] ?? nil else { return false }
            return data == other
        }
    }

    /// The version of the skill in `folder`: `metadata.version` in the frontmatter of its SKILL.md,
    /// where the Agent Skills format keeps one. Nil without one, or when it is not a whole number.
    static func version(of folder: URL) -> Int? {
        guard let text = try? String(contentsOf: folder.appendingPathComponent("SKILL.md"), encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: "\n")
        guard lines.first == "---" else { return nil }
        var inMetadata = false
        for line in lines.dropFirst() {
            if line == "---" { break }
            if !line.hasPrefix(" ") { inMetadata = line == "metadata:"; continue }
            let pair = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if inMetadata, pair.count == 2, pair[0] == "version" { return Int(pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))) }
        }
        return nil
    }

    /// Whether anything is at `url`. `attributesOfItem` is `lstat`, so a link is something there
    /// even when it points at nothing.
    private static func present(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    /// Every regular file under `folder`, keyed by its path inside it. A file that will not read is
    /// there with no contents, which is not the same as an empty file.
    private static func files(under folder: URL) -> [String: Data?] {
        guard let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                                                        options: [.skipsHiddenFiles]) else { return [:] }
        var out: [String: Data?] = [:]
        for case let url as URL in walk {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            out.updateValue(try? Data(contentsOf: url), forKey: String(url.path.dropFirst(folder.path.count)))
        }
        return out
    }
}

/// One agent's line in the Settings window's Agents tab. Each row carries its own root, because
/// each agent's button acts on that agent alone.
struct AgentSkillStatus: Equatable, Identifiable {
    let root: URL
    let name: String
    let installed: Bool

    var status: String { installed ? "Installed" : "Not installed" }
    /// The name its logo has under `Resources/agents`: the agent's directory without the dot.
    var logoKey: String { String(root.lastPathComponent.drop { $0 == "." }) }
    var id: String { name }
}
