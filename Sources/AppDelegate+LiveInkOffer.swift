import AppKit

extension AppDelegate {
    /// The one-time live ink offer, for an install that finished setup without seeing live ink's page,
    /// which the launch has decided before calling this. It opens the General tab, where the offer is,
    /// and is recorded as made, in the file and on this Mac (`Settings.liveInkOffered`, `ThisMac`).
    func offerLiveInk() {
        guard !(settings.data.liveInkOffered && ThisMac.saw(ThisMac.liveInkOfferKey)), !settings.data.liveInk else { return }
        settings.update { ThisMac.recordLiveInkOffer(in: &$0) }
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
