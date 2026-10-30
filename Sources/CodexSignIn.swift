import AppKit

/// How Codex's responder is signed in. Its Codex home is Vignette's own (`defaultHome`),
/// so it is signed in on its own, once, through Codex's browser login, and Codex keeps that sign-in in
/// `auth.json` there and renews it itself. The person's own Codex folder is never read
/// (docs/adr/0026-codex-answers-live-ink-too.md).
enum CodexSignIn {
    /// Vignette's own Codex home: none of the person's config, instructions, memories or sessions.
    /// None in a test launch that left the home folder in place (`home(in:environment:personHome:)`).
    nonisolated static let defaultHome = home(in: Identity.applicationSupportURL)

    /// The Codex home in `folder`, the app's Application Support folder. A test launch
    /// (`VIGNETTE_SETTINGS`) gets none while that folder is the person's own, since it holds their
    /// sign-in, as `AgentPlugin.guarded` keeps it out of `~/.codex`. `CFFIXED_USER_HOME` moves it.
    nonisolated static func home(in folder: URL, environment: [String: String] = ProcessInfo.processInfo.environment,
                                 personHome: URL = AgentPlugin.personHome) -> URL? {
        let home = folder.appendingPathComponent("live-ink/codex-home", isDirectory: true)
        let own = personHome.appendingPathComponent("Library/Application Support").resolvingSymlinksInPath().path + "/"
        guard Launch.isTest(in: environment), folder.resolvingSymlinksInPath().path.hasPrefix(own) else { return home }
        Log.write("[live-ink] test launch: left \(home.path) alone; launch with CFFIXED_USER_HOME to use Codex")
        return nil
    }

    /// Whether Vignette's Codex home holds a ChatGPT sign-in. Only whether the tokens are there is
    /// read. It reads a file, so it runs off the main thread.
    nonisolated static func isSignedIn(home: URL? = CodexSignIn.defaultHome) -> Bool {
        guard let home, let data = try? Data(contentsOf: home.appendingPathComponent("auth.json")),
              let auth = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tokens = auth["tokens"] as? [String: Any] else { return false }
        return (tokens["refresh_token"] as? String).map { !$0.isEmpty } ?? false
    }

    /// Keeps the sign-in in `auth.json` in Vignette's Codex home, which is Codex's default, so
    /// `isSignedIn` can read it without starting Codex, and removing that folder signs Vignette out.
    /// A config that moved it to the keychain would leave both untrue.
    static let arguments = ["-c", #"cli_auth_credentials_store="file""#]
}

/// Codex's browser sign-in for Vignette's Codex home: a `codex app-server` there starts the login
/// (`account/login/start` with type `chatgpt`), the browser opens the page it answers, and the sign-in
/// ends when the server reports the login completed or failed, when a limit passes, or when it is
/// cancelled. The server serves the page's callback itself, so it runs for the length of the sign-in
/// and stops after it.
@MainActor
final class CodexLogin {
    enum Outcome: Equatable {
        case signedIn
        case cancelled
        /// Why it did not sign in, for the person, and the detail for the log.
        case failed(reason: String, detail: String)
    }

    /// The port Codex 0.165 serves the login's callback on. When something holds it, Codex sends that
    /// a `GET /cancel`, then after 2 to 4 s serves on 1457 instead, or fails when that is taken too
    /// (measured 2026-10-30). Another Codex login waiting there would be sent that cancel, so the
    /// sign-in does not start while the port is taken.
    nonisolated static let callbackPort: UInt16 = 1455
    /// How long `account/login/start` may take to answer: 6 s when both of Codex's ports are taken.
    static let startLimit: TimeInterval = 15
    /// How long the person has to finish signing in in the browser.
    static let signInLimit: TimeInterval = 10 * 60
    /// How long Codex's logout may take: its request to revoke the tokens waits up to 10 s (0.165).
    static let signOutLimit: TimeInterval = 15

