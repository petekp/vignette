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
6. **Marks hold still while Claude edits.** When Chrome reloaded the page, the marks sat for 2 s,
   hid, and came back found by their pixels. Gliding them to their content instead still read as
   everything shifting around. Now, while the session works and while the done animation plays,
   the content moving under a mark moves nothing. The marks finish where they are.
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
11. **The reply keeps off the person's loop.** Its spot under the note was checked against what
    the answer points at and other notes, not the person's ink, so with the note above a loop the
    reply could land on the loop. It now counts the ink too, and tries the note's right edge as well
    as its left before going above the note.
12. **Claude's marks stay on their targets.** Making every mark of the answer follow the person's
    ink kept the label off the reply, but when Claude's fix moved the content under the ink, every
    mark slid away from what it pointed at (take of 2026-10-05 17:50). Each pointing mark is again
    anchored to its own target.
13. **The chip sits by the ink.** A note left of its ink keeps the pill and the chip against its
    right edge, next to the ink.
14. **A hook does not flip the note.** Which way an arrow leaves its tail is measured over its first
    24 pt, so a stroke that curls at the head no longer puts the note on the wrong side.
15. **Withdrawn: fading a mark that is never found.** It belonged to the glide, which item 6 removed.
16. **Claude's labels touch their arrows, in a column.** A label goes where a hand writes one, the
    same spots as the person's note: touching an arrow's tail on the far side, or a circle's edge.
    Later arrows come from the first one's side, with their tails level, so the labels line up.
17. **An action shows the findings it covers.** An action may name its marks by index
    (`{"title": "Header only", "marks": [0]}`). Pointing at its button fades the other findings.
    The reply protocol is now version 4, the skill version 13, the plugin 6.3.4. The responder's
    own schema still sends plain words, which act on every mark.
18. **A take stops early when it cannot finish.** `devtake.py` checks that Claude Code's API
    resolves and that nothing covers the stage before recording. It raises the stage before each
    beat, stops a beat as soon as the stage's Claude Code logs an API error, and runs that beat
    again once.
19. **The demo notes lost an outdated tip** about keeping the pointer still: the note follows the ink.
20. **The reply replaces the question and quotes it.** Once Claude answers, the person's note goes,
    and the reply sits in its place. Its first line is the person's words in quotes, in their font,
    smaller and muted, cut with an ellipsis to the reply's width. The question and the reply no
    longer compete for room, so the reply is never pushed away from it.
21. **Ink counts as strokes.** Notes and labels avoided the whole bounding box of the person's ink,
    so with a loop round the whole page the reply went to the window's bottom and both labels were
    dropped. The ink now counts as its strokes; what a loop encloses counts as lightly as text.
22. **A take reports marks that move.** Five times a mark moved where it should not, and Pete saw
    it before any check did. A take now reads live ink's state twice a second and records a finding
    for a mark that moves on its window, a note that moves while open or opens more than 30 pt from
    its ink, and a label Claude asked for that had no room. `[state] liveInk` gives each mark's
    `id` for this, `state?section=liveInk` reports that section alone, so the readings do not
    rotate the log, and `[live-ink] drew answer` logs `labels=<drawn>/<asked>`. The first take with
    it (`take-20261005-185039`) reported the missing label and no moved marks.
23. **A take checks the stage before recording.** It stops when the stage's Claude Code is signed
    out or busy, a stage window lost its size, or, for a whole take, Postcard's files changed since
    `dev.py up`.
24. **Live ink's rules moved to `docs/live-ink.md`.** `AGENTS.md` is read on every turn, so it keeps
    one pointer. The doc adds a map of which file owns which part, and how to check a change.
    `LiveInk.swift` stays one file: 64 of its 107 private members are shared between its parts, so
    splitting it would open them to the whole module. Its note placement moved under Asking, and
    the answer has its own section.
25. **CI runs the unit tests.** `.github/workflows/test.yml` runs `scripts/build.sh --test` on a
    macOS 26 runner for every push and pull request, ad-hoc signed.

## Verification

A new take after the fixes, read frame by frame, then another round of findings.
