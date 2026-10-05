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
- **Fit the card.** A headline is two or three words. A reason is one or two short sentences, about
  60 characters, since it sits under the headline on a card.
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
| Sending | Sending to *project* | |
| Sent | Sent to *project* | |
| Queued: no Codex engine has the thread open | Queued for *project* | Codex reads it when you open this thread. |
| Not confirmed in time | Check *project* | Codex didn't confirm it. It may still have arrived. |
| Not sent | Not sent | One of the reasons below |
| A reply that could not be shown | Reply not shown | You can ask *agent* to send it again. / Vignette couldn't save the reply. The log has details. |

### Why a send did not go (`SubmissionOutcome.reason`)

| When | Reason |
| --- | --- |
| The Claude Code session ended | This session has ended. You can send it to another one. |
| The Claude Code session was cleared | This session was cleared. You can send it to another one. |
| Codex has no such thread | Codex can't find this thread. You can send it to another one. |
| Codex's engine can't be reached | Codex isn't running. You can send again once it's open. |
| No Codex on this Mac | Sending to Codex needs the Codex app or its CLI. |
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
| Live ink (`liveInk`), in the General tab | Live ink | Holding Control and Option lets you draw over any app. A click on a mark while you hold them erases it. |

### Live ink

The menu bar menu names the switch as the General tab does.

| Where | Words |
| --- | --- |
| The menu's switch, with a badge | Live Ink, badge "Hold ⌃⌥" |
| The menu, while live ink is on, greyed out with no marks | Clear Live Ink |
| The General tab, under the switch while Accessibility is missing and the double tap is not asking for it (`liveInkAccessibilityReason`) | Needs Accessibility permission. Lets Vignette notice Control and Option held down in any app. |
| The menu's first item while Accessibility is missing | Allow Accessibility for Live Ink…, or for the Shortcut and Live Ink… when the double tap needs it too |
| The menu bar intro's popover, while Accessibility is missing | Live ink needs Accessibility. Click the icon to allow it. (The shortcut and live ink need Accessibility, when both do.) |
| The General tab, under the switch while Screen Recording is missing (`liveInkScreenRecordingReason`) | Needs Screen Recording permission. Lets Vignette see the window under your ink when you ask about it. macOS may ask you to reopen Vignette after you allow it. |
| The menu's first item while Screen Recording is missing | Allow Screen Recording for Live Ink… |
| The menu bar intro's popover, while Screen Recording is missing | Live ink needs Screen Recording. Click the icon to allow it. |
| The note's placeholder (`LiveNotePanel.placeholder`) | Ask about this |
| The note's target, and its tooltip | to Claude ▾, "Claude answers on the screen." / to *project* ▾, "The session's reply comes back as a card." |
| The target's menu | Claude, on the screen; then a "Send to a session" heading and the sessions, each by project with its name under it |

#### On the ink, in the person's colour

Vignette's own words about an ask, beside the ink it was about.

| When | Words |
| --- | --- |
| Sending to a session | Sending to *project* |
| The session took it | Sent to *project*. Its reply comes back as a card. |
| Queued, or not confirmed in time | Queued for *project*. / Check *project*. Then the reason, as on a card. |
| The session did not take it | Not sent. Then the reason, as on a card. |
| No Screen Recording | Live ink needs Screen Recording permission to see the screen. |
| The capture failed | Vignette couldn't see the screen. / Vignette couldn't capture the window. |
| No `claude` found | Vignette couldn't find Claude Code. |
| Claude Code is signed out | Claude Code isn't signed in. You can sign in by running claude in Terminal. |
| The usage limit | Claude's usage limit is reached for now. |
| No answer in 45 s | Claude took too long to answer. You can ask again. |
| The process ended | Claude stopped before it answered. You can ask again. |
| The answer did not parse | Vignette couldn't draw Claude's answer. You can ask again. |
| Anything else | Claude couldn't answer. You can ask again. |
| The CLI started with tools | Live ink stopped Claude, which started with tools. |

### A copy, on its card ("Not copied")

| When | Reason |
| --- | --- |
| The screenshot did not read | Vignette couldn't read the screenshot. |
| The rendering could not be written | Vignette couldn't save the drawing. |
