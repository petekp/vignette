# Send and Reply in the annotator's bar (2026-09-24)

Pete asked to bring part of the paused redesign (`docs/annotator-redesign-2026-09-24.md`) forward,
kept small. The goal is to make two things clear and quick: handing a drawing to an agent, and
answering an agent's drawing. Pete chose design A from the mockup,
`docs/send-and-reply-2026-09-24-mockup.html`, and asked for it in the next release. Built and checked
on 2026-09-24.

## What was wrong

- **Send looked like a label.** It was grey text and a chevron with no button shape.
- **The bar had two blue buttons.** The selected tool and Done used the same accent fill. Done read
  as part of the tools, and nothing read as the main action.
- **Every send meant reading a list.** Send had no default, by design, so each send opened the menu.
  Its rows were titles that Claude Code and Codex generated, which you didn't write.
- **Done didn't say it copies.** Esc also closes the editor and keeps the marks, so copying is the
  only difference, and the label hid it.
- **A card an agent pushed had no Reply.** Reply existed only for an answer to a request you sent. A
  card pushed with `vignette://add` recorded the agent's name but not its session.

## The idea

When you copy and paste, you don't pick a session. You go back to the pane you came from. herdr
knows where that is: `herdr pane list` marks the focused pane.

So Send starts on the session you came from. The bar only has to show that choice, and changing it
becomes the rare case. A wrong default would hand your drawing to the wrong agent. So the target is
shown before anything is sent, and Return never sends to it.

## What the bar does

`ToolbarOffer` is the one place that decides. Each offer has one filled button.

| The image | The bar | Return | Cmd+Return |
|---|---|---|---|
| No session to send to | Copy, filled | Copy | Copy |
| A session to send to | Copy, then the target, then Send, filled | Copy | Send |
| It names the session it came from | Reply alone, filled, with the agent's logo | Reply | Reply |

- **Copy is Done** under a label that says what it does. The code and the log still call it done.
- **The target** is the agent's logo and the project's folder. It sits beside Send as its own
  control, as Pete asked on 2026-09-24: "maybe the thread selection is separate from the note and
  Send CTA". Its menu lists five sessions, the one used last first, then More sessions. Each row is
  the logo, the project, and the title in grey under it. A check marks the target.
- **The default** is the first of these that exists (`AgentDestination.defaultTarget`):
  1. The session in herdr's focused pane.
  2. The one agent in the focused pane's tab, when the focused pane runs no agent, such as a
     browser beside the session. If the focused pane runs Codex, the Claude session beside it is
     not the default, because Codex is who you were talking to.
  3. The session used last. This is how a Codex thread becomes the default.
- **The target settles once.** herdr answers in about 60 ms, before the bar is up, so a focused
  session is known at once. With no focus, the target waits for every client, since "used last" is
  a comparison across them; Codex takes 1 to 2 seconds. After that the target changes only when its
  session is gone from the whole list, or when you pick another. So it never changes under the
  pointer.
- **Reply goes to the session the image names**: an agent's reply to a request, or a push with
  `session=`. If that Claude Code session is missing from the whole list, it has closed, since herdr
  lists every pane, and the bar changes to the layout for your own screenshot. A Codex thread is
  never judged closed that way, because Codex's listing holds only the threads used last.
- **The selected tool gets a grey fill instead of the accent blue.** Blue is left for the one
  action.
- **Return never sends to a session Vignette picked.** It replies only where the image names the
  session. The cost: on your own screenshot, the filled button isn't the Return button, which breaks
  a macOS convention. Each button shows its key, so the rule is visible.

## Pushed cards carry their session

- **The skill passes its session with the push:** `add?…&agent=claude&session=$CLAUDE_CODE_SESSION_ID`.
  Claude Code sets that variable in the shell it runs commands in; checked in this session, it
  matched the transcript's id. Codex isn't checked, so only Claude Code's id makes a reply target.
- **Vignette records it on the copy,** in an extended attribute beside the agent's name.
  `Agent.origin(of:)` reads it back.
- **Anything but a UUID is not recorded,** and `add` still answers `ok`, with a warning. An empty
  value, which is what an unset variable sends, is ignored silently.
- **The id is a claim, not proof.** `add` has no authenticated sender. The most a false id can do
  is send your reply to another of your own sessions, and only one in a herdr pane, since
  `ClaudeCodeConnection.submit` checks that before submitting. Any local process can already push
  cards.
- **The skill says so.** On a card pushed with `session=`, Return sends the drawing to the agent's
  session as a request, and no `-annotated.png` is written.

## Changed while testing

- **The project comes from herdr, not the transcript.** The target first read ".scratch" for this
  session, because the transcript's `cwd` follows the session's shell and it had run
  `cd .scratch`. herdr's pane folder is where the session was started.
- **The bar centres itself a turn after its contents change.** It first measured itself before
  SwiftUI laid out Send and the target, so it sat 100 points right of centre until Codex answered,
  then slid back. Now it moves in place a turn later. It doesn't touch the pending hide, so a
  change that lands as the editor closes can't leave the bar on screen.
- **A pick in the menu centres the bar too,** since the project's name changes its width.
- **Menu rows get a 16-point logo.** A menu draws an item's image at the image's own size, and the
  Claude logo drew at 94 points.

## Checked

On the Vignette Demo copy, which has its own bundle id, settings and watch folder. Pete's build,
settings and pasteboard were not touched: the pasteboard's change count was the same before and after.

- **Unit tests:** 386 passed. New ones cover the keys, the offer, the settling rule, herdr's focus
  and a push's session.
- **Your screenshot:** the bar opened as Copy, "✳ vignette" and Send, on this session through the
  browser pane beside it. The log had the herdr answer 66 ms after opening and the bar coming up
  about 160 ms later. A burst of captures showed no movement after the bar appeared, including when
  Codex answered at 1.8 seconds.
- **The menu:** it opened upward above the Dock, with the check on the target. Picking `pdk-ui`
  changed the target to that Codex thread and centred the bar. Nothing was sent.
- **Claude's card:** a push with this session's id opened as Reply alone, with the logo in white.
- **Return on Reply:** a push naming a session in no pane, with Return pressed before the full list
  arrived. The request was stored and refused: "is in no herdr pane now". Nothing was delivered.
- **A closed session:** the same push, left open, changed to Copy, the target and Send once the full
  list arrived.

Not checked live: the Copy-only bar, which needs a Mac with no herdr and no Codex, and Cmd+Return
delivering to a real session, which would have sent to one of Pete's. The unit tests cover both, and
the send path after the key is the one Return on Reply went through.

## Not now

- **Choosing the session from what the screenshot shows,** such as a page's port leading to the
  project's folder. `docs/session-auto-select-2026-09-24.md` investigates it and recommends it.
- **Outlining the target pane on screen when you hover Send.** herdr reports a pane's place in
  terminal cells, so this needs the terminal window's frame and its cell size too.
- **A Codex CLI in a herdr pane as the default.** herdr's focus is only matched against Claude Code
  sessions.

Comments, the tool rail, the message field and the tabs stay in the paused redesign.
