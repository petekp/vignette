import AppKit

// MARK: Send and Reply

extension AnnotationController {
    /// A new image opened: `replyTo` is the session it came from, when it names one, and the list
    /// of sessions is on its way. Read once per image: the list comes from subprocesses, and a menu
    /// that re-read it on every click would stall the bar. Answers the kept pick's session, which
    /// this image's listing starts on while it holds.
    func beginDestinations(replyTo: AgentDestination?) -> AgentDestination? {
        toolbar.model.begin(replyTo: replyTo, carryingTarget: toolbar.model.shown)
        logOffer(was: nil)
        if keptPick?.holds(at: Date()) == false { endKeptPick("time") }
        return keptPick?.session
    }

    /// Another client answered with its sessions, and the pick made from them.
    func destinationsAnswered(_ answer: DestinationChoice.Answer) {
        let before = toolbar.model.offer.destination
        toolbar.model.answered(answer)
        logOffer(was: before)
        if answer.keptIsGone { endKeptPick("gone") }
    }

    /// A send from the editor stored its request (`DestinationChoice.KeptPick.after`).
    func sent(to destination: AgentDestination) {
        let now = Date()
        if keptPick?.holds(at: now) == false { endKeptPick("time") }
        let after = DestinationChoice.KeptPick.after(sendTo: destination, isSend: toolbar.model.offer.isSend,
                                                     handPicked: toolbar.model.isHandPick(destination), kept: keptPick, at: now)
        guard after != keptPick else { return }
        keptPick = after
        Log.write("[send] kept \(destination.address.description) project=\(destination.detail)")
    }

    private func endKeptPick(_ reason: String) {
        guard let kept = keptPick else { return }
        keptPick = nil
        Log.write("[send] kept ended \(kept.session.address.description) reason=\(reason)")
    }

    /// Logs where the bar's filled button sends, why, and its terminal's role, whenever one changes:
    /// the card's own session for a Reply, else the target. `reply` marks the first, since the target
    /// is then not on the bar. A carried target that this image's answer settles on again, now as the
    /// kept pick, is a change of why. The role comes with Claude Code's listing.
    private func logOffer(was before: AgentDestination?) {
        let offer = toolbar.model.offer
        guard let to = offer.destination, to.id != before?.id || to.focus != before?.focus || to.role != before?.role else { return }
        Log.write("[send] target \(to.address.description) project=\(to.detail) focus=\(to.focus?.rawValue ?? "none") role=\(to.role ?? "none")\(offer.isSend ? "" : " reply")")
    }

    /// Whether the open image's drawing is still exactly what its agent sent, which Reply reads
    /// (`AnnotatorToolbar.Model.nothingToReply`).
    func drawingChanged(_ drawing: Drawing) {
        toolbar.model.drawingAsSent = current.map { Agent.hasSentDrawing(drawing, at: $0.url) } ?? false
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
