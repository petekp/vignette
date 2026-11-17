import Foundation
import os

/// The Codex app-server's JSON-RPC, spoken over a child process's standard input and output.
/// `thread/list` reads the thread store on disk, so a server started here for the length of one
/// listing answers for every session, whoever owns it.
///
/// What it asks of the person's own Codex home only reads, but for one call: it takes a line Vignette
/// queued out of the queue when the person asks (`withdrawRequests`). It never starts a thread, sends
/// a turn, or changes anything else a session holds. Live ink's responder and its sign-in talk to a server in
/// Vignette's own Codex home, through `AppServerSession` and `logoutRequests`.
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
        /// When the thread was created: the listing's `createdAt`.
        var createdAt: Date? = nil
        /// The remote the thread's repository was cloned from, `gitInfo.originUrl`.
        var originURL: String? = nil
    }

    /// The request lines for one discovery: the handshake, the listing of the threads used last, and
    /// a read of each thread in `ids`, which finds it whatever its age. The reads are numbered from
    /// `readID`, in order. `initialized` is a notification and takes no id. The listing reads the
    /// store's state database only (`useStateDbOnly`): the five used last took 0.06 s instead of 0.13
    /// to 0.26 s (measured 2026-09-25).
    static func discoveryRequests(limit: Int = listLimit, reading ids: [String] = []) -> [String] {
        handshake + [request(id: listingID, "thread/list", ["limit": limit, "sortKey": "recency_at", "useStateDbOnly": true])]
            + ids.enumerated().map { request(id: readID + $0.offset, "thread/read", ["threadId": $0.element]) }
    }

    /// The request lines for a read of one thread, which names its rollout file.
    static func readRequests(_ thread: String) -> [String] {
        handshake + [request(id: readID, "thread/read", ["threadId": thread])]
    }

    /// The request lines for Codex's logout in the home the server runs in, which also revokes the
    /// sign-in's tokens with OpenAI.
    static var logoutRequests: [String] {
        handshake + [request(id: 2, "account/logout", nil)]
    }

    /// The request lines for a look at a thread's queue and a read of the thread, which names its
    /// rollout. The queue calls are experimental in 0.169 and answer only a client that asks for
    /// `experimentalApi`.
    static func queueRequests(_ thread: String) -> [String] {
        experimentalHandshake + [request(id: queueID, "thread/queue/list", ["threadId": thread, "limit": queueLimit]),
                                 request(id: readID, "thread/read", ["threadId": thread])]
    }

    /// The request lines that take one line out of a thread's queue, by the id `codex queue` printed.
    /// It is the one call here that changes what a session holds, and only a line Vignette put there.
    static func withdrawRequests(_ line: QueuedLine) -> [String] {
        experimentalHandshake + [request(id: queueID, "thread/queue/delete", ["threadId": line.thread, "queuedSubmissionId": line.id])]
    }

    /// What Vignette says of itself in `initialize`, here and in an `AppServerSession`.
    static var initializeParams: [String: Any] {
        ["clientInfo": ["name": "Vignette", "version": BuildInfo.current.version]]
    }

    private static var handshake: [String] {
        [request(id: 1, "initialize", initializeParams), #"{"method":"initialized"}"#]
    }

    private static var experimentalHandshake: [String] {
        var params = initializeParams
        params["capabilities"] = ["experimentalApi": true]
        return [request(id: 1, "initialize", params), #"{"method":"initialized"}"#]
    }

    /// The id of the listing's answer, and of the first read's.
    static let listingID = 2
    static let readID = 3
    /// The id of a queue call's answer.
    static let queueID = 2
    /// How many queued lines one look asks for. A thread's queue holds what was sent while it was
    /// busy, a handful at most.
    static let queueLimit = 200

    /// What a look at a thread's queue found.
    enum QueueAnswer: Equatable {
        /// The ids of the lines the queue holds, in order. `more`: the queue has lines past these.
        case listed([String], more: Bool)
        /// The server refused the call, in its own words.
        case refused(String)
        /// No answer arrived.
        case none
    }

    /// The answer to `queueRequests`' look at the queue.
    static func queue(in lines: [String]) -> QueueAnswer {
        if let refusal = refusal(queueID, in: lines) { return .refused(refusal) }
        guard let result = answer(queueID, in: lines), let items = result["data"] as? [[String: Any]] else { return .none }
        let more = result["nextCursor"] as? String != nil
        return .listed(items.compactMap { $0["id"] as? String }, more: more)
    }

    /// The answer to `withdrawRequests`: whether the queue had the line and removed it.
    static func withdrawal(in lines: [String]) -> Result<Bool, QueueRefusal> {
        if let refusal = refusal(queueID, in: lines) { return .failure(QueueRefusal(message: refusal)) }
        guard let deleted = answer(queueID, in: lines)?["deleted"] as? Bool else { return .failure(QueueRefusal(message: "no answer")) }
        return .success(deleted)
    }

    struct QueueRefusal: Error, Equatable {
        let message: String
    }

    private static func request(id: Int, _ method: String, _ params: [String: Any]?) -> String {
        var request: [String: Any] = ["id": id, "method": method]
        request["params"] = params
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

    /// The threads the reads of `ids` found, in the order of `ids`. A read the server refused, as it
    /// does a thread that is not in the store, or that answered another thread, finds none.
    static func reads(of ids: [String], in lines: [String]) -> [Thread] {
        ids.enumerated().compactMap { index, id in
            (answer(readID + index, in: lines)?["thread"] as? [String: Any]).flatMap(thread).flatMap { $0.id == id ? $0 : nil }
        }
    }

    /// The rollout file the read found, the thread's `path`, which 0.165 still marks unstable.
    static func rolloutPath(in lines: [String]) -> CodexTurns.Path {
        guard let thread = answer(readID, in: lines)?["thread"] as? [String: Any] else { return .unknown }
        guard let path = thread["path"] as? String, !path.isEmpty else { return .unnamed }
        return .at(path)
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

    /// The message of the error the server answered the request with this id, if it refused it.
    private static func refusal(_ id: Int, in lines: [String]) -> String? {
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  message["id"] as? Int == id, let error = message["error"] else { continue }
            return (error as? [String: Any])?["message"] as? String ?? "refused"
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
                      preview: item["preview"] as? String,
                      createdAt: (item["createdAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) },
                      originURL: (item["gitInfo"] as? [String: Any])?["originUrl"] as? String)
    }

    /// Writes every request, reads until each one that carries an id has been answered, and ends
    /// the process. Standard input stays open until then: the server exits on EOF, and a batch
    /// written with the pipe already closed is answered only as far as `initialize` (measured).
    /// Returns whatever lines arrived, so a partial conversation still yields what it got.
    /// `environment` is added to the app's own, as `Subprocess.run` adds it.
    static func converse(_ binary: String, _ arguments: [String], _ requests: [String],
                         timeout: TimeInterval = AppServer.timeout, environment: [String: String] = [:]) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.environment = Subprocess.environment(for: binary, adding: environment)
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        // Writing to a process that has gone would otherwise end Vignette with SIGPIPE.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
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
