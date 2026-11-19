# Pulled into the Codex app with a context menu open (2026-11-18)

On 2026-11-18 at 22:42, Pete reported being "whisked away to the Codex app with the macOS context
menu pulled up", several times within minutes, and suspected Vignette. This note gives the
diagnosis, with evidence, and a proposal for the long term. Times are Pacific. The Codex app is
`/Applications/ChatGPT.app` (bundle id `com.openai.codex`, version 26.1111.21308) and shows as
ChatGPT in logs. macOS is 27.2.1.

## What happened

The context menu was the Codex app's. One Codex thread, "Investigate team member status
indicators" (`01a1ec12-a778-7bb1-ab0c-9ffb79176dbd`), tests a web page in Codex's in-app browser.
Its scripts right-click a person's avatar (`click({button:'right'})`). Each right-click made while
Codex was not the front app opened a native menu window over the app Pete was using. The window
took the keyboard from that app. This happened 13 times on 11-18, 7 of them between 22:30 and 22:39.

Pete then went to Codex himself, within seconds of a menu, five times. Twice he clicked a Codex
window (17:36:23 and 22:31:04), once more at 22:38:56, and twice he pressed Cmd-Tab (22:38:04 and
22:38:36). Each came 0.5 to 3.3 seconds after the menu closed. This is the likely "whisked away"
moment. Why he went to Codex is not in any log.

Vignette did not bring Codex forward on its own. It brings another app forward when one of its
windows closes, such as the editor, the stack, a live ink note or Settings, and hands the focus
back (`FocusReturn.restore`). On 11-18 it handed back to Codex 10 times. Each time, Codex had been
the front app when Vignette opened, through Pete's own click or Cmd-Tab, or through another app
quitting. Three of those came right after the 17:36:23 click and two after the 22:31:04 click.

Codex never brought itself forward from 22:15 to 22:43, or before any hand-back. Send to a Codex
thread does not bring Codex forward either.

## Evidence

Each finding below is marked verified (checked in a log or the code) or unverified.

### The menu is Codex's, driven by its browser agent (verified)

WindowServer logs a "key thief" when a process takes the keyboard without becoming the front app.
On 11-18, a Codex process did that 13 times while another app was in front. Two Codex processes
ran that day, because the app was relaunched at 22:16. Before then the thief was connection
`13bbf3` (pid 77997), and after it `157d57` (pid 87731).

Each theft came 0.1 to 11 s after a tool call in thread `01a1ec12` that contained a right-click in
the in-app browser. Every one of the thread's 13 right-clicks made while Codex was behind another
app was followed by a theft, and no Codex theft came without one. Its 3 right-clicks made while
Codex was in front (22:20:39, 22:21:37 and 22:22:21) opened the same kind of window and logged no
theft, which is what macOS does for a menu in the front app.

| Right-click (rollout) | App in front | Codex took the keys | Keys given back |
| --- | --- | --- | --- |
| 17:02:40.958 | Dia | 17:02:41.322 | 17:02:42.850 |
| 17:30:13.183 | Herdr | 17:30:14.187 | 17:36:22.835 |
| 20:04:07.834 | Dia | 20:04:08.563 | 20:04:09.950 |
| 20:05:02.016 | Dia | 20:05:02.928 | 20:05:06.351 |
| 21:11:45.125 | Herdr | 21:11:45.869 | 21:11:47.398 |
| 21:29:33.421 | Dia | 21:29:33.588 | 21:29:37.220 |
| 22:30:21.198 | Dia | 22:30:21.332 | 22:30:22.763 |
| 22:30:54.747 | Herdr | 22:30:57.619 | 22:31:01.403 |
| 22:35:34.043 | Herdr | 22:35:44.247 | 22:35:45.944 |
| 22:37:06.842 | Herdr | 22:37:06.917 | 22:37:12.749 |
| 22:37:58.460 | Herdr | 22:38:01.588 | 22:38:03.321 |
| 22:38:30.232 | Herdr | 22:38:33.021 | 22:38:36.089 |
| 22:38:46.319 | Herdr | 22:38:49.593 | 22:38:53.206 |

The rollout time is when the tool call started. A call that loads or reloads a page first takes
longer to reach its right-click.

While Codex held the keys, Pete's typing went to Codex. Between 22:38:01 and 22:38:03, five key
presses meant for Herdr went to Codex's process, and between 22:38:33 and 22:38:36 three more. Six
of tonight's seven thefts ended within 20 ms of a physical click, which is Pete clicking the menu
away. The 22:38:01 one ended 0.4 s after his Cmd-Tab. The 17:30 one stayed up for six minutes,
until a click at 17:36:22.

The thief opened two windows. AppKit then logged
`-[NSWindow makeKeyWindow] called on <AppKit._NSGlassEffectWindow …>` in Codex's process. That
glass window class is how macOS 27 draws menus. It is the reason to read the window as the context
menu Pete saw. That last step is inferred, not seen (unverified).

