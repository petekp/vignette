import Foundation
import os

/// The Codex app-server's JSON-RPC, spoken over a child process's standard input and output.
/// `thread/list` reads the thread store on disk, so a server started here for the length of one
/// listing answers for every session, whoever owns it.
///
/// This is the only thing in the app that knows the app-server protocol. It reads; it never starts
/// a thread, sends a turn, or changes anything a session holds.
enum AppServer {
    /// How many threads discovery asks for, the ones used last. The store's list call costs about
    /// 0.12 s for five, 0.50 s for fifteen, and 2.9 s for thirty (measured 2026-09-21); a whole
    /// discovery took 0.15 s for five and 0.89 s for fifteen (2026-09-25). Send's menu shows five
    /// sessions, and a thread older than the five used last is rarely the one being sent to.
    static let listLimit = 5

    /// How long the whole conversation may take before the process is ended and whatever arrived
    /// is used. Longer than the measured list call, short enough that the Send button is not
    /// waiting on it.
    static let timeout: TimeInterval = 8

    /// One session the server knows about. `cwd` is its project. The listing's `status` is not
    /// kept: it is what the answering server holds in memory, and a server started for one listing
    /// holds nothing, so it says nothing about the session's real state.
    struct Thread: Equatable {
        let id: String
        let name: String?
        let cwd: String
        /// When the thread was last used: the listing's `recencyAt`, in seconds since 1970.
        var recencyAt: Date? = nil
        /// The thread's first message, which names a thread that has no name.
        var preview: String? = nil
    }

    /// The request lines for one discovery: the handshake, the listing of the threads used last, and,
    /// given `shown`, a read of that thread, which finds it whatever its age. `initialized` is a
    /// notification and takes no id. The listing reads the store's state database only
    /// (`useStateDbOnly`): the five used last took 0.06 s instead of 0.13 to 0.26 s (measured
    /// 2026-09-25).
    static func discoveryRequests(limit: Int = listLimit, shown: String? = nil) -> [String] {
        var lines = [
            #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"Vignette","version":"\#(BuildInfo.current.version)"}}}"#,
            #"{"method":"initialized"}"#,
            request(id: listingID, "thread/list", ["limit": limit, "sortKey": "recency_at", "useStateDbOnly": true]),
        ]
        if let shown { lines.append(request(id: readID, "thread/read", ["threadId": shown])) }
        return lines
    }

    /// The id of the listing's answer, and of the read's.
    static let listingID = 2
    static let readID = 3

    private static func request(id: Int, _ method: String, _ params: [String: Any]) -> String {
        let request: [String: Any] = ["id": id, "method": method, "params": params]
        let data = (try? JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// The threads in the listing's answer, in the order the server gave them.
    static func threads(in lines: [String]) -> [Thread] {
        var found: [Thread] = []
        var seen = Set<String>()
        for item in answer(listingID, in: lines)?["data"] as? [[String: Any]] ?? [] {
            guard let thread = thread(item), !seen.contains(thread.id) else { continue }
            seen.insert(thread.id)
            found.append(thread)
        }
        return found
    }

    /// The thread the read found. Nil when there was none, or the server refused it, as it does a
    /// thread that is not in the store.
    static func read(in lines: [String]) -> Thread? {
        (answer(readID, in: lines)?["thread"] as? [String: Any]).flatMap(thread)
    }

    /// The result of the answer with this id. Anything else is ignored, so a notification arriving
    /// mid-conversation is not an error.
    private static func answer(_ id: Int, in lines: [String]) -> [String: Any]? {
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  message["id"] as? Int == id else { continue }
            return message["result"] as? [String: Any]
        }
        return nil
    }

    /// One thread as the server describes it. A repeated id is kept once by the caller: the store's
    /// pages can overlap. An ephemeral thread and a sub-agent's thread (one with a `parentThreadId`)
    /// are nil: neither is a session a person sends to.
    private static func thread(_ item: [String: Any]) -> Thread? {
        guard let id = item["id"] as? String, let cwd = item["cwd"] as? String else { return nil }
        if item["ephemeral"] as? Bool == true { return nil }
        if let parent = item["parentThreadId"] as? String, !parent.isEmpty { return nil }
        return Thread(id: id, name: item["name"] as? String, cwd: cwd,
                      recencyAt: (item["recencyAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) },
                      preview: item["preview"] as? String)
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
        process.environment = Subprocess.environment(for: binary)
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
                    // An error is an answer too, or a request the server refused would hold the
                    // conversation until the timeout.
                    if line.contains("\"id\"") && (line.contains("\"result\"") || line.contains("\"error\"")) { s.answers += 1 }
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
