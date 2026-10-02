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

### A copy, on its card ("Not copied")

| When | Reason |
| --- | --- |
| The screenshot did not read | Vignette couldn't read the screenshot. |
| The rendering could not be written | Vignette couldn't save the drawing. |
