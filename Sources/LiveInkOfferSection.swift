import SwiftUI

/// Live ink's one-time offer, at the top of the General tab.
struct LiveInkOfferSection: View {
    let pair: String
    let answer: (Bool) -> Void
    @ObservedObject private var responders = ResponderStatus.shared

    var body: some View {
        Section {
            Text(SetupInkCopy.offer(pair: pair, codex: responders.codexAlone))
            HStack {
                Button("Not Now") { answer(false) }
                Button("Turn On") { answer(true) }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
