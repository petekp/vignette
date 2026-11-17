# Checking a live ink change

These are the checks for a change to live ink. Its rules are in `docs/live-ink.md`.

- `Tests/LiveInkTests.swift` holds the unit tests: the chord, strokes, placement and result cards.
  `Tests/NoteCardWaitTests.swift` holds how a note card's wait ends, in any order of reply, turn end and delivery.
  `Tests/NoteCardGroups*.swift` hold how the notes one turn end answers end together.
  `Tests/LiveAsksTests.swift` holds the asks' sequences: asks waiting their turn, answers on the screen together, late
  callbacks, erasing, follow-ups, dismiss, finish and clear, and random sequences that check the invariants.
- A script reaches the note with no hand on the keys: `live-ink-chord-down`, `live-ink-stroke` per
  stroke, then `live-ink-chord-up` (all need `debug`). A VM's VNC cannot press ⌃⌥, so a VM check
  opens the note only this way.
- A take records the developer demo on a stage
  (`docs/live-ink-dev-demo-plan-2026-10-05.md`), taking the screen for minutes. From
  `media/live-ink-demo/`: `python3 ../trailer/trailer.py build`, then `python3 dev.py up`, left
  running until it prints "the stage is up", then `python3 devtake.py [--only BEAT]`, then
  `python3 dev.py down`.
- A take prints a `[check]` line for each mark that moved on its window, each note that moved while
  open or opened away from its ink, and each label that had no room, and keeps them as `findings`
  in `<take>.beats.json`. Read them before reading frames. The labels come from the log:
  `[live-ink] drew answer … labels=<drawn>/<asked>` counts the labels that found room.

