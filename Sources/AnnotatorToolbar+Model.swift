import AppKit
import SwiftUI

extension AnnotatorToolbar {
    final class Model: ObservableObject {
        @Published var tool: EditorCore.Tool? = nil
        /// The open image's pins that have a number. Past 0 the bar shows the Pins button.
        @Published var pinCount = 0
        /// Those of them that are not resolved, which the Pins button counts.
        @Published var openPinCount = 0
        @Published var shown = false     // drives the entrance and exit
        /// The answer whose sessions the target's menu lists (`DestinationChoice.replacesList`). Whether
        /// a reply's Claude Code session has closed is read from its `complete`, so the bar shows no
        /// Reply for a closed one until this image's list does.
        @Published private(set) var listing = DestinationChoice.Answer.nothingListed { didSet { refreshTargetRow(); reportOffer() } }
        /// Every client has answered. Until then a session missing from the list may only be late.
        @Published private(set) var listed = false
        /// The session the open image came from, when it names one: an agent's reply, or a push
        /// that said which session it was. The bar is Reply alone, so the target is never guessed at.
        @Published private(set) var replyTo: AgentDestination? { didSet { reportOffer() } }
        /// Where Send goes: the default until someone picks another in the menu.
        @Published private(set) var target: AgentDestination? { didSet { refreshTargetRow(); reportOffer() } }
        private var cachedTargetRow: SessionMenu.Row?

        /// The target's row among the sessions on offer, cached: wording every row is too much for a
        /// view body that runs on every keystroke.
        func targetRow(for target: AgentDestination) -> SessionMenu.Row {
            if let cached = cachedTargetRow, cached.destination.id == target.id { return cached }
            return SessionMenu.row(of: target, among: listing.sessions)
        }

        private func refreshTargetRow() {
            cachedTargetRow = target.map { SessionMenu.row(of: $0, among: listing.sessions) }
        }
        /// The target was picked in the menu, so no later answer changes it.
        private var picked = false
        /// The target is the image before's, kept while the bar stays up so Send does not leave it
        /// for the 60 to 90 ms the listing takes. The first answer that settles a target replaces it.
        private var carried = false
        /// One more at each `begin`, so a menu pick lands only on the image whose menu it came from.
        private(set) var imageNumber = 0
        /// The `imageNumber` the target menu last opened on, the image its picks belong to.
        private(set) var targetMenuImage: Int?
        func targetMenuOpened() { targetMenuImage = imageNumber }
        /// From Send's press until the bar leaves. The button shows the send and takes no second click.
        /// A new press puts a failure's reason away.
        @Published var sending = false { didSet { if sending { failure = nil } } }
        /// Why the last send failed before its request was stored, and what to do about it. While it
        /// is set the button says "Not sent" and the reason stands beside it, until the person moves
        /// on: a click elsewhere, or Send again.
        @Published var failure: String?
        var notSent: Bool { failure != nil }
        /// The open image's drawing is exactly what its agent sent (`Agent.hasSentDrawing`).
        @Published var drawingAsSent = false
        /// Counts those failures; each one shakes the button.
        @Published private(set) var failures = 0

        func sendFailed(_ reason: String) {
            sending = false
            failure = reason
            failures += 1
        }

        /// A new image opens with a button that offers Send.
        func resetSend() {
            sending = false
            failure = nil
        }
        /// What the person typed to go with Send or Reply, as typed. It is stored with the image's
        /// drawing, and the image opens with the words it was last left with (`restore`), after a
        /// send, a failed send, Copy or a close alike.
        @Published var message = "" { didSet { if message != oldValue { onMessageChanged?() } } }
        var onMessageChanged: (() -> Void)?
        /// The words the image opened with.
        private(set) var messageOnOpen = ""
        /// The image opened with `message`, the words it was last left with, or "".
        func restore(message: String) {
            messageOnOpen = message
            self.message = message
        }
        /// The bar's panel holds the keys, which it does only while the message field is typed in.
        @Published var keyed = false
        /// The message field took the keys on its own as the image opened, and has kept them since.
        var tookKeysOnOpen = false
        /// A tool letter typed first into that field, waiting to learn whether it began a word.
        var toolLetter = HeldToolLetter()

