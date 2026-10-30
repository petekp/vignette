import Foundation

/// Whether Claude Code can answer live ink, checked without sending a message.
extension LiveResponder {
    /// Whether Claude Code can answer, as `claude auth status` reports it (`availability()`).
    enum Availability: Equatable {
        /// The first check has not answered. An ask is sent while it runs, and fails if Claude cannot answer.
        case checking
        case ready
        case notInstalled
        case signedOut

        /// Whether a note aimed at Claude may send its ask.
        var canAnswer: Bool { self == .checking || self == .ready }

        /// For the person: why Claude cannot answer, or nil when it can.
        var problem: String? {
            switch self {
            case .checking, .ready: nil
            case .notInstalled: "Vignette couldn't find Claude Code. You can send your ink to a session."
            case .signedOut: "Claude Code isn't signed in. You can sign in by running claude in Terminal."
            }
        }
    }

    /// How long `claude auth status` may take before the check counts as ready.
    static let authStatusLimit: TimeInterval = 10

    /// The `claude` that answers live ink. In a test launch it is only what `VIGNETTE_CLAUDE` names.
    static func claudeBinary() -> String? {
        AgentTools.forSessions("VIGNETTE_CLAUDE") { PluginHost.binary(for: .claude) }
    }

    /// Whether Claude Code is installed and signed in. It runs `claude auth status`, which sends no
    /// message and costs nothing. A `claude` whose answer cannot be read counts as ready, and the first
    /// ask then reports what the process says.
    static func availability() async -> Availability {
        guard let binary = claudeBinary() else { return .notInstalled }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: authStatus(binary: binary))
            }
        }
    }

    /// The answer of `claude auth status --json`, read off the calling thread. A check that does not
    /// answer within `authStatusLimit` stops the process and counts as ready.
    private static func authStatus(binary: String) -> Availability {
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
