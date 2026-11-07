import AppKit

// MARK: Send and Reply

extension AnnotationController {
    /// A new image opened: `replyTo` is the session it came from, when it names one, and the list
    /// of sessions is on its way. Read once per image: the list comes from subprocesses, and a menu
    /// that re-read it on every click would stall the bar.
    func beginDestinations(replyTo: AgentDestination?) {
        toolbar.model.begin(replyTo: replyTo, carryingTarget: toolbar.model.shown)
        logOffer(was: nil)
    }

    /// Another client answered with its sessions, and the pick made from them.
    func destinationsAnswered(_ answer: DestinationChoice.Answer) {
        let before = toolbar.model.offer.destination?.id
        toolbar.model.answered(answer)
        logOffer(was: before)
    }

    /// Logs where the bar's filled button sends, whenever that changes: the card's own session for a
    /// Reply, else the target. `reply` marks the first, since the target is then not on the bar.
    private func logOffer(was before: String?) {
        let offer = toolbar.model.offer
        guard let to = offer.destination, to.id != before else { return }
        Log.write("[send] target \(to.address.description) project=\(to.detail) focus=\(to.focus?.rawValue ?? "none")\(offer.isSend ? "" : " reply")")
    }

    /// Return and Cmd+Return do what the bar offers, and a message field that arrived with the
    /// session list may take the keys.
    func offerChanged(_ offer: ToolbarOffer) {
        editor.finishes = offer.finishes
        offerTyping()
    }

    /// True from Send's press until the bar leaves; the button shows the send and takes no second
    /// click. `prepare` resets it.
    var sending: Bool {
        get { toolbar.model.sending }
        set { toolbar.model.sending = newValue }
    }

    /// The send failed before its request was stored, so the drawing is still here: the button says
    /// so, with `reason` beside it, until the person moves on.
    func sendFailed(_ reason: String) { toolbar.model.sendFailed(reason) }
}
