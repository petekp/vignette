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

    /// Whether Codex is the one agent that can answer, now or once it is signed in: it is installed
    /// and Claude Code cannot answer. Setup then offers Codex's sign-in, since without it the person
    /// would finish setup with live ink unable to answer, and names Codex where it would name Claude.
    var codexAlone: Bool { codexInstalled && !claude.canAnswer }

    /// Whether setup's permissions page still asks for Codex's sign-in.
    var codexSignInLeft: Bool { codexAlone && codex != .ready }

    /// Whether setup's Codex row shows Sign In to Codex…, which it does while the sign-in is left and
    /// not waiting in the browser.
    var offersCodexSignIn: Bool { codexSignInLeft && signIn != .waiting }

    var costNote: String { SetupInkCopy.costNote(claude: claude.canAnswer, codex: codex == .ready || codexAlone) }

    /// Setup's live ink page's line after the one about drawing: who to ask, or why Claude cannot
    /// answer when neither agent can.
    var askLine: String {
        claude.canAnswer || codexAlone ? SetupInkCopy.askLine(codex: codexAlone) : claude.problem ?? ""
    }

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

/// The row for Codex's sign-in on setup's permissions page for live ink, while `codexAlone`. Its
/// Sign In is the step after the permissions, which the guide points at.
struct CodexSetupSection: View {
    @ObservedObject var status: ResponderStatus
    let spots: ScreenSpots
    /// Whether both permissions are allowed, which makes the sign-in the next step.
    let permissionsDone: Bool
    private let step = SetupInkGuide.Step.codexSignIn

    var body: some View {
        if status.codexAlone {
            Section {
                CodexSignInRow(status: status, signInTitle: "Sign In to Codex…", offersSignOut: false, isDefault: permissionsDone,
                               spot: (spots, step.button, step.words))
                    .screenSpot(step.row, in: spots)
            }
        }
    }
}

/// Where setup's permissions page for live ink starts its title. The page's height is fixed, so
/// while Codex's row shows, the title starts higher to keep room under the cost line for the
/// guide's note.
struct LiveInkSetupTop: ViewModifier {
    @ObservedObject var status: ResponderStatus

    func body(content: Content) -> some View {
        content.padding(.top, status.codexAlone ? 30 : 60)
    }
}

/// The lines under setup's permissions for live ink: why macOS may reopen Vignette, while Screen
/// Recording is missing, and what leaves the Mac, for the agents that can answer. It is always on
/// the page, so it is what looks at the agents when the page appears.
struct LiveInkSetupFooter: View {
    @ObservedObject var status: ResponderStatus
    let spots: ScreenSpots
    let reopens: Bool

    /// Room under the rows for the label beside the next button: an Allow button, or Sign In to
    /// Codex… while Codex's row shows it. Once Codex is signed in or signing in, the guide's note
    /// needs the room under these lines instead.
    private var roomAbove: CGFloat { !status.codexAlone || status.offersCodexSignIn ? 30 : 8 }

    var body: some View {
        Section {} footer: {
            VStack(alignment: .leading, spacing: 6) {
                if reopens { Text(SetupInkCopy.reopenNote) }
                Text(status.costNote)
            }
            .font(.caption).foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .screenSpot(SetupInkGuide.footer, in: spots)
            .padding(.top, roomAbove)
            .onAppear { status.look() }
        }
    }
}
