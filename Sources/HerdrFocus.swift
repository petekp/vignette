import Foundation
import os

/// Where Herdr's focus is, and the agents it runs, read from the Herdr app's window and from
/// herdr-core (`hc`), which runs its terminals. `herdr-app status` names the focused pane and its
/// tab, `herdr-app ls` places each terminal in a tab and a pane and says which run an agent, and
/// `hc` gives each terminal's foreground process and labels. A fact for `DestinationChoice`, which
/// decides what it marks.
struct HerdrFocus: Equatable, Sendable {
    /// The focused pane. When the focus is on the inbox mod's panel, the pane of the terminal that
    /// panel belongs to.
    let pane: String
    let tab: String
    let agents: [AgentPane]
    /// Each tab's name, by tab id. A name that is only a number is left out: Herdr numbers a tab
    /// nobody named (observed 2026-11-12), and the number says nothing about the session.
    var tabLabels: [String: String] = [:]
    /// The terminals Herdr shows running no agent. Herdr names a terminal's agent only once the
    /// program reports its status, and a Claude Code that hc started may never report (observed
    /// 2026-11-12), so `sessions(from:)` adds one whose process is a listed Claude Code session.
    var unreported: [AgentPane] = []

    /// One terminal running an agent, of any kind.
    struct AgentPane: Equatable, Sendable {
        let pane: String
        /// The Claude Code session the terminal runs, when it is known (`sessions(from:)`).
        var session: String? = nil
        /// The tab the pane is in.
        var tab: String = ""
        /// The terminal's foreground process, which is Claude Code itself when the terminal runs it.
        var pid: Int32? = nil
        /// What the log says of the terminal's place in the fleet (`role(labels:parent:)`), such as
        /// `coordinator` or `delegate`. Nil for a terminal with neither. Only the log reads it.
        var role: String? = nil
    }

    /// A `fleet.role` label as the log may hold it: the label when it is 1 to 24 letters, digits and
    /// hyphens, else `other`. Pete's tools set the label, and it may be any text.
    static func loggedRole(_ label: String) -> String {
        let isName = (1...24).contains(label.count) && label.unicodeScalars.allSatisfy {
            $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-")
        }
        return isName ? label : "other"
    }

    static let delegateRole = "delegate"

    /// A terminal's role in the log: its `fleet.role` label when it has one, else `delegate` when
    /// herdr-core gives it a parent terminal, which the terminals a coordinator starts have.
    static func role(labels: [String: String], parent: String?) -> String? {
        if let label = labels["fleet.role"] { return loggedRole(label) }
        guard let parent, !parent.isEmpty else { return nil }
        return delegateRole
    }

    /// How long each read may take. Each answered in 5 to 20 ms (measured 2026-11-12). The focus is
    /// read in Claude Code's listing job, so a read that hangs holds back Send's target.
    static let readTimeout: TimeInterval = 1

    private static let appPaths = ["\(NSHomeDirectory())/.local/bin/herdr-app", "/Applications/Herdr.app/Contents/MacOS/Herdr",
                                   "\(NSHomeDirectory())/Applications/Herdr.app/Contents/MacOS/Herdr"]
    private static let corePaths = ["\(NSHomeDirectory())/.local/bin/hc",
                                    "\(NSHomeDirectory())/.local/share/herdr-core/current/Contents/MacOS/herdr-core"]

    /// The Herdr app Vignette asks: none in a test launch unless VIGNETTE_HERDR_APP names one.
    static func appToRun() -> String? {
        AgentTools.forSessions("VIGNETTE_HERDR_APP") { appPaths.first { FileManager.default.isExecutableFile(atPath: $0) } }
    }

    /// The `hc` Vignette asks: none in a test launch unless VIGNETTE_HC names one.
    static func coreToRun() -> String? {
        AgentTools.forSessions("VIGNETTE_HC") { corePaths.first { FileManager.default.isExecutableFile(atPath: $0) } }
    }

