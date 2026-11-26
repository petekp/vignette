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
        let first = shots[0], name = first.url.lastPathComponent
        let message = Shown.message(request.message)
        if message.cut { Log.write("[show] warning \(name): its message is longer than \(Shown.messageLimit) characters and was cut") }
        let session = Agent.pushOrigin(agent: request.agent, session: request.session)
        if session == nil, !(request.session ?? "").isEmpty {
            Log.write("[show] warning \(name): session= names a session only with agent=claude or agent=codex and a session id; Send on its card starts where it would")
        }
        // Marks need someone to come from: with no `agent=` they are an agent's with no name.
        let agent = request.agent ?? (agentMarks.isEmpty ? nil : "")
        var marks: [ScreenshotKey: PendingMarks.Entry] = [:]
        if let agent, !agentMarks.isEmpty {
            guard first.kind == .image, let drawing = drawings.preview(agentMarks, from: agent, to: first.key, style: settings.data.ui.textStyle,
                                                                     newScreen: Self.newDrawingScreen, rule: settings.data.ui.markScaleRule) else {
                Commands.error(cmd, .invalidMarks, "\(name): none of its marks can be drawn on it"); return
            }
            marks[first.key] = PendingMarks.Entry(agent: agent, marks: agentMarks, drawing: drawing)
        }
        let shown = agent.map { Shown(agent: $0, session: session, message: message.text, at: Date()) }
        thumbnail.show(.init(shots: shots, shown: shown, marks: marks, agent: request.agent, tag: request.tag, asked: asked))
    }

    /// The corner and the editor draw an agent's marks from one store, and Keep and Clear in either
    /// one settle them.
    func connectAgentMarks() {
        thumbnail.pendingMarks.changed = { [weak self] key in
            self?.thumbnail.agentMarksChanged(key)
            self?.annotator.agentMarksChanged(key)
        }
        annotator.pendingMarks = { [weak self] key in self?.thumbnail.pendingMarks[key] }
        annotator.onAgentMarks = { [weak self] key, keep in self?.settleAgentMarks(on: key, keep: keep) }
        thumbnail.model.onAgentMarks = { [weak self] card, keep in self?.settleAgentMarks(on: card.shot.key, keep: keep) }
    }

    /// Keep joins the agent's marks to the drawing as one undo step, through `add`'s own path;
    /// Clear lets them go. Either way they leave the top. Marks that could not be written go back on
    /// top, and the card says why.
    func settleAgentMarks(on key: ScreenshotKey, keep: Bool) {
        guard let entry = thumbnail.pendingMarks[key] else { return }
        thumbnail.pendingMarks.set(nil, on: key)
        guard keep else { Log.write("[show] cleared marks=\(entry.drawing.marks.count) \(key.name)"); return }
        addMarks(entry.marks, from: entry.agent, to: key, rule: settings.data.ui.markScaleRule) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let joined):
                Log.write("[show] kept marks=\(joined) \(key.name)")
            case .failure(let failure):
                thumbnail.pendingMarks.set(entry, on: key)
                Log.write("[show] error \(failure.code.rawValue) \(key.name): its marks were not kept: \(failure)")
                thumbnail.post(.notSaved(reason: "The marks could not be added."), on: Screenshot(key: key), comesUp: false)
            }
        }
    }
}
