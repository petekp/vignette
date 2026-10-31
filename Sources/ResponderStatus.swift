import SwiftUI

/// Whether Claude Code and Codex can answer live ink, as their last checks found, and Codex's
/// sign-in, which Settings and setup start and end (docs/live-ink-responders.md). Live ink, Settings
/// and setup all read it, and a sign-in or sign-out writes it.
@MainActor
final class ResponderStatus: ObservableObject {
    enum SignIn: Equatable {
        case idle
        case waiting
        case signingOut
        /// Why the last sign-in did not finish.
        case failed(String)
    }

    /// This Mac's agents, and a real sign-in.
    static let shared = ResponderStatus(live: true)
    /// The Setup Lab's: Claude Code still checking, no Codex, and no sign-in, since a run records
    /// nothing.
    static let inert = ResponderStatus(live: false)

    /// How often Claude Code is asked again while a window shows this: asking it starts `claude`.
    static let claudeRecheck: TimeInterval = 30

    @Published private(set) var availability: [AgentClient: LiveResponder.Availability] = [.claude: .checking, .codex: .checking]
    @Published private(set) var signIn = SignIn.idle
    /// Hears Codex's home signed in or out, which leaves its process on the old sign-in.
    var onCodexSignIn: ((_ signedIn: Bool) -> Void)?

    /// The driver whose check and words each agent has.
    static let drivers: [AgentClient: any ResponderDriver.Type] = [.claude: ClaudeDriver.self, .codex: CodexDriver.self]

    private let live: Bool
    private var login: CodexLogin?
    private var claudeAsked: Date?
    private var claudeAsking = false

    private init(live: Bool) {
        self.live = live
        if !live { availability[.codex] = .notInstalled }
    }

    var claude: LiveResponder.Availability { availability[.claude] ?? .checking }
    var codex: LiveResponder.Availability { availability[.codex] ?? .checking }

    /// Whether Codex is installed, once its check has answered.
    var codexInstalled: Bool { codex == .ready || codex == .signedOut }

    /// The agent setup and the offer name as the one that will answer: Codex where it is the one that
    /// can, now or once it is signed in, since it is installed and Claude Code cannot answer; else
    /// Claude. Where it is Codex, setup offers Codex's sign-in, since without it the person would
    /// finish setup with live ink unable to answer.
    var namedAgent: AgentClient { codexInstalled && !claude.canAnswer ? .codex : .claude }

    /// Whether setup's permissions page still asks for Codex's sign-in.
    var codexSignInLeft: Bool { namedAgent == .codex && codex != .ready }

    /// Whether setup's Codex row shows Sign In to Codex…, which it does while the sign-in is left and
    /// not waiting in the browser.
    var offersCodexSignIn: Bool { codexSignInLeft && signIn != .waiting }

    var costNote: String { SetupInkCopy.costNote(claude: claude.canAnswer, codex: codex == .ready || namedAgent == .codex) }

    /// Setup's live ink page's line after the one about drawing: who to ask, or why Claude cannot
    /// answer when neither agent can.
    var askLine: String {
        claude.canAnswer || namedAgent == .codex ? SetupInkCopy.askLine(agent: namedAgent) : ClaudeDriver.problem(claude) ?? ""
    }

    /// Asks each of `clients` whether it can answer, off the main thread, and runs `changed` after
    /// each answer.
    func check(_ clients: [AgentClient] = AgentClient.allCases, then changed: @escaping () -> Void = {}) {
        guard live else { return }
        for client in clients {
            guard let driver = Self.drivers[client] else { continue }
            Task { [weak self] in
                // A dispatch queue, not a detached task: Claude Code's check waits for `claude auth
                // status`, and a wait on one of Swift's few cooperative threads stalls every task
                // queued behind it.
                let found: LiveResponder.Availability = await withCheckedContinuation { found in
                    DispatchQueue.global(qos: .utility).async { found.resume(returning: driver.availability()) }
                }
                guard let self else { return }
                if availability[client] != found { availability[client] = found }
                Log.write("[live-ink] responder \(found) agent=\(client.rawValue)")
                changed()
            }
        }
    }

    /// Looks again for a window: Codex each time, since its check reads one file, and Claude Code at
    /// most every `claudeRecheck`, since its check runs `claude`. A look for the person's own act is
    /// `afresh`: it asks Claude Code unless an earlier look's ask is still under way, so a sign-in
    /// made since shows at once.
    func look(afresh: Bool = false) {
        check([.codex])
        let claudeDue = afresh ? !claudeAsking : claudeAsked.map { Date().timeIntervalSince($0) >= Self.claudeRecheck } ?? true
        guard claudeDue, live else { return }
        claudeAsked = Date()
        claudeAsking = true
        check([.claude]) { [weak self] in self?.claudeAsking = false }
    }

    func startSignIn() {
        guard live, login == nil else { return }
        let login = CodexLogin()
        self.login = login
        signIn = .waiting
        login.start { [weak self] outcome in
            guard let self else { return }
            self.login = nil
            switch outcome {
            case .signedIn:
                signIn = .idle
                changed(signedIn: true)
            case .cancelled:
                signIn = .idle
            case .failed(let reason, _):
                signIn = .failed(reason)
            }
        }
    }

    func cancelSignIn() {
        login?.cancel()
    }

    func signOut() {
        guard live, signIn != .signingOut else { return }
        signIn = .signingOut
        CodexLogin.signOut { [weak self] in
            self?.signIn = .idle
            self?.changed(signedIn: false)
        }
    }

    private func changed(signedIn: Bool) {
        availability[.codex] = signedIn ? .ready : .signedOut
        Log.write("[live-ink] responder \(signedIn ? "ready" : "signedOut") agent=codex source=signIn")
        onCodexSignIn?(signedIn)
    }
}

/// Codex's sign-in as a form row: the General tab's, under Live ink, while Codex is installed, and
/// that of setup's permissions page for live ink. The words are in docs/voice.md.
struct CodexSignInRow: View {
    @ObservedObject var status: ResponderStatus
    /// The button while Codex is signed out.
    let signInTitle: String
    /// Setup leaves signing out to Settings.
    let offersSignOut: Bool
    /// Whether Sign In carries the window's default button, as setup's next step does.
    var isDefault = false
    /// Names the button and the row's words in `spots`, for what is drawn over the row.
    var spot: (spots: ScreenSpots, button: String, words: String)?

    static let line = "Codex can answer live ink after a sign-in of its own, apart from the Codex app's."
    static let waiting = "You can finish signing in in your browser."
    static let signedIn = "Signed in to Codex"

    private var isWaiting: Bool { status.signIn == .waiting }
    private var isSignedIn: Bool { status.codex == .ready }

    private var title: String {
        if isWaiting { return Self.waiting }
        return isSignedIn ? Self.signedIn : Self.line
    }

    var body: some View {
        if status.codexInstalled {
            LabeledContent {
                if isWaiting {
                    Button("Cancel") { status.cancelSignIn() }
                } else if isSignedIn {
                    if offersSignOut {
                        Button("Sign Out") { status.signOut() }.disabled(status.signIn == .signingOut)
                    }
                } else {
                    Button(signInTitle) { status.startSignIn() }.keyboardShortcut(isDefault ? .defaultAction : nil)
                        .screenSpot(spot?.button ?? "", in: spot?.spots)
                }
            } label: {
                Text(title).screenSpot(spot?.words ?? "", in: spot?.spots)
                if case .failed(let reason) = status.signIn, !isSignedIn { Text(reason) }
            }
        }
    }
}
