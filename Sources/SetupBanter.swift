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

    /// Where the script is: `step` is nil before the first hold, `holds` counts the holds that
    /// reached a line, so the symbol bounces even when the words stay, and `proven` is whether the
    /// shortcut as it is now was held.
    private struct Place: Equatable {
        var step: Int?
        var holds = 0
        var proven = false
    }
    /// A hold counts at once, and shows once the editor it opened has closed (`reveal`).
    private var counted = Place()
    private var shown = Place()

    var line: Line? { shown.proven ? shown.step.map { Self.script[$0] } : nil }
    var bounce: Int { shown.holds }
    var saysBye: Bool { shown.step == Self.bye }

    /// The first hold starts the script wherever it happens. A later one moves it on only while
    /// `rowReady` and its line shows, and "Bye." stays until the page is left.
    mutating func hold(rowReady: Bool) {
        let lineShows = rowReady && line != nil
        counted.proven = true
        guard let step = counted.step else {
            counted.step = 0
            counted.holds = 1
            return
        }
        guard lineShows else { return }
        counted.holds += 1
        if step != Self.bye { counted.step = min(step + 1, Self.script.count - 1) }
    }

    mutating func reveal() { shown = counted }

    mutating func shortcutChanged() {
        counted.proven = false
        shown.proven = false
    }

    mutating func leftPage() {
        if counted.step == Self.bye { counted.step = Self.greeting }
        if shown.step == Self.bye { shown.step = Self.greeting }
    }
}

extension View {
    /// Answers each hold of the shortcut with `banter`'s next line, once the editor the hold
    /// opened has closed, and presses Continue through `moveOn` a moment after "Bye.". `rowReady`
    /// says whether the shortcut page shows and its status row has nothing left to ask.
    func answersHolds(_ banter: Binding<SetupBanter>, on page: SetupModel.Page, rowReady: @escaping () -> Bool,
                      moveOn: @escaping () -> Void) -> some View {
        modifier(SetupBanterHolds(banter: banter, page: page, rowReady: rowReady, moveOn: moveOn))
    }
}

private struct SetupBanterHolds: ViewModifier {
    @Binding var banter: SetupBanter
    let page: SetupModel.Page
    let rowReady: () -> Bool
    let moveOn: () -> Void
    @State private var editorOpen = false

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .hotKeyHeld)) { _ in
                banter.hold(rowReady: rowReady())
                // The hold opens the editor after it posts, in the same turn.
                DispatchQueue.main.async { if !editorOpen { reveal() } }
            }
            .onReceive(NotificationCenter.default.publisher(for: .annotatingChanged)) { note in
                editorOpen = (note.object as? StackModel)?.annotating ?? false
                if !editorOpen { reveal() }
            }
            .onChange(of: page) { left, _ in if left == .shortcut { banter.leftPage() } }
    }

    private func reveal() {
        var next = banter
        next.reveal()
        guard next != banter else { return }
        withAnimation(SetupView.spring) { banter = next }
        guard banter.saysBye else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + SetupBanter.byeDwell) {
            if banter.saysBye, rowReady() { moveOn() }
        }
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
