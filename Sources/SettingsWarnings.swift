import SwiftUI

/// The warnings at the top of the Settings window's General tab: a settings.json this launch could
/// not parse or create, or a write that failed. Only a person who edits the file by hand, whose
/// `~/.config` another tool owns, or whose disk refuses the write meets these, and this window is
/// where they look. Both can be true after a launch that set a bad file aside; each says something
/// the other does not.
struct SettingsWarnings: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        let showsNotSaved = settings.lastWriteFailed
        if showsNotSaved || settings.startupNotice != nil {
            Section {
                if showsNotSaved { warning(Settings.notSavedNotice) }
                if let notice = settings.startupNotice { warning(notice) }
            }
        }
    }

    private func warning(_ notice: Settings.Notice) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                Text(notice.detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
        }
    }
}