Whether the page's own right-click handler should have stopped the browser's menu is unverified.
The Paddock page was not read.

### How Codex came forward tonight (verified)

From 22:15 to 22:43, each change of the front app was classified by what came just before it in
WindowServer's log: a physical button press, Cmd-Tab, or neither. Other key presses, such as an
app's own shortcut, were not counted, so "neither" means no click or Cmd-Tab. Connection `754c3`
is the Dock: WindowServer posts each Cmd-Tab to the Dock just before `754c3` changes the front app.

| Codex came forward | How |
| --- | --- |
| 22:16:36 | Click; Codex launched |
| 22:16:43 | Click on its window |
| 22:17:32, 22:18:06 | Cmd-Tab |
| 22:19:23 | Click |
| 22:19:37 | Activity Monitor quit, and macOS brought forward the app behind it |
| 22:23:49 | Vignette's hand-back after Send |
| 22:25:20 | Click |
| 22:31:04 | Click on its window, 2.9 s after the click that ended a Codex menu |
| 22:32:01 | Vignette's hand-back after Esc |
| 22:32:29 | Vignette's hand-back after Send |
| 22:38:04 | Cmd-Tab, 0.8 s after a Codex menu closed on an earlier Cmd-Tab |
| 22:38:36 | Cmd-Tab, 0.5 s after the click that ended a Codex menu |
| 22:38:56 | Click on its window, 3.3 s after the click that ended a Codex menu |
| 22:40:43 | Click |
| 22:41:23, 22:42:27 | Cmd-Tab |

From 22:17 on, Codex's own process logged "application did become active" at exactly these times
and no others.

Earlier in the day, the same classification finds five times Codex came forward with no click or
Cmd-Tab just before. Four followed another app quitting (18:56:53, 20:12:16, 20:27:30 and
20:50:31). At 18:55:19 an unidentified process, connection `1568f3`, made Codex front 1.5 s after
a click. None of the five came before a hand-back.

### Vignette's hand-backs went where Pete had been (verified)

`Vignette.log` has 10 hand-backs to Codex on 11-18. For each, the front app just before Vignette
opened was Codex.

| Hand-back | How Codex had come forward before Vignette opened |
| --- | --- |
| 12:48:56 editor | Click on its window at 12:48:08 |
| 13:52:21 live ink note | Click at 13:51:12 |
| 14:19:29 editor | Click on its window at 14:18:17 |
| 17:36:46, 17:37:01, 17:37:04 editor | Click on its window at 17:36:23, 1 s after the click that ended the six-minute Codex menu |
| 21:19:52 editor | Cmd-Tab at 21:19:21 |
| 22:23:49 editor | Activity Monitor quit at 22:19:37 |
| 22:32:01, 22:32:29 editor | Click on its window at 22:31:04 |

`FocusReturn` follows every activation of a regular app other than Vignette and System Settings.
`restore` brings that app forward only while Vignette is the active app
(`Sources/FocusReturn.swift`).

Two other places in `Sources/` bring another app forward. Neither can reach Codex:

- `SettingsWindow.bringForward` activates macOS's own Accessibility alert when it is already up.
- `NSWorkspace.shared.open` opens a file or a URL in its default app when the person asks: the
  Open action, Open Log, the screenshot folder, a System Settings pane, and the problem report in
  the browser.

### Send does not bring Codex forward (verified)

`focus=app` in a `[send] target` line means why Send chose the thread. Codex was the app before
Vignette (`AgentDestination.Focus.app`). It triggers no action. A Codex send goes through the app
server and the queue (`docs/rules/send.md`), and no line in the send path activates an app.

### Not checked

- Hand-backs to Codex on other days. The unified log on this Mac has front app changes from 11:38
  on 11-18 and key thefts from 09:08.
- What Pete was looking at, or meant to do, each time he went to Codex right after a menu.
- Which process connection `1568f3` is.
- Whether a right-click by a person on a Codex window behind another app does the same. macOS
  normally lets a background app open a context menu on a right-click, so it probably does.

## How to check this again

The unified log keeps these lines for a few days. These predicates found them:

- Key thefts: `log show --predicate 'process == "WindowServer" AND (eventMessage CONTAINS
  "StealKeyFocus" OR eventMessage CONTAINS "keyThief")'`. Each line starts with the thief's
  connection id; `frontmostProcess: … (Name) mainConnectionID: <id>` and `key thief updated <id>
  <PSN> (Name)` lines map ids to apps. An app relaunch gets a new id.
