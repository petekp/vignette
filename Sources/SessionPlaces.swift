import Foundation

/// Where an agent session works: its repository, or else its folder.
enum Place: Equatable, Sendable {
    /// `name` is the main checkout's folder name as it is on disk. `root` is that checkout's
    /// canonical path, nil when the repository was read from the shape of a path or from a remote's
    /// address, so only its name is known. `worktree` is set when the session is in a worktree;
    /// `subfolder` is the path below the checkout, without folders whose name starts with a dot. A
    /// folder in `<parent>/worktrees/<repo>` that is no worktree has `worktrees` and the path below it.
    case repository(name: String, root: String?, worktree: String?, subfolder: String?)
    /// A folder with no repository, as a path from home.
    case folder(fromHome: String)
    /// A session with no folder.
    case none
}

/// Finds a session's repository, worktree, subfolder and branch from its folder. It reads files
/// only, and never runs `/usr/bin/git`, which raises the install dialog for Apple's developer tools
/// on a Mac without them. It is meant for the listing job, off the main thread.
enum SessionPlaces {
    struct Found: Equatable, Sendable {
        var place: Place
        /// The checked-out branch when it is not the repository's default; nil on the default
        /// branch, on a detached `HEAD`, and when nothing could be read.
        var branch: String?
    }

    /// What the worktrees Codex makes are called, since their folder's name is the repository's.
    static let codexWorktree = "Codex worktree"

    /// `folder`'s place. `originURL` is a Codex thread's remote, used last for a folder that is gone.
    /// `environment` says where Codex's folder is (`CODEX_HOME`), whose worktrees are named for Codex.
    static func resolve(folder: String?, originURL: String? = nil, home: String = NSHomeDirectory(),
                        environment: [String: String] = ProcessInfo.processInfo.environment) -> Found {
        guard let folder, !folder.isEmpty else { return Found(place: .none, branch: nil) }
        let fileManager = FileManager.default
        let canonicalHome = canonical(home) ?? home
        // The deepest folder that still exists, made canonical, with what is gone below it.
        var existing = URL(fileURLWithPath: folder).standardizedFileURL
        var gone: [String] = []
        while !existing.path.isEmpty, existing.path != "/", !fileManager.fileExists(atPath: existing.path) {
            gone.insert(existing.lastPathComponent, at: 0)
            existing.deleteLastPathComponent()
        }
        let start = canonical(existing.path) ?? existing.path
        let components = Array((start as NSString).pathComponents.dropFirst() + gone)
        let onDisk = components.count - gone.count
        func shaped() -> Place? { shape(of: components, onDisk: onDisk, home: canonicalHome, environment: environment) }

        var directory = URL(fileURLWithPath: start)
        while directory.path != "/", directory.path != canonicalHome {
            if let checkout = checkout(at: directory, home: canonicalHome, environment: environment) {
                let below = relative(from: directory.path, to: start, gone: gone)
                var place = Place.repository(name: checkout.mainFolder.lastPathComponent, root: checkout.mainFolder.path,
                                             worktree: checkout.worktree, subfolder: subfolder(below))
                // A worktree that is gone lies inside its repository's folder or beside it. Its path
                // says which worktree it was, which walking up to the checkout cannot.
                if !gone.isEmpty, case .repository(let name, _, let worktree?, let rest)? = shaped(),
                   name == checkout.mainFolder.lastPathComponent {
                    place = .repository(name: name, root: checkout.mainFolder.path, worktree: worktree, subfolder: rest)
                    return Found(place: place, branch: nil)
                }
                return Found(place: place, branch: branch(of: checkout))
            }
            directory.deleteLastPathComponent()
        }
        if let shaped = shaped() { return Found(place: shaped, branch: nil) }
        if let name = remoteName(originURL) {
            return Found(place: .repository(name: name, root: nil, worktree: nil, subfolder: nil), branch: nil)
        }
        let path = components.isEmpty ? "/" : "/" + components.joined(separator: "/")
        return Found(place: .folder(fromHome: fromHome(path, home: canonicalHome)), branch: nil)
    }

    /// The path from home, such as `~/Code`, and `~` for home itself. Outside home it stays absolute.
    static func fromHome(_ path: String, home: String) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    /// The last part of a remote's address without `.git`: `git@github.com:ever/foo.git` is `foo`.
    static func remoteName(_ url: String?) -> String? {
        guard var text = url?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        while text.hasSuffix("/") { text.removeLast() }
        if text.hasSuffix(".git") { text.removeLast(4) }
        guard let last = text.split(whereSeparator: { $0 == "/" || $0 == ":" }).last, !last.isEmpty else { return nil }
        return String(last)
    }

