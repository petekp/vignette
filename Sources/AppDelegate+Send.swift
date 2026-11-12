import AppKit

// MARK: Send and Reply from the annotator

extension AppDelegate {
    /// Send, from the annotator's toolbar. The drawing is rendered without closing anything; the
    /// image leaves the editor only once that rendering and the request are stored, so a failure
    /// anywhere before then leaves the drawing exactly where the hand left it.
    /// The button shows the send from the press until the bar leaves, and says "Not sent" when it
    /// fails before the request is stored, since the drawing is still in the editor then.
    ///
    /// A Reply to the agent's own image, with the drawing exactly as the agent sent it, sends the
    /// person's words and no picture: the agent has it (`ScreenshotRequests.Picture.unchanged`).
    /// With no words either there is nothing new to send. The bar's Reply is unavailable then
    /// (`AnnotatorToolbar.Model.nothingToReply`), and Return copies and closes as Done does.
    func sendDrawing(_ drawing: Drawing, of shot: Screenshot, to destination: AgentDestination, titled title: String, message: String?) {
        guard !annotator.sending, let opening = annotator.opening else { return }
        let name = shot.url.lastPathComponent
        let carried = ScreenshotRequests.Carried.of(card: shot.url, origin: requests.origin(of: shot.url)?.address,
                                                    destination: destination.address,
                                                    asTheAgentSent: Agent.hasSentDrawing(drawing, at: shot.url), message: message)
        if carried == .nothingNew {
            Log.write("[send] \(name): nothing new to reply with; copied as Done")
            return finishAnnotation(shot, drawing)
        }
        let wordsAlone = carried == .wordsAlone
        let agentTitle = wordsAlone ? Agent.title(of: shot.url)?.title : nil
        annotator.sending = true
        if wordsAlone, ScreenshotRequests.isPNG(shot.url) {
            return submit(.unchanged(card: shot.url, title: agentTitle, png: nil), of: shot, to: destination, titled: title, message: message)
        }
        let ui = settings.data.ui
        let rendering = RenderingQueue.shared.render(carried.rendering(drawing), imageAt: shot.url, output: .bytes, style: ui.textStyle, markStyle: ui.markStyle)
        rendering.whenDone { [weak self] output in
            guard let self else { return }
            // A rendering that answers after the opening Send was pressed in has ended belongs to no
            // image now, even the same one opened again: it is dropped, and nothing is sent and
            // nothing closed. The image open now has its own `sending`, which this leaves alone.
            guard annotator.opening == opening else {
                Log.write("[send] dropped \(name); the editor moved on"); return
            }
            guard let png = output.png, output.failure == nil else {
                let failure = output.failure ?? .writeFailed("the rendering made no image")
                Commands.error("send", failure.code, "\(name): \(failure)")
                if case .unreadableImage = failure { annotator.sendFailed(Self.unreadable(name)) }
                else { annotator.sendFailed("Vignette couldn't render the drawing. The log has details.") }
                return
            }
            let picture: ScreenshotRequests.Picture = wordsAlone ? .unchanged(card: shot.url, title: agentTitle, png: png) : .drawing(png: png)
            submit(picture, of: shot, to: destination, titled: title, message: message)
        }
    }

    private static func unreadable(_ name: String) -> String {
        "Vignette can't read \(name). It may have been moved or deleted."
    }

    private func submit(_ picture: ScreenshotRequests.Picture, of shot: Screenshot, to destination: AgentDestination,
                        titled title: String, message: String?) {
        let record: ScreenshotRequests.Record
        do {
            record = try requests.send(picture, source: shot.key, to: destination, message: message,
                                       instructions: settings.data.sendInstructions,
                                       grace: settings.data.ui.sendGraceSeconds)
        } catch {
            annotator.sendFailed((error as? ScreenshotRequests.Refusal)?.reason ?? "Vignette couldn't send the drawing. The log has details.")
            return
        }
        // Stored, so the request survives whatever the client does next. The image goes home
        // with a send notice rather than a Copied one: copying is Done's contract. A queued run
        // carries on. `sending` stays on, so the button keeps its plane while the bar leaves;
        // the next `prepare` resets it.
        sentShots[record.id] = shot
        annotator.sent(to: destination)
        thumbnail.showSending(shot, request: record.id, to: destination, titled: title, grace: requests.grace(of: record.id))
        thumbnail.annotationSent()
    }

    /// Where the bar can send while this image is open, and the session it came from: an agent's
    /// reply to a request, or a push that named its session. Reading the sessions runs
    /// subprocesses, so it answers later; the bar offers Send once it has a session to send to.
    func refreshDestinations(for shot: Screenshot) {
        guard let opening = annotator.opening else { return }
        let kept = annotator.beginDestinations(replyTo: requests.origin(of: shot.url))
        let asked = CACurrentMediaTime()
        let app = FocusReturn.shared.previousApp
        guard let client = AgentApp.client(of: app), let pid = app?.processIdentifier else {
            return listDestinations(for: shot, opening: opening, asked: asked, cameFrom: nil, kept: kept)
        }
        // The thread the agent's app shows is read before anything is listed: Claude Code's list
        // comes first and would settle the target on the session in herdr's focus, which you were not in.
        let launched = app?.launchDate
        DispatchQueue.global(qos: .userInitiated).async {
            let shown = AgentApp.shownThread(pid: pid, launched: launched)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.annotator.opening == opening else { return }
                Log.write("[send] came from the \(client.label) app, showing \(shown ?? "no thread") after=\(Int((CACurrentMediaTime() - asked) * 1000))ms")
                self.listDestinations(for: shot, opening: opening, asked: asked, cameFrom: (client, shown), kept: kept)
            }
        }
    }

    private func listDestinations(for shot: Screenshot, opening: Opening, asked: CFTimeInterval,
                                  cameFrom: (client: AgentClient, shown: String?)?, kept: AgentDestination?) {
        sessions.list(including: SessionListing.readByID(kept: kept, cameFrom: cameFrom)) { [weak self] candidates in
            guard let self else { return }
            Log.write("[send] sessions \(candidates.destinations.count)\(candidates.complete ? " complete" : "")\(candidates.fresh ? "" : " kept") after=\(Int((CACurrentMediaTime() - asked) * 1000))ms \(shot.url.lastPathComponent)")
            // A file can reopen while its earlier destination listing is still running.
            guard self.annotator.opening == opening else { return }
            self.annotator.destinationsAnswered(DestinationChoice.choose(candidates, for: .send(cameFrom: cameFrom, kept: kept)))
        }
    }

    /// A screenshot's drawing as the editor opens it (`AnnotationController.storedDrawing`).
    func storedDrawing(_ key: ScreenshotKey) -> Drawing? {
        PixelSize(imageAt: key.url).flatMap { drawings.read(key, pixels: $0, style: settings.data.ui.textStyle) }
    }
}
