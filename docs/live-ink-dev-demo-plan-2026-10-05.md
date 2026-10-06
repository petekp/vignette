# Live ink demo for developers: plan (2026-10-05)

Status: built. `media/live-ink-demo/devtake.py` performs and records it.

## The story

A developer is building Postcard, the trip planner the trailer uses. Three windows are open:

- Postcard in Chrome, at desktop width, served with live reload.
- The same page in a narrow Chrome window at mobile width, tucked into the screen's bottom-right
  corner. Its top bar is left broken at that width on purpose, for beat 3 to find.
- Claude Code in Ghostty, working in the Postcard folder.

The developer never types where something is. They draw on the running app, type a few words in the
note that opens beside the ink, and the work happens. Each beat is one ask:

1. **Number the days.** On the desktop window, an arrow from the map's first stop to the first day.
   "number the days like the map", sent to the Claude Code session, picked from the chip under the
   note. The ink and the note shimmer while Claude edits `styles.css`. Both windows reload, the
   days get numbered badges, and the ink turns green, a check pops up, and it leaves.
2. **Stack on mobile.** On the mobile window, a loop round the squeezed day cards: "stack these on
   mobile". The note remembers the session. While Claude works, the developer drags the window in
   from the corner, and the ink goes with it. The cards stack, and the ink finishes as before.
3. **Review on mobile.** A loop round the mobile page: "what else should we fix on mobile?" Claude
   answers on the window. Its reply hangs on the question, its marks point at what breaks ("Share
   cut off", "Map cropped"), and two buttons sit under the reply: "Fix both" and "Header only". The
   developer clicks "Fix both". The answer and the ink shimmer while Claude fixes both, glide with
   the page as it reloads, and finish.

The beats show what a screenshot tool cannot: ink on live windows, a window moved mid-task with its
ink, and the agent answering on the page itself, in one continuous session with no capture step.

## How it is staged

It builds on the trailer's pipeline (`docs/trailer-pipeline-2026-09-26.md`):

- **App:** Vignette Demo, the stage copy, built from this branch with its own bundle id.
- **Claude Code:** the trailer's own copy, signed in under its own config in `media/trailer/out/stage/claude`.
- **Project:** Postcard, copied to `~/Code/postcard` for the take.
- **Stage:** `media/live-ink-demo/dev.py up` sets the windows and holds them; `dev.py down` takes
  them down and reopens Pete's own Vignette.
- **Recorder:** captures only the stage's processes.

`devtake.py` checks Vignette's state before every press and writes each beat's time to
`<take>.beats.json`. Claude takes 10 to 20 s per change, so the video needs cuts.

## Decisions

1. **Claude's answer is drawn on the window.** Its reply hangs on the person's note, and its marks
   point at the words they name, found in a fresh capture of the window. ADR 0021 and
   `scripts/reply --answer`.
2. **The stage copy runs the take.** Vignette Demo, with its own bundle id, so the target menu
   shows only the stage's Claude Code. Pete grants it Screen Recording and Accessibility once.
3. **A captioned cut of about 40 s.** It skips Claude's working time.