    typealias Answer = (status: Int32, output: String, timedOut: Bool)

    /// `hc connect` speaks JSON-RPC on its standard input; `terminal.list` answers every live
    /// terminal with its foreground process and labels, which `hc ls` leaves out.
    static let terminalListRequest = #"{"id":1,"jsonrpc":"2.0","method":"terminal.list","params":{}}"#

    /// Reads the focus, running the three reads at once. Nil without the Herdr app or `hc`, or when
    /// a read fails, as when the Herdr window is closed. A failure logs one `[herdr] no focus` line
    /// each time its reason changes. It blocks, so it never runs on the main thread.
    static func read(app: () -> String? = { appToRun() }, core: () -> String? = { coreToRun() },
                     run: @escaping @Sendable (String, [String], TimeInterval) -> Answer? = {
                         Subprocess.run($0, $1, timeout: $2, includingErrors: false)
                     },
                     converse: @escaping @Sendable (String, [String], [String], TimeInterval) -> [String] = {
                         AppServer.converse($0, $1, $2, timeout: $3)
                     }) -> HerdrFocus? {
        try? readReporting(app: app, core: core, run: run, converse: converse).get()
    }

    /// `read`, with the reason when there is no focus. Without the Herdr app or `hc` the reason is
    /// `noHerdr`, which is not logged as `[herdr] no focus`.
    static func readReporting(app: () -> String? = { appToRun() }, core: () -> String? = { coreToRun() },
                              run: @escaping @Sendable (String, [String], TimeInterval) -> Answer? = {
                                  Subprocess.run($0, $1, timeout: $2, includingErrors: false)
                              },
                              converse: @escaping @Sendable (String, [String], [String], TimeInterval) -> [String] = {
                                  AppServer.converse($0, $1, $2, timeout: $3)
                              }) -> Result<HerdrFocus, Unread> {
        guard let app = app(), let core = core() else { return .failure(noHerdr) }
        let answers = OSAllocatedUnfairLock(initialState: (status: Answer?.none, ls: Answer?.none, terminals: [String]()))
        DispatchQueue.concurrentPerform(iterations: 3) { index in
            switch index {
            case 0: let status = run(app, ["status"], readTimeout); answers.withLock { $0.status = status }
            case 1: let ls = run(app, ["ls"], readTimeout); answers.withLock { $0.ls = ls }
            default: let lines = converse(core, ["connect"], [terminalListRequest], readTimeout); answers.withLock { $0.terminals = lines }
            }
        }
        let (status, ls, terminals) = answers.withLock { ($0.status, $0.ls, $0.terminals) }
        let result = reading(status: status, ls: ls, terminals: terminals)
        switch result {
        case .success: note(nil)
        case .failure(let unread): note(unread.reason)
        }
        return result
    }

    struct Unread: Error, Equatable { let reason: String }

    static let noHerdr = Unread(reason: "no herdr-app or hc")

