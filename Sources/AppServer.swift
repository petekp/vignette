import Foundation
import os

/// The Codex app-server's JSON-RPC, spoken over a child process's standard input and output.
/// `thread/list` reads the thread store on disk, so a server started here for the length of one
/// listing sees every session, whoever owns it. `codex app-server proxy --sock <path>` bridges the
/// same stdio to a server already running, which is cheaper when there is one; the conversation is
/// identical either way.
///
/// This is the only thing in the app that knows the app-server protocol. It reads; it never starts
/// a thread, sends a turn, or changes anything a session holds.
enum AppServer {
    /// Where a running app-server publishes its control socket. Present means one is already up and
    /// the proxy can ask it; absent means discovery starts its own, which answers the same listing.
    static var controlSocket: URL {
        URL(fileURLWithPath: ("~/.codex/app-server-control/app-server-control.sock" as NSString).expandingTildeInPath)
    }

    static var controlSocketExists: Bool {
        (try? controlSocket.resourceValues(forKeys: [.isRegularFileKey])) != nil
            || FileManager.default.fileExists(atPath: controlSocket.path)
    }

    /// How many threads discovery asks for, newest first. The store's list call costs about 0.12 s
    /// for five, 0.50 s for fifteen, and 2.9 s for thirty (measured 2026-09-21), and this runs
    /// every time an image opens. A menu longer than this is not one a person reads anyway.
    static let listLimit = 15

    /// How long the whole conversation may take before the process is ended and whatever arrived
    /// is used. Longer than the measured list call, short enough that the Send button is not
    /// waiting on it.
    static let timeout: TimeInterval = 8

    /// One session the server knows about. `cwd` is the project the menu groups by; `loaded` is
    /// whether the server has it in memory, which is per server: a process of our own reports
    /// every thread `notLoaded` because it has just started.
    struct Thread: Equatable {
        let id: String
        let name: String?
        let cwd: String
        let loaded: Bool
    }

    /// The request lines for one discovery: the handshake, then the listing. `initialized` is a
    /// notification and takes no id, so only two answers are ever waited for.
    static func discoveryRequests(limit: Int = listLimit) -> [String] {
        [
            #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"Vignette","version":"\#(BuildInfo.current.version)"}}}"#,
            #"{"method":"initialized"}"#,
            #"{"id":2,"method":"thread/list","params":{"limit":\#(limit)}}"#,
        ]
    }

    /// The threads in an answer to `thread/list`, in the order the server gave them. Anything that
    /// is not that answer is ignored, so a notification arriving mid-conversation is not an error.
    /// A repeated id is kept once: the store's pages can overlap.
    static func threads(in lines: [String]) -> [Thread] {
        var found: [Thread] = []
        var seen = Set<String>()
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  message["id"] as? Int == 2,
                  let result = message["result"] as? [String: Any],
                  let list = result["data"] as? [[String: Any]] else { continue }
            for item in list {
                guard let id = item["id"] as? String, let cwd = item["cwd"] as? String,
                      !seen.contains(id) else { continue }
                seen.insert(id)
                let status = (item["status"] as? [String: Any])?["type"] as? String
                found.append(Thread(id: id, name: item["name"] as? String, cwd: cwd,
                                    loaded: status != nil && status != "notLoaded"))
            }
        }
        return found
    }

    /// Writes every request, reads until each one that carries an id has been answered, and ends
    /// the process. Standard input stays open until then: the server exits on EOF, and a batch
    /// written with the pipe already closed is answered only as far as `initialize` (measured).
    /// Returns whatever lines arrived, so a partial conversation still yields what it got.
    static func converse(_ binary: String, _ arguments: [String], _ requests: [String],
                         timeout: TimeInterval = AppServer.timeout) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }

        let wanted = requests.filter { $0.contains("\"id\"") }.count
        let state = OSAllocatedUnfairLock(initialState: (lines: [String](), answers: 0, buffer: Data()))
        let done = DispatchSemaphore(value: 0)
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { done.signal(); return }
            let finished: Bool = state.withLock { s in
                s.buffer.append(chunk)
                while let end = s.buffer.firstIndex(of: UInt8(ascii: "\n")) {
                    let line = String(data: s.buffer[..<end], encoding: .utf8) ?? ""
                    s.buffer.removeSubrange(...end)
                    guard !line.isEmpty else { continue }
                    s.lines.append(line)
                    if line.contains("\"id\"") && line.contains("\"result\"") { s.answers += 1 }
                }
                return s.answers >= wanted
            }
            if finished { done.signal() }
        }
        for request in requests {
            guard let data = (request + "\n").data(using: .utf8) else { continue }
            try? input.fileHandleForWriting.write(contentsOf: data)
        }
        _ = done.wait(timeout: .now() + timeout)
        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        try? input.fileHandleForWriting.close()
        return state.withLock { $0.lines }
    }
}
