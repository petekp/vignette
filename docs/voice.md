# How Vignette speaks

Every word a person reads in Vignette is clear, short and humble, and it points to what can happen
next. Pete set this on 2026-10-01. This file holds the rules and the messages written to them, so a
new message matches the ones already there. Change a message here and in the code together.

## Rules

- **Say what happened in plain words.** Name the thing: the thread, the session, the drawing.
  Leave out the mechanism, such as "rollout", "inbox" or "exit 1". The log keeps those.
- **Then say what can happen next, as a possibility.** "You can send it to another one", not "Send
  to another one". The person decides. A message never gives orders.
- **Be humble about what Vignette knows.** Say what Vignette saw, not more: "Codex can't find this
  thread", not "This thread is gone". When the fault is Vignette's, Vignette says so: "Vignette
  couldn't render the drawing".
- **Keep the way forward in view.** Nothing is lost when a send fails, since the drawing is still
  there, so a message points at the next try rather than at the failure. A queued send says when it
  will be read.
- **Fit the card.** A headline is two or three words, plus the session's title when it names one.
  The card cuts a title that is too long. A reason is one or two short sentences, about 60
  characters, since it sits under the headline on a card.
- **"The log has details."** is how a message points at the log. Use it only when the person can do
  nothing else.
- **Contractions, and no exclamation marks.** "couldn't", "can't", "isn't".
- **Draw, not annotate.** Every string a person reads says draw. The names scripts read say
  annotate (AGENTS.md, "Words and motion").
- **No toasts.** A message goes on something already on screen, usually the card it is about
  (`docs/no-toasts-2026-09-30.md`).

## Release notes

Release notes are for people who use Vignette. Give the gist of what they will notice, in a few
short bullets: a bold name and one sentence. Leave out wording changes, internal rework, and how
anything works inside.

## Messages

### A send, on its card (`SendOverlay`)

| State | Headline | Reason |
| --- | --- | --- |
| Waiting to send (the line has not gone yet) | Sending to *session* | Button: Don't send |
| Sending | Sending to *session* | |
| Starting the session, which was not running at Send | Starting in *session* | |
| Sent | Sent to *session* | |
| Queued: no Codex engine has the thread open | Queued for *session* | Codex reads it when you open this thread. |
| Not confirmed in time | Check *session* | Codex didn't confirm it. It may still have arrived. |
| Not sent | Not sent | One of the reasons below |
| A reply that could not be shown | Reply not shown | You can ask *agent* to send it again. / Vignette couldn't save the reply. The log has details. |
| A live ink note whose session finished with nothing to show as a result card | Done in *session* | |

*session* is the session's title as the toolbar or the live ink note showed it when Send was pressed: the herdr tab's label, else the session's name, with a suffix when two sessions share a title. `SessionMenu.cardTitle` decides it. A session that Send starts has no title yet, so the card names its project folder instead. On a card too narrow for the headline, the title stands alone. A title too long even for that is cut in the middle.

Pressing Don't send says nothing. The press is the confirmation, the ring and the button go with
it, and "Not sent" is the headline for a failure, not for a choice.

### Why a send did not go (`SubmissionOutcome.reason`)

| When | Reason |
| --- | --- |
| The Claude Code session ended | This session has ended. You can send it to another one. |
| The Claude Code session was cleared | This session was cleared. You can send it to another one. |
| Codex has no such thread | Codex can't find this thread. You can send it to another one. |
| Codex's engine can't be reached | Codex isn't running. You can send again once it's open. |
| No Codex on this Mac | Sending to Codex needs the Codex app or its CLI. |
| herdr did not open a tab for a session that was not running | Vignette couldn't open a herdr tab for Claude Code. The log has details. |
| The started session had no inbox 45 s later | Claude Code didn't open in time. You can send again once it's running. |
| Codex did not start | Codex couldn't start. The log has details. |
| Codex refused it for a reason Vignette has no words for | Codex: *its own words* |
| Anything else | Something went wrong in Vignette. The log has details. |

### Before the request is stored, beside Send's "Not sent"

| When | Reason |
| --- | --- |
| The drawing did not render | Vignette couldn't render the drawing. The log has details. |
| The request could not be written | Vignette couldn't save the request. *the system's words* |
| Anything else | Vignette couldn't send the drawing. The log has details. |
| The screenshot is gone | Vignette can't read *name*. It may have been moved or deleted. |

### Settings switches

A switch's line says what changes when it is on, or what happens without it when that is the reason
to turn it on.

| Switch | Title | Line under it |
| --- | --- | --- |
| Claude Code may open sent drawings (`ClaudeReadRule`), in the Agents tab | Let Claude Code open drawings without asking | Otherwise Claude Code stops to ask you in its terminal each time you send one. This adds a permission to Claude Code's settings for these drawings only. |
| Under setup's agents while Claude Code is on (`ClaudeReadRule.setupNote`) | | Claude Code will open the drawings you send without asking you first. You can change this in Settings. |
| Live ink (`liveInk`), in the General tab | Live ink | Holding *pair* lets you draw over any app. A click on a mark while you hold them erases it. Then, on a line of its own, what leaves the Mac (`SetupInkCopy.costNote`), from the table at the end of this section. |
| Speaking while drawing (`liveInkSpeech`), under Live ink | Speak while you draw | What you say goes into the note beside your ink. Your voice stays on this Mac. |
| When the ask goes (`liveInkSendWhenQuiet`), an experiment | Ask when you let go | |