    /// The focus from the three answers, or why there is none. The focused terminal is the one in
    /// the focused pane, or else the one whose inbox mod panel has the focus. A pane that is neither,
    /// or a terminal running no agent, leaves `DestinationChoice` the one agent in the tab.
    static func reading(status: Answer?, ls: Answer?, terminals: [String]) -> Result<HerdrFocus, Unread> {
        if let failed = failure(status, "status") ?? failure(ls, "ls") { return .failure(failed) }
        guard let window = object(status?.output), let focused = window["focused_pane"] as? String,
              let tab = window["tab"] as? String else { return .failure(Unread(reason: "status unreadable")) }
        guard let spaces = object(ls?.output)?["spaces"] as? [[String: Any]] else { return .failure(Unread(reason: "ls unreadable")) }
        guard let core = terminalRecords(in: terminals) else { return .failure(Unread(reason: "hc did not answer")) }

        var placed: [(terminal: String, pane: String, tab: String, isAgent: Bool)] = []
        var labels: [String: String] = [:]
        var tabs: Set<String> = []
        for tab in spaces.flatMap({ $0["tabs"] as? [[String: Any]] ?? [] }) {
            guard let id = tab["id"] as? String else { continue }
            tabs.insert(id)
            if let name = (tab["name"] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
               !name.allSatisfy(\.isNumber) { labels[id] = name }
            for terminal in tab["terminals"] as? [[String: Any]] ?? [] {
                guard let address = terminal["terminal"] as? String, let pane = terminal["pane"] as? String else { continue }
                placed.append((address, pane, id, terminal["app"] is String))
            }
        }
        guard tabs.contains(tab) else { return .failure(Unread(reason: "status's tab \(tab) is not in ls")) }

        let owner = core.first { $0.value.labels["inbox.panel"] == focused }?.key
        let focusedTerminal = placed.first { $0.pane == focused } ?? placed.first { $0.terminal == owner }
        if let focusedTerminal, focusedTerminal.tab != tab {
            return .failure(Unread(reason: "status's tab \(tab) is not the focused terminal's \(focusedTerminal.tab)"))
        }
        func pane(_ terminal: (terminal: String, pane: String, tab: String, isAgent: Bool)) -> AgentPane {
            AgentPane(pane: terminal.pane, session: terminal.isAgent ? core[terminal.terminal]?.labels["inbox.session"] : nil,
                      tab: terminal.tab, pid: core[terminal.terminal]?.pid,
                      role: core[terminal.terminal].flatMap { role(labels: $0.labels, parent: $0.parent) })
        }
        return .success(HerdrFocus(pane: focusedTerminal?.pane ?? focused, tab: tab, agents: placed.filter(\.isAgent).map(pane),
                                   tabLabels: labels, unreported: placed.filter { !$0.isAgent }.map(pane)))
    }

    /// Each live terminal in `hc`'s answer to `terminalListRequest`, by address: its foreground
    /// process, its labels and the terminal that started it. Nil when there is no such answer.
    static func terminalRecords(in lines: [String]) -> [String: (pid: Int32?, labels: [String: String], parent: String?)]? {
        guard let answer = lines.lazy.compactMap({ object($0) }).first(where: { $0["id"] as? Int == 1 }),
              let terminals = (answer["result"] as? [String: Any])?["terminals"] as? [[String: Any]] else { return nil }
        var records: [String: (pid: Int32?, labels: [String: String], parent: String?)] = [:]
        for terminal in terminals {
            guard let address = terminal["address"] as? String else { continue }
            let pid = ((terminal["foreground"] as? [String: Any])?["pid"] as? NSNumber)?.int32Value
            records[address] = (pid, terminal["labels"] as? [String: String] ?? [:], terminal["parent"] as? String)
        }
        return records
    }

    /// The same focus with each terminal's session found among Claude Code's `listed` sessions by its
    /// process: the session whose plugin inbox belongs to the terminal's foreground process. That
    /// follows `/clear`, as the inbox does. An unreported terminal found this way is an agent. An agent
    /// no listed session runs keeps the session the inbox mod labelled it with, unless another
    /// terminal runs that session: a label can outlast the Claude Code it named.
    func sessions(from listed: [AgentDestination]) -> HerdrFocus {
        func byProcess(_ terminal: AgentPane) -> String? {
            terminal.pid.flatMap { pid in listed.first { $0.inbox == pid }?.id }
        }
        let found = unreported.filter { byProcess($0) != nil }
        let claimed = Set((agents + found).compactMap(byProcess))
        let resolved = (agents + found).map { terminal in
            var resolved = terminal
            if let session = byProcess(terminal) {
                resolved.session = session
            } else if let label = terminal.session, claimed.contains(label) {
                resolved.session = nil
            }
            return resolved
        }
        return HerdrFocus(pane: pane, tab: tab, agents: resolved, tabLabels: tabLabels)
    }

    /// The role of the terminal that runs `session`, as `loggedRole` writes it.
    func role(ofSession session: String) -> String? {
        agents.first { $0.session == session }?.role
    }

    /// The label of the tab whose terminal runs `session`, if Herdr names it.
    func label(ofSession session: String) -> String? {
        agents.first { $0.session == session }.flatMap { tabLabels[$0.tab] }
    }

    private static func failure(_ answer: Answer?, _ name: String) -> Unread? {
        guard let answer else { return Unread(reason: "\(name) did not run") }
        if answer.timedOut { return Unread(reason: "\(name) timed out") }
        guard answer.status == 0 else {
            return Unread(reason: "\(name) exit \(answer.status)" + (Subprocess.detail(answer.output).map { ": \($0)" } ?? ""))
        }
        return nil
    }

    private static func object(_ text: String?) -> [String: Any]? {
        text.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    }

    private static let lastReason = OSAllocatedUnfairLock<String?>(initialState: nil)

    private static func note(_ reason: String?) {
        let changed = lastReason.withLock { last -> Bool in
            defer { last = reason }
            return last != reason
        }
        guard changed else { return }
        Log.write(reason.map { "[herdr] no focus: \($0)" } ?? "[herdr] focus read again")
    }
}

/// What Herdr's focus says when a screenshot is taken, for the `[capture] clues` log line. The session
/// is the one Send would start on for this focus (`DestinationChoice`), so it is never guessed from
/// the screen: nothing read from the picture or from a window title is part of it.
extension HerdrFocus {
    struct CaptureClue: Equatable {
        let pane: String
        /// The Claude Code session in the focused pane, or the one in its tab when the pane runs none.
        let session: String?
        /// `pane` or `tab` when there is a session, else nil.
        let focus: AgentDestination.Focus?
        /// The session's repository, or its folder when it has none.
        let project: String?
    }

