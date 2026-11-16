import Foundation

extension SetupModel {
    /// What closing setup writes: setup is done, live ink's offer was made when its page showed, and
    /// the login choice made here.
    func record(in data: inout SettingsData, on defaults: UserDefaults = Identity.defaults) {
        data.setup = SetupState.done.rawValue
        if sawLiveInk { ThisMac.recordLiveInkOffer(in: &data, on: defaults) }
        if let choice = launchAtLoginChoice { data.launchAtLogin = choice }
    }

    /// Set until setup is done, so a quit and reopen part way through comes back to live ink's permissions.
    static var returnsToLiveInkSetup: Bool {
        get { Identity.defaults.bool(forKey: returnsToLiveInkSetupKey) }
        set { Identity.defaults.set(newValue, forKey: returnsToLiveInkSetupKey) }
    }
    private static let returnsToLiveInkSetupKey = "setupReturnsToLiveInkPermissions"
}
