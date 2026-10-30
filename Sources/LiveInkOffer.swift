import AppKit
import SwiftUI

extension AppDelegate {
    /// The one-time live ink offer, for an install that finished setup without seeing live ink's page. It
    /// opens the General tab, where the offer is, and is recorded as made (`Settings.liveInkOffered`).
    func offerLiveInk() {
        guard !settings.data.liveInkOffered, !settings.data.liveInk, SetupState(rawValue: settings.data.setup) == .done else { return }
        settings.update { $0.liveInkOffered = true }
        liveInkOfferOpen = true
        Log.write("[settings] offered live ink")
        settingsWindow.show(tab: .general, activating: false)
    }

    /// The offer's answer: Turn On turns live ink on, as the General tab's switch does.
    func answerLiveInkOffer(_ on: Bool) {
        liveInkOfferOpen = false
        if on {
            settings.update { $0.liveInk = true }
            ScreenRecording.request()
        }
        Log.write("[settings] live ink offer \(on ? "turned on" : "not now")")
    }
}

/// Live ink's one-time offer, at the top of the General tab.
struct LiveInkOfferSection: View {
    let pair: String
    let answer: (Bool) -> Void

    var body: some View {
        Section {
            Text(SetupInkCopy.offer(pair: pair))
            HStack {
                Button("Not Now") { answer(false) }
                Button("Turn On") { answer(true) }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
