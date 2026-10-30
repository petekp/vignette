import SwiftUI

/// One row for every permission, in setup and in Settings: a symbol, what is needed, why, and
/// Allow…. A check replaces the button once it is granted. A refusal swaps the symbol for a
/// warning, and Allow… then opens Privacy & Security, since macOS doesn't ask twice.
struct PermissionRow: View {
    enum Status { case ask, refused, granted }
    let symbol: String
    let title: String
    var reason: String?
    let status: Status
    /// Setup gives the window's default button to the next step still to take.
    var isDefault = false
    /// macOS's own prompt is up and has not been answered.
    var busy = false
    var button = "Allow…"
    /// Names the button and the row's words in `spots`, for what is drawn over the row.
    var spot: (spots: ScreenSpots, button: String, words: String)?
    let allow: () -> Void

    var body: some View {
        LabeledContent {
            if status == .granted {
                Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(Color.installed)
                    .accessibilityLabel("Allowed")
            } else {
                Button(button, action: allow).keyboardShortcut(isDefault && !busy ? .defaultAction : nil).disabled(busy)
                    .screenSpot(spot?.button ?? "", in: spot?.spots)
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let reason {
                        Text(reason).font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .screenSpot(spot?.words ?? "", in: spot?.spots)
            } icon: {
                if status == .refused {
                    Image(systemName: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
                } else {
                    Image(systemName: symbol).foregroundStyle(.secondary)
                }
            }
        }
    }
}
