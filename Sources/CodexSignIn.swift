import AppKit

/// How Codex's responder is signed in. Its Codex home is Vignette's own (`defaultHome`),
/// so it is signed in on its own, once, through Codex's browser login, and Codex keeps that sign-in in
/// `auth.json` there and renews it itself. The person's own Codex folder is never read
/// (docs/adr/0026-codex-answers-live-ink-too.md).
enum CodexSignIn {
    /// Vignette's own Codex home: none of the person's config, instructions, memories or sessions. It
    /// is in the app's Application Support folder (`Launch.dataHome`). A test launch on the person's
    /// own home has none, as it runs no agent tool there (`AgentPlugins.runsNoTool`).
    nonisolated static let defaultHome: URL? =
        Launch.isOnPersonsHome(AgentPlugin.appHome, environment: AgentPlugin.appEnvironment, personHome: AgentPlugin.personHome)
            ? nil : Identity.applicationSupportURL.appendingPathComponent("live-ink/codex-home", isDirectory: true)

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
    nonisolated static let signOutLimit: TimeInterval = 15

    static let portTaken = "Another sign-in to Codex may be open. You can try again once it's done."
    static let couldNotStart = "Vignette couldn't start the sign-in to Codex. You can try again."
    static let notSignedIn = "The sign-in to Codex didn't finish. You can try again."

    private let binary: () -> String?
    private let home: URL?
    private let open: (URL) -> Void
    private var session: AppServerSession?
    private var done: ((Outcome) -> Void)?
    private var loginID: String?
    private var limit: Timer?

    init(binary: @escaping () -> String? = CodexConnection.binaryToRun, home: URL? = CodexSignIn.defaultHome,
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
            session = try AppServerSession(binary: binary, home: home,
                                           onNotification: { [weak self] in self?.notified($0, $1) },
                                           onEnd: { [weak self] in self?.ended($0) },
                                           ready: { [weak self] in self?.initialized($0) })
        } catch {
            return finish(.failed(reason: Self.couldNotStart, detail: error.localizedDescription))
        }
        Log.write("[codex-login] starting pid=\(session?.pid ?? 0)")
        wait(Self.startLimit, reason: Self.couldNotStart, detail: "no answer to account/login/start")
    }

    /// Ends the sign-in, as the person closing what asked for it does. Stopping the server ends its
    /// login and frees the port.
    func cancel() {
        finish(.cancelled)
    }

    /// Signs `home` out with Codex's own logout, which also revokes the tokens with OpenAI, then
    /// removes `auth.json` if it is still there, since the folder is Vignette's. The logout runs off
    /// the main thread, and `done` runs on it once.
    nonisolated static func signOut(home: URL? = CodexSignIn.defaultHome, done: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            if let home {
                if let binary = CodexConnection.binaryToRun() {
                    _ = AppServer.converse(binary, ["app-server"] + CodexIsolation.arguments + CodexSignIn.arguments, AppServer.logoutRequests,
                                           timeout: signOutLimit, environment: ["CODEX_HOME": home.path])
                }
                try? FileManager.default.removeItem(at: home.appendingPathComponent("auth.json"))
                Log.write("[codex-login] signed out")
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { done() } }
        }
    }

    private func initialized(_ answer: Result<Void, AppServerSession.ServerError>) {
        if case .failure(let error) = answer { return finish(.failed(reason: Self.couldNotStart, detail: "initialize: \(error.message)")) }
        session?.call("account/login/start", ["type": "chatgpt"]) { [weak self] in self?.started($0) }
    }

    private func started(_ answer: Result<[String: Any], AppServerSession.ServerError>) {
        guard case .success(let result) = answer, let id = result["loginId"] as? String,
              let page = (result["authUrl"] as? String).flatMap(URL.init(string:)) else {
            var detail = "account/login/start answered no page"
            if case .failure(let error) = answer { detail = error.message }
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
        session?.stop()
        session = nil
        loginID = nil
        switch outcome {
        case .signedIn: Log.write("[codex-login] signed in")
        case .cancelled: Log.write("[codex-login] cancelled")
        case .failed(_, let detail): Log.write("[codex-login] error \(detail)")
        }
        done(outcome)
    }

    private func notified(_ method: String, _ params: [String: Any]) {
        guard method == "account/login/completed", params["loginId"] as? String == loginID, loginID != nil else { return }
        if params["success"] as? Bool == true { return finish(.signedIn) }
        finish(.failed(reason: Self.notSignedIn, detail: params["error"] as? String ?? "login failed"))
    }

    private func ended(_ status: Int32) {
        let tail = session?.lastErrorLine ?? ""
        session = nil
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
