import SwiftUI

/// An agent's logo from the bundle, or the fallback symbol for a vendor without one. `template`
/// draws it in the foreground colour, for the white of a filled button. A one-colour logo is always
/// drawn in the foreground colour.
struct AgentLogo: View {
    let client: AgentClient
    let template: Bool

    var body: some View {
        if let logo = Agent.logo(for: client.rawValue) {
            Image(nsImage: logo).renderingMode(template || logo.isTemplate ? .template : .original).resizable().aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: Agent.fallbackSymbol).resizable().aspectRatio(contentMode: .fit)
        }
    }
}
