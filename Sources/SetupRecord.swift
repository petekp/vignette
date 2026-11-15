import Foundation

extension SetupModel {
    /// What closing setup writes: setup is done, live ink's offer was made when its page showed, and
    /// the login choice made here.
    func record(in data: inout SettingsData, on defaults: UserDefaults = Identity.defaults) {
        data.setup = SetupState.done.rawValue
        if sawLiveInk { ThisMac.recordLiveInkOffer(in: &data, on: defaults) }
        if let choice = launchAtLoginChoice { data.launchAtLogin = choice }
    }
}
