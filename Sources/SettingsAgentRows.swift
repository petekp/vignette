import SwiftUI

/// An agent's logo and name, and what its switch is doing or why it can't.
struct AgentName: View {
    let row: AgentPluginStatus
    var failure: String?
    /// Whether an install (true) or a removal (false) is running.
    var working: Bool?
    var justInstalled = false

    /// One line under the name, the most pressing first.
    private var note: String? {
        if let working { return working ? "Installing…" : "Removing…" }
        if !row.hasTool { return "Needs the `\(row.client == .claude ? "claude" : "codex")` command, which Vignette can't find." }
        // Claude Code reads its plugins when a session starts.
        if justInstalled && row.client == .claude { return "Sessions already open need `/reload-plugins` to use it." }
        return nil
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let image = Agent.logo(for: row.logoKey) {
                Image(nsImage: image).renderingMode(image.isTemplate ? .template : .original)
                    .resizable().aspectRatio(contentMode: .fit).frame(width: 18, height: 18)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                if failure == nil, let note {
                    Text(.init(note))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let failure {
                    Label { Text(failure) } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
                    }
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// The switch that lets Send name the apps a screenshot shows (`sendCaptureApps`, `CaptureApps`).
struct CaptureAppsSetting: View {
    @Binding var isOn: Bool

    var body: some View {
        Section {
            Toggle(isOn: $isOn) {
                Text("Tell agents which app a screenshot shows")
                Text("Send names the apps in screenshots you take from now on, such as Safari or Xcode. Vignette keeps the names with each screenshot, never a window's title.")
            }
        }
    }
}
