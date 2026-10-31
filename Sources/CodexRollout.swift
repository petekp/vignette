import Foundation
import os

/// Where a Codex thread is in its turns, as far as the lines Vignette sent it go, read from the
/// thread's rollout: the JSON lines file the engine that has the thread appends to. It is the one
/// record of a turn's start and end that another process can read (docs/codex-issues.md,
/// 2026-10-25). Pure: `CodexTurns` hands it the file's lines.
///
/// The engine writes `event_msg` lines `task_started`, then `task_complete` or `turn_aborted`, each
/// with the `turn_id`. A queued line becomes a turn of its own and is that turn's user message: a
/// `response_item` message from 0.165, an `event_msg` `user_message` before it. A line this reader
/// does not know how to place makes the rollout unreadable, and its turn then reads as nil, as from
/// a route that cannot tell. So does a turn that shows these events in a changed form: one that ends
/// with no user message it could read while a sent line waits, or a turn that starts while another
/// has not ended.
struct RolloutTurns: Equatable {
    /// The lines sent to the thread that the rollout has not shown as a user message yet.
    private(set) var pending: [String] = []
    /// The turn the rollout last said started and has not said ended; empty when it gave no id.
    private(set) var openTurn: String?
    /// The open turn has a user message this reader could read.
    private var openTurnHeard = false
    /// A sent line's turn started after the last reading said busy. A turn that starts and ends
    /// between two readings still reads busy once, since `TurnWatch` ends a turn only after it.
    private var owesBusy = false
    /// Why the rollout cannot be read, once it is not.
    private(set) var unreadable: String?

    mutating func sent(_ line: String) { pending.append(line) }

    mutating func unsent(_ line: String) {
        if let index = pending.firstIndex(of: line) { pending.remove(at: index) }
    }

    /// One complete line of the rollout. A line that is not JSON is skipped: the first one read
    /// from the middle of a file can be the end of a line.
    mutating func read(_ line: Data) {
        guard unreadable == nil, let entry = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return }
        guard let type = entry["type"] as? String, let payload = entry["payload"] as? [String: Any] else {
            unreadable = "a line with no type and payload"
            return
        }
        switch (type, payload["type"] as? String) {
        case ("event_msg", "task_started"):
            let id = payload["turn_id"] as? String ?? ""
            let root = payload["root_turn_id"] as? String ?? id
            if let open = openTurn, !open.isEmpty, root == id, id != open {
                unreadable = "a turn that started before the last one ended"
                return
            }
            openTurn = id
            openTurnHeard = false
        case ("event_msg", "task_complete"), ("event_msg", "turn_aborted"):
            let ended = payload["turn_id"] as? String
            guard let open = openTurn, ended == nil || open.isEmpty || ended == open else { return }
            if !openTurnHeard, !pending.isEmpty {
                unreadable = "a turn that ended with no user message it could read"
                return
            }
            openTurn = nil
        case ("event_msg", "user_message"):
            took(payload["message"] as? String)
        case ("response_item", "message") where payload["role"] as? String == "user":
            let parts = payload["content"] as? [[String: Any]] ?? []
            took(parts.compactMap { $0["type"] as? String == "input_text" ? $0["text"] as? String : nil }.joined(separator: "\n"))
        default:
            break
        }
    }

    private mutating func took(_ message: String?) {
        if openTurn != nil, !(message ?? "").isEmpty { openTurnHeard = true }
        guard let message, let index = pending.firstIndex(where: { message.contains($0) }) else { return }
        guard openTurn != nil else {
            unreadable = "a sent line outside any turn"
            return
        }
        pending.remove(at: index)
        owesBusy = true
    }

    /// Whether a sent line still waits or its turn runs, which is when the rollout should grow.
    var expectsMore: Bool { !pending.isEmpty || openTurn != nil }

    /// `waiting` while a sent line has not reached the rollout, `busy` while a turn runs after it,
    /// and `idle` after that. Nil once the rollout is unreadable.
    mutating func reading() -> SessionTurn? {
        guard unreadable == nil else { return nil }
        if !pending.isEmpty { return .waiting }
        if openTurn != nil || owesBusy {
            owesBusy = false
            return .busy
        }
        return .idle
    }
}

/// The rollouts of the Codex threads Vignette sent lines to this launch, each read on from where
/// the last reading stopped. One per `CodexConnection`, shared by its copies. Its lock is held while
/// a file is read, never while a server is asked for a path.
final class CodexTurns: Sendable {
    /// How long a rollout may stay the same size while a sent line waits or its turn runs before
    /// the thread's path is asked again, which starts an app-server. A long thread moves on to a new
    /// file, and a thread no engine has loaded may get one when it is opened. Each ask that finds
    /// the same file doubles the wait, up to `staleAfterLongest`, and an engine opening the thread
    /// asks at once.
    static let staleAfter: TimeInterval = 30
    static let staleAfterLongest: TimeInterval = 240

    /// What `thread/read` said of a thread's rollout.
    enum Path: Equatable {
        case at(String)
        /// The server answered with a thread and no `path`, which a build that moved it would do.
        case unnamed
        /// No answer, or no such thread: worth asking again.
        case unknown
    }

