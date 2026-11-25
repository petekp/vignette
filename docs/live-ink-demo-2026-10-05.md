# Live ink demo: the beats (2026-10-05)

A two-to-three-minute demo of live ink across four windows. One story runs through it: an invoice
total is wrong, and live ink finds out why. Each beat shows one thing live ink does that a
screenshot tool cannot.

## The stage

`media/live-ink-demo/demo.py up` lays out four windows on a plain dark desktop that hides
everything else:

| Window | App | Content |
|---|---|---|
| Invoice, front left | Chrome (a profile of the demo's own) | Invoice 1042. Its total is $4,008.20, but should be $3,975.48: tax was charged before the discount. |
| Launch notes, top right | TextEdit | Two screens of release notes. One sentence halfway down is unreadable. |
| Notifications, lower right | Chrome | A settings page with three checkboxes, Discard and Save changes. It overlaps the notes. |
| Tests, lower left | Ghostty | A failing test: `assert Decimal('4008.20') == Decimal('3975.48')`. |

| Command | What it does |
|---|---|
| `demo.py up` | Lays out the stage. |
| `demo.py up --capture` | Also relaunches Vignette so screen recordings and screen shares see the ink. |
| `demo.py reset` | Erases the ink and lays the stage out again, for another take. |
| `demo.py down` | Takes the stage down and puts Vignette back as it was. |

**Recording or sharing the screen needs `--capture`.** Live ink keeps its marks out of screen
captures, so without it a recording shows the windows and no ink. `--capture` relaunches Vignette
on a copy of the settings file, with its own screenshot folder, and `down` puts the real one back.

## Before a take

- Run one throwaway ask, on anything, a minute before. The first ask starts the responder, which
  takes about 1.5 s on top of the answer.
- Use a trackpad for the scroll beat. A trackpad scroll fades the marks as the content starts
  moving.

## The beats

Drawing is always the same move: hold ⌃⌥, draw, let go. A closed loop circles something, and any
other stroke is an arrow. Letting go opens the note: type a question and press Return, or press
Return alone.

| # | Window | You do | What happens | What it shows |
|---|---|---|---|---|
| 1 | Invoice | Loop **Total due**. Ask "is this right?" | The reply streams in beside your loop. The agent circles the subtotal, the discount and the tax it checked, and says the total should be $3,975.48 because tax was charged before the discount. | It answers by drawing on the page, and marks its evidence. |
| 2 | Invoice | Drag the invoice right by its title bar until its total sits under the launch notes. | Every mark rides along with the window and stays on top of it. | The ink belongs to the window, not the screen. |
| 3 | Notes, then Invoice | Click the launch notes, then click the invoice. | The notes cover the marks with the invoice, and the marks come back with it. | The ink sits in the window's layer. |
| 4 | Launch notes | Scroll to **Export**. Loop the long sentence. Ask "say this simply". | A plain one-line version appears beside it. | It reads any app's text, here a native one. |
| 5 | Launch notes | Scroll down, then back up. | The marks fade as the text moves and come back on the sentence once it stops. | The ink stays on its content. |
| 6 | Notifications | Loop **Discard** and **Save changes** together. Ask "what does this do?" | The agent points at both and asks which you mean. | It asks back instead of guessing. |
| 7 | Notifications | Hold ⌃⌥ and rest the pointer on its arrow at **Discard**. Tap, let go, press Return. | The arrow turns red under the pointer. The tap makes it yours, and Return asks about Discard alone. | Picking is a tap. |
| 8 | Notifications | Loop the page's heading. Ask "how do I get the weekly summary?" | One step shows: the checkbox. Click it, and the next step draws itself on Save changes. Click that, and the step goes. | Guided steps that wait for your clicks. |
| 9 | Tests | Loop the `AssertionError` line. Ask "why?" | It underlines the line that adds tax before the discount and ties it to the invoice. | It works in a terminal too. |
| 10 | Invoice | Press ⌘M on the invoice, then bring it back from the Dock. | The marks fade as the window leaves, and come back with it. | The ink goes where the window goes. |

End with **Clear Live Ink** in the menu bar menu, or `demo.py reset` for another take.

## Optional: hand it to a coding session

At beat 9, switch the note's target from the responder to a Claude Code session before pressing
Return. The session gets the picture and your question, and its reply comes back as a card. This
needs a Claude Code session running with the Vignette plugin.

## What can go wrong

- **An answer takes longer than 5 s.** The pages are short so that answers come in 2 to 4 s. A
  page with a lot of text, such as a long Dia page, has taken 25 s.
- **The agent words things differently each take.** The beats depend on what it does, such as
  circling the evidence, asking which button, or giving steps, not on its exact words. Beats 1, 6
  and 8 behaved as described in tests on 2026-10-05 with similar pages.
- **Steps stop at the first picture.** Every step must be on screen when you ask. Beat 8 works
  because the checkbox and Save changes are both visible.
- **Ghostty's anchors are lines.** A mark in the terminal follows its line, not the words in it.
- **Dragging a window shows a small lag** of about 4 pt, visible only when looking for it.