    static let portTaken = "Another sign-in to Codex may be open. You can try again once it's done."
    static let couldNotStart = "Vignette couldn't start the sign-in to Codex. You can try again."
    static let notSignedIn = "The sign-in to Codex didn't finish. You can try again."

    private let binary: () -> String?
    private let home: URL?
    private let open: (URL) -> Void
    private var process: JSONLinesProcess?
    private var done: ((Outcome) -> Void)?
    private var nextID = 1
    private var replies: [Int: ([String: Any]?, String?) -> Void] = [:]
    private var loginID: String?
    private var limit: Timer?

    init(binary: @escaping () -> String? = LiveResponder.codexBinary, home: URL? = CodexSignIn.defaultHome,
         open: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        self.binary = binary
        self.home = home
        self.open = open
    }

    /// Starts the sign-in, which answers `done` once.
    func start(_ done: @escaping (Outcome) -> Void) {
        guard self.done == nil else { return }
        self.done = done
        guard let binary = binary() else { return finish(.failed(reason: Self.couldNotStart, detail: "no codex")) }
        guard let home else { return finish(.failed(reason: Self.couldNotStart, detail: "no Codex home in a test launch")) }
        guard !Self.isTaken(Self.callbackPort) else {
            return finish(.failed(reason: Self.portTaken, detail: "port \(Self.callbackPort) is taken"))
        }
        do {
            process = try JSONLinesProcess(binary: binary, arguments: ["app-server"] + CodexIsolation.arguments + CodexSignIn.arguments,
                                           environment: Subprocess.environment(for: binary, adding: ["CODEX_HOME": home.path]),
                                           folder: home,
                                           onLine: { [weak self] in self?.received($0) },
                                           onEnd: { [weak self] status in self?.ended(status) })
        } catch {
            return finish(.failed(reason: Self.couldNotStart, detail: error.localizedDescription))
        }
        Log.write("[codex-login] starting pid=\(process?.pid ?? 0)")
        wait(Self.startLimit, reason: Self.couldNotStart, detail: "no answer to account/login/start")
        call("initialize", ["clientInfo": ["name": "Vignette", "version": BuildInfo.current.version],
                            "capabilities": ["experimentalApi": true]]) { [weak self] _, error in
            guard let self else { return }
            if let error { return finish(.failed(reason: Self.couldNotStart, detail: "initialize: \(error)")) }
            process?.write(["method": "initialized"])
            call("account/login/start", ["type": "chatgpt"]) { [weak self] result, error in self?.started(result, error) }
        }
    }

    /// Ends the sign-in, as the person closing what asked for it does. Stopping the server ends its
    /// login and frees the port.
    func cancel() {
        finish(.cancelled)
    }

