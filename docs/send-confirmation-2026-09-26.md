# Send's confirmation on the card (2026-09-26)

Pete found the Send flow rough: the button's change to a sending state had no finesse, and the
confirmation came as a toast. He asked for the card itself to say that the drawing was sent and
where it went, as a card says it was copied.

## What happens now

A send has two waits. The drawing renders, about 150 ms (`docs/e2e-2026-09-26.md`), and the
request is stored. Then the editor closes and the client delivers the line off the main thread:
380 ms for one herdr submission in the log on 2026-09-26.

- **The button.** Its title swaps to "Sending…" and loses its ⌘↩, so its width changes, and its
  fill drops to 55%, which reads as disabled. The other controls grey out in one frame. The state
  lasts about 150 ms, so it shows as a flicker.
- **The card.** It flies home with no mark.
- **The confirmation.** A toast, "Sent to <session title>", about a third of a second later. In
  the open stack it sits under the cards. For a lone thumbnail, `showFeedback` removes the card
  that just flew home and puts the toast in its place.
- **A failure before the request is stored** (the rendering fails, the image does not read, the
  store refuses) is a toast too, while the editor stays open with the drawing.

## The button

- **It keeps its size.** Its label stays in the layout under whatever the button shows, so the
  message field and the target beside it never move.
- **A press turns the label into a paper plane.** The label blurs out and a `paperplane.fill`
  blurs in from the lower left. The wait is about 150 ms, too short for a spinner to read as
  anything but a flicker. If the wait runs past 0.5 s, a small spinner replaces the plane.
  `sending` stays on until the bar has left, so the plane carries on up and to the right as the bar
  fades, instead of the label coming back for a frame.
- **The fill stays full.** The button is busy, not disabled. The other controls fade to 40% on a
  spring (`Resting`), because `.disabled` switches AppKit controls in one frame.
- **A failure before the store** leaves the drawing in the editor, so it shows there. The button
  shakes, turns red and reads "Not sent", and a popover on it gives the reason, such as "Vignette
  can't read Screenshot 3.png. It may have been moved or deleted." Both stay until a click
  elsewhere, which closes the popover, or Send again, which is a retry.

## The card

- **It carries a send mark from the moment the request is stored**, as a card carries the copied
  mark after Done (`SendMark`, keyed by the file's path). The mark shows when the card lands, in
  its slot or in the corner.
- **The mark matches the copied mark.** It uses the same dim and the same spring in. In the middle
  is the destination's logo on a white disc. Under it is the destination's project, the name the
  target button showed.
- **A badge on the logo gives the delivery state:** a spinner while the client delivers, a green
  check once it accepted, orange when delivery is uncertain, red when it failed. The words follow:
  "Sending to mew", "Sent to mew", "Check mew", "Not sent".
- **A failure says why and what to do**, in a line under the words, such as "This session is
  closed. Send to another one." or "Answer Claude's question in the session, then send again."
  Every failed or uncertain `SubmissionOutcome` carries this `reason`, written where the client
  knows what went wrong; a failure Vignette has no sentence for quotes herdr's or Codex's own
  words. A click on the card opens it in the editor, which is where a retry happens.
- **Two steps, not a flicker.** A delivery usually answers about as the card lands. Once the
  sending state is on screen it holds 0.45 s before it gives way, and the words change as one
  piece (a blur replace) rather than letter by letter.
- **A narrow card drops the reason first, then the words.** The stack narrows while the annotator
  is open, and a queue sends from there. The logo and its badge stay.
- **It holds as the copied mark does**, `toastSeconds` plus `expandDuration`, counted from the
  outcome. A failure holds three times as long, since it has a sentence to read. A lone thumbnail
  stays until its mark goes, and while a delivery is still pending.
- **A card that is gone by the outcome** (the stack was dismissed, or the thumbnail left) shows
  nothing more for a success. A failure brings the card back as a lone thumbnail with the failed
  mark.

## Later the same day

`docs/prerelease-fixes-2026-09-26.md` took the two points left out here:

- The "<session> replied" toast is gone, since a reply arrives as a card of its own. A reply that
  could not be made a card shows on the card it answers, as "Reply not shown".
- A send past 50 open requests clears the oldest instead of refusing.

## Checked

On the stage copy, with a stub in place of herdr at `media/trailer/out/stage/bin/herdr` that
reports one Claude Code session and answers a submission after a set delay, or refuses it. Nothing
was sent to a real session. 60 fps recordings of each case:

| Case | Result |
| --- | --- |
| Lone thumbnail, accepted in 0.43 s | The card lands with "Sending to mew" and a spinner, then the check and "Sent to mew". It holds, then the thumbnail leaves. |
| Stack, accepted in 2.1 s | "Sending to mew" for the whole wait, then "Sent to mew". |
| Refused as a closed session | "Not sent" and "This session is closed. Send to another one." for about 6 s. |
| Refused after the stack was dismissed | The card comes back as a lone thumbnail with the failed mark. |
| Rendering fails (image made unreadable) | The button shakes and reads "Not sent", and the popover gives the reason. A click on the image closes both. |
