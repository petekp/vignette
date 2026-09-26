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
    /// given a `title`, the searches that find the thread the Codex app shows under it, whatever its
    /// age (`searchTerms`). `initialized` is a notification and takes no id. Every listing reads the
    /// store's state database only (`useStateDbOnly`): the five used last took 0.06 s instead of 0.13
    /// to 0.26 s, and a search 0.06 s instead of 3.25 s (measured 2026-09-25).
    static func discoveryRequests(limit: Int = listLimit, title: String? = nil) -> [String] {
        var lines = [
            #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"Vignette","version":"\#(BuildInfo.current.version)"}}}"#,
            #"{"method":"initialized"}"#,
            listing(id: listingID, ["limit": limit]),
        ]
        for (id, term) in zip(searchIDs, searchTerms(for: title ?? "")) {
            lines.append(listing(id: id, ["limit": searchLimit, "searchTerm": term]))
        }
        return lines
    }

    /// The id of the listing's answer, and the ids of the searches' answers, one per search term.
    static let listingID = 2
    static let searchIDs = 3...5

    /// How many threads each search asks for. Every thread of 144 was among the first ten its terms
    /// found (measured 2026-09-25).
    static let searchLimit = 10

    /// What to search the store for to find the thread the Codex app shows under `title`: the title,
    /// and its two longest words. The store searches a thread's name, or for a thread with none its
    /// first message as it was typed. The app's title is that text with its markdown and tags taken
    /// out and its lines joined, cut at 80 characters with an ellipsis. So the title alone, without
    /// the ellipsis, found 83 of 144 threads, and with its two longest words all 144 (measured
    /// 2026-09-25). A word finds other threads too; `CodexConnection` keeps only the one the title
    /// names.
    static func searchTerms(for title: String) -> [String] {
        var whole = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if whole.hasSuffix("…") { whole = String(whole.dropLast()).trimmingCharacters(in: .whitespaces) }
        guard !whole.isEmpty else { return [] }
        let words = whole.split(separator: " ")
            .map { $0.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols)) }
            .filter { $0.count >= 4 }
        var terms = [whole]
        // Longest first, and in the title's order among words of one length, so the terms are stable.
        for word in words.enumerated().sorted(by: { ($0.element.count, $1.offset) > ($1.element.count, $0.offset) }).map(\.element)
        where terms.count < 3 && !terms.contains(word) {
            terms.append(word)
        }
        return terms
    }

    private static func listing(id: Int, _ params: [String: Any]) -> String {
        let request: [String: Any] = ["id": id, "method": "thread/list",
                                      "params": params.merging(["sortKey": "recency_at", "useStateDbOnly": true]) { a, _ in a }]
        let data = (try? JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// The threads in the listing's answer, in the order the server gave them.
    static func threads(in lines: [String]) -> [Thread] { threads(in: lines, answering: [listingID]) }

    /// The threads the searches found, in the order of their terms, each kept once.
    static func searched(in lines: [String]) -> [Thread] { threads(in: lines, answering: Array(searchIDs)) }

    /// The threads in the answers with these ids. Anything that is not one of those answers is
    /// ignored, so a notification arriving mid-conversation is not an error. A repeated id is kept
    /// once: the store's pages can overlap, and two searches can find one thread. An ephemeral thread
    /// and a sub-agent's thread (one with a `parentThreadId`) are left out: neither is a session a
    /// person sends to.
    private static func threads(in lines: [String], answering ids: [Int]) -> [Thread] {
        var found: [Thread] = []
        var seen = Set<String>()
        let answers: [(id: Int, list: [[String: Any]])] = lines.compactMap { line in
            guard let data = line.data(using: .utf8),
                  let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let id = message["id"] as? Int, ids.contains(id),
                  let result = message["result"] as? [String: Any],
                  let list = result["data"] as? [[String: Any]] else { return nil }
            return (id, list)
        }
        for (_, list) in answers.sorted(by: { $0.id < $1.id }) {
            for item in list {
                guard let id = item["id"] as? String, let cwd = item["cwd"] as? String,
                      !seen.contains(id) else { continue }
                if item["ephemeral"] as? Bool == true { continue }
                if let parent = item["parentThreadId"] as? String, !parent.isEmpty { continue }
                seen.insert(id)
                found.append(Thread(id: id, name: item["name"] as? String, cwd: cwd,
                                    recencyAt: (item["recencyAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) },
                                    preview: item["preview"] as? String))
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
