import SwiftUI

/// Setup's page for live ink's two permissions, after Use Live Ink, with Codex's sign-in where only
/// Codex can answer. Each is asked for from its own button, and the agent's light points at the
/// next one. Once Screen Recording is allowed, its row's button raises macOS's window picker
/// question, and the row is done once that is answered.
struct LiveInkSetupPage: View {
    let guide: SetupInkGuide
    let trusted: Bool
    let screenRecording: Bool
    let pickerQuestion: PickerQuestion.Status
    /// Where the Allow buttons go: macOS or the Setup Lab.
    let callbacks: SetupWindowController.Callbacks
    @ObservedObject var responders: ResponderStatus
    @State private var askedScreenRecording = SetupModel.returnsToLiveInkSetup
    private let accessibility = SetupInkGuide.Step.accessibility
    private let recording = SetupInkGuide.Step.screenRecording

    private var screenRecordingSetUp: Bool { screenRecording && pickerQuestion == .answered }

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Text("Set Up Live Ink").font(.title).bold()
                Text("macOS asks for two permissions.").foregroundStyle(.secondary)
            }
            .screenSpot(SetupInkGuide.header, in: guide.spots)
            .modifier(LiveInkSetupTop(status: responders))
            Form {
                Section {
                    PermissionRow(symbol: "hand.draw", title: "Accessibility", reason: "So you can draw while holding \(Settings.shared.data.liveInkChordChoice.glyphs).",
                                  status: trusted ? .granted : .ask, isDefault: !trusted,
                                  spot: (guide.spots, accessibility.button, accessibility.words)) {
                        callbacks.askAccessibility()
                    }
                    .screenSpot(accessibility.row, in: guide.spots)
                    PermissionRow(symbol: "rectangle.dashed.badge.record", title: "Screen Recording",
                                  reason: screenRecording ? SetupInkCopy.pickerQuestionReason
                                      : SetupInkCopy.screenRecordingReason(agent: responders.namedAgent),
                                  status: screenRecordingSetUp ? .granted : .ask,
                                  isDefault: trusted && !screenRecordingSetUp, busy: pickerQuestion == .waiting,
                                  button: askedScreenRecording && !screenRecording ? "Open Settings…" : "Allow…",
                                  spot: (guide.spots, recording.button, recording.words)) {
                        guard !screenRecording else { return callbacks.askPickerQuestion() }
                        if askedScreenRecording { callbacks.openScreenRecordingSettings() } else { callbacks.askScreenRecording() }
                        askedScreenRecording = true
                        callbacks.askedForScreenRecording()
                    }
                    .screenSpot(recording.row, in: guide.spots)
                }
                CodexSetupSection(status: responders, spots: guide.spots, permissionsDone: trusted && screenRecordingSetUp)
                LiveInkSetupFooter(status: responders, spots: guide.spots, trusted: trusted, screenRecording: screenRecording,
                                   pickerQuestion: pickerQuestion)
            }
            .formStyle(.grouped).scrollDisabled(true).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .inkStage(guide.stage)
        .onDisappear { guide.leave() }
    }
}
