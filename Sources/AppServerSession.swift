import Foundation

/// One `codex app-server` that Vignette talks to for as long as it runs, in a Codex home of its own:
/// live ink's responder (`CodexDriver`) and its sign-in (`CodexLogin`). It launches with every switch
/// in `CodexIsolation` and the sign-in kept in a file (`CodexSignIn.arguments`), does the handshake
/// `AppServer` does, answers each `call` once, hands every notification on, and refuses every
/// request the server makes, since Vignette grants none. After `stop` nothing more is reported.
@MainActor
final class AppServerSession {
    /// An app-server's error answer.
    struct ServerError: Error {
        let message: String
    }

    private var process: JSONLinesProcess?
    private var nextID = 1
    private var replies: [Int: (Result<[String: Any], ServerError>) -> Void] = [:]
    private let onNotification: (String, [String: Any]) -> Void
    private let onEnd: (Int32) -> Void

    var pid: Int32 { process?.pid ?? 0 }
    /// The last line of the server's standard error, for words about why it ended.
    var lastErrorLine: String { process?.lastErrorLine ?? "" }

    /// Launches the server in `home`, with `arguments` after the switches, and starts the handshake.
    /// `ready` answers once the server has answered `initialize`, or with its error.
    init(binary: String, home: URL, arguments: [String] = [],
         onNotification: @escaping (_ method: String, _ params: [String: Any]) -> Void,
         onEnd: @escaping (_ status: Int32) -> Void, ready: @escaping (Result<Void, ServerError>) -> Void) throws {
        self.onNotification = onNotification
        self.onEnd = onEnd
        let switches: [String] = CodexIsolation.arguments + CodexSignIn.arguments
        process = try JSONLinesProcess(binary: binary, arguments: ["app-server"] + switches + arguments,
                                       environment: Subprocess.environment(for: binary, adding: ["CODEX_HOME": home.path]),
                                       folder: home,
                                       onLine: { [weak self] in self?.received($0) },
                                       onEnd: { [weak self] in self?.ended($0) })
        call("initialize", AppServer.initializeParams) { [weak self] answer in
            if case .success = answer { self?.process?.write(["method": "initialized"]) }
            ready(answer.map { _ in })
        }
    }

    func call(_ method: String, _ params: [String: Any], then reply: @escaping (Result<[String: Any], ServerError>) -> Void) {
        let id = nextID
        nextID += 1
        replies[id] = reply
        process?.write(["id": id, "method": method, "params": params])
    }

    /// Ends the server. Its answers, notifications and end are not reported from now on.
    func stop() {
        process?.stop()
        process = nil
        replies = [:]
    }

    /// An error's `message`, as an answer or a turn carries it.
    static func text(of error: Any?) -> String? {
        (error as? [String: Any])?["message"] as? String
    }

    private func received(_ message: [String: Any]) {
        let method = message["method"] as? String
        if let id = message["id"] as? Int, method == nil {
            let reply = replies.removeValue(forKey: id)
            if let result = message["result"] as? [String: Any] { reply?(.success(result)) }
            else { reply?(.failure(ServerError(message: Self.text(of: message["error"]) ?? "no result"))) }
            return
        }
        guard let method else { return }
        if let id = message["id"] {
            process?.write(["id": id, "error": ["code": -32601, "message": "Vignette does not support \(method)"]])
            return
        }
        onNotification(method, message["params"] as? [String: Any] ?? [:])
    }

    private func ended(_ status: Int32) {
        replies = [:]
        onEnd(status)
    }
}
