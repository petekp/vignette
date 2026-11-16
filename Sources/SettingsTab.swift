import AppKit

/// One tab of the Settings window: a toolbar item, the window title while it is up, and one form.
enum SettingsTab: String, CaseIterable {
    case general, screenshots, liveInk, agents, developer

    var name: String {
        switch self {
        case .general: return "General"
        case .screenshots: return "Screenshots"
        case .liveInk: return "Live Ink"
        case .agents: return "Agents"
        case .developer: return "Developer"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .screenshots: return "camera.viewfinder"
        case .liveInk: return "scribble"
        case .agents: return "sparkles"
        case .developer: return "wrench.and.screwdriver"
        }
    }

    var itemIdentifier: NSToolbarItem.Identifier { NSToolbarItem.Identifier("settings.\(rawValue)") }

    init?(itemIdentifier: NSToolbarItem.Identifier) {
        guard let tab = SettingsTab.allCases.first(where: { $0.itemIdentifier == itemIdentifier }) else { return nil }
        self = tab
    }
}