    /// Signs `home` out with Codex's own logout, which also revokes the tokens with OpenAI, then
    /// removes `auth.json` if it is still there, since the folder is Vignette's. `done` runs once.
    static func signOut(binary: String?, home: URL? = CodexSignIn.defaultHome, done: @escaping () -> Void) {
        guard let home else { return done() }
        var process: JSONLinesProcess?
        var finished = false
        let finish = {
            guard !finished else { return }
            finished = true
            process?.stop()
            try? FileManager.default.removeItem(at: home.appendingPathComponent("auth.json"))
            Log.write("[codex-login] signed out")
            done()
        }
        guard let binary else { return finish() }
        process = try? JSONLinesProcess(binary: binary, arguments: ["app-server"] + CodexIsolation.arguments + CodexSignIn.arguments,
                                        environment: Subprocess.environment(for: binary, adding: ["CODEX_HOME": home.path]), folder: home,
                                        onLine: { message in
                                            guard message["method"] == nil else { return }
                                            if message["id"] as? Int == 2 { return finish() }
                                            process?.write(["method": "initialized"])
                                            process?.write(["id": 2, "method": "account/logout"])
                                        },
                                        onEnd: { _ in finish() })
        guard process != nil else { return finish() }
        process?.write(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "Vignette", "version": BuildInfo.current.version]]])
        Timer.scheduledTimer(withTimeInterval: signOutLimit, repeats: false) { _ in MainActor.assumeIsolated { finish() } }
    }

    private func started(_ result: [String: Any]?, _ error: String?) {
        guard let result, let id = result["loginId"] as? String, let page = (result["authUrl"] as? String).flatMap(URL.init(string:)) else {
            let detail = error ?? "account/login/start answered no page"
            let taken = detail.contains("already in use")
            return finish(.failed(reason: taken ? Self.portTaken : Self.couldNotStart, detail: detail))
        }
        loginID = id
        wait(Self.signInLimit, reason: Self.notSignedIn, detail: "not signed in after \(Int(Self.signInLimit))s")
        Log.write("[codex-login] page opened callback=\(URLComponents(url: page, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "redirect_uri" }?.value ?? "?")")
        open(page)
    }

    /// Gives up after `seconds`, cancelling the login, with `reason`.
    private func wait(_ seconds: TimeInterval, reason: String, detail: String) {
        limit?.invalidate()
        limit = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(.failed(reason: reason, detail: detail)) }
        }
    }

    private func finish(_ outcome: Outcome) {
        guard let done else { return }
        self.done = nil
        limit?.invalidate()
        limit = nil
        process?.stop()
        process = nil
        replies = [:]
        loginID = nil
        switch outcome {
        case .signedIn: Log.write("[codex-login] signed in")
        case .cancelled: Log.write("[codex-login] cancelled")
        case .failed(_, let detail): Log.write("[codex-login] error \(detail)")
        }
        done(outcome)
    }

    private func call(_ method: String, _ params: [String: Any], then reply: @escaping ([String: Any]?, String?) -> Void) {
        let id = nextID
        nextID += 1
        replies[id] = reply
        process?.write(["id": id, "method": method, "params": params])
    }

    private func received(_ message: [String: Any]) {
        let method = message["method"] as? String
        if let id = message["id"] as? Int, method == nil {
            let error = (message["error"] as? [String: Any])?["message"] as? String
            replies.removeValue(forKey: id)?(message["result"] as? [String: Any], message["result"] == nil ? error ?? "no result" : nil)
            return
        }
        if let id = message["id"], let method {
            process?.write(["id": id, "error": ["code": -32601, "message": "Vignette's sign-in does not support \(method)"]])
            return
        }
        guard method == "account/login/completed", let params = message["params"] as? [String: Any],
              params["loginId"] as? String == loginID, loginID != nil else { return }
        if params["success"] as? Bool == true { return finish(.signedIn) }
        finish(.failed(reason: Self.notSignedIn, detail: params["error"] as? String ?? "login failed"))
    }

    private func ended(_ status: Int32) {
        let tail = process?.lastErrorLine ?? ""
        process = nil
        finish(.failed(reason: Self.couldNotStart, detail: "codex ended \(status) \(tail)"))
    }

    /// Whether something on this Mac holds `port` at 127.0.0.1, found by connecting, which sends
    /// nothing. Only a refusal means it is free: a listener that does not take the connection within
    /// `probeLimit` still holds the port.
    nonisolated static func isTaken(_ port: UInt16) -> Bool {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { return false }
        defer { close(socket) }
        _ = fcntl(socket, F_SETFL, fcntl(socket, F_GETFL) | O_NONBLOCK)
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        if connected == 0 { return true }
        guard errno == EINPROGRESS else { return errno != ECONNREFUSED }
        var poll = pollfd(fd: socket, events: Int16(POLLOUT), revents: 0)
        guard Darwin.poll(&poll, 1, Int32(probeLimit * 1000)) > 0 else { return true }
        var error: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(socket, SOL_SOCKET, SO_ERROR, &error, &length)
        return error != ECONNREFUSED
    }

    nonisolated static let probeLimit: TimeInterval = 0.25
}

extension Notification.Name {
    /// Vignette's Codex home was signed in or out: `userInfo["signedIn"]` says which.
    static let codexSignInChanged = Notification.Name("CodexSignInChanged")
}
