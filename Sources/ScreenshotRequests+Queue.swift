import Foundation

// MARK: A line in a session's queue

extension ScreenshotRequests {
    func lookAgain(_ id: String) {
        guard let watch = queueWatches[id] else { return }
        schedule(watch.nextLook(at: now())) { [weak self] in self?.look(id, at: watch.line) }
    }

    /// Asks the connection where the line is, off the main thread.
    private func look(_ id: String, at line: QueuedLine) {
        guard queueWatches[id]?.line == line, let record = requests[id], let connection = connections[record.address.client] else { return }
        DispatchQueue.global(qos: .utility).async {
            // The line names its request's folder, so only this send's line holds the id.
            let state = connection.look(at: line, carrying: id) ?? .unread(detail: "\(connection.client.label) has no queue")
            DispatchQueue.main.async { MainActor.assumeIsolated { self.looked(id, line, state) } }
        }
    }

    private func looked(_ id: String, _ line: QueuedLine, _ state: QueuedLine.State) {
        guard var watch = queueWatches[id], watch.line == line, let record = requests[id] else { return }
        // Don't send's own answer says what became of the line.
        if watch.withdrawing { return lookAgain(id) }
        let effect = watch.look(state, at: now())
        queueWatches[id] = watch
        switch effect {
        case .wait:
            lookAgain(id)
        case .logUnread(let detail):
            Log.write("[send] queue unread \(id) line=\(line.id): \(detail)")
            lookAgain(id)
        case .show(let hold):
            Log.write("[send] queued \(id) \(record.destinationName) line=\(line.id) \(hold.forLog)")
            callbacks.queueChanged(record)
            lookAgain(id)
        case .taken(let wasShown):
            queueWatches[id] = nil
            Log.write("[send] taken \(id) \(record.destinationName) line=\(line.id) after=\(Int((now() - watch.queued) * 1000))ms")
            if wasShown { callbacks.queueChanged(record) }
        case .removed:
            queueWatches[id] = nil
            Log.write("[send] removed in session \(id) line=\(line.id)")
            forgetSent(record)
            do { _ = try clear(id) }
            catch { Log.write("[send] error \(CommandError.writeFailed.rawValue) could not clear \(id): \(error.localizedDescription)") }
            callbacks.queueChanged(requests[id] ?? record)
        case .threadGone(let detail):
            queueWatches[id] = nil
            let failed = recordOutcome(.destinationChanged(detail: "line=\(line.id) \(detail)", reason: Self.threadGoneReason), for: id) ?? record
            callbacks.laterAnswer(failed, .failed, Self.threadGoneReason)
            callbacks.queueChanged(failed)
        }
    }

    /// The card's tab names the last send that reached its client, and a line taken back out never did:
    /// the tab goes back to the newest other send of the file that reached its client, or goes.
    private func forgetSent(_ record: Record) {
        let source = sourceKey(of: record)
        guard Agent.sent(of: source.url)?.address == record.address else { return }
        let others = requests.values.filter { $0.id != record.id && $0.status == .submitted && sourceKey(of: $0) == source }
        if let earlier = others.max(by: { $0.created < $1.created }) { Agent.record(sent: earlier.sent, on: source.url) }
        else { Agent.forgetSent(on: source.url) }
    }

    static let threadGoneReason = "Codex can't find this thread. You can send it to another one."

    /// Don't send on a line a session's queue holds: takes it out, off the main thread.
    func withdraw(_ id: String) -> Record? {
        guard var watch = queueWatches[id], !watch.withdrawing, let record = requests[id],
              let connection = connections[record.address.client] else { return nil }
        watch.withdrawing = true
        queueWatches[id] = watch
        let line = watch.line
        Log.write("[send] withdrawing \(id) line=\(line.id)")
        callbacks.withdrawing(record)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = connection.withdraw(line)
            DispatchQueue.main.async { MainActor.assumeIsolated { self.withdrew(id, line, result) } }
        }
        return record
    }

    private func withdrew(_ id: String, _ line: QueuedLine, _ result: QueuedLine.Withdrawal) {
        guard queueWatches[id]?.line == line, let record = requests[id] else { return }
        switch result {
        case .removed:
            queueWatches[id] = nil
            Log.write("[send] withdrawn \(id) line=\(line.id)")
            forgetSent(record)
            do { _ = try clear(id) }
            catch { Log.write("[send] error \(CommandError.writeFailed.rawValue) could not clear \(id): \(error.localizedDescription)") }
        case .alreadyTaken:
            queueWatches[id] = nil
            Log.write("[send] withdraw \(id) line=\(line.id): already taken")
            callbacks.laterAnswer(record, .sent, QueuedLine.Withdrawal.alreadyTakenReason)
        case .failed(let detail):
            queueWatches[id]?.withdrawing = false
            Log.write("[send] error \(CommandError.sendFailed.rawValue) withdraw \(id) line=\(line.id): \(detail)")
            callbacks.laterAnswer(record, .queued, QueuedLine.Withdrawal.refusedReason)
            lookAgain(id)
        }
        callbacks.queueChanged(requests[id] ?? record)
    }

    /// The reason the card shows for a line a session's queue holds, nil once the session took it.
    func queued(_ request: String) -> String? {
        queueWatches[request]?.shown
    }

    /// What the tab of `file`'s card says about its last send while Codex holds that send's line, nil
    /// when the session has the line or the last send was not queued. The tab names the last send that
    /// reached its client (`Agent.Sent`), so a failed send after a queued one leaves it queued.
    func queuedSend(of file: ScreenshotKey) -> Card.Queued? {
        guard let last = queuedRequest(of: file), let watch = queueWatches[last.id], let reason = watch.shown else { return nil }
        return Card.Queued(reason: reason, withdrawing: watch.withdrawing)
    }

    /// The send `queuedSend(of:)` is about: the newest send of `file` to the session its tab names
    /// (`Agent.sent(of:)`), while that session's queue is said to hold its line. Answers can come
    /// back out of order, so the tab, not the newest send, says which one it is.
    func queuedRequest(of file: ScreenshotKey) -> Record? {
        guard queueWatches.keys.contains(where: { requests[$0].map(sourceKey(of:)) == file }),
              let tab = Agent.sent(of: file.url) else { return nil }
        let named = requests.values.filter { $0.status == .submitted && sourceKey(of: $0) == file && $0.address == tab.address }
        guard let last = named.max(by: { $0.created < $1.created }), queueWatches[last.id]?.shown != nil else { return nil }
        return last
    }
}
