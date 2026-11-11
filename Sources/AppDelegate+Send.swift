import AppKit

// MARK: Send and Reply from the annotator

extension AppDelegate {
    /// What Reply does when the person changed nothing on the agent's image and typed nothing: there
    /// is nothing new for the agent. Return on such a card is the person's habit of copying, so it
    /// copies and closes as Done does.
    enum EmptyReply {
        /// Copy and close, as Done does. Nothing is sent.
        case copy
        /// Leave the editor open with "Not sent" and `emptyReplyReason`.
        case refuse
        /// Send the picture, as before 2026-11-11.
        case sendPicture
    }

    static let emptyReply = EmptyReply.copy
    static let emptyReplyReason = "There's nothing new to send yet. You can draw on it or add a message."

    /// Send, from the annotator's toolbar. The drawing is rendered without closing anything; the
    /// image leaves the editor only once that rendering and the request are stored, so a failure
    /// anywhere before then leaves the drawing exactly where the hand left it.
    /// The button shows the send from the press until the bar leaves, and says "Not sent" when it
    /// fails before the request is stored, since the drawing is still in the editor then.
    ///
    /// A Reply to the agent's own image, with the drawing exactly as the agent sent it, sends the
    /// person's words and no picture: the agent has it (`ScreenshotRequests.Picture.unchanged`).
    func sendDrawing(_ drawing: Drawing, of shot: Screenshot, to destination: AgentDestination, titled title: String, message: String?) {
        guard !annotator.sending, let opening = annotator.opening else { return }
        let name = shot.url.lastPathComponent
        let toItsAgent = requests.origin(of: shot.url)?.address == destination.address
        let asTheAgentSent = toItsAgent && Agent.hasSentDrawing(drawing, at: shot.url)
        if asTheAgentSent, message == nil {
            switch Self.emptyReply {
            case .copy:
                Log.write("[send] \(name): nothing new to reply with; copied as Done")
                return finishAnnotation(shot, drawing)
            case .refuse:
                Log.write("[send] \(name): nothing new to reply with")
                return annotator.sendFailed(Self.emptyReplyReason)
            case .sendPicture:
                break
            }
        }
        let wordsAlone = asTheAgentSent && message != nil
        let agentTitle = wordsAlone ? Agent.title(of: shot.url)?.title : nil
        annotator.sending = true
        if wordsAlone, ScreenshotRequests.isPNG(shot.url) {
            return submit(.unchanged(card: shot.url, title: agentTitle, png: nil), of: shot, to: destination, titled: title, message: message)
        }
        // Words alone on a card that is not a PNG: the picture a drawn answer goes on is the card's
        // own, made a PNG, without the agent's marks.
        var rendered = drawing
        if wordsAlone { rendered.marks = [] }
        let ui = settings.data.ui
        let rendering = RenderingQueue.shared.render(rendered, imageAt: shot.url, output: .bytes, style: ui.textStyle, markStyle: ui.markStyle)
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
        thumbnail.showSending(shot, request: record.id, to: destination, titled: title, grace: requests.grace(of: record.id))
        thumbnail.annotationSent()
    }

    /// A screenshot's drawing as the editor opens it (`AnnotationController.storedDrawing`).
    func storedDrawing(_ key: ScreenshotKey) -> Drawing? {
        PixelSize(imageAt: key.url).flatMap { drawings.read(key, pixels: $0, style: settings.data.ui.textStyle) }
    }
}
