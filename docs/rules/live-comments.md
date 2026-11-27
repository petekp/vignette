# Live comments

A comment the person posts on a pin goes to an agent session as they post it, without Send. So
do their edits, deletes, Resolve and Reopen of what that session already has. `pins.md` has the
pins themselves, `send.md` how a line reaches a session, and ADR 0035 why it works this way.

- Every change the editor commits is diffed against the pins before it (`CommentChange.between`,
  called from `AnnotationController.drawingChanged`), so a post, an edit, an undo and a redo all
  count the same way. Only the person's own changes count: a comment they post, change or delete,
  an agent's comment they edit, which becomes theirs, and a Resolve or Reopen they press. A comment
  that reopens its pin is one post marked "(reopened)", not a post and a reopen. A new pin, number
  0, counts once its first comment numbers it. The opening's own load is no change
  (`AnnotationController+Opening.swift` clears `pinsBefore`).
- A change goes to one session (`CommentTarget.destination`). It is the pin's own session, the
  newest agent comment on it that named one, or else the screenshot's last session
  (`AppDelegate.lastSession`, `CommentTarget.last`). That is the session showing it in this opening,
  then the newest of the sessions its comments, its sends and its reply came from, then the session
  that pushed it. It goes only while the annotator's session list holds that session running
  (`DestinationChoice.Answer.list`, a row with no `start`). Nothing starts a session for a
  comment. With no running session it stays on the pin, and the log says
  `[comments] stay <name> changes=<n>: <session> is not running`.
- A post always goes. An edit or delete goes only to a session that got that comment, has it
  waiting or wrote it. A Resolve or Reopen goes only to a session that knows a comment on the pin
  (`CommentTarget.knows`, `CommentDeliveries.known`). A session never hears about a comment it
  never saw. A failed delivery does not count.
- Changes wait `ui.sendGraceSeconds`, Send's grace, from the first one, held per screenshot and
  session (`CommentDeliveries.add`, `HeldChanges`). The wait does not restart. During it, an edit
  of a held post changes the post's words, a delete of a held post takes both out, a delete
  replaces a held edit, and a Resolve and a Reopen of the same pin cancel. A hold left with nothing
  is dropped (`[comments] held <id> went empty`). At quit every hold goes at once, and Vignette
  waits at most 0.5 s for their answers.
- The hold becomes one line (`HeldChanges.line`): what changed, pin by pin, then where in
  brackets, with each pin's id, the comment's id and its place in percent. It names the
  screenshot's path and the skill's `references/live-comments.md`. It goes through the same
  connection a send does (`AgentConnection.submit`): into the Claude Code session's inbox as a
  `.line`, or into the Codex thread's queue with `codex queue`. Both are read between turns. No
  image goes, since the session can read the file and `vignette://comments`.
- Each line is a delivery in its own store, `comment-deliveries.json` in the app's Application
  Support folder (`CommentDeliveries`), never in Send's request records. A delivery holds the
  screenshot's path, the session, the comments it carried, the pins it named, when, its status
  (`sending`, `sent`, `queued`, `uncertain`, `failed`), why, and the line a Codex queue holds.
  It keeps the newest 1,000. A delivery still `sending` when the app starts reads `uncertain`,
  since its answer was lost. A delivery still `queued` with its line is watched again at launch, as
  often as the line's age calls for, until it is `sent` or `failed`. A rename moves the screenshot's
  deliveries, and a file that leaves the folder drops them and its holds. The log says
  `[comments] <status> <id> <session> comments=<n> <detail>`.
- A Codex line waits in the queue until the thread takes it (`QueueWatch`, as Send's does). Taken,
  it is `sent`. Taken back out of the queue in Codex, it fails, saying so
  (`CommentDeliveries.removedReason`). A thread that is gone fails it with Send's reason.
- After a line is `sent`, Vignette reads the session's turn (`AgentConnection.turn`) 0.5 s later
  and then every second (`CommentTurnWatch`). A busy turn is the comment's, since a session takes a
  line only between turns, and logs `[comments] working`. The watch ends when that turn ends, when
  no turn starts within 10 s, or after 30 min.
- In the popover, a delivered comment shows just its time. While sending, queued, unconfirmed or
  failed, it also shows "Sending to Claude", "Queued for Codex", "Not confirmed" or "Not sent"
  (`CommentDeliveries.Shown`, `PinPopover+Delivery.swift`). For a queued, unconfirmed or failed
  delivery, the reason is under the comment, in the secondary label colour. While the turn it started
  runs, a row under the pin's comments holds the agent's avatar, "Claude is working" and the
  system's small spinner, still at `ui.motion` 0. The row goes when the turn ends, or when the
  agent answers on the pin. A delivery's change reaches the open popover
  (`AnnotationController.commentDeliveriesChanged`, `EditorView.refreshLiveComments`).
- `vignette://comments` gives each comment a `delivered` list, oldest first: `agent`,
  `session`, `to` (the session's name), `at` and `status` (`PinCommentsReport`). It is empty for
  a comment no line carried.
