import AppKit

extension AppDelegate {
    /// The checks every command that names screenshots runs on each file: it is inside the folder,
    /// and it is not a reply still being imported. Nil when the command may act on it.
    func fileError(_ file: URL) -> (code: CommandError, detail: String)? {
        if let code = Commands.policyError(for: file, watchFolder: watchFolder, debug: settings.data.debug) { return (code, file.path) }
        // A reserved reply is Vignette's own until its import commits: opening it would show
        // a drawing still missing its marks, and trashing it would delete the file the import
        // is about to draw on. The listings hide it; so does naming it.
        guard requests.isVisible(file) else { return (.missingFile, "\(file.path): an agent reply that is not imported yet") }
        return nil
    }

    /// `vignette://show`: checks every file before any card comes up, then hands the call to the
    /// corner, which runs it once the person's hand has left it.
    func show(_ request: CommandRequest) {
        let cmd = "show", asked = CACurrentMediaTime()
        var named = Set<String>()
        let files = request.files.filter { named.insert($0.standardizedFileURL.path).inserted }
        guard !files.isEmpty else { Commands.error(cmd, .missingFile, "no file given"); return }
        let limit = settings.data.recentCount
        guard files.count <= limit else { Commands.error(cmd, .tooManyFiles, "needs at most \(limit), got \(files.count)"); return }
        let shots = files.map { Screenshot(key: ScreenshotKey(naming: $0, in: watchFolder)) }
        for shot in shots {
            if let bad = fileError(shot.url) { Commands.error(cmd, bad.code, bad.detail); return }
            guard FileManager.default.fileExists(atPath: shot.url.path) else { Commands.error(cmd, .missingFile, shot.url.path); return }
            guard thumbnail.canShow(shot) else { Commands.error(cmd, .unreadableImage, shot.url.path); return }
        }
        var agentMarks: [AgentMark] = []
        if let value = request.marks {
            do { agentMarks = try AgentMark.parse(value) } catch { Commands.error(cmd, .invalidMarks, "\(error)"); return }
        }
        var agentPins: [AgentPin] = []
        if let value = request.pins {
            do { agentPins = try AgentPin.parse(value) } catch { Commands.error(cmd, .invalidPins, "\(error)"); return }
        }
        let first = shots[0], name = first.url.lastPathComponent
        let message = Shown.message(request.message)
        if message.cut { Log.write("[show] warning \(name): its message is longer than \(Shown.messageLimit) characters and was cut") }
        let session = Agent.pushOrigin(agent: request.agent, session: request.session)
        if session == nil, !(request.session ?? "").isEmpty {
            Log.write("[show] warning \(name): session= names a session only with agent=claude or agent=codex and a session id; Send on its card starts where it would")
        }
        let from = Agent.cleanSender(request.from)
        if from.cut { Log.write("[show] warning \(name): its from= is longer than \(Agent.maxSenderLength) characters and was cut") }
        // Marks and pins need someone to come from: with no `agent=` they are an agent's with no name.
        let agent = request.agent ?? (agentMarks.isEmpty && agentPins.isEmpty ? nil : "")
        let shown = agent.map { Shown(agent: $0, session: session, message: message.text, at: Date(), sender: from.name) }
        var call = ThumbnailController.ShowCall(shots: shots, shown: shown, agent: request.agent, tag: request.tag, asked: asked)
        func bringUp() {
            thumbnail.show(call)
            if shown != nil, from.name == nil, let session { nameSender(of: session, asked: asked) }
        }
        guard let agent, !agentMarks.isEmpty || !agentPins.isEmpty else { return bringUp() }
        let additions = AgentAdditions(marks: agentMarks, pins: agentPins, agent: agent), ui = settings.data.ui
        guard first.kind == .image, let joining = drawings.joining(additions, to: first.key, style: ui.textStyle,
                                                                 newScreen: Self.newDrawingScreen, rule: ui.markScaleRule) else {
            Commands.error(cmd, agentMarks.isEmpty ? .invalidPins : .invalidMarks, "\(name): it is not an image its marks or pins can go on"); return
        }
        guard agentMarks.isEmpty || joining.drawable > 0 else {
            Commands.error(cmd, .invalidMarks, "\(name): none of its marks can be drawn on it"); return
        }
        if let problem = AgentPin.problem(agentPins, on: joining.onto, name: name) { Commands.error(cmd, .invalidPins, problem); return }
        // The marks and pins join the drawing as `add`'s do, as one undo step, before the cards come up.
        addMarks(additions, to: first.key, rule: ui.markScaleRule) { result in
            switch result {
            case .success(let joined):
                call.joined = joined
                bringUp()
            case .failure(let failure):
                Commands.error(cmd, failure.code, failure.description)
            }
        }
    }

    /// The session's name, for a `show` that did not give one with `from=`: the cards come up at
    /// once and say "From Claude" until the session list answers, then its name in place.
    private func nameSender(of session: AgentAddress, asked: CFTimeInterval) {
        sessions.senderName(of: session) { [weak self] sender in
            let after = "after=\(Int((CACurrentMediaTime() - asked) * 1000))ms"
            guard let sender = Agent.cleanSender(sender).name else { Log.write("[show] sender not found session=\(session.id) \(after)"); return }
            Log.write("[show] sender found session=\(session.id) \(after)")
            self?.thumbnail.named(sender, of: session)
        }
    }
}
