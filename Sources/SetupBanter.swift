import SwiftUI

/// What setup's shortcut page says to each hold of the shortcut: Pete's script, which
/// `docs/voice.md` records as a deliberate exception to Vignette's voice. The first hold says
/// line 1. A later hold says the next line only while the line before it is showing. "Bye." moves
/// setup on to the next page, and coming back to the shortcut page after it is greeted once
/// before the script goes on. The last line stays.
struct SetupBanter: Equatable {
    struct Line: Equatable {
        let text: String
        var muted = false
    }

    private static let script: [Line] = [
        "You're a quick learner! Think you got it down?",
        "Amazing, you did it again!",
        "Sheesh. You're an expert now.",
        "You're THE expert, now.",
        "You've done this before, haven't you?",
        "The ease with which you do it... marvelous.",
        "Must feel nice to be so good at something.",
        "Very good. Let's move on shall we?",
        "Great.",
        "Nice.",
        "Hmm.",
        "I see what you're doing.",
        "Okay, ha ha. Let's continue on, yeah?",
        "Yes, you did it again.",
        "You're trying to get a rise out of me aren't you.",
        "Let's get a rise out of the ol' setup menu, very funny.",
        "Picking on a setup menu is an interesting choice.",
        "...",
        ".....",
        "What do you want from me?",
        "Bro.",
        "C'mon bro.",
        "BRUH.",
        "Okay whatever. I'll just wait here.",
        "...",
        "...",
        "...",
        "Ugh.",
        "Fine, that's it.",
        "One more time and I'm pushing the button myself.",
        "Bye.",
        "Hi! Welcome to the setup... oh, it's you.",
        "Dude. No.",
        "F%@#!",
        "I'm out. ✌️",
    ].map { Line(text: $0) } + [Line(text: "The setup assistant has peaced out.", muted: true)]
    private static let bye = 30
    private static let greeting = 31

    /// How long "Bye." shows before setup moves on. A time to read it, so the motion setting leaves it alone.
    static let byeDwell: TimeInterval = 1.2

    /// Where the script is: nil before the first hold.
    private(set) var step: Int?
    /// Every hold that reached a line, so the line's symbol bounces even when its words stay.
    private(set) var holds = 0

    var line: Line? { step.map { Self.script[$0] } }
    var saysBye: Bool { step == Self.bye }

    mutating func hold(lineShows: Bool) {
        guard let step else {
            self.step = 0
            holds = 1
            return
        }
        guard lineShows else { return }
        holds += 1
        if step != Self.bye { self.step = min(step + 1, Self.script.count - 1) }
    }

    mutating func leftPage() {
        if step == Self.bye { step = Self.greeting }
    }
}

/// One line of the script, in the status row's place.
struct SetupBanterLine: View {
    let line: SetupBanter.Line
    let bounce: Int

    var body: some View {
        if line.muted {
            Text(line.text).italic().foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Label {
                Text(line.text).fixedSize(horizontal: false, vertical: true).contentTransition(.opacity)
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.installed)
                    .symbolEffect(.bounce, value: bounce)
            }
        }
    }
}