    private struct Watch {
        var turns = RolloutTurns()
        var path: String?
        var offset: UInt64 = 0
        /// The end of a line the writer had not finished when the file was last read.
        var partial = Data()
        var grew: Date
        var asked: Date
        /// How long after `asked` the path is asked again, from `staleAfter` to `staleAfterLongest`.
        var askAfter = CodexTurns.staleAfter
        /// Whether an engine had the thread loaded when it was last looked at.
        var loaded: Bool
        var logged = false
        /// The open turn that has been said to be quiet for `TurnWatch.workingLimit`.
        var quietTurn: String?

        /// Reads what was added since the last reading. Answers whether to ask for the path again:
        /// there is none to read, the file has gone or shrunk, or it has stopped growing while a line
        /// waits or its turn runs, each once `askAfter` has passed; or an engine has just opened the
        /// thread.
        mutating func readOn(at now: Date, loaded: Bool) -> Bool {
            let opened = loaded && !self.loaded
            self.loaded = loaded
            guard let path, !path.hasSuffix(".zst"),
                  let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? UInt64,
                  size >= offset else { return opened || now.timeIntervalSince(asked) >= askAfter }
            if size > offset, let file = FileHandle(forReadingAtPath: path) {
                defer { try? file.close() }
                try? file.seek(toOffset: offset)
                let chunk = (try? file.read(upToCount: Int(size - offset))) ?? Data()
                offset += UInt64(chunk.count)
                partial.append(chunk)
                if let end = partial.lastIndex(of: UInt8(ascii: "\n")) {
                    for line in partial[..<end].split(separator: UInt8(ascii: "\n")) { turns.read(Data(line)) }
                    partial = Data(partial[partial.index(after: end)...])
                }
                if !chunk.isEmpty {
                    grew = now
                    askAfter = CodexTurns.staleAfter
                }
            }
            let quiet = now.timeIntervalSince(grew) >= CodexTurns.staleAfter && now.timeIntervalSince(asked) >= askAfter
            return turns.expectsMore && (opened || quiet)
        }

        mutating func move(to found: Path, at now: Date) {
            asked = now
            switch found {
            case .at(let new) where new != path:
                path = new
                offset = 0
                partial = Data()
                askAfter = CodexTurns.staleAfter
            case .unnamed:
                path = nil
                turns = RolloutTurns(unreadable: "thread/read gave no path")
            case .at, .unknown:
                askAfter = min(askAfter * 2, CodexTurns.staleAfterLongest)
            }
        }
    }

    private let watches = OSAllocatedUnfairLock(initialState: [String: Watch]())
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    /// `line` is going to `thread`, whose rollout `thread/read` found just before, and which an engine
    /// had `loaded` or not then. A thread already
    /// watched is read on from where it stopped, or from the start of a file it moved to, which can
    /// hold the turn of a line sent earlier. A thread not watched yet is read from the file's end as
    /// it is now, or from its start when the file is not there yet.
    func sending(_ line: String, to thread: String, rollout: Path, loaded: Bool) {
        let time = now()
        watches.withLock { watches in
            let watched = watches[thread] != nil
            var watch = watches[thread] ?? Watch(grew: time, asked: time, loaded: loaded)
            if case .at(let path) = rollout, path != watch.path {
                watch.path = path
                watch.offset = watched ? 0 : (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? UInt64 ?? 0
                watch.partial = Data()
            } else if rollout == .unnamed {
                watch.move(to: .unnamed, at: time)
            }
            watch.turns.sent(line)
            watch.grew = time
            watch.asked = time
            watch.askAfter = CodexTurns.staleAfter
            watch.loaded = loaded
            watches[thread] = watch
        }
    }

    /// A line that did not reach the thread.
    func unsent(_ line: String, to thread: String) {
        watches.withLock { $0[thread]?.turns.unsent(line) }
    }

    /// Where `thread` is in its turns, or nil when no line went to it this launch or its rollout
    /// cannot be read. `loaded` says whether an engine has the thread now, and `path` asks a server
    /// for the rollout, outside the lock. It reads files, so it never runs on the main thread.
    func turn(of thread: String, loaded: (String) -> Bool, path: (String) -> Path) -> SessionTurn? {
        let time = now()
        let isLoaded = loaded(thread)
        let asks = watches.withLock { watches -> Bool in
            guard var watch = watches[thread] else { return false }
            defer { watches[thread] = watch }
            return watch.readOn(at: time, loaded: isLoaded)
        }
        if asks {
            let found = path(thread)
            watches.withLock { watches in
                guard var watch = watches[thread] else { return }
                watch.move(to: found, at: time)
                _ = watch.readOn(at: time, loaded: isLoaded)
                watches[thread] = watch
            }
        }
        return watches.withLock { watches -> SessionTurn? in
            guard var watch = watches[thread] else { return nil }
            defer { watches[thread] = watch }
            if let reason = watch.turns.unreadable, !watch.logged {
                watch.logged = true
                Log.write("[live-ink] codex rollout of \(thread) unreadable: \(reason); its turn is not watched")
            }
            // A turn can work for many minutes without writing, so a quiet one is still waited on.
            if let open = watch.turns.openTurn, open != watch.quietTurn, time.timeIntervalSince(watch.grew) >= TurnWatch.workingLimit {
                watch.quietTurn = open
                Log.write("[live-ink] codex rollout of \(thread): a turn has written nothing for \(Int(TurnWatch.workingLimit))s; "
                          + "if it ended, its end is in a form this build does not read")
            }
            return watch.turns.reading()
        }
    }
}

private extension RolloutTurns {
    init(unreadable reason: String) {
        self.init()
        unreadable = reason
    }
}
