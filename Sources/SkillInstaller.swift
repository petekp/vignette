import Foundation

/// The agent skill the app ships, and the copies of it under a coding agent's own directory.
/// A root is an agent's directory (`~/.claude`, `~/.codex`); the skill lands in
/// `<root>/skills/<skillName>`. Roots are parameters everywhere, so a test never reaches the
/// real ones.
///
/// The installer only ever touches a copy it made. It writes a marker beside the skill naming the
/// build that wrote it, and refuses anything at that path without one: a directory, a link, or a
/// file someone put there by hand is left exactly as it is.
enum SkillInstaller {
    /// The skill's folder, in the bundle and under `<root>/skills`.
    static let skillName = "vignette"
    /// Names the build that wrote this copy. A directory without it is not ours.
    static let markerName = ".vignette-skill.json"
    /// Where Claude Code and Codex keep their skills. A directory that is not there means that
    /// agent is not installed on this Mac.
    static let agentDirectories = [".claude", ".codex"]

    /// What the marker holds: which build wrote the copy.
    struct Stamp: Codable, Equatable {
        var app: String
        var version: String
        var build: String

        static var current: Stamp {
            Stamp(app: Identity.name, version: BuildInfo.current.version, build: BuildInfo.current.build)
        }
    }

    /// What is at `<root>/skills/<skillName>` right now.
    enum State: String {
        case none        // nothing there
        case ours        // this installer wrote it
        case foreign     // something else: never written, never removed
    }

    /// What one root's install or remove did.
    enum Outcome: String {
        case installed              // written where there was nothing
        case updated                // our copy, rewritten for this build
        case unchanged              // our copy, already this build
        case removed
        case absent                 // nothing of ours to remove
        case notOurs = "not-ours"
        case linkedRoot = "linked-root"   // the root or its `skills` is a link: the copy would land elsewhere
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

    static func folder(in root: URL) -> URL {
        root.appendingPathComponent("skills").appendingPathComponent(skillName)
    }

    /// The agent directories this Mac has, in a fixed order. `fileExists` follows a link, so a root
    /// that is itself a link is listed; `linkedPath` is what refuses to write through it.
    static func roots(home: URL) -> [URL] {
        agentDirectories.map { home.appendingPathComponent($0) }.filter { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    /// The link the skill would be written through, or nil when there is none: the root itself or
    /// its `skills`. Writing through one puts the skill somewhere the user did not name — on this
    /// Mac one agent's `skills` links into a git repository of theirs — so the installer neither
    /// writes nor removes through a linked root. `attributesOfItem` is `lstat`, so it reports the
    /// link rather than what it points at; `fileExists` would follow it.
    static func linkedPath(in root: URL) -> URL? {
        [root, root.appendingPathComponent("skills")].first(where: isLink)
    }

    private static func isLink(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return false }
        return attributes[.type] as? FileAttributeType == .typeSymbolicLink
    }

    /// Reads the marker. `attributesOfItem` does not follow links, so a symlink at the skill's
    /// path is foreign rather than whatever it points at.
    static func state(of root: URL) -> (state: State, stamp: Stamp?) {
        let folder = folder(in: root)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: folder.path) else { return (.none, nil) }
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { return (.foreign, nil) }
        guard let raw = try? Data(contentsOf: folder.appendingPathComponent(markerName)),
              let stamp = try? JSONDecoder().decode(Stamp.self, from: raw) else { return (.foreign, nil) }
        return (.ours, stamp)
    }

    /// Copies `source` into each root, replacing our own older copy and refusing anyone else's.
    static func install(source: URL, into roots: [URL], stamp: Stamp) -> [Result] {
        roots.map { root in
            let folder = folder(in: root)
            if let linked = linkedPath(in: root) { return linkedRootResult(root, linked: linked) }
            let found = state(of: root)
            switch found.state {
            case .foreign:
                return Result(root: root, path: folder, outcome: .notOurs, detail: "not written by \(Identity.name)")
            case .ours where found.stamp == stamp && matches(source: source, installed: folder):
                return Result(root: root, path: folder, outcome: .unchanged)
            case .ours, .none:
                // Staged beside the folder, marker included, and moved into place in one step. A
                // copy that failed part way would otherwise leave a folder without its marker, which
                // reads as foreign: neither install nor remove would touch it again.
                let skills = folder.deletingLastPathComponent()
                let staging = skills.appendingPathComponent(".\(skillName)-incoming")
                do {
                    try FileManager.default.createDirectory(at: skills, withIntermediateDirectories: true)
                    try? FileManager.default.removeItem(at: staging)
                    try FileManager.default.copyItem(at: source, to: staging)
                    try marker(stamp).write(to: staging.appendingPathComponent(markerName), options: .atomic)
                    if found.state == .ours { try FileManager.default.removeItem(at: folder) }
                    try FileManager.default.moveItem(at: staging, to: folder)
                    return Result(root: root, path: folder, outcome: found.state == .ours ? .updated : .installed)
                } catch {
                    try? FileManager.default.removeItem(at: staging)
                    return Result(root: root, path: folder, outcome: .failed, detail: error.localizedDescription)
                }
            }
        }
    }

    /// Removes our copy from each root. Anything without our marker stays.
    static func remove(from roots: [URL]) -> [Result] {
        roots.map { root in
            let folder = folder(in: root)
            if let linked = linkedPath(in: root) { return linkedRootResult(root, linked: linked) }
            switch state(of: root).state {
            case .none:
                return Result(root: root, path: folder, outcome: .absent)
            case .foreign:
                return Result(root: root, path: folder, outcome: .notOurs, detail: "not written by \(Identity.name)")
            case .ours:
                do {
                    try FileManager.default.removeItem(at: folder)
                    return Result(root: root, path: folder, outcome: .removed)
                } catch {
                    return Result(root: root, path: folder, outcome: .failed, detail: error.localizedDescription)
                }
            }
        }
    }

    /// True when `installed` holds exactly the files `source` does, byte for byte. Hidden files are
    /// skipped on both sides: the marker is the installer's own, and macOS leaves .DS_Store behind.
    /// A file that will not read matches nothing, so the copy is written again rather than taken on
    /// trust for a file nobody could compare.
    static func matches(source: URL, installed: URL) -> Bool {
        let wanted = files(under: source), found = files(under: installed)
        guard Set(wanted.keys) == Set(found.keys) else { return false }
        return wanted.allSatisfy { name, data in
            guard let data, let other = found[name] ?? nil else { return false }
            return data == other
        }
    }

    private static func linkedRootResult(_ root: URL, linked: URL) -> Result {
        Result(root: root, path: folder(in: root), outcome: .linkedRoot,
               detail: "\(linked.path) is a link, so the skill would land somewhere else")
    }

    private static func marker(_ stamp: Stamp) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(stamp)
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
