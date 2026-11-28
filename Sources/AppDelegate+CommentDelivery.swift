import Foundation

// MARK: Comments reaching the screenshot's session as they are posted (ADR 0035)

extension AppDelegate {
    func connectCommentDeliveries() {
        annotator.onPinsChanged = { [weak self] shot, before, after in self?.pinsChanged(on: shot, from: before, to: after) }
        annotator.liveComments = { [weak self] key, pin in self?.liveComments(on: key, pin: pin) ?? PinLiveComments() }
        commentDeliveries.changed = { [weak self] key in self?.annotator.commentDeliveriesChanged(key) }
    }

    /// The session the screenshot last exchanged with (`CommentTarget.last`), from what the file, its
    /// records and its pins keep. Send starts on it, and the pins' comments go to it.
    func lastSession(of key: ScreenshotKey, pins: [Pin]) -> DestinationChoice.LastSession? {
        let opening = annotator.opening
        let showedIt = thumbnail.model.openedShown.flatMap { $0.opening == opening ? $0.session : nil }
        var exchanges = CommentTarget.exchanges(on: pins)
        if let sent = Agent.sent(of: key.url) { exchanges.append(CommentTarget.Exchange(session: sent.address, at: sent.at)) }
        if let reply = requests.replyExchange(of: key.url) { exchanges.append(reply) }
        let last = CommentTarget.last(showedIt: showedIt, exchanges: exchanges, origin: Agent.origin(of: key.url)?.address)
        return last.map { DestinationChoice.LastSession(address: $0, showedIt: $0 == showedIt) }
    }

    /// The person changed the open image's pins: each change goes to its session when one runs, after
    /// the wait Send's lines have (`ui.sendGraceSeconds`).
    private func pinsChanged(on shot: Screenshot, from before: Drawing, to after: Drawing) {
        let changes = CommentChange.between(before.pins, after.pins)
        guard !changes.isEmpty else { return }
        let last = lastSession(of: shot.key, pins: after.pins)?.address
        let running = annotator.runningSessions
        let width = Double(max(after.pixels.width, 1)), height = Double(max(after.pixels.height, 1))
        var stays = 0
        for change in changes {
            let was = before.pins.first { $0.id == change.pin }
            guard let pin = after.pins.first(where: { $0.id == change.pin }) ?? was else { continue }
            guard let destination = CommentTarget.destination(for: pin, last: last, running: running) else {
                stays += 1
                continue
            }
            let known = commentDeliveries.known(on: shot.key, to: destination.address)
            guard CommentTarget.knows(destination.address, change, pin: was ?? pin, delivered: known) else { continue }
            let item = HeldChanges.Item(change: change, number: pin.number,
                                        x: Double(pin.extent.minX) / width, y: Double(pin.extent.minY) / height)
            commentDeliveries.add(item, on: shot.key, to: destination, grace: settings.data.ui.sendGraceSeconds)
        }
        if stays > 0 {
            Log.write("[comments] stay \(shot.key.name) changes=\(stays): \(last.map { "\($0.description) is not running" } ?? "no session")")
        }
    }

    /// What pin `pin`'s popover says about its comments on the image `key`.
    private func liveComments(on key: ScreenshotKey, pin: Pin) -> PinLiveComments {
        var live = PinLiveComments()
        for comment in pin.comments { live.shown[comment.id] = commentDeliveries.shown(comment: comment.id, on: key) }
        if let working = commentDeliveries.working(pin: pin.id, on: key) {
            // An answer on the pin since the line went ends the row, as the turn's end does.
            let since = Date(timeIntervalSince1970: working.since.timeIntervalSince1970.rounded(.down))
            if !pin.comments.contains(where: { $0.agent && ($0.at ?? .distantPast) >= since }) { live.working = working.client }
        }
        return live
    }
}
