import Foundation

// MARK: Don't send

extension ScreenshotRequests {
    /// Don't send, on `file`'s card or by URL: takes back the send the card shows. Every send of
    /// `file` still in its grace is cancelled, since the card shows only the newest and an older one
    /// would go out unseen. A line a session's queue holds is taken out only when it is the send the
    /// card's tab names (`queuedSend(of:)`) and no send in its grace is newer, so the line of an
    /// earlier send, to this session or another, stays. Answers the requests it cancelled or is taking
    /// back, and nothing when none was waiting: the session has the line already, or there was no send.
    @discardableResult
    func unsend(file: ScreenshotKey) -> [Record] {
        let waiting = sends(of: file).filter { grace(of: $0.id) != nil }
        let cancelled = cancelInGrace(waiting.map(\.id))
        guard let queued = queuedRequest(of: file), waiting.allSatisfy({ $0.created < queued.created }),
              let withdrawing = withdraw(queued.id) else { return cancelled }
        return cancelled + [withdrawing]
    }

    /// Don't send on one send, a live ink note's: cancels it in its grace, or takes its line out of
    /// the session's queue.
    @discardableResult
    func unsend(request id: String) -> Record? {
        cancelInGrace([id]).first ?? withdraw(id)
    }

    /// The file left the watch folder: every send of it still in its grace is cancelled, and every
    /// line of it a session's queue holds is taken back out.
    @discardableResult
    func unsendEverySend(of file: ScreenshotKey) -> [Record] {
        let sent = sends(of: file).map(\.id)
        return cancelInGrace(sent) + sent.compactMap(withdraw)
    }

    /// Every request sent of `file`, oldest first.
    private func sends(of file: ScreenshotKey) -> [Record] {
        requests.values.filter { sourceKey(of: $0) == file }.sorted { $0.created < $1.created }
    }
}
