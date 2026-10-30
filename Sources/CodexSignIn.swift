import AppKit

/// How Codex's responder is signed in. Its Codex home is Vignette's own (`CodexDriver.defaultHome`),
/// so it is signed in on its own, once, through Codex's browser login, and Codex keeps that sign-in in
/// `auth.json` there and renews it itself. The person's own Codex folder is never read
/// (docs/adr/0026-codex-answers-live-ink-too.md).
enum CodexSignIn {
    /// Whether Vignette's Codex home holds a ChatGPT sign-in. Only whether the tokens are there is
    /// read. It reads a file, so it runs off the main thread.
    nonisolated static func isSignedIn(home: URL = CodexDriver.defaultHome) -> Bool {
        guard let data = try? Data(contentsOf: home.appendingPathComponent("auth.json")),
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

    static let portTaken = "Another sign-in to Codex is open. You can try again once it's finished."
    static let couldNotStart = "Vignette couldn't start the sign-in to Codex. You can try again."
    static let notSignedIn = "Codex didn't sign in. You can try again."

    private let binary: () -> String?
    private let home: URL
    private let open: (URL) -> Void
    private var process: JSONLinesProcess?
    private var done: ((Outcome) -> Void)?
    private var nextID = 1
    private var replies: [Int: ([String: Any]?, String?) -> Void] = [:]
    private var loginID: String?
    private var limit: Timer?

    init(binary: @escaping () -> String? = LiveResponder.codexBinary, home: URL = CodexDriver.defaultHome,
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