    // MARK: Reading .git

    private struct Checkout {
        /// The git folder with this checkout's own `HEAD`.
        let gitDirectory: URL
        /// The main repository's git folder, which holds the refs.
        let commonDirectory: URL
        /// The main checkout's folder.
        let mainFolder: URL
        let worktree: String?
    }

    private static func checkout(at folder: URL, home: String, environment: [String: String]) -> Checkout? {
        let dot = folder.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dot.path, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue {
            return Checkout(gitDirectory: dot, commonDirectory: dot, mainFolder: folder, worktree: nil)
        }
        // A `.git` file: `gitdir: <path>`, relative to its folder.
        guard let text = try? String(contentsOf: dot, encoding: .utf8),
              let line = text.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("gitdir:") }) else { return nil }
        let gitDirectory = resolve(String(line.dropFirst("gitdir:".count)).trimmingCharacters(in: .whitespaces), from: folder)
        guard let common = (try? String(contentsOf: gitDirectory.appendingPathComponent("commondir"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines), !common.isEmpty else {
            // A submodule: its own repository, whose git folder lives elsewhere.
            return Checkout(gitDirectory: gitDirectory, commonDirectory: gitDirectory, mainFolder: folder, worktree: nil)
        }
        let commonDirectory = resolve(common, from: gitDirectory)
        let mainFolder = commonDirectory.lastPathComponent == ".git"
            ? commonDirectory.deletingLastPathComponent()
            : commonDirectory.deletingLastPathComponent().appendingPathComponent(
                commonDirectory.lastPathComponent.hasSuffix(".git") ? String(commonDirectory.lastPathComponent.dropLast(4)) : commonDirectory.lastPathComponent)
        let components = Array(folder.pathComponents.dropFirst())
        let inCodex = codexWorktreeIndex(in: components, home: home, environment: environment).map { $0 < components.count } ?? false
        let worktree = inCodex ? codexWorktree : folder.lastPathComponent
        return Checkout(gitDirectory: gitDirectory, commonDirectory: commonDirectory,
                        mainFolder: URL(fileURLWithPath: canonical(mainFolder.path) ?? mainFolder.path), worktree: worktree)
    }

    /// For a path in the folder Codex makes worktrees in, `worktrees` in Codex's folder or in any
    /// `.codex`, the index of the folder below it; it may be past the path's end. Nil for any other path.
    private static func codexWorktreeIndex(in path: [String], home: String, environment: [String: String]) -> Int? {
        let root = AgentPlugin.root(of: .codex, home: URL(fileURLWithPath: home), environment: environment).path
        let worktrees = Array(((canonical(root) ?? root) as NSString).pathComponents.dropFirst()) + ["worktrees"]
        if path.starts(with: worktrees) { return worktrees.count }
        return path.indices.first { $0 + 1 < path.count && path[$0] == ".codex" && path[$0 + 1] == "worktrees" }.map { $0 + 2 }
    }

    private static func resolve(_ path: String, from folder: URL) -> URL {
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : folder.appendingPathComponent(path)
        return url.standardizedFileURL
    }

    private static func canonical(_ path: String) -> String? {
        try? URL(fileURLWithPath: path).resourceValues(forKeys: [.canonicalPathKey]).canonicalPath
    }

    /// The checked-out branch, when it is not the default one.
    private static func branch(of checkout: Checkout) -> String? {
        guard let head = firstLine(checkout.gitDirectory.appendingPathComponent("HEAD")), head.hasPrefix("ref: refs/heads/") else {
            return nil
        }
        let branch = String(head.dropFirst("ref: refs/heads/".count))
        guard let standard = defaultBranch(in: checkout.commonDirectory), standard != branch else { return nil }
        return branch
    }

    /// `refs/remotes/origin/HEAD`'s target, else `main`, else `master`.
    private static func defaultBranch(in common: URL) -> String? {
        let prefix = "ref: refs/remotes/origin/"
        if let origin = firstLine(common.appendingPathComponent("refs/remotes/origin/HEAD")), origin.hasPrefix(prefix) {
            return String(origin.dropFirst(prefix.count))
        }
        let packed = (try? String(contentsOf: common.appendingPathComponent("packed-refs"), encoding: .utf8)) ?? ""
        for name in ["main", "master"] {
            if FileManager.default.fileExists(atPath: common.appendingPathComponent("refs/heads/\(name)").path)
                || packed.contains(" refs/heads/\(name)\n") || packed.hasSuffix(" refs/heads/\(name)") { return name }
        }
        return nil
    }

    private static func firstLine(_ file: URL) -> String? {
        (try? String(contentsOf: file, encoding: .utf8))?.split(whereSeparator: \.isNewline).first.map(String.init)
    }

    // MARK: Paths

    /// The components of `target` below `base`, with `gone` after them.
    private static func relative(from base: String, to target: String, gone: [String]) -> [String] {
        let below = target == base ? [] : target.dropFirst(base.count + 1).split(separator: "/").map(String.init)
        return below + gone
    }

    private static func subfolder(_ components: [String]) -> String? {
        let shown = components.filter { !$0.hasPrefix(".") }
        return shown.isEmpty ? nil : shown.joined(separator: "/")
    }

    /// A repository read from the shape of the path, for a folder with no `.git` above it:
    /// `<Codex's folder>/worktrees/<any>/<repo>/…`, `<repo>/.claude/worktrees/<name>/…`,
    /// `<parent>/worktrees/<repo>/…`, and `<repo>/.worktrees/<name>/…`. A path in Codex's worktrees
    /// is read as Codex's or not at all, and `<repo>` is never the home folder. The first `onDisk`
    /// components of `path` exist; the rest are gone.
    private static func shape(of path: [String], onDisk: Int, home: String, environment: [String: String]) -> Place? {
        func place(_ name: String, worktree: String, rest: ArraySlice<String>) -> Place {
            .repository(name: name, root: nil, worktree: worktree, subfolder: subfolder(Array(rest)))
        }
        if let any = codexWorktreeIndex(in: path, home: home, environment: environment) {
            return any + 1 < path.count ? place(path[any + 1], worktree: codexWorktree, rest: path[(any + 2)...]) : nil
        }
        let homeFolder = Array((home as NSString).pathComponents.dropFirst())
        func isRepository(below index: Int) -> Bool { index > 0 && Array(path[..<index]) != homeFolder }
        for index in path.indices where path[index] == ".claude" && index + 2 < path.count && path[index + 1] == "worktrees" && isRepository(below: index) {
            return place(path[index - 1], worktree: path[index + 2], rest: path[(index + 3)...])
        }
        for index in path.indices where path[index] == "worktrees" && index + 1 < path.count {
            if let found = worktreesFolder(path, at: index, onDisk: onDisk, home: home, environment: environment) { return found }
        }
        for index in path.indices where path[index] == ".worktrees" && index + 1 < path.count && isRepository(below: index) {
            return place(path[index - 1], worktree: path[index + 1], rest: path[(index + 2)...])
        }
        return nil
    }

    /// `<parent>/worktrees/<repo>` and every folder below it belong to the checkout at
    /// `<parent>/<repo>`, which is how worktrees are laid out beside their repository. A folder below
    /// it that is on disk is a subfolder, since a worktree there has a `.git` the walk up finds first;
    /// the first one that is gone is taken for the worktree it was. With no checkout there, only a
    /// worktree that is gone still names its repository.
    private static func worktreesFolder(_ path: [String], at index: Int, onDisk: Int, home: String,
                                        environment: [String: String]) -> Place? {
        let name = path[index + 1]
        let firstBelow = index + 2
        let worktree = firstBelow < path.count && firstBelow >= onDisk ? path[firstBelow] : nil
        let rest = worktree == nil ? [path[index]] + path.dropFirst(firstBelow) : Array(path.dropFirst(firstBelow + 1))
        let repositoryFolder = "/" + (path[..<index] + [name]).joined(separator: "/")
        if let folder = canonical(repositoryFolder), folder != home,
           let found = checkout(at: URL(fileURLWithPath: folder), home: home, environment: environment) {
            return .repository(name: found.mainFolder.lastPathComponent, root: found.mainFolder.path,
                               worktree: worktree, subfolder: subfolder(rest))
        }
        guard let worktree else { return nil }
        return .repository(name: name, root: nil, worktree: worktree, subfolder: subfolder(rest))
    }
}
