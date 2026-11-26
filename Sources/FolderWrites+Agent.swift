import Foundation

extension FolderWrites {
    /// What `add` records about the agent on the file at `destination`: the agent and its session,
    /// the session's name, and the title. Answers the title, as `AgentTitle.validated` read it.
    func recordAgent(of request: CommandRequest, origin: AgentAddress?, on key: ScreenshotKey,
                     at destination: URL) -> (value: AgentTitle?, cut: [AgentTitle.Part]) {
        let name = destination.lastPathComponent
        if let agent = request.agent { Agent.record(agent: agent, origin: origin, on: destination) }
        let from = Agent.cleanSender(request.from)
        if from.cut { Log.write("[add] warning \(name): its from= is longer than \(Agent.maxSenderLength) characters and was cut") }
        if request.agent != nil {
            if let sender = from.name { Agent.record(sender: sender, on: destination) } else if let origin { nameSender(of: origin, on: key, at: destination) }
            // A push of a file already in the folder makes no new card, so its card's tab follows here.
            callbacks.senderRecorded(Screenshot(key: key))
        }
        if origin == nil {
            // Not quoted: the value is the caller's, and the log is not a place for it.
            if Agent.cleanSession(request.session) != nil {
                Log.write("[add] warning \(name): session= names a session only with agent=claude or agent=codex; Reply on its card will ask where to send")
            } else if !(request.session ?? "").isEmpty {
                Log.write("[add] warning \(name): session= is not a session id; Reply on its card will ask where to send")
            }
        }
        let title = AgentTitle.validated(title: request.title, description: request.description)
        Agent.record(title: title.value, on: destination)
        for part in title.cut {
            Log.write("[add] warning \(name): its \(part.rawValue) is longer than \(part.limit) characters and was cut")
        }
        return title
    }

    /// Records the name the session list gives `origin`, for a push that did not give one with
    /// `from=`. The card says "From Claude" until it answers, then the name in place. The answer is
    /// dropped when a later push changed the file's session or gave its own name.
    private func nameSender(of origin: AgentAddress, on key: ScreenshotKey, at url: URL) {
        let asked = now()
        callbacks.senderName(origin) { [weak self] sender in
            guard let self else { return }
            let after = "after=\(Int((now() - asked) * 1000))ms \(url.lastPathComponent)"
            guard let sender = Agent.cleanSender(sender).name else { Log.write("[add] sender not found session=\(origin.id) \(after)"); return }
            guard Agent.origin(of: url)?.address == origin, Agent.sender(of: url) == nil else { return }
            Agent.record(sender: sender, on: url)
            Log.write("[add] sender found session=\(origin.id) \(after)")
            callbacks.senderRecorded(Screenshot(key: key))
        }
    }
}