- Front app changes and their cause: the same process, with `eventMessage CONTAINS "the front
  process" OR eventMessage CONTAINS "ButtonMask=" OR eventMessage CONTAINS "specialkey" OR
  eventMessage CONTAINS "kCGSEventKeyDown"`. A `[SetFrontProcessWithInfo]` from Vignette's
  connection is a Vignette activation. `[DoDeferredOrdering]` from the app's own connection follows
  a click on its window. `0[outside of RPC]` is macOS choosing the next app after one quits.
- Keys during a theft: `kCGSEventKeyDown` delivery lines name the process that received each key.
- The agent's actions: the thread's rollouts under `~/.codex/sessions/<year>/<month>/<day>/`. One
  thread can have several rollout files, under different days, so search every day for its id.
  Codex's own log is under `~/Library/Logs/com.openai.codex/`, dated in UTC.

## Proposal

### The app to return to

The app to return to is the app that was in front when Vignette took the keys. Vignette's own
window comes first, when Settings, setup or the tweaks was key. This is what `FocusReturn` does
today. The proposal makes it the stated contract and does not change it.

The reason is that closing Vignette should leave the screen as Vignette found it. Vignette then
never changes which app is in front, taken over the whole visit. On 11-18 that put Pete back in
Codex each time, because Codex was where he had been. Returning him anywhere else would have been
Vignette moving him.

Alternatives weighed and rejected:

- Return to the app Pete last brought forward with his own input, skipping an app that came forward
  on its own. It would change nothing on 11-18. Before every hand-back, Codex had come forward
  through Pete's click or Cmd-Tab, or when he quit Activity Monitor. Public macOS interfaces do not say who brought an app forward. A guess from input
  timing fails both ways. Launching an app from Spotlight or the Dock can take over a second, and
  Pete types almost constantly, so a recent key press says nothing. When the guess is wrong,
  Vignette sends him to an app he had left, which is the harm reported here. This rests on one
  day's logs.
- Take one snapshot when the session starts, in place of following every activation. It gives the
  same answer except when the person goes to another app mid-session and comes back. Nothing on
  11-18 depended on that, so it is not worth the change.
- Never hand back to an agent's app. That is wrong whenever the person was working in it.
- Hand back by deactivating Vignette and letting macOS choose. Whether macOS picks the app Vignette
  found is unverified. Vignette would also lose the return to its own Settings window, and the log
  would no longer say where the focus went.

### An app that comes forward on its own

Vignette does not fight it. It neither pushes the app back nor brings the person's previous app
forward when it happens. If that app is still in front when Vignette opens, it is the app Vignette
returns to, since that is what the screen showed.

Each `[focus]` hand-back line should also say when that app came forward, for example
`[focus] annotator closed: returned to ChatGPT, in front since 22:31:04`. Today's diagnosis needed
`log show`, which keeps only a few days, to learn that Codex had been in front for a minute before
Vignette opened. With the time in the line, `Vignette.log` alone answers whether Vignette moved the
person. It would not have shown the menus. A key theft activates no app, so Vignette never sees it.

### Send never brings the destination's app forward

Send delivers the drawing, and the card says what happened (Sent, Queued, or why it failed). The
person decides where to look. Bringing Codex forward after a send would be the same switch Pete did
not ask for. When he sent from Codex, the hand-back already returns him there.

### Codex's menus

Vignette cannot prevent them. Vignette has no say over another app's menus. It cannot refuse
another app's key theft, and it should not script Codex's browser. `docs/codex-issues.md` records
this as X2, with what Codex could change. Two things are outside Vignette and need Pete's yes:

- A report to Codex. Its browser agent's right-click should not open the app's native context menu,
  or at least not while the app is behind another app.
- Guidance for the agent in thread `01a1ec12`, or in that project's `AGENTS.md`. It would open the
  person card by dispatching a `contextmenu` event in the page instead of a pointer right-click.
  Whether a dispatched event avoids the native menu is unverified.

### What changes

Nothing about which app the focus returns to. When the proposal is built:

- The `[focus]` line gains the time the app came forward.
- `docs/rules/stack.md` states the contract above, that Send never brings an app forward, and which
  code may bring another app forward.

### What would hold it

`scripts/check-app-activation.py`, run by `scripts/build.sh --test` like the display link check. It
counts each call that activates, launches or opens an app: `activate` on another app,
`openApplication`, `NSWorkspace.shared.open` and a `/usr/bin/open` process. Its `ALLOWED` list
gives each file its number of calls and why. It holds `FocusReturn.restore`, `AppLocation`'s
relaunch and `SettingsWindow.bringForward`, and each place that opens what the person asked for. A
new call fails until it is given a reason. The future failure it catches is a change, in Send or
elsewhere, that brings an agent's app forward, such as opening a `codex://` link.

Unit tests for `FocusReturn`'s choice are left out. It has none today
(`docs/state-machines/annotation-run-effects.md`), and testing it would need its decision split
from AppKit into a new type. The contract does not change, so that type would exist only for the
tests.
