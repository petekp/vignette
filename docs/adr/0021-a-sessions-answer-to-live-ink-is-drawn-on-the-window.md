# A session's answer to live ink is drawn on the window

Live ink sent to a working session, such as "move these under the title", is answered on the window
the ink is on. The session's words appear beside the ink, and its marks point at what it changed.
The person drew on that window and is looking at it, so an answer there needs no trip to the stack.

The session names what its marks point at by words, and Vignette finds them in a fresh capture of
the window when the reply arrives. Positions in the picture the session was sent would be wrong
whenever its change moved things, which is most changes. The responder's answers already find their
marks by text lines (ADR 0020), so a session's answer is the same `LiveAnswer` and is drawn by the
same code.

The answer travels in the reply's bundle, which raised `ReplyProtocol.version` to 2. A reply from a
helper of version 1 is refused, and a request sent before the change cannot be answered by the new
helper. Requests are answered within the hour, so that loss is small.

An answer that cannot be drawn on its window becomes a card: the words in its corner, and a ring for
each mark that gave a box. That happens when the ink was cleared, when a newer ask is under way, or
after Vignette relaunched, since the window and the ink are not kept across launches.

## Considered options

- A card, as every reply was. The answer then leaves the window the person drew on.
- Marks in fractions of the sent picture, as a drawing's are. They land on the old layout after a
  change.
- A ticket field that marks a live ink request. The message already says so, and the app decides
  where an answer goes from its own state.

Sources: docs/live-ink-dev-demo-plan-2026-10-05.md, docs/live-ink-integration-2026-10-04.md (decision 6).
