import Foundation
import os

/// How the connections run the command line tools they talk through.
enum Subprocess {
    /// The app's environment with `adding` over it and a `PATH` that finds what `binary` needs.
    static func environment(for binary: String, adding: [String: String] = [:]) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment.merging(adding) { $1 }
        environment["PATH"] = AgentTools.searchPath(for: binary)
        return environment
    }

    /// How long a command stopped on its deadline has to exit before it is killed.
    static let killGrace: TimeInterval = 1
    /// How long, once the command exited, to wait for the last of its output. A process it started
    /// in the background can hold the output open for as long as it runs.
    static let drainLimit: TimeInterval = 0.5

    /// Runs a command and returns its status, its combined output, and whether the watchdog had to
    /// stop it; nil when it cannot start. It blocks, so callers keep it off the main thread, but for
    /// no longer than `timeout` plus `killGrace` and `drainLimit`: a command that ignores SIGTERM is
    /// killed, and output still held open by a process it started is left behind, still read so
    /// that process can go on writing. A command killed on the deadline may still have been accepted
    /// by whatever it was talking to, so a caller that has to tell a definite failure from an
    /// uncertain one reads `timedOut` rather than the exit status. `environment` is added to the
    /// app's own, with `PATH` from `AgentTools.searchPath`. It runs in `folder` when one is given.
    /// Without `includingErrors`, the output is standard output alone, so a warning cannot spoil
    /// what a caller parses.
    static func run(_ binary: String, _ arguments: [String], timeout: TimeInterval, environment: [String: String] = [:],
                    folder: URL? = nil, includingErrors: Bool = true) -> (status: Int32, output: String, timedOut: Bool)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.environment = Self.environment(for: binary, adding: environment)
        process.currentDirectoryURL = folder
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = includingErrors ? pipe : FileHandle.nullDevice
        // `waitUntilExit` polls, and can return 60 to 70 ms after the child exits, even off the main
        // thread. The handler runs as it exits.
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        let output = OSAllocatedUnfairLock(initialState: (data: Data(), answered: false))
        let ended = DispatchSemaphore(value: 0)
        let reader = pipe.fileHandleForReading
        // The handler holds the handle until the end of the output: released earlier, it would close
        // the pipe under a process still writing to it.
        reader.readabilityHandler = { [reader] _ in
            let chunk = reader.availableData
            if chunk.isEmpty {
                reader.readabilityHandler = nil
                ended.signal()
            } else {
                output.withLock { if !$0.answered { $0.data.append(chunk) } }
            }
        }
        do { try process.run() } catch {
            reader.readabilityHandler = nil
            return nil
        }
        let timedOut = exited.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            process.terminate()
            if exited.wait(timeout: .now() + killGrace) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                exited.wait()
            }
        }
        _ = ended.wait(timeout: .now() + drainLimit)
        let data = output.withLock { state in
            state.answered = true
            return state.data
        }
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "", timedOut)
    }

    /// A command's own words as one short log detail; nil when it said nothing. Errors often come
    /// as JSON on stderr, which the log line carries as it is.
    static func detail(_ output: String?) -> String? {
        let text = (output ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(200))
    }
}
