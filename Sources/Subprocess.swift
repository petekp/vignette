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

    /// Runs a command and returns its status, its combined output, and whether the watchdog had to
    /// stop it; nil when it cannot start. It blocks, so callers keep it off the main thread. A
    /// command killed on the deadline may still have been accepted by whatever it was talking to, so
    /// a caller that has to tell a definite failure from an uncertain one reads `timedOut` rather
    /// than the exit status. `environment` is added to the app's own, with `PATH` from
    /// `AgentTools.searchPath`. It runs in `folder` when one is given. Without `includingErrors`, the
    /// output is standard output alone, so a warning cannot spoil what a caller parses.
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
        do { try process.run() } catch { return nil }
        let killed = OSAllocatedUnfairLock(initialState: false)
        let watchdog = DispatchWorkItem {
            guard process.isRunning else { return }
            killed.withLock { $0 = true }
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        exited.wait()
        watchdog.cancel()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "", killed.withLock { $0 })
    }

    /// A command's own words as one short log detail; nil when it said nothing. Errors often come
    /// as JSON on stderr, which the log line carries as it is.
    static func detail(_ output: String?) -> String? {
        let text = (output ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(200))
    }
}