*pair* is the live ink chord as glyphs, ⌃⌥ unless another is chosen (`LiveInkChord.glyphs`).

| Where | Words |
| --- | --- |
| The pop-up that picks the pair (`liveInkChord`), under the Live ink switch | Hold to draw; its choices ⌃⌥, ⌃⇧, ⌥⇧, ⌃⌘, ⌥⌘ |
| Under it, when the stack's key combination holds the pair picked (`LiveInkChord.refusal(against:)`) | *shortcut*, the stack's shortcut, starts with these keys. You can pick another pair. |
| Under the stack's Keys box, when the combination pressed holds live ink's pair (`LiveInkChord.refusal(ofStackShortcut:)`) | Live ink uses *pair*. You can pick another combination. |
| Under the stack's Keys box, for ⌘ with one key (`HotKeySpec.refusal`) | *keys* is a command in every app. You can add ⌥ or ⌃. |
| The same, for ⌘⇧3, ⌘⇧4 or ⌘⇧5 | *keys* takes screenshots. You can pick another combination. |
| The same, for ⌃ with Space or an arrow | macOS uses *keys*. You can pick another combination. |
| Live ink's one-time offer, at the top of the General tab | Live ink is new. Holding *pair* lets you draw over any app and ask Claude about what you drew. Buttons: Not Now, Turn On |
| The same, where Codex is installed and Claude Code can't answer (`ResponderStatus.namedAgent`) | Live ink is new. Holding *pair* lets you draw over any app and ask Codex about what you drew. Buttons: Not Now, Turn On |

What leaves the Mac (`SetupInkCopy.costNote`) is a line under the Live ink switch and on setup's
live ink permissions page. It names the agents that can answer.

| Agents that can answer | Words |
| --- | --- |
| Claude Code, or neither | When you ask, Claude sees a picture of each window you drew on, with its title and URL, through your own Claude Code. An ask costs about one to four cents. |
| Codex alone, or Codex before its sign-in where Claude Code can't answer | When you ask, Codex sees a picture of each window you drew on, with its title and URL, through your ChatGPT account. An ask counts toward your plan's usage limit. |
| Both | When you ask, Claude or Codex sees a picture of each window you drew on, with its title and URL. An ask to Claude costs about one to four cents. One to Codex counts toward your ChatGPT plan's usage limit. |

Setup's live ink pages name Codex where Codex is installed and Claude Code can't answer
(`ResponderStatus.namedAgent`), and Claude elsewhere. The guide's label is Start here beside
Accessibility's Allow…, and Then this beside Screen Recording's Allow… and Sign In to Codex….

| Where | Words |
| --- | --- |
| The live ink page, under the line about drawing (`SetupInkCopy.askLine`) | Then ask Claude about it, or send it to a Claude Code or Codex session. On that Mac: Then ask Codex about it, … |
| Screen Recording's reason on the permissions page (`SetupInkCopy.screenRecordingReason`) | So Claude can see the window you drew on. On that Mac: So Codex can see the window you drew on. |

### Setup's shortcut page, after the hold (`SetupBanter`)

These lines break the rules above on purpose. Pete wrote them on 2026-11-01, and they stay word for
word. The first hold of the shortcut says line 1, and each later hold says the next line. A hold
moves the script on only while its line shows on the shortcut page.

| Hold | Words |
| --- | --- |
| 1 | You're a quick learner! Think you got it down? |
| 2 | Amazing, you did it again! |
| 3 | Sheesh. You're an expert now. |
| 4 | You're THE expert, now. |
| 5 | You've done this before, haven't you? |
| 6 | The ease with which you do it... marvelous. |
| 7 | Must feel nice to be so good at something. |
| 8 | Very good. Let's move on shall we? |
| 9 | Great. |
| 10 | Nice. |
| 11 | Hmm. |
| 12 | I see what you're doing. |
| 13 | Okay, ha ha. Let's continue on, yeah? |
| 14 | Yes, you did it again. |
| 15 | You're trying to get a rise out of me aren't you. |
| 16 | Let's get a rise out of the ol' setup menu, very funny. |
| 17 | Picking on a setup menu is an interesting choice. |
| 18 | ... |
| 19 | ..... |
| 20 | What do you want from me? |
| 21 | Bro. |
| 22 | C'mon bro. |
| 23 | BRUH. |
| 24 | Okay whatever. I'll just wait here. |
| 25 | ... |
| 26 | ... |
| 27 | ... |
| 28 | Ugh. |
| 29 | Fine, that's it. |
| 30 | One more time and I'm pushing the button myself. |
| 31 | Bye. Then setup goes on to the next page, as Continue would. |
| Back on the shortcut page | Hi! Welcome to the setup... oh, it's you. |
| 32 | Dude. No. |
| 33 | F%@#! |
| 34 | I'm out. ✌️ |
| 35 and after | *The setup assistant has peaced out.* In muted italics, and it stays. |

### Live ink

Live ink's messages are in [voice-live-ink.md](voice-live-ink.md).

### A copy, on its card ("Not copied")

| When | Reason |
| --- | --- |
| The screenshot did not read | Vignette couldn't read the screenshot. |
| The rendering could not be written | Vignette couldn't save the drawing. |
