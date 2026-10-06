# Live ink refinement round (2026-10-05)

Status: in progress. Pete asked for autonomous refinement while he is away, so the list below is
the plan of record and each item says what was done.

Findings come from take 19 (`media/live-ink-demo/out/dev/takes/take-20261005-145744.mov`) and its
log.

## Fixes

1. **The target moves under the note.** Pete asked for it. The note is the person's words alone,
   as wide as they are. A small chip under it, left-aligned, names where Return sends: the agent's
   logo, the project, and a chevron. Sending fades the chip, and the note keeps its width, so the
   composing and sent states differ only by the chip.
2. **Claude's reply hangs under the person's note.** In take 19 the reply landed at the bottom of
   the window, over a card, far from the question. A reply now goes right under the note that asked,
   left-aligned with it, with the actions under the reply. That reads as one thread: the question,
   the answer, what to do next. It falls back to the ink when there is no note.
3. **Nothing Claude draws covers what it points at.** The reply and labels are placed before the
   targets are cleared, so a reply can sit on the words a circle names. The targets become
   obstacles for every note of the answer.
4. **One badge per answer.** Every label carried its own "Claude" badge, so three findings showed
   four badges. Labels keep the agent's colour and font and drop the badge. Only the reply names
   Claude.
5. **Marks stay on the page.** The person's note sat on the mobile window's title bar, and an answer
   could too. The room for notes and answers is now the page's web area when the app reports one,
   else the window.
6. **Marks no longer blink while Claude edits.** When Chrome reloads the page, the elements the
   marks are anchored to die. The marks then sat where they were for 2 s, hid, and came back
   160 ms later, found by their pixels. Now, while the session works, a mark whose element stops
   reading is looked for by its pixels while it still shows. Once two looks agree, it glides there
   and takes the element now under it as its anchor.
7. **The note opens sooner.** It showed 0.53 s after the chord was let go, waiting on the capture
   of the window. The capture's steps are timed in the log, and the slow ones run side by side.
8. **The skill asks for cohesive answers.** Marks in reading order, one finding each. Labels that
   name the problem in the person's terms. A `say` that counts and ties them together. Actions that
   match the findings. Words fully visible in the window.
9. **The demo plan matches what is built.** `docs/live-ink-dev-demo-plan-2026-10-05.md`.
10. **The person's note touches its ink.** Placed clear of the window's text, the note about an
    arrow could land a long way from it, and read as a separate remark. A note now goes where a
    hand would write it: against an arrow's tail, on the side the arrow came from, or beside a
    loop's edge. It may cover a few words of the window there. Left of the ink, it grows to the
    left, so its right edge stays at the tail as the words come.

## Verification

A new take after the fixes, read frame by frame, then another round of findings.