    /// The clue from `read`'s focus and `listing`'s Claude Code sessions, or why there is none. It
    /// lists the sessions only once the focus is read, so a launch that runs no Herdr runs no listing.
    /// It blocks on subprocesses, so it never runs on the main thread.
    static func clue(read: () -> Result<HerdrFocus, Unread> = { readReporting() },
                     listing: () -> [AgentDestination]) -> Result<CaptureClue, Unread> {
        switch read() {
        case .failure(let unread):
            return .failure(unread)
        case .success(let focus):
            let listed = listing()
            let candidates = DestinationChoice.Candidates(destinations: listed, complete: true, fresh: true,
                                                          herdr: focus.sessions(from: listed))
            let answer = DestinationChoice.choose(candidates, for: .send(cameFrom: nil))
            let focused = answer.list.first { $0.focus == .pane || $0.focus == .tab }
            return .success(CaptureClue(pane: focus.pane, session: focused?.id, focus: focused?.focus,
                                        project: focused.flatMap { projectName($0.place) }))
        }
    }

    private static func projectName(_ place: Place) -> String? {
        switch place {
        case .repository(let name, _, _, _): return name
        case .folder(let path): return path
        case .none: return nil
        }
    }

    /// The line's Herdr part: `herdr=<pane>/<session or none> focus=<pane|tab|none> project=<name or none>`,
    /// or `herdr=unread:<reason> focus=none project=none`. The reason is one word, so the line stays
    /// `key=value` pairs.
    static func logged(_ clue: Result<CaptureClue, Unread>) -> String {
        switch clue {
        case .success(let clue):
            return "herdr=\(clue.pane)/\(clue.session ?? "none") focus=\(clue.focus?.rawValue ?? "none") project=\(clue.project ?? "none")"
        case .failure(let unread):
            let word = unread.reason.split(whereSeparator: \.isWhitespace).joined(separator: "-").prefix(60)
            return "herdr=unread:\(word) focus=none project=none"
        }
    }
}
