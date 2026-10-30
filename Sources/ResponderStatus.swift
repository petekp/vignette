import SwiftUI

/// What Settings and setup show about live ink's responders: whether Claude Code and Codex can
/// answer, and Codex's sign-in, which they start and end (docs/live-ink-responders.md). Live ink's
/// own checks are `LiveResponders`'; a sign-in or sign-out here reaches them as
/// `codexSignInChanged`.
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

    @Published private(set) var claude = LiveResponder.Availability.checking
    @Published private(set) var codex = LiveResponder.Availability.checking
    @Published private(set) var signIn = SignIn.idle

    private let live: Bool
    private var login: CodexLogin?
    private var claudeAsked: Date?

    private init(live: Bool) {
        self.live = live
        if !live { codex = .notInstalled }
    }

    /// Whether Codex is installed, once its check has answered.
    var codexInstalled: Bool { codex == .ready || codex == .signedOut }

    var costNote: String { SetupInkCopy.costNote(claude: claude.canAnswer, codex: codex == .ready) }

    /// Looks again: Codex each time, since its check reads one file, and Claude Code at most every
    /// `claudeRecheck`.
    func look() {
        guard live else { return }
        Task { [weak self] in
            let found = await LiveResponder.availability(of: .codex)
            if let self, found != codex { codex = found }
        }
        guard claudeAsked.map({ Date().timeIntervalSince($0) >= Self.claudeRecheck }) ?? true else { return }
        claudeAsked = Date()
        Task { [weak self] in
            let found = await LiveResponder.availability(of: .claude)
            if let self, found != claude { claude = found }
        }
    }

    /// Whether either agent can answer, for setup's live ink page: Claude Code's answer, unless only
    /// Codex can.
    func answer() async -> LiveResponder.Availability {
        live ? await LiveResponder.availability() : .checking
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
        CodexLogin.signOut(binary: LiveResponder.codexBinary()) { [weak self] in
            self?.signIn = .idle
            self?.changed(signedIn: false)
        }
    }

    private func changed(signedIn: Bool) {
        codex = signedIn ? .ready : .signedOut
        NotificationCenter.default.post(name: .codexSignInChanged, object: nil, userInfo: ["signedIn": signedIn])
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
                    Button(signInTitle) { status.startSignIn() }
                }
            } label: {
                Text(title)
                if case .failed(let reason) = status.signIn, !isSignedIn { Text(reason) }
            }
        }
    }
}

/// The row for Codex's sign-in on setup's permissions page for live ink, only while Codex is
/// installed and Claude Code cannot answer: without it, a person with Codex alone would finish
/// setup with live ink unable to answer.
struct CodexSetupSection: View {
    @ObservedObject var status: ResponderStatus

    var body: some View {
        if status.codexInstalled, !status.claude.canAnswer {
            Section { CodexSignInRow(status: status, signInTitle: "Sign In to Codex…", offersSignOut: false) }
        }
    }
}

/// Setup's cost line, `SetupInkCopy.costNote`, for the agents that can answer. It is always on the
/// page, so it is what looks at them when the page appears.
struct ResponderCostNote: View {
    @ObservedObject var status: ResponderStatus

    var body: some View {
        Text(status.costNote).onAppear { status.look() }
    }
}
