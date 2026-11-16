import SwiftUI

/// Live ink's one-time offer, at the top of the Live Ink tab.
struct LiveInkOfferSection: View {
    let pair: String
    let answer: (Bool) -> Void
    @ObservedObject private var responders = ResponderStatus.shared

    var body: some View {
        Section {
            Text(SetupInkCopy.offer(pair: pair, agent: responders.namedAgent))
            HStack {
                Button("Not Now") { answer(false) }
                Button("Turn On") { answer(true) }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
