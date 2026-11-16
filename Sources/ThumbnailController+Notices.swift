import AppKit

extension ThumbnailController {
    /// The request for `shot` is stored and its card is going home: the card shows where it is going
    /// from the moment it lands, calling the session `title`.
    func showSending(_ shot: Screenshot, request: String, to destination: AgentDestination, titled title: String, grace: SendNotice.Grace? = nil) {
        post(.sending(request: request, client: destination.client, sessionTitle: title, grace: grace,
                      starts: destination.startsProcess), on: shot)
    }

    /// The grace of the send `request` ended and its line is going to the client.
    func released(_ shot: Screenshot, request: String) {
        post(.released(request: request), on: shot)
    }

    /// The send `request` was cancelled before its line went. Its notice goes and the card is as it
    /// was; a lone thumbnail that stayed for the grace leaves after the usual hold.
    func cancelled(_ shot: Screenshot, request: String) {
        post(.cancelled(request: request), on: shot)
        if isSeen(shot) { leaveCorner(after: ui.markSeconds + ui.expandDuration) }
    }

    /// The client answered for the request `request` about `shot`. A card no longer on screen says
    /// nothing more about a delivery that worked, and comes back as a lone thumbnail about any other.
    func delivered(_ shot: Screenshot, request: String, _ state: SendNotice.State, reason: String?) {
        post(.answered(request: request, state: state, reason: reason), on: shot)
    }

    /// The session's turn on the live ink note `shot` ended with nothing to show as a result card.
    /// A card not on screen comes up as the lone thumbnail to say it, as a result card would, unless
    /// `quietly`: it then says it in place, and a card off screen stays off.
    func finished(_ shot: Screenshot, request: String, in destination: AgentDestination, titled title: String, quietly: Bool = false) {
        post(.finished(request: request, client: destination.client, sessionTitle: title), on: shot, comesUp: !quietly)
    }

    /// A reply to a send could not be made a card, so the card that was sent says so, as it says a
    /// failed send.
    func replyFailed(_ shot: Screenshot, request: String, client: AgentClient, reason: String) {
        post(.replyFailed(request: request, client: client, reason: reason), on: shot)
    }
}
