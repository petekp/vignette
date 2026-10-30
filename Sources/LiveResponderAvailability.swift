import Foundation

/// Whether each agent can answer live ink, checked without sending a message.
extension LiveResponder {
    /// Whether an agent can answer, as its own tools report it (`availability(of:)`).
    enum Availability: Equatable {
        /// The first check has not answered. An ask is sent while it runs, and fails if the agent cannot answer.
        case checking
        case ready
        case notInstalled
        case signedOut

        /// Whether a note aimed at the agent may send its ask.
        var canAnswer: Bool { self == .checking || self == .ready }

        /// For the person: why Claude cannot answer, or nil when it can.
        var problem: String? { problem(for: .claude) }

        /// For the person: why `client` cannot answer, or nil when it can.
        func problem(for client: AgentClient) -> String? {
            switch (self, client) {
            case (.checking, _), (.ready, _): nil
            case (.notInstalled, .claude): "Vignette couldn't find Claude Code. You can send your ink to a session."
            case (.signedOut, .claude): "Claude Code isn't signed in. You can sign in by running claude in Terminal."
            case (.notInstalled, .codex): "Vignette couldn't find Codex. You can send your ink to a session."
            case (.signedOut, .codex): CodexDriver.signedOut
            }
        }
    }

    /// How long `claude auth status` may take before the check counts as ready.
    nonisolated static let authStatusLimit: TimeInterval = 10

    /// The `claude` that answers live ink. In a test launch it is only what `VIGNETTE_CLAUDE` names.
    nonisolated static func claudeBinary() -> String? {
        AgentTools.forSessions("VIGNETTE_CLAUDE") { PluginHost.binary(for: .claude) }
    }

    /// Whether `client` is installed and signed in. Claude Code's check runs `claude auth status`,
    /// which sends no message and costs nothing; a `claude` whose answer cannot be read counts as
    /// ready, and the first ask then reports what the process says. Codex's reads whether
    /// Vignette's own Codex home holds a sign-in (`CodexSignIn.isSignedIn`).
    /// Every step, the command's lookup included, runs off the main thread.
    static func availability(of client: AgentClient) async -> Availability {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                switch client {
                case .claude:
                    continuation.resume(returning: claudeBinary().map(authStatus(binary:)) ?? .notInstalled)
                case .codex:
                    guard CodexConnection.binaryToRun() != nil, CodexSignIn.defaultHome != nil else { return continuation.resume(returning: .notInstalled) }
                    continuation.resume(returning: CodexSignIn.isSignedIn() ? .ready : .signedOut)
                }
            }
        }
    }

    /// The answer of `claude auth status --json`, read off the calling thread. A check that does not
    /// answer within `authStatusLimit` stops the process and counts as ready.
    nonisolated private static func authStatus(binary: String) -> Availability {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["auth", "status", "--json"]
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            Log.write("[live-ink] responder check could not run \(binary): \(error)")
            return .ready
        }
        let exited = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            exited.signal()
        }
        guard exited.wait(timeout: .now() + authStatusLimit) == .success else {
            process.terminate()
            Log.write("[live-ink] responder check timed out")
            return .ready
        }
        let answer = (try? JSONSerialization.jsonObject(with: output.fileHandleForReading.readDataToEndOfFile())) as? [String: Any]
        guard let loggedIn = answer?["loggedIn"] as? Bool else { return .ready }
        return loggedIn ? .ready : .signedOut
    }
}
