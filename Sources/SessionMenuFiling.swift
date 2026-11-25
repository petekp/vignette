import Foundation

extension SessionMenu {
    /// How every session on offer is filed and worded, decided over all of them so that a session
    /// reads the same whichever menu it is in.
    ///
    /// A repository is its origin remote's address when one is known, else its main checkout's path,
    /// so clones of one remote share a group. One of them is the main clone (`mainFirst`), and a row
    /// in any other names its clone as a place, as a worktree's row names its worktree.
    struct Filer {
        /// Where one session is filed.
        struct Filing: Equatable {
            /// Identifies the group across menus: `remote:` and the remote's address in lowercase,
            /// else the main checkout's path, else `name:` and the name a session alone gave; or
            /// `otherFolders`.
            let key: String
            let header: String
            /// The path from home of the clone the session runs in, when that is not the main clone.
            let clone: String?
        }

        let sessions: [AgentDestination]
        private let filings: [String: Filing]

        init(_ sessions: [AgentDestination], home: String = SessionPlaces.home) {
            self.sessions = sessions
            var repositories: [String: Repository] = [:]
            for session in sessions {
                guard case .repository(let name, let root, let remote, _, _) = session.place,
                      let key = Self.key(root: root, remote: remote) else { continue }
                repositories[key, default: Repository()].add(name: name, root: root, remote: remote)
            }
            let headers = Self.headers(of: repositories, home: home)
            var filings: [String: Filing] = [:]
            for session in sessions where filings[session.id] == nil {
                filings[session.id] = Self.filing(of: session, in: repositories, headers: headers, home: home)
            }
            self.filings = filings
        }

        /// The group key and header for a session on offer.
        func filing(_ session: AgentDestination) -> Filing {
            guard let filing = filings[session.id] else { preconditionFailure("session \(session.id) is not on offer") }
            return filing
        }

        /// Every session's row.
        func rows(now: Date) -> [String: SessionMenu.Row] {
            let suffixes = titleSuffixes()
            var rows: [String: SessionMenu.Row] = [:]
            for session in sessions {
                rows[session.id] = Self.row(for: session, titleSuffix: suffixes[session.id], now: now, filing: filing(session))
            }
            return rows
        }

        // MARK: Repositories

        /// One repository on offer: the clones its sessions run in and the names they go by.
        private struct Repository {
            /// Each clone's canonical path, with its folder's name.
            var clones: [String: String] = [:]
            /// Each clone's remote, as it writes it.
            var remotes: [String: String] = [:]
            /// The names of its sessions' places: its clones' folders, and a name read from a path's
            /// shape or a remote.
            var names: Set<String> = []
            var remotesWithoutClone: Set<String> = []

            mutating func add(name: String, root: String?, remote: String?) {
                names.insert(name)
                if let root {
                    clones[root] = name
                    if let remote { remotes[root] = remote }
                } else if let remote {
                    remotesWithoutClone.insert(remote)
                }
            }

            func main(home: String) -> String? { clones.keys.min { Filer.mainFirst($0, $1, home: home) } }
            func name(home: String) -> String { main(home: home).flatMap { clones[$0] } ?? names.min() ?? "" }
            func remote(home: String) -> String? {
                main(home: home).flatMap { remotes[$0] } ?? Set(remotes.values).union(remotesWithoutClone).min()
            }
        }

        private static func key(root: String?, remote: String?) -> String? {
            remote.map { "remote:" + $0.lowercased() } ?? root
        }

        /// The main clone is the one the person keeps: a clone outside every folder whose name starts
        /// with a dot comes first, since that is where tools keep their own clones (kickflip's are in
        /// `~/.claude/kickflip/repos`), then the shorter path, then the first by path. How many
        /// sessions each clone has does not count, so the main clone changes only when a clone joins or
        /// leaves the sessions on offer.
        static func mainFirst(_ a: String, _ b: String, home: String) -> Bool {
            func inDotFolder(_ path: String) -> Bool {
                SessionPlaces.fromHome(path, home: home).split(separator: "/").contains { $0.hasPrefix(".") }
            }
            let (x, y) = (inDotFolder(a), inDotFolder(b))
            if x != y { return !x }
            let (m, n) = (a.split(separator: "/").count, b.split(separator: "/").count)
            return m != n ? m < n : a < b
        }

        /// Each repository's header: its main clone's folder name, or with another repository of that
        /// name, its remote's owner and name, else its main clone's path from home.
        private static func headers(of repositories: [String: Repository], home: String) -> [String: String] {
            var headers: [String: String] = [:]
            for same in Dictionary(grouping: repositories, by: { $0.value.name(home: home).lowercased() }).values {
                let owned = same.map { $0.value.remote(home: home).flatMap(ownerAndName) }
                for ((key, repository), mine) in zip(same, owned) {
                    let ownsIt = mine.map { mine in owned.filter { $0?.lowercased() == mine.lowercased() }.count == 1 } ?? false
                    if same.count == 1 {
                        headers[key] = repository.name(home: home)
                    } else if let mine, ownsIt {
                        headers[key] = mine
                    } else {
                        headers[key] = repository.main(home: home).map { SessionPlaces.fromHome($0, home: home) }
                            ?? repository.remote(home: home) ?? repository.name(home: home)
                    }
                }
            }
            return headers
        }

        /// The last two parts of a remote's path, such as `Ever-Cars/evercars-backend`.
        private static func ownerAndName(_ remote: String) -> String? {
            let parts = remote.split(separator: "/")
            let path = remote.hasPrefix("/") ? parts[...] : parts.dropFirst()
            return path.count < 2 ? nil : path.suffix(2).joined(separator: "/")
        }

        private static func filing(of session: AgentDestination, in repositories: [String: Repository],
                                   headers: [String: String], home: String) -> Filing {
            guard case .repository(let name, let root, let remote, _, _) = session.place else {
                return Filing(key: SessionMenu.otherFolders, header: SessionMenu.otherFolders, clone: nil)
            }
            if let key = key(root: root, remote: remote), let repository = repositories[key] {
                let main = repository.main(home: home)
                let clone = root.flatMap { $0 == main ? nil : SessionPlaces.fromHome($0, home: home) }
                return Filing(key: key, header: headers[key] ?? name, clone: clone)
            }
            // Known by name only: it joins the one repository that goes by that name. With two, the
            // name cannot say which it belongs to, so it is filed under the name alone.
            let same = repositories.keys.filter { repositories[$0]?.names.contains(name) == true }
            if same.count == 1, let key = same.first { return Filing(key: key, header: headers[key] ?? name, clone: nil) }
            return Filing(key: "name:\(name)", header: name, clone: nil)
        }
    }
}
