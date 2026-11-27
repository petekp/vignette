# A comment reaches the agent as it is posted

Status: accepted, 2026-11-27. Pete chose this design ("Build step 1") and its look ("A"), and that
the toolbar's Send target starts on the same session ("Match it").

A person who draws on a screenshot an agent showed them often answers on a pin, and the agent
asked for that answer. Until now the comment stayed in Vignette until they pressed Send, which
carries the whole picture again, or the agent read `vignette://comments` on its own. A short
"yes, that one" needed a full send.

## What happens

A comment the person posts goes to one running agent session after Send's 3 s grace. Their edits,
deletes, Resolve and Reopen go too, to a session that already has the comment. The session is the
pin's own, the one whose agent wrote on it, or else the screenshot's last session. A session that
is not running gets nothing, and nothing starts one. The comment says on its top line where it
went, and a row says while the turn it started runs. `docs/rules/live-comments.md` has the rules.

The toolbar's Send target starts on the same session, the screenshot's last, ahead of the kept
pick, so the bar and the popover never name two sessions for one image (`docs/rules/send-start.md`).

## What was weighed

- Every comment waiting for Send, as before. The agent that asked the question would wait on a
  second action it cannot see coming.
- A switch per pin or per comment to send it. Pete chose that every comment goes, the way a reply
  in a chat does, and the popover says where before the person posts.
- Starting the session when none runs. A comment would then open a terminal or a thread the person
  never asked for. Send's target menu stays the one way to start one.
- Storing deliveries in Send's request records. A record is one send with its picture, its pins and
  its reply ticket, and the stack's send notices, `clear` and the reply protocol all read it. A
  delivery is one line of words with no picture and no ticket. A second kind in the same store
  would make every reader tell the two apart, so a delivery has its own file.
- Sending each change at once. Edits made seconds apart would each start a turn. The grace merges
  them into one line, and a post deleted inside it never goes.
- Telling a session about every comment on the screenshot. A session hears only about posts and
  about the comments it got or wrote, so it is never asked about words it never saw.
- Showing a delivery as a toast or a card notice. Vignette has no toasts, and the card is behind
  the editor. The comment's own top line says it, as a card says a send.
