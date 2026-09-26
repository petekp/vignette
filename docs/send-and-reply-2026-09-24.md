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
| A session to send to | Copy, then the target, the message field, then Send, filled | Copy | Send |
| It names the session it came from | The message field, then Reply, filled, with the agent's logo | Reply | Reply |

The message field keeps these keys. Cmd+Return sends. Return replies on Reply, and beside Send it
sends nothing and bounces Send's ⌘↩ instead, so a Return typed as in a chat never hands the
drawing to a session Vignette picked. Send with Return, in the Agents tab (`sendWithReturn`), makes
Return beside Send send, as Pete asked on 2026-09-26, following chat apps such as Codex that offer
the same choice. Send keeps showing ⌘↩, which sends either way; a hint that changed with the focus
changed the button's width and moved the whole bar. `docs/request-line-2026-09-25.md` has what the
message becomes.

- **Copy is Done** under a label that says what it does. The code and the log still call it done.
- **The target** is the agent's logo and the project's folder. It sits beside Send as its own
  control, as Pete asked on 2026-09-24: "maybe the thread selection is separate from the note and
  Send CTA". Its menu lists the active sessions used last, five at most. Each row is
  the logo, the project, and the title in grey under it. A check marks the target.
- **The default** is the first of these that exists (`AgentDestination.defaultTarget`):
  1. The thread the Codex app shows, when it was the app in front before Vignette. Vignette reads
     the title of its page through Accessibility and matches it to a thread's name. If it can't,
     it takes the Codex thread used last. herdr's focus is ignored in this case: herdr keeps a
     focused pane while its terminal is behind, so on 2026-09-25 Send started on a Claude session
     while Pete was in the Codex app.
  2. The session in herdr's focused pane.
  3. The one agent in the focused pane's tab, when the focused pane runs no agent, such as a
     browser beside the session. If the focused pane runs Codex, the Claude session beside it is
     not the default, because Codex is who you were talking to.
  4. The session used last.
- **The title finds the thread the Codex app shows.** On 2026-09-25 Send started on the wrong
  Codex thread for one Pete had open. A test of every thread on this Mac, 144, with the title the
  app shows for each, found the cause. Only 39 matched, and for 92 Send picked another thread.
  - The app names a thread with no name by its whole first message as plain text: markdown and
    tags taken out, lines joined, cut to 79 characters and "…". Vignette used the first line.
  - The app takes tags out of names too, such as `<task>`. Vignette kept them.
  - Vignette searched the store with the title as shown. The store holds the first message as
    typed, so a title with "…", a joined line or a link in it found nothing.

  Now a thread is named by the app's rule, read from its bundle, and the name matched the app's
  title for all 144 threads. Titles compare by letters and digits only. The search sends the
  title and its two longest words, which found all 144, and a word's other hits are dropped.
  137 threads now match. The other 7 share their title with another thread, and Send takes the
  newest of them, which is as far as a title can tell. The whole lookup took 68 ms at the median
  and 222 ms at most.
- **The target settles once.** herdr answers in about 60 ms, before the bar is up, so a focused
  session is known at once. With no focus, the target waits for every client, since "used last" is
  a comparison across them. After that the target changes only when its session is gone from the
  whole list, or when you pick another. So it never changes under the pointer.
- **The list is ready when the bar comes up.** On 2026-09-25 Pete saw the target and Send appear
  late. The Codex listing took 0.9 to 1.7 s, and every open without a herdr focus, or from the
  Codex app, waited for it. Two changes fixed it:
  - Vignette asks Codex for the five threads used last instead of fifteen. The whole discovery
    took 0.15 s instead of 0.89 s.
  - Vignette keeps the last Codex list and answers from it at once, while a fresh one is asked
    for. It asks again at launch, on a capture and when the stack opens, so the kept list is
    current before an editor opens.

  herdr is always asked afresh, because its focus moves as you change panes. On the demo copy the
  kept list answered at 0 ms, herdr at 62 ms and the fresh Codex list at 114 ms. The editor takes
  clicks at about 200 ms. Coming from the Codex app, a kept list that doesn't hold the open thread
  waits for the fresh one, since the thread may have started since.
- **The menu lists only active sessions,** five at most, and the target always, so its check is
  seen. A Claude Code session is active while it runs in a herdr pane. Nothing says which threads
  the Codex app has open, so a Codex thread counts when it was used in the last day. On 2026-09-25,
  2 of the 15 threads the listing returned had been, and the rest were 33 hours to 17 days old.
  Pete removed More sessions the same day: "i don't see people using this".
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
