# Live ink: Claude gestures while it talks (2026-10-05)

Status: exploring. A lab tries the open questions; nothing in Vignette has changed. The principles
these follow are in `docs/vision.md`.

## The idea

Claude's marks become gestures, made while it talks, rather than notes left on the page.

- **Each gesture draws on as its words arrive.** A loop, an underline or an arrow appears the
  moment Claude mentions the thing, and its words stream in beside it.
- **The words sit next to the gesture they belong to.** An answer can have several separate
  phrases, one per gesture.
- **Clearing is one motion.** A quick tap of ⌃⌥ with nothing drawn clears every mark. Esc cannot do
  it: the overlay never takes keys, so Esc reaches the frontmost app, and in a
  terminal that interrupts the agent.

This direction replaces the review-pass proposal in `docs/live-ink-10x-2026-10-05.md`.

## Gestures and findings

Claude makes two kinds of marks.

- **A gesture** points at something while Claude talks, then fades. It asks nothing of you.
- **A finding** stays on the page until you act on it or dismiss it. It carries buttons that Claude
  writes for that finding, such as "Fit them on one row" or "Show the whole map".

A mark stays only when it has a button. A mark that asks nothing of you has done its job once you
have seen it. A mark that offers an action has to wait for you. That makes persistence follow from
what the mark is for, so Claude never has to choose it separately. The rejected alternative was a
`persistent` flag on each mark: it is a second choice Claude can get wrong, and a lasting mark with
nothing to click is one more thing to clear by hand.

How a finding behaves:

- **Its buttons sit on its label.** Today's actions sit under the reply and name their marks by
  index (`LiveAnswer.Action`). On the label, the button is next to the thing it acts on, and the
  index goes.
- **A click sends the button to the session as your next turn**, with the finding it came from.
  Clicks on several findings queue, since a Claude Code session takes events between turns.
- **The finding shows the work.** It reads as working until the session's turn ends. Then Claude
  answers with gestures at what changed, and the finding goes. A follow-up can raise new findings.
- **Claude can change a finding's buttons** as the answer goes on. A question Claude asks back is a
  finding too: the button on each underline is the answer, such as "This one".
- **Clearing takes gestures first.** A tap of ⌃⌥ clears the gestures, and findings stay. Each
  finding has its own ×.

## Open questions

1. **When does a gesture fade?** After its words, at the next gesture, after the whole answer, or
   never.
2. **Bare words or words on a tag?** Bare words are drawn in the agent's ink with a white outline.
3. **Does a button only ever send a turn to the session?** Some could run on the Mac at once, such
   as opening the source file at the line.
4. **Does every finding need a button?** A warning with nothing to fix, such as "Safari won't
   support this", would then be a gesture and fade.

## The lab

`.scratch/gesture-lab/` is a throwaway app, not Vignette code. It shows Postcard at mobile width in
its own window and plays three of Claude's answers over it:

- **Review:** two findings on the page's mobile bugs. Each has a button for its fix and a ×.
  Pressing a button runs that fix: the finding reads Working… while Claude works, then the page
  changes and Claude points at what changed. A second press waits as Queued.
- **Fix both:** Claude works for 3 s, the page changes, and it points at what changed. Gestures
  only.
- **Ask back:** a question. The title and the dates are underlined, and each underline ends in a
  button, "The title" or "The dates", that answers it.

A question's buttons sit at the end of its underlines, and the buttons are the answers. A finding's
words and buttons take about three times the room of a gesture's words. On this page a question's
words could not sit beside their lines, and a button far from its line did not say which line it
picked.

Gestures follow the page as it scrolls and resizes. Labels keep off the page's text, the target and
other gestures.

Run it from the worktree with `.scratch/gesture-lab/run.sh`. The keys work while its window is in
front. The lab still draws a notch and can rewind; neither is part of the design.

| Key | Does |
|---|---|
| `1` `2` `3` | play Review, Fix both, Ask back |
| `0` | reset the page and the history |
| `f` | cycle when gestures fade |
| `-` `=` | fewer or more seconds before fading |
| `s` | bare words or tags |
| `w` | cycle how rewind replays |
| `,` `.` | step back or forward through past answers |
| `x`, or a tap of ⌃⌥ | clear the gestures; findings stay |
| the notch's × | clear everything, and cancel waiting work |

`run.sh --selftest <folder>` plays it off screen and writes captures, for checking a change
without using the screen.
