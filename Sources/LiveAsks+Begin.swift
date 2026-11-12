import Foundation

extension LiveAsks {
    /// What of the person's `ink` ask `id`'s picture and message carry: none for an ask about the
    /// window under the pointer, or one following its answer.
    func drawnInk(_ ink: [Mark], for id: Ask.ID) -> [Mark] { ask(id)?.spot == nil ? ink : [] }

    /// The reply the person answered with one of its buttons, and the words sent.
    struct Following: Equatable {
        var reply: Mark
        var pick: LiveAnswerActions.Pick
        var words: String
    }

    /// Why an ask did not begin.
    enum Refusal: String, Equatable {
        case noInk = "There's no ink to ask about."

        var detail: String {
            switch self {
            case .noInk: "no ink"
            }
        }
    }

    enum Begun: Equatable {
        /// `about` is oldest first and its last mark has a shape, centred on `point`. For an ask about
        /// the window under the pointer, `about` is empty and `point` is the pointer. The ask looks for
        /// its packet at once, whatever else is under way. Following a reply, `effects` ends the answer
        /// it takes the place of.
        case began(Ask.ID, about: [Mark], point: CGPoint, effects: [Effect])
        /// Following a reply, the answer it hangs from comes back, saying why.
        case refused(Refusal, effects: [Effect])
    }
}
