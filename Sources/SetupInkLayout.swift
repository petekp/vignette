import SwiftUI

/// The row for Codex's sign-in on setup's permissions page for live ink, while setup names Codex
/// (`namedAgent`). Its Sign In is the step after the permissions, which the guide points at.
struct CodexSetupSection: View {
    @ObservedObject var status: ResponderStatus
    let spots: ScreenSpots
    /// Whether both permissions are allowed, which makes the sign-in the next step.
    let permissionsDone: Bool
    private let step = SetupInkGuide.Step.codexSignIn

    var body: some View {
        if status.namedAgent == .codex {
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
/// guide's note. It switches on the row rather than on what fits, so the page stays still across
/// the sign-in's steps, whose rows differ in height.
struct LiveInkSetupTop: ViewModifier {
    @ObservedObject var status: ResponderStatus

    func body(content: Content) -> some View {
        content.padding(.top, status.namedAgent == .codex ? 30 : 60)
    }
}

/// The lines under setup's permissions for live ink: why macOS may reopen Vignette, while Screen
/// Recording is missing, and what leaves the Mac, for the agents that can answer, with the room the
/// guide's marks take on either side of them (`SetupInkGuide.Rooms`). It is always on the page, so
/// it is what looks at the agents when the page appears.
struct LiveInkSetupFooter: View {
    @ObservedObject var status: ResponderStatus
    let spots: ScreenSpots
    let trusted: Bool
    let screenRecording: Bool

    /// The lines' gap under the rows while the label needs no room there.
    private static let gap: CGFloat = 8

    /// Whether the rows keep room under them for the label beside the next button: an Allow button,
    /// or Sign In to Codex… while Codex's row shows it. Once Codex is signed in or signing in, the
    /// guide's note needs the page's room under these lines instead.
    private var keepsLabelRoom: Bool { status.namedAgent != .codex || status.offersCodexSignIn }

    /// Whether the guide draws its note under these lines, which it does once every step is taken.
    /// The note's room is kept only then, since the page's height is fixed: with the label's room as
    /// well, the page outgrew the window after a failed sign-in.
    private var drawsNote: Bool {
        SetupInkGuide.Pointing(trusted: trusted, screenRecording: screenRecording, codexSignIn: status.codexSignInLeft,
                               signingIn: status.signIn == .waiting) == .ready
    }

    var body: some View {
        let rooms = SetupInkGuide.Rooms(ui: Settings.shared.data.ui, agent: status.namedAgent)
        Section {} footer: {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    if !screenRecording { Text(SetupInkCopy.reopenNote) }
                    Text(status.costNote)
                }
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .screenSpot(SetupInkGuide.footer, in: spots)
                if drawsNote { Color.clear.frame(height: rooms.note).screenSpot(SetupInkGuide.noteRoom, in: spots) }
            }
            .padding(.top, keepsLabelRoom ? rooms.label : Self.gap)
            .onAppear { status.look() }
        }
    }
}
