import AppKit

// MARK: Send and Reply

extension AnnotationController {
    /// A new image opened: `replyTo` is the session it came from, when it names one, and the list
    /// of sessions is on its way. Read once per image: the list comes from subprocesses, and a menu
    /// that re-read it on every click would stall the bar. Answers the kept pick's session, which
    /// this image's listing starts on while it holds. `capture` is the apps whose windows the
    /// capture showed, when the image opened from one, which every target line logs.
    func beginDestinations(replyTo: AgentDestination?, capture: [CaptureRect.Owner]?) -> AgentDestination? {
        captured = capture
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

    /// A send from the editor to `destination`, a row of the bar, stored `record`
    /// (`DestinationChoice.KeptPick.after`). A row Vignette starts is kept as the session the send started.
    func sent(to destination: AgentDestination, as record: ScreenshotRequests.Record) {
        let now = Date()
        logMenuRows(of: record)
        let session = destination.sent(as: record)
        let after = DestinationChoice.KeptPick.after(sendTo: session, isSend: toolbar.model.offer.isSend,
                                                     handPicked: toolbar.model.isHandPick(destination), kept: keptPick, at: now)
        if after == nil { return endKeptPick("time") }
        guard after != keptPick else { return }
        keptPick = after
        Log.write("[send] kept \(session.address.description) project=\(session.detail)")
    }

    /// `[send] menu request=<id> top=<rows>`: the rows the target menu opens with at this send, which
    /// the pick's line (`TargetMenuActions`) says only when the menu was used. A Reply has no menu,
    /// so it writes none.
    private func logMenuRows(of record: ScreenshotRequests.Record) {
        let model = toolbar.model
        guard model.offer.offersTarget else { return }
        let top = SessionMenu.menu(model.listing.sessions, destination: model.offer.destination,
                                   targetNotFirst: true).topRows.map(\.destination)
        Log.write("[send] menu request=\(record.id) top=\(top.map(TargetMenuActions.loggedName).joined(separator: ","))")
    }

    private func endKeptPick(_ reason: String) {
        guard let kept = keptPick else { return }
        keptPick = nil
        Log.write("[send] kept ended \(kept.session.address.description) reason=\(reason)")
    }

    /// Logs where the bar's filled button sends, why, and its terminal's role, whenever one changes:
    /// the card's own session for a Reply, else the target. `reply` marks the first, since the target
    /// is then not on the bar. A carried target that this image's answer settles on again, now as the
    /// kept pick, is a change of why. The role comes with Claude Code's listing. `capture=` names
    /// the apps whose windows the capture showed, with their shares, the largest first.
    private func logOffer(was before: AgentDestination?) {
        let offer = toolbar.model.offer
        guard let to = offer.destination, to.id != before?.id || to.focus != before?.focus || to.role != before?.role else { return }
        let capture = captured.flatMap { $0.isEmpty ? nil : " capture=" + $0.prefix(3).map { "\($0.app):\(Int(($0.share * 100).rounded()))%" }.joined(separator: ",") } ?? ""
        Log.write("[send] target \(to.address.description) project=\(to.detail) focus=\(to.focus?.rawValue ?? "none") role=\(to.role ?? "none")\(offer.isSend ? "" : " reply")\(capture)")
    }

    /// Whether the open image's drawing is still exactly what its agent sent, which Reply reads
    /// (`AnnotatorToolbar.Model.nothingToReply`).
    func drawingChanged(_ drawing: Drawing) {
        toolbar.model.drawingAsSent = current.map { Agent.hasSentDrawing(drawing, at: $0.url) } ?? false
        guard let current else { return }
        if let before = pinsBefore, before.key == current.key, before.drawing.pins != drawing.pins {
            onPinsChanged?(current, before.drawing, drawing)
        }
        pinsBefore = (current.key, drawing)
    }

    /// The sessions running now, as the image's session list last answered.
    var runningSessions: [AgentDestination] { toolbar.model.listing.list }

    /// A comment on the open image changed how it stands with its session.
    func commentDeliveriesChanged(_ key: ScreenshotKey) {
        guard current?.key == key else { return }
        editor.refreshLiveComments()
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
