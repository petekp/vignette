# Live ink sent to a session goes through cards

A live ink note sent to an agent session leaves the window as a card: the window without the ink,
with the ink and the words as its drawing, in the screenshots folder. When the session's turn ends,
its result comes back as a card from that session: the window captured afresh, with the session's
answer drawn on it when it gave one. A turn that changed nothing under the ink makes no result card,
and the note card says the session is done. Live ink's built-in responder still answers on the
window.

Windows move, scroll, get minimized and close, and a request queued behind another turn kept the
ink on the window for as long as 30 minutes. A card stays put, says what happened to the send as
a send from the editor does, and its Reply goes back to the session. The responder answers within
a few seconds while the person is still looking at the window, so the window is still the right
place for it.

This supersedes ADR 0022, which drew a session's answer on the window.

## Considered options

- Answers on the window, as ADR 0022 chose. The window is often gone or changed by the time a
  session answers.
- Keeping the ink on the window while the session takes the note at once, and making a card only
  when the note is queued. Two behaviours for one action, and a turn that starts at once can still
  run for minutes.
- A note card that is not a file. The stack shows files from the screenshots folder, so a card
  without one is a larger change, and the note could not be copied, dragged or sent again.

Source: docs/live-ink-note-cards-2026-10-08.md. Supersedes: 0022.