        /// A control Tab reaches, in the bar's order.
        enum Control: Hashable {
            case tool(EditorCore.Tool), pins, copy, target, message, action

            /// For `[state]`: `copy`, or `tool.arrow`.
            var name: String {
                if case .tool(let tool) = self { return "tool.\(tool.rawValue)" }
                return "\(self)"
            }
        }
        /// The control the keyboard's focus is on, drawn with a ring. The editor keeps the keys
        /// meanwhile, and gives Tab and Space to the bar; the message field takes the keys itself.
        @Published var focus: Control?
        /// Counts the asks to type in the message field: Tab onto it, or M or P in the editor.
        @Published private(set) var messageAsks = 0
        func askForMessage() { messageAsks += 1 }
        /// Counts presses on the bar. A press puts a tooltip away, as AppKit's does.
        @Published private(set) var presses = 0
        func pressed() { presses += 1 }
        /// Points from the bar's bottom edge down to the bottom of the visible screen, the Dock's top
        /// when it is there. The message field grows down into it, and up out of the bar past it.
        @Published var roomBelow: CGFloat = .greatestFiniteMagnitude

        /// The controls on the bar for this offer.
        var controls: [Control] {
            let offer = self.offer
            var controls = EditorCore.Tool.allCases.map(Control.tool)
            if pinCount > 0 { controls.append(.pins) }
            if offer.destination == nil || offer.isSend { controls.append(.copy) }
            if offer.offersTarget { controls.append(.target) }
            if offer.destination != nil { controls += nothingToReply ? [.message] : [.message, .action] }
            return controls
        }


        var offer: ToolbarOffer {
            ToolbarOffer(replyTo: replyTo, destinations: listing.list, listed: listing.complete, target: target, startable: listing.startable)
        }

        /// Called with the offer each time it changes, whatever changed it: an answer, a new image or a pick.
        var onOfferChanged: ((ToolbarOffer) -> Void)?
        private var reportedOffer = ToolbarOffer.copy

        private func reportOffer() {
            let offer = self.offer
            guard offer != reportedOffer else { return }
            reportedOffer = offer
            onOfferChanged?(offer)
        }

        /// A new image: nothing listed yet, and nothing picked. `carryingTarget`, when the bar is
        /// on screen for the image before, keeps that image's list and target until this one's settle.
        func begin(replyTo: AgentDestination?, carryingTarget: Bool) {
            self.replyTo = replyTo
            imageNumber += 1
            focus = nil
            tookKeysOnOpen = false
            toolLetter = HeldToolLetter()
            listed = false
            picked = false
            carried = carryingTarget && target != nil
            guard !carried else { return }
            listing = .nothingListed
            target = nil
        }

        /// Another client answered. The target settles on the first answer that decides a pick
        /// (`DestinationChoice`). Once settled it changes only when its session is gone from the whole
        /// list, so it never changes under the pointer.
        func answered(_ answer: DestinationChoice.Answer) {
            let list = answer.list
            if DestinationChoice.replacesList(answer.complete, over: listing.complete) { listing = answer }
            listed = answer.complete
            if let current = target, let fresh = list.first(where: { $0.id == current.id }) { target = fresh }
            guard !picked else { return }
            if carried {
                guard answer.decided else { return }
                carried = false
                target = answer.pick
                return
            }
            let gone = answer.complete && target.map { current in !list.contains { $0.id == current.id } } == true
            guard target == nil || gone, answer.decided else { return }
            target = answer.pick
        }

        /// A hand pick, which also chooses to write to it: the field counts as pressed from here.
        func pick(_ destination: AgentDestination) {
            target = destination
            picked = true
            carried = false
            tookKeysOnOpen = false
        }

        func isHandPick(_ destination: AgentDestination) -> Bool { picked && target?.id == destination.id }
    }
}
