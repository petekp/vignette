import AppKit
import SwiftUI

/// The Settings window's Live Ink tab: the switch, the one-time offer, Codex's sign-in, the pair to
/// hold, and the permissions and speech rows that go with them. It is a form's sections, so
/// `SettingsView` places it in its `Form`.
@MainActor
struct LiveInkSettings: View {
    let callbacks: SettingsWindowController.Callbacks

    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var responders = ResponderStatus.shared
    @State private var trusted = ModifierTap.trusted(prompt: false)
    @State private var screenRecording = ScreenRecording.granted
    @State private var speechAllowed = SpeechPermission.granted
    @State private var offeringLiveInk = false
    /// Why the last chord picked cannot be taken, or nil. Shown under the picker.
    @State private var chordRefusal: String?
    /// Neither macOS's Accessibility, Screen Recording nor speech grants announce a change, so the
    /// rows that show them look again while the window is up.
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    static func switchLine(pair: String) -> String {
        "Hold \(pair) to draw anywhere on your screen. You can also share your drawings with an agent session."
    }

    var body: some View {
        Group {
            // A header rather than a row, since a boxed row reads as a setting.
            Section {} header: { LiveInkTabTitle() }
            if offeringLiveInk {
                LiveInkOfferSection(pair: settings.data.liveInkChordChoice.glyphs, answer: answerLiveInkOffer)
            }
            Section {
                Toggle(isOn: Binding(get: { settings.data.liveInk }, set: { on in
                    settings.update { $0.liveInk = on }
                    if on { ScreenRecording.request() }
                })) {
                    Text("Live ink")
                    Text(Self.switchLine(pair: settings.data.liveInkChordChoice.glyphs))
                }
                CodexSignInRow(status: responders, signInTitle: "Sign In…", offersSignOut: true)
                Picker("Hold to draw", selection: Binding(get: { settings.data.liveInkChordChoice }, set: { chord in
                    let refusal = chord.refusal(against: HotKeySpec.parse(settings.data.recentHotkey))
                    withAnimation(SettingsView.noticeMotion) { chordRefusal = refusal }
                    if refusal == nil { settings.update { $0.liveInkChord = chord.rawValue } }
                })) {
                    ForEach(LiveInkChord.allCases, id: \.self) { chord in Text(chord.glyphs).tag(chord) }
                }
                // A pick refused now, or the pair a stack shortcut set elsewhere already starts with.
                if let refusal = chordRefusal ?? settings.data.liveInkChordChoice.refusal(against: HotKeySpec.parse(settings.data.recentHotkey)) {
                    Text(refusal).font(.footnote).foregroundStyle(.secondary).transition(.opacity)
                }
                // The General tab's shortcut row asks for the same permission.
                if settings.data.liveInk, !settings.data.usesDoubleTap, !trusted {
                    PermissionRow(symbol: "lock.fill", title: "Needs Accessibility permission",
                                  reason: SetupInkCopy.liveInkAccessibilityReason, status: .refused) { Accessibility.request() }
                }
                if settings.data.liveInk, !screenRecording {
                    PermissionRow(symbol: "lock.fill", title: "Needs Screen Recording permission",
                                  reason: SetupInkCopy.liveInkScreenRecordingReason, status: .refused) { ScreenRecording.openSystemSettings() }
                }
                if settings.data.liveInk {
                    Toggle(isOn: Binding(get: { settings.data.liveInkSpeech }, set: { on in
                        settings.update { $0.liveInkSpeech = on }
                        if on, !SpeechPermission.granted, SpeechPermission.unanswered { SpeechPermission.request { speechAllowed = $0 } }
                    })) {
                        Text("Speak while you draw")
                        Text("What you say goes into the note beside your ink. Your voice stays on this Mac.")
                    }
                    if settings.data.liveInkSpeech, !speechAllowed {
                        PermissionRow(symbol: "lock.fill", title: "Needs microphone and speech recognition permission",
                                      reason: SetupInkCopy.liveInkSpeechReason, status: .refused) {
                            if SpeechPermission.unanswered { SpeechPermission.request { speechAllowed = $0 } } else { SpeechPermission.openSystemSettings() }
                        }
                    }
                    if settings.data.liveInkSpeech {
                        Toggle("Ask when you let go", isOn: Binding(get: { settings.data.liveInkSendWhenQuiet }, set: { on in settings.update { $0.liveInkSendWhenQuiet = on } }))
                    }
                }
            }
            // A stack shortcut changed outside this window can bring or end a collision with the pair.
            .animation(SettingsView.noticeMotion, value: settings.data.recentHotkey)
            // On the section that is always there, so each runs once.
            .onAppear(perform: look)
            .onReceive(poll) { _ in look() }
            // Asking the agents can run `claude auth status`, so the tab asks as it appears and as
            // its window becomes key, not on the poll.
            .onAppear { responders.look(afresh: true) }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
                if (note.object as? NSWindow)?.contentView is NSHostingView<SettingsView> { responders.look(afresh: true) }
            }
        }
    }

    private func look() {
        trusted = ModifierTap.trusted(prompt: false)
        screenRecording = ScreenRecording.granted
        speechAllowed = SpeechPermission.granted
        let offering = callbacks.liveInkOffered()
        if offering != offeringLiveInk { withAnimation(SettingsView.noticeMotion) { offeringLiveInk = offering } }
    }

    private func answerLiveInkOffer(_ on: Bool) {
        withAnimation(SettingsView.noticeMotion) { offeringLiveInk = false }
        callbacks.answerLiveInkOffer(on)
    }
}

/// "Live Ink" in the ink's gel, centred at the top of the tab, smaller than setup's title.
private struct LiveInkTabTitle: View {
    static let scale: CGFloat = 0.55
    @StateObject private var writer = InkTitleWriter(scale: LiveInkTabTitle.scale)

    var body: some View {
        Color.clear
            .frame(width: SetupInkTitle.size.width * Self.scale, height: SetupInkTitle.size.height * Self.scale)
            .overlay { SetupInkCanvas(stage: writer.stage).allowsHitTesting(false) }
            .frame(maxWidth: .infinity)
            .accessibilityElement()
            .accessibilityLabel("Live Ink")
            .accessibilityAddTraits(.isHeader)
            .onAppear { writer.appear() }
            .onDisappear { writer.disappear() }
    }
}
