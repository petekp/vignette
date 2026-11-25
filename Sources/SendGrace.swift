import Foundation

/// The sends whose line has not gone to the client yet, and what each event does to them. It decides
/// and nothing else: `ScreenshotRequests` arms the timers and runs the effects, and the times come in
/// with the events (`ProcessInfo.systemUptime` in the app).
struct SendGrace: Equatable {
    struct Wait: Equatable {
        /// The line the client gets, built at send. Only in memory: it holds the person's message.
        let line: String
        let deadline: TimeInterval
        let length: TimeInterval
        /// Send order, so several sends end in the order they were made.
        let sequence: Int
    }

    /// The sends still in their grace, by request id.
    private(set) var waiting: [String: Wait] = [:]
    private var nextSequence = 0

    enum Event: Equatable {
        case sent(request: String, line: String, grace: TimeInterval, at: TimeInterval)
        /// A timer armed by `.arm` ran.
        case due(request: String, at: TimeInterval)
        /// Don't send, or the screenshot left the folder: the requests it takes back.
        case cancelled(requests: [String])
        /// A clear took the request: `requests?clear=` or the admission of a fiftyfirst.
        case cleared(request: String)
        case quit
    }

    enum Effect: Equatable {
        case arm(request: String, after: TimeInterval)
        /// Hand the line to the client. `waited` is the grace it waited out, nil for a send with none.
        case submit(request: String, line: String, waited: TimeInterval?)
        /// The person cancelled: clear the request and tell the card.
        case discard(request: String)
        /// A clear took it: tell the card, and do not clear again.
        case dropped(request: String)
    }

    mutating func handle(_ event: Event) -> [Effect] {
        switch event {
        case .sent(let request, let line, let grace, let at):
            // No grace: nothing is kept, the line goes at once.
            guard grace > 0 else { return [.submit(request: request, line: line, waited: nil)] }
            waiting[request] = Wait(line: line, deadline: at + grace, length: grace, sequence: nextSequence)
            nextSequence += 1
            return [.arm(request: request, after: grace)]
        case .due(let request, let at):
            // A timer for a request that is no longer waiting is stale and does nothing.
            guard let wait = waiting[request] else { return [] }
            // The deadline never moves: a timer that runs early arms again for what is left.
            guard at >= wait.deadline else { return [.arm(request: request, after: wait.deadline - at)] }
            waiting[request] = nil
            return [.submit(request: request, line: wait.line, waited: wait.length)]
        case .cancelled(let requests):
            // Every one still waiting, so no earlier send goes out unseen. None means the line was
            // handed over already, which a cancel cannot take back.
            let ids = ordered(among: Set(requests))
            for id in ids { waiting[id] = nil }
            return ids.map { .discard(request: $0) }
        case .cleared(let request):
            guard waiting.removeValue(forKey: request) != nil else { return [] }
            return [.dropped(request: request)]
        case .quit:
            // Quitting is not a retraction: every waiting send goes now.
            let all = ordered(among: nil)
            let effects = all.compactMap { id in waiting[id].map { Effect.submit(request: id, line: $0.line, waited: $0.length) } }
            waiting = [:]
            return effects
        }
    }

    func wait(of request: String) -> Wait? { waiting[request] }

    /// The waiting requests, in send order, among `requests` or of all of them.
    private func ordered(among requests: Set<String>?) -> [String] {
        waiting.filter { requests?.contains($0.key) ?? true }.sorted { $0.value.sequence < $1.value.sequence }.map(\.key)
    }
}
