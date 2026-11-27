# How Vignette speaks: live comments

These are the words for a pin comment that goes to an agent session as it is posted
(`docs/rules/live-comments.md`). `voice.md` has the rules and the rest of the pins' words.

| Where | Words |
| --- | --- |
| After a comment's time, while sending, queued, unconfirmed or failed (`CommentDeliveries.Shown.words`) | Sending to Claude; Queued for Codex; Not confirmed; Not sent |
| Under a queued, unconfirmed or failed comment's words | The reason, as Send says it (`SubmissionOutcome.reason`) |
| Under a comment taken back out of a Codex queue (`CommentDeliveries.removedReason`) | It was removed from the thread's queue in Codex. |
| The row under a pin's comments while the turn its comment started runs | Claude is working, beside the system's small spinner |
| The popover's field, empty, when a comment would go to a session | Comment for Claude · vignette, on a new pin; Reply to Claude · vignette, on a pin with comments |
| The line the session gets, before its brackets (`HeldChanges.line`) | Pin 3: *words*; Pin 3 (reopened): *words*; Pin 3's comment now reads: *words*; Pin 3: deleted the comment "*words*".; Pin 3: resolved.; Pin 3: reopened. |
| In its brackets | From Vignette: comments on "*path*". Pin 3 (id *pin*, comment *comment*) at 42% across and 18% down. Answer on the pin with show and pins=, and resolve it when it is done (the vignette skill's references/live-comments.md). |
