import Foundation

/// Where the agents' command line tools are. The app is launched by LaunchServices, so it inherits
/// no shell `PATH`: a tool is found in its installer's usual folders, then in the folders the
/// version managers put a global npm or Bun command in, then where the person's login shell finds
/// it. The shell is asked once, off the main thread, at launch (`start`), since it runs the
/// person's startup files and can take seconds.
enum AgentTools {
    /// Posted on the main thread when the login shell found a tool the folders did not.
    static let found = Notification.Name("vignette.agentToolsFound")

    /// How long the login shell may take. Past it, the folders' answer stands.
    static let shellTimeout: TimeInterval = 8

    private static let lock = NSLock()
    private static var fromShell: [String: String] = [:]
    /// The login shell's `PATH`, once it has answered.
    private static var shellPath: String?
    private static let shellDone = DispatchSemaphore(value: 0)
    private static var started = false

    /// The tool named `name`: the first of `fixed` that runs, then a version manager's, then the
    /// login shell's. Off the main thread this waits for the shell's answer if it has not come;
    /// on it, it answers at once with what is known, and `found` says when the shell adds a tool.
    static func path(_ name: String, fixed: [String], home: String = NSHomeDirectory(),
                     exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        if let path = (fixed + managed(name, home: home)).first(where: exists) { return path }
        if !Thread.isMainThread, lock.withLock({ started }) {
            _ = shellDone.wait(timeout: .now() + shellTimeout)
            shellDone.signal()
        }
        return lock.withLock { fromShell[name] }.flatMap { exists($0) ? $0 : nil }
    }

    /// A tool that reaches the person's agent sessions or account: codex, which lists and queues to
    /// their threads, herdr, which reads their panes, and claude, which answers live ink. In a test launch (`VIGNETTE_SETTINGS` set) it is
    /// only the one the environment names in `variable`, and none without it, since any other found
    /// on this Mac is the person's own.
    static func forSessions(_ variable: String, environment: [String: String] = ProcessInfo.processInfo.environment,
                            exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
                            otherwise: () -> String?) -> String? {
        guard environment["VIGNETTE_SETTINGS"].map({ !$0.isEmpty }) ?? false else { return otherwise() }
        return environment[variable].flatMap { exists($0) ? $0 : nil }
    }

    /// Every folder `path` looks in before the shell, for an error line that names them.
    static func searched(_ name: String, fixed: [String], home: String = NSHomeDirectory()) -> [String] {
        fixed + managed(name, home: home)
    }

    /// Where the version managers put a global command: Volta, Bun, pnpm, npm with its prefix in the
    /// home folder, asdf and mise shims, and the newest Node that nvm or fnm installed.
    static func managed(_ name: String, home: String) -> [String] {
        var paths = [".volta/bin", ".bun/bin", "Library/pnpm", ".npm-global/bin", ".asdf/shims", ".local/share/mise/shims"]
            .map { "\(home)/\($0)/\(name)" }
        for (versions, bin) in [(".nvm/versions/node", "bin"), (".local/share/fnm/node-versions", "installation/bin"),
                                ("Library/Application Support/fnm/node-versions", "installation/bin")] {
            let folder = "\(home)/\(versions)"
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
            // Newest first: `v22.1.0` before `v9.0.0`.
            for version in names.sorted(by: { $0.compare($1, options: .numeric) == .orderedDescending }) {
                paths.append("\(folder)/\(version)/\(bin)/\(name)")
            }
        }
        return paths
    }

    /// Asks the login shell once where `names` are. Call at launch.
    static func start(names: [String] = ["claude", "codex"]) {
        guard !lock.withLock({ let was = started; started = true; return was }) else { return }
        if Settings.isOverridden {
            let env = ProcessInfo.processInfo.environment
            Log.write("[tools] test launch: codex=\(env["VIGNETTE_CODEX"] ?? "none") herdr=\(env["VIGNETTE_HERDR"] ?? "none") claude=\(env["VIGNETTE_CLAUDE"] ?? "none"), from VIGNETTE_CODEX, VIGNETTE_HERDR and VIGNETTE_CLAUDE")
        }
        DispatchQueue.global(qos: .utility).async {
            let (found, path) = shellPaths(names)
            let new = lock.withLock { () -> Bool in
                fromShell = found
                shellPath = path
                return !found.isEmpty
            }
            shellDone.signal()
            Log.write("[tools] login shell found \(found.isEmpty ? "none" : found.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
            if new { DispatchQueue.main.async { NotificationCenter.default.post(name: AgentTools.found, object: nil) } }
        }
    }

    /// The person's login shell, interactive so it reads the files where nvm and the like set up
    /// `PATH`, asked `command -v` for each name and for its `PATH`, with nothing on its input.
    private static func shellPaths(_ names: [String]) -> (found: [String: String], path: String?) {
        guard let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell.map({ String(cString: $0) }),
              FileManager.default.isExecutableFile(atPath: shell),
              let result = Subprocess.run(shell, ["-ilc", "command -v \(names.joined(separator: " ")); printf '\\n\(pathMarker)%s\\n' \"$PATH\""],
                                          timeout: shellTimeout, environment: ["TERM": "dumb"]) else { return ([:], nil) }
        return (parse(result.output, names: names), parsePath(result.output))
    }

    private static let pathMarker = "VIGNETTE_SHELL_PATH="

    /// The `PATH` the shell printed after `pathMarker`, or nil.
    static func parsePath(_ output: String) -> String? {
        output.split(whereSeparator: \.isNewline).last { $0.hasPrefix(pathMarker) }
            .map { String($0.dropFirst(pathMarker.count)) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The `PATH` to run `binary` with. An app opened from Finder has only the system's folders, and
    /// a tool npm installed is a `#!/usr/bin/env node` script, which fails without `node` on it. So
    /// the tool's own folder comes first, as written and with its links resolved, since npm, nvm,
    /// Volta and Homebrew keep `node` beside the command. Then the login shell's `PATH`, once it
    /// has answered, then the system's.
    static func searchPath(for binary: String, shell: String? = nil, system: String? = ProcessInfo.processInfo.environment["PATH"]) -> String {
        let url = URL(fileURLWithPath: binary)
        var folders = [url.deletingLastPathComponent().path, url.resolvingSymlinksInPath().deletingLastPathComponent().path]
        for path in [shell ?? lock.withLock({ shellPath }), system ?? "/usr/bin:/bin:/usr/sbin:/sbin"] {
            folders += (path ?? "").split(separator: ":").map(String.init)
        }
        var seen = Set<String>()
        return folders.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
    }

    /// The lines of `command -v` output that are absolute paths to one of `names`. Anything else a
    /// shell prints while it starts is ignored.
    static func parse(_ output: String, names: [String]) -> [String: String] {
        var found: [String: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let path = line.trimmingCharacters(in: .whitespaces)
            let name = (path as NSString).lastPathComponent
            guard path.hasPrefix("/"), names.contains(name), found[name] == nil else { continue }
            found[name] = path
        }
        return found
    }
}
