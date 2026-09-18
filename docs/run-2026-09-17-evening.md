# Run 2026-09-17, evening: five branches merged into `todo4/integration`

Five agents worked in parallel this evening. Everything they built is merged, builds, passes the
tests, and was driven in one combined build. Nothing is left half-merged.

The branch to take is `todo4/integration`. Section 3 says how.

Merge commits, in order:

| commit | branch | what it brings |
| --- | --- | --- |
| `f1b02ce` | `todo4/page` | the rectangle opens, no palette, a mark coloured for what it covers, a stitch a model can read |
| `0a32751` | `todo4/stack-look` | the selection number in SF Rounded, Copy and the strip name themselves on hover |
| `9f44d64` | `todo4/stack-keys` | the newest card has the focus, it follows the pointer, annotating a list is a queue |
| `3e7d297` | `todo4/zoom` | the annotator zooms a native stand-in, and the page paints only at rest |
| `5330015` | `todo4/room` | the stack narrows to make room for the annotator; tests point at their own settings |

`./scripts/build.sh --test` passed after every merge: 157, 158, 158, 166, 169 tests. Three merges
conflicted (`stack-keys` and `room`, in the docs and in `ThumbnailController.send`); section 4 says
what each resolution keeps. Ten files needed reading by hand because more than one branch changed
them.

Both `page` and `zoom` bumped the bridge protocol from 7 to 8, so the merged number is 8 on both
sides, one step above `foundation`'s. The running build logs
`[web] ready protocol=8 tools=4 colors=0 markColors=5`.

---

## 1. What landed

### The editor opens on the rectangle, and the circle tool is gone
`todo4/page`, `1f4f57d`.

`TOOLS` in `web/src/config.ts` is select, rectangle, arrow, text; `DEFAULT_TOOL` is the rectangle.
`hideUi` hides tldraw's UI but leaves its own shortcuts bound on the document body, so `Hotkeys`
in `App.tsx` stops every plain letter in the capture phase: a key tldraw binds cannot reach a tool
the toolbar does not show. `ellipse` is still a mark kind an agent can push.

Verified in my round: a fresh image reported `annotator.tool = rectangle`; the toolbar crop
(`integration-scratch/captures/toolbar-crop.png`) shows four tools, one divider and Done. The agent
proved the key path: after `o`, `r`, `a`, `t`, `v` the tool is never ellipse, and tldraw's own geo
style reads `rectangle`. Typing in a text annotation still works — the handler returns early while
a shape is being edited.

Not verified: every letter of the alphabet, only the five bound ones.

### No palette, and a mark takes its colour from what it covers
`todo4/page`, `482eba7`.

`SHOW_COLORS` is off, so `ready` carries an empty swatch list and the toolbar drops the swatches
and their divider. `web/src/contrast.ts` decodes the screenshot once at 320 px, samples at most
20x20 pixels under a mark's bounds, and keeps the first colour in `CANDIDATES` (red, yellow,
light-blue, white, violet) whose CIE76 distance in CIELAB from the 10th percentile of that sample
is at least `MIN_COLOR_DISTANCE` (55). It runs when a mark is created, when the hand lets go,
before every park and Done rendering, and inside `build` for a pushed mark with no colour, all
outside undo history. A colour the user picked or an agent named is kept (`meta.colorChosen`).

Verified in my round on a fixture that is white on the left and `#e03131` on the right:

- Drawn live with the rectangle tool over the red half: `geo x=300 yellow`.
- Pushed with `add?marks=`: the mark over white came out `red`, the mark over red came out
  `yellow`, and the arrow that named `violet` kept it with `meta {'colorChosen': True}`.

The agent's quadrant numbers are the reason for 55: the largest distance the rule must reject is 36
(red on dark red), the smallest it must accept is 58. `docs/annotation-colour-2026-09-17.md` has the
table.

Not verified: the timing of the decode and the pick (no ms figure), and a busy photographic
background beyond one spot check.

### A stitch is laid out for the model that will read it
`todo4/page`, `004c746`.

`Stitch.compose` tries every column count, fewest first, and keeps the one whose composition
survives a vision model's resize best (`readerScale` against a 1568 px long edge and 1568 patches of
28 px). The gap is 2% of the mean piece width (12–48 px) and each badge is 6% of its own piece's
short side (32–128 px), so both keep their size relative to the screenshot's own text.
`ui.stitchLongSide` (4096, bounds 64–20000, a slider under Stitch) caps the output.

Verified in my round: three selected cards, Cmd+S →
`[stitch] ok … from 3 images, 2042x3444 columns=1 readerScale=0.41 1745843 bytes, copied`, then
`[stack] stitched cards=3`. The three pieces left the column and the new card took their place at
the bottom (`[1375, 740, 120, 153]`). `sips` confirms 2042x3444. Badge 1 is a red disc with a white
number, inset from its piece's corner. The agent's six-piece case went to three columns and the
long-side cap brought 5408x2516 down to 4096x1906.

Not verified: an actual paste into a model. `readerScale` is arithmetic from the published limits.

### A selected card's number is drawn in SF Rounded
`todo4/stack-look`, `f96b39c`.

`SelectionCircle` draws at `size * 0.56`, semibold, `design: .rounded`, proportional widths. At the
default circle size the type goes 11.4 → 10.64 pt and the advances go 1=7.7 → 5.5, 23=15.4 → 13.9.

Verified in my round by the crop `captures/strip-revealed-big.png`: the numbers 1 and 2 read
clearly in the rounded face. The agent measured the before and after on the same 24 fixtures with
identical card frames and scroll values.

Not verified: three digits (more than 99 cards), left to `minimumScaleFactor`.

### Copy on a card, and every button in the strip, names itself on hover
`todo4/stack-look`, `c53a460` and `86ff8c2`.

One `hovered` bool animates a label's frame from 0 to its measured width and its opacity from 0 to
1, under `Anim.spring(ui.hoverRevealDuration)` — the tweak that already meant this, so no new
number. The icons never move: Copy grows to the right from a fixed leading edge (27 → 62 pt), and
the strip keeps a layout box the grown width with the strip against its leading edge, so nothing in
the panel moves when the labels come out. The reveal is the widest label's own width, measured in
the font the view draws, so it followed the strip's buttons changing without a line of code:
35 → 140 pt while Copy Annotated was on it, 35 → 98 pt now that Annotate is.
`StackLayout.stripReveal` caps the growth at the panel's right edge. A strip row drops the 1.08
hover scale; a press still scales.

Verified in my round: `stack.strip` `[1264, 574, 35, 128]` at rest → `[1264, 574, 98, 128]` with
`stripHovered true`, the x unchanged; the crop shows Copy, Annotate, Stitch and Delete beside their
icons. The agent's 60 fps recordings show an interrupted reveal turning around at 58% and running
back monotonically, and `ui.motion: 0` reaching full width in two frames (33 ms).

Not verified: a label clipped by the cap on a very narrow selected card (unit test only).

### The stack focuses the newest card, and the focus follows the pointer
`todo4/stack-keys`, `9d5c634` and `5998887`.

`takeKeys` sets `model.focused` to the hovered card, else the newest, so arrows, Space and Return
act without a first click. `onHover` moves the focus while the stack holds the keys; leaving a card
leaves the focus there. `targetCards` is the selection, else the focused card. Space over a card
therefore selects the card under the mouse.

Verified in my round: the stack opened with `focused = Screenshot smoke 3.png` (the newest) and
`hovered = null`. Walking onto a card moved both. Space over one card then another gave
`selected: ['Screenshot smoke 1.png', 'Screenshot smoke 2.png']` — the pick order, not the column
order — and the strip appeared between them.

Not verified: focus across a screen change, and a scrolled column with many cards.

### Annotating several cards is a queue
`todo4/stack-keys`, `534023a`.

`annotate(_ shots:)` opens the first and keeps the rest in `queue`. The handover happens inside
`send`: when `parked` leaves the reducer idle, the next file is taken **before** the effects run and
`annotate` is sent **after** them, so the finished card flies home with its copied mark while the
next flies out — a swap's two flights. `returnCard` only ends the session when nothing follows. The
selection is no longer cleared by `prepare`, so the same cards are still selected at the end.

Verified in my round, two selected cards, Return:

```
20:44:29.007 [annotate] ok Screenshot smoke 1.png 1 of 2
20:44:43.965 [transition] finish -> parking(…) effects=park(Screenshot smoke 1.png)
20:44:43.970 [transition] parked -> idle effects=returnCard(…) markCopied(…)
20:44:43.970 [annotate] next Screenshot smoke 2.png 2 of 2
20:44:43.971 [transition] annotate(Screenshot smoke 2.png from stack) -> flyingOut(…) effects=prepare(…)
```

After the last Done: `queue: []`, `phase: idle`, both files still selected, one
`[focus] annotator closed` for the whole run.

Not verified here: a new capture arriving mid-queue, and a click on a card mid-queue replacing the
queue (the agent read both paths in code; the click path is the same line the swap test below
exercises).

### The annotator zooms a native stand-in
`todo4/zoom`, `24b9dd4`.

While a zoom moves, what is on screen is the app's own picture: `Sources/StandIn.swift` draws the
screenshot (decoded no larger than the visible screen) with the page's annotation overlay on top,
in the frame's own layer tree. One tick sets the level, splits it, moves the frame and lays the
stand-in out inside it, in one run-loop turn. At rest the web view is laid out at the frame's size
rounded up to whole points and the page is given the exact view through `setView`; it answers when
it has painted, and the stand-in crossfades out (0.12 s, motion scaled) — but only while the spring
is still at rest.

Verified in my round, four keyboard steps on a 1000x600 image:

| step | level | window | camera | stand-in | frame right | stack width | gap |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 1.239 | 1.198 | 1.033 | up | 1377 | 0.50 | 24 |
| 2 | 1.553 | 1.198 | 1.296 | up | 1377 | 0.50 | 24 |
| 3 | 1.938 | 1.198 | 1.617 | up | 1377 | 0.50 | 24 |
| 4 | 2.422 | 1.198 | 2.021 | up | 1377 | 0.50 | 24 |

At rest: `standIn false`, `page.inner [1378, 825]` against a frame 1377 wide, `page.zoom 2.037`
against `zoomLevel 2.441 = zoom 1.198 × canvasZoom 2.037`. Each hand-over logged
`[annotate] view 21–36ms ratio=… waited=0`. Cmd+0 came home to the fitted frame
`[114, 103, 1149, 689]` with one more `view 21ms ratio=1.0000`.

The agent's frame-by-frame measurements are the reason for the design: a moving magnification drew
a new picture in 118 of 125 frames (was 64 of 132), grid lines are 56.2 grey levels deep while
moving (was 45.1), and the swap at rest is two frames identical to within 6 grey levels of 255.

Not verified by either of us: a real trackpad pinch, a two-finger double tap, drawing immediately
after a zoom, the Studio Display's negative y, and a swap while zoomed.

### The recent stack narrows to make room for the annotator
`todo4/room`, `4dd0b97`.

One number, `StackLayout.widthScale`, says how wide the stack is drawn. It scales the cards and the
column with the right edge fixed; spacing, insets, corners, shadows and the panel are unchanged, so
a card casts the same shadow at any width and no window is resized while a zoom moves.
`annotatorRoom` is the visible frame less `screenMargin + cardMaxWidth * stackMinScale + stackGap`,
and it is what the annotator fits and grows within (`growthLimit`). Between the extremes the stack
takes the widest value that still clears the frame by `ui.stackGap`, quantised to hundredths,
rounded down: a zoom sets it straight in the frame's own turn, everything else springs through
`ui.relayoutDuration`. New tweaks: `ui.stackMinScale` 0.5 and `ui.stackGap` 24, both with sliders.

Verified in my round with a 1500x300 fixture: `annotator.room [0, 38, 1377, 872]` (1512 − 135),
frame `[65, 322, 1247, 251]`, `widthScale 0.84`, cards 158x101 at x 1337, 25 points clear. Zoomed,
the frame stopped at 1377, the width at 0.50, the cards at 1401, and the gap never went below 24.
Cancel brought all five cards back to `[1307, …, 188, 120]`.

**The swap the room agent could not drive** works: with the stack squeezed to 0.84 by the wide
image, a click on another card logged one batch —
`parked -> flyingOut(Screenshot smoke 3.png) effects=returnCard(wide-source.png) prepare(Screenshot smoke 3.png)`
— and the width was set once up front, so both flights were aimed at the same column. The new
image's frame ends at 1263, which leaves room, so the width went back to 1 and every card,
including the one flying home, landed on `x 1307, 188 wide`.

Not verified: a real pinch, a second display, a scrolled column while squeezed, and Instruments on
the per-frame relayout.

### A test run points at its own settings file
`todo4/room`, `fda8262`.

Any test that reaches `Settings.shared` bootstraps it, and a bootstrap fills in the keys the file
lacks. Without an override that file is the user's own — which is how `ui.stackGap` and
`ui.stackMinScale` were written into `~/.config/shotnote/settings.json` at 20:05 today.
`project.yml` now gives the scheme's test action `SHOTNOTE_SETTINGS=/tmp/shotnote-tests/settings.json`.

Verified on the merged branch: that file was deleted, `./scripts/build.sh --test` recreated it
(2154 bytes, 20:40) and `~/.config/shotnote/settings.json` kept the mtime it had before the run
(1789701474, 20:17:54). It has that mtime now.

---

## 2. Decisions made without you, and open questions

### Pete's answers

Three of the questions below are settled, and the branch carries the answers.

- **The strip's pencil is Annotate, not Copy Annotated.** `annotate` is a strip action with the
  pencil the strip already showed; `copy-annotated` is a shortcut, so it keeps Cmd+Shift+C and
  `shotnote://copy-annotated` and leaves the strip. The strip reads Copy, Annotate, Stitch, Delete.
  Annotate runs the queue exactly as Return does.
- **The annotator stays centred in the room**, so with the stack up it opens about 68 points left
  of where it did.
- **The test scheme keeps its own settings file** (`/tmp/shotnote-tests/settings.json`).

Everything else in this section is still open.

### The page
- **`SHOW_COLORS` is a source constant**, like the other editor knobs, so turning the palette back
  on needs a rebuild. Say if it should be a settings key.
- **The colour measure is CIELAB distance, not a WCAG contrast ratio.** Luminance cannot separate
  red on dark grey (2.44) from red on dark red (2.42); CIELAB can (93 against 36).
- **The score is the 10th percentile of the sample**, not the mean: a mean colour need not exist in
  the picture.
- **`markColors` is a second list in `ready`.** Hiding the palette emptied the host's colour list,
  which would have refused every coloured push, so swatches and mark colours are now separate.
- **Two or three pieces stack, more go in a grid**, because the long edge and the token budget bite
  at once and an aspect longer than about 2:1 wastes the budget. A stitch of three reaches a reader
  at 41–45% of its size: separate images are still better when the model has to read small text.

### The stack's look
- **The strip's labels sit over the cards' left edge** while the cursor is on the strip. That was
  your open question: the alternative is sliding the icons left, which breaks "the button under the
  cursor is the button you press".
- **Copy on a card keeps its 1.08 hover scale**, so it behaves like Delete beside it; the icon
  moves 1.0 pt. One argument turns it off.

### The stack's keys
- **Annotate is in the strip now** (answered above), so a run starts from the button or from
  Return. Both go through `Config.actions`, so the queue is the same.
- **A single card annotated from a selection of one now stays selected.** That falls out of one
  rule — the selection survives a run — rather than a special case.

### Zoom
- **The overlay is capped at 2048 px** (`Config.overlayMaxPixel`), so a 6× magnified mark on a 5K
  screenshot can be slightly soft while the gesture moves; it is exact again at rest.
- **`standInFadeSeconds` is 0.12**, in code with the other zoom springs, not in `ui`.
- **Nothing reports that the frame is at the limit of its room.** The seam is `growthLimit`.

### The room
- **The annotator is centred in the room, not on the screen**, so with the stack showing, every
  annotation opens about 68 points left of where it did — including small images that would clear
  the stack anyway. Answered: it stays as built.
- **`ui.stackGap` is 24 and the annotator's frame shadow has radius 24**, so the shadow reaches into
  the gap. The frames never touch.
- **Cmd+0 leaves the stack at the fit's width, not full width.** Full width would put the cards
  under the frame.

### Mine, as integrator
- **The selection strip now overlaps the annotator's frame when the stack is squeezed.** Two
  branches are each right on their own: `stack-keys` keeps the selection through an annotation, and
  `room` reserves room for the cards. `StackLayout.reservedWidth` counts the cards only, so with a
  selection out and a wide image open the strip sits over the frame's right edge — measured
  `strip [1294, 390, 35, 128]` against a frame ending at 1312, an 18 pt overlap, and a capture
  confirms it on screen. It is bounded (the strip grows right, away from the frame), and the fix is
  a design choice: count the strip in the reserved width, or hide the strip while the annotator has
  an image. I left it for you. The room agent's report says the two "cannot coincide today" —
  that was true of its branch alone, and is no longer true of the merge.
- **The queue's handover keeps the room.** `send` releases the stack's width when a batch returns a
  card, but a queue handover is not the end of a session, so the merged code makes room for the
  image the queue is about to open instead of giving the width back and taking it again in the same
  turn. Without that, the returning card would be aimed at a column the next image immediately
  narrows.
- **The ragged lines are reflowed.** Six lines this run left 124–194 characters wide in `AGENTS.md`
  and `README.md` are wrapped to the files' own width. Nothing else in those paragraphs changed.

---

## 3. How to take it

```
cd ~/Code/shotnote
git merge todo4/integration       # on foundation
./scripts/run.sh
```

`docs/TODOS.md` is untouched by every branch. The five worktrees under `~/Code/shotnote-todo` and
their `todo4/*` branches can go once you have merged.

Two things to know before the first run:

- The first launch after the merge fills in `ui.stackMinScale`, `ui.stackGap` and
  `ui.stitchLongSide` in your settings file, as any new tweak does. `ui.stackGap` and
  `ui.stackMinScale` are already in it at their defaults; a test run put them there this evening
  (section 4).
- `web/dist` must be rebuilt, which `run.sh` does. The protocol is 8 on both sides now, so a stale
  bundle is refused with `[web] error protocol-mismatch` rather than ignored.

---

## 4. Incidents

- **Your settings file was written at 20:05 today by a test run**, not by an app launch: it gained
  `ui.stackGap: 24` and `ui.stackMinScale: 0.5`, both valid keys at their defaults. The cause is
  `StateReportTests` building an `AnnotationController`, which reaches `Settings.shared`; the fix is
  in the merge (`fda8262`). Nothing else in the file changed, and the two keys are yours to keep or
  clear.
- **Every test run of mine was pinned away from that file.** Until the `room` merge carried the
  project.yml fix, I patched the generated (gitignored) scheme to point the test action at
  `integration-scratch/test-settings.json`, and checked after each run that the file appeared there
  and that `~/.config/shotnote/settings.json` kept its mtime. It did, at every one of the five runs.
- **A second round, 21:14 to 21:15**, drove the strip's new Annotate button on build
  `586081b-dirty` (pid 6796), the same way: three fixtures, two selected, the labels read from a
  crop, `[annotate] ok … 1 of 2` and `next … 2 of 2` from the button, `[copy-annotated] ok` from
  Cmd+Shift+C. Fixtures deleted, clipboard cleared, your build back (pid 8709), lock released.
- **My smoke round held the lock from 20:42 to 20:50** and drove only my own build
  (`5330015`, pid 94079) on `integration-scratch/settings.json`, watching
  `integration-scratch/shots`. Every action URL went through a guard that reads `[state]` and the
  running process's own environment (`ps -wwEp <pid> | grep SHOTNOTE_SETTINGS=…`); it never tripped.
- **Your build was killed once, to launch mine.** `open --env` is ignored when a build with that
  bundle id is already running, so the running instance has to go first. Your build (`83cae53`) is
  running again on your real settings and folder, pid 95231, and the lock is released.
- **The clipboard held a fixture PNG** (two Done presses copied the originals, and the stitch copied
  its output). It is an empty string now.
- **Drafts**: the pushed fixture made one (`[drafts] 16`); deleting the fixture and relaunching your
  build swept it (`[drafts] 15`, your own).
- **Fixtures**: six files, all in `integration-scratch/shots`, all deleted. Nothing was written to
  `~/Dropbox/Screenshots`.
- **Posted mouse moves are unreliable on this Mac**, as three agents reported. Two of my hover
  walks were dropped; every hover in section 1 is one a `[state]` line confirmed before the key or
  the click that followed.
- One drag drew nothing because tldraw returns to the select tool after a shape, which is why the
  live colour pick was proven on the red half only; the white half is proven through the push.

---

## 5. Merge notes

### Conflicts, and what each resolution keeps

- **`AGENTS.md`, the `[state]` stack line** (twice: `stack-keys`, then `room`). All three new keys
  are named: `queue`, `widthScale`, `stripHovered`.
- **`AGENTS.md`, the bullet after the panel rule** (`room`). Two bullets, not one: the strip's
  hover reveal, then the stack's narrowing.
- **`README.md`, the recent-stack list** (`stack-keys`, then `room`). The page's Cmd+S sentence
  (a grid, and why) stays and the focus bullet follows it; the strip's hover sentences stay on the
  strip's bullet and the narrowing bullet follows.
- **`Sources/ThumbnailController.swift`, `send(_:)`** (`room`). Both branches rewrote it. The merged
  order is: reduce, log, take the queue's next file, set the stack's width for the image that is
  opening, run the effects with the slot the leaving card is drawn in, then hand over to the queue.
  A handover suppresses the release of the room, because the annotator is not going away; the width
  is set for the file the queue opens next. This is the one place the merge chose behaviour that is
  in neither branch, and the swap and the queue were both driven afterwards.

### Files read by hand, and what was checked

- `Sources/Bridge.swift` and `web/src/bridge.ts` — protocol 8 on both sides, one step above
  `foundation`; `markColors` in `ready` (page) and `ViewRequest`/`ViewResult`/`overlay`/`setView`
  (zoom) all present; `Mark.Kind` still has `ellipse` on both sides.
- `web/src/App.tsx` — the whole file. The colour pick, the letter swallow and the text-edit guard
  (page) sit alongside `setView`, `applyView`, the resize observer and the overlay (zoom). The
  canvas queue still covers `load`, `reset`, `park`, `export`, `build` and `finish` — the review
  found `overlay` and `setView` outside it, which section 6 fixes.
- `Sources/AnnotationController.swift` — the whole file. Page's two changes (`colorIDs` from
  `markColors`, the `ready` line) survive zoom's rewrite; the stand-in, the hand-over guard, the
  overlay throttle and `fitBeforeHide` are intact; `room` is stored and `growthLimit` returns it.
- `Sources/ThumbnailController.swift` — the whole file. `stripHovered` (stack-look), the focus rule,
  the queue and `remove`'s pruning (stack-keys), and `widthScale`, `makeRoom`, `annotatorRoom` and
  `perform(_:leaving:)` (room) coexist. `cardSizes` is the drawn sizes, so the strip's placement
  follows the narrowed column. `prepare` no longer clears the selection.
- `Sources/StackView.swift` and `Sources/StackLayout.swift` — the reveal (stack-look) and the width
  scale (room) touch different quantities; every `StackLayout.current` in the view became the
  width-scaled layout, and the card's own `size` is the rest size, scaled at draw time.
- `Sources/Settings.swift` and `Sources/DebugPanel.swift` — three new tweaks
  (`stackMinScale`, `stackGap`, `stitchLongSide`), each with bounds and a slider.
- `Sources/AppDelegate.swift` — `annotate` opens the first and queues the rest (stack-keys), the
  stitch line reports size, columns and `readerScale` (page), and `onAnnotatorPrepare` carries the
  room with `onFrame` wired back to the stack (room).
- `Sources/Config.swift`, `Tests/BridgeTests.swift`, `project.yml` — the annotate doc comment
  (stack-keys) beside `overlayMaxPixel` (zoom); `markColors` and `setView` cases in the tests; the
  scheme's test environment.
- `AGENTS.md` and `README.md` — read end to end after the last merge. No rule is stated twice, and
  the sentences each branch rewrote are consistent with each other: the reopen bullet no longer
  mentions a colour press, the `annotate` entry under "Adding things" says the queue, the zoom
  bullet says the window grows to fill its room, and the `[state]` lines name every new key.

### What the reports disagreed about

- The `room` report says `prepare` clears the selection, "so the two cannot coincide today". With
  `stack-keys` merged it does not, and the strip is out while the stack is squeezed. Section 2 has
  the measurement.
- The `page` and `zoom` reports both claim protocol 8. They now share it.

---

## 6. Review

An adversarial review of `todo4/integration` ran after the merges, reading the tip at `586081b`
with F1 and F2 re-checked at `eff26c3`. It ranked eleven findings, F1 to F11. Nine were real and
are fixed; F8 turns out not to be reachable and is left alone; the doubled draft save it could not
confirm does not happen, and is measured below. `./scripts/build.sh --test` passes at the tip:
168 tests, one fewer than before because two assertions that recomputed a formula became one test
that pins the doc's table.

Fixes are in three commits:

- `a759066` — the selection strip stands aside while the annotator has an image (F1).
- `15174bb` — the page and the zoom (F2, F4, F5, F7, F9, F10).
- `44663e2` — the stitch, the settings hazard and the tests (F3, F6, F11).

### What was found and fixed

**The selection strip sat inside the annotator's frame.** The strip hangs to the left of the
column, and `widthScale(clearing:)` clears the column alone, so the strip overlapped the annotator
by `(buttonSize + 2·buttonSpacing) + selectionStripGap − stackGap` — 19 pt at every width scale,
not only when the stack was squeezed. The panel is `.statusBar` and the annotator `.floating`, so
the strip drew over the image and caught the click. Reserving the width does not fix it: the search
places the column at every intermediate frame, and the room is frozen at `prepare`. The strip is
hidden instead, for as long as the annotator holds an image. One new published flag,
`StackModel.annotating`, set in `ThumbnailController.send` — the one place the session changes —
and read by the two places that ask where the strip goes (`stripFrame` and `StackView`), never by
`showsStrip`, which sizes the panel window and would resize it mid-session. `[state] stack.strip`
is null while a card is in the annotator.

**`setView` was the one page call outside the canvas queue.** The camera is part of a tldraw
snapshot, so `export` and `build` put it back as it was when they started. An export running while
a zoom came to rest would take the new camera away behind a stand-in that had already faded: the
page left at the wrong magnification until the window next changed size. `setView` now takes its
turn like every other canvas call. `overlay` was already in the queue and missing from the AGENTS
sentence; both are named there now, with the reason.

**A mark took its colour from pixels it never covers.** The pick sampled a grid over the mark's
bounding box. A diagonal arrow's box is the whole rectangle its two ends span, most of which the
stroke never touches, so a red banner in a corner of that box turned an arrow that runs nowhere
near it yellow. `Area` in `contrast.ts` now says what the ink covers: a strip along the line for an
arrow (41 points, one to either side), the border band for a shape drawn with no fill, the whole
box for anything else. `docs/annotation-colour-2026-09-17.md` has the rule.

**A build failed outright when the screenshot would not decode.** `build` awaited `prepareSample`
inside its `try`, and `img.decode()` rejects on a load failure, so `add?file=…&marks=…` with an
unreadable image lost the agent's marks entirely. Both calls catch now: the marks keep the colour
they were given and the draft is stored. Losing an agent's marks over a colour is not a trade.

**`setColor` wrote its guard inside undo history.** The `colorChosen` meta mark was the only
colour-related write not wrapped in `silently()`. One Cmd+Z reverted it, `noteChanged` put the
shape back in `unpicked`, and 300 ms later the heuristic overwrote the user's own colour. Latent
while `SHOW_COLORS` is off; fixed anyway, since the palette is one constant away.

**The hand-over had no deadline, and its answer was read out of a raw dictionary.** The page
answers `setView` from a `requestAnimationFrame`, which WebKit stops while the screen is locked, so
a hand-over could never settle and the stand-in would cover a live editor. It now has an export's
deadline and one retry, and then comes down anyway: a picture that never leaves is worse than a
page at the wrong camera, which the next rest corrects. `ViewResult` has a Swift mirror, so the
page's painted size is checked against the host's frame and a gap wider than the layout's own
rounding is logged as `[annotate] view mismatch`. The page checks the five numbers it is sent
before they reach the camera and answers null if they are not finite or the ratio is under 1.

**`[stitch] ok readerScale=` reported a number nobody sees.** It was the reader's resize of the
capped picture, not what a reader leaves of the screenshots: a six-piece 5K stitch printed 0.38 and
arrives at 0.29, because `ui.stitchLongSide` had already taken a quarter of it. The line now
reports the cap and the resize together, which is the number the layout is chosen against and the
number the doc's headline claim is about. The doc's verified block carried the old one.

**The stitch badge could leave its piece.** A badge is inset by a quarter of itself, so it needs
1.25 times its diameter to sit in; the 32 px floor pushed it off any piece under 40 px, and under
28 px it reached the neighbouring screenshot through the gap. It is capped at 80% of its piece's
short side, which is exactly what `docs/stitch-2026-09-17.md` already claimed as an invariant.

**The ok line counted files, not pieces.** `Stitch.compose` drops a file that will not decode; the
line and the toast said how many were asked for. Both count what is in the picture now.

**`ui.stitchLongSide` is refused below 512**, the slider's own floor. Under it a stitch is not a
smaller picture but a useless one: the review's own example is four wide captures at 64, which
compose to a 64 x 1 PNG the app still calls ok.

**No test process can reach the user's settings file.** `project.yml`'s scheme covers
`xcodebuild -scheme Shotnote test` and Xcode's Product ▸ Test, but not `xcrun xctest`, a
hand-written `.xctestrun`, or CI running the bundle, and any of those reading `Settings.shared`
would bootstrap whatever path `Settings.fileURL` returns — the user's own. It now refuses that path
whenever `XCTestConfigurationFilePath` is in the environment and uses a per-process file under
`NSTemporaryDirectory()`, which also keeps parallel worktree runs apart. The scheme entry stays.

**Two tests asserted the implementation.** `gap == 22` and `badgeDiameter == 65` were the formula
recomputed, and `testNoOtherColumnCountSurvivesTheResizeBetter` followed from the search loop by
induction. In their place one test pins the table in `docs/stitch-2026-09-17.md` — column count,
composed size and reader scale for two through six browser windows — and the badge test asserts the
invariant that a badge fits its piece. The floor assertions stay. `StackLayoutTests` no longer says
the annotator centres on the screen, which it has not done since the room landed.

**F8 is not reachable, and nothing changed for it.** The annotator's room is a snapshot taken at
`prepare` and never widened, so a `shotnote://dismiss` that took the stack away while the annotator
was open would leave the room narrowed around a stack that has gone. It cannot happen: every phase
answers `dismiss` with `parking(… then dismiss)`, whose effect is `hideAnnotator`. Driven below.

### How the fixes were checked

`./scripts/build.sh --test` passed before each commit and at the tip, and the user's settings file
kept the same mtime (1789701474) across every run. One launch round, 21:49 to 21:59, on my scratch
settings, guarded by `[state] app.settingsFile` and the running pid's own environment:

- **The strip stands aside.** Two cards selected by clicking their circles, strip at
  `[1264, 704, 35, 128]` showing Copy, Annotate, Stitch, Delete
  (`integration-scratch/captures/rev2-strip-before.png`). A click on its pencil gave
  `[annotate] ok Screenshot fix 3.png 1 of 2`; `[state]` then read `strip: null` with
  `selected` still both files and `panel` still the widened `[1245, 494, 269, 418]`. A capture of
  the strip's own place (`rev2-strip-during.png`) is empty. After Done on both images the strip is
  back at `[1264, 569, 35, 128]` with the same two cards selected (`rev2-strip-after.png`). The
  annotator's frame was `[134, 103, 1109, 689]`, whose right edge is 1243 against the panel's 1245:
  no overlap left even in the frame the review measured.
- **F8, driven.** `shotnote://dismiss` with `Screenshot halves.png` in the annotator gave
  `[transition] dismiss -> parking(…) effects=park(…)`, `[draft] parked`, and
  `[transition] parked -> idle effects=hideAnnotator`. The annotator went with the stack, so the
  frozen room is never read with the stack gone. Nothing changed.
- **The arrow's colour.** A fixture 1200x800, white with a red block over its top-right quarter.
  An arrow drawn from (100, 100) to (1100, 700) — its box covers a fifth of that red block, its
  line never goes near it — came out `["arrow","red"]`. `window.contrast.explain` on the same
  arrow, both ways: along the line, 123 points, red at distance 93.2, so red is kept; over the box,
  400 points, red at distance 0, so yellow would win. That is the defect and the fix in one call.
- **The doubled draft save, measured.** Drawing a rectangle over the red half of the halves fixture
  gave exactly two `[draft] saved` lines, 312 ms apart: the draw, then the colour change 300 ms
  later, which the eval confirms happened (`["geo","yellow","none"]`, drawn red). The arrow, whose
  colour the heuristic kept, gave exactly one. One save per change, not two per change — the
  review's unconfirmed doubling does not reproduce, and `quiet` is left as it is.
- **Copy Annotated while the annotator holds the canvas.** `shotnote://copy-annotated` answered
  `ok Screenshot corner-annotated.png; 1 with annotations` in 30 ms with the annotator open and a
  live draft, as it did before. Three keyboard zoom steps each handed over cleanly
  (`[annotate] view 21ms/29ms/30ms ratio=… waited=0`), with no timeout, no refusal and no mismatch,
  and `[state] annotator.standIn` false at rest. An export fired a frame before a zoom step left
  `page.zoom` and `annotator.canvasZoom` equal to sixteen digits (1.9290469108371562).
- **The stitch numbers.** Six fixtures at the documented sizes: `from 2 images, 1792x1928
  columns=1 readerScale=0.59`, `from 3 images, 1792x3344 columns=1 readerScale=0.45`, and
  `from 6 images, 4096x1906 columns=3 readerScale=0.29` — the third was 0.38 before the fix, and
  the first two are unchanged because nothing capped them. The same six with a file that is not an
  image among them reported `from 2 images`.
- **The settings guard.** The tests were run once with the scheme's `SHOTNOTE_SETTINGS` disabled:
  the settings file appeared at `…/T/shotnote-test-25420/settings.json` and the user's file kept its
  mtime. The temporary check that proved it was removed and the scheme restored.

### What is left, and what is not proven

- The F2 race itself was never staged. The export in the round finished in 30 ms, far too fast to
  still be running when a zoom settled; what is proven is the ordering and that the camera survives
  an export. The fix is structural — the call is in the queue — rather than measured under the race.
- `[annotate] view timeout` has not been seen. Locking the screen mid-zoom was not driven, so the
  retry and the give-up path are read, not run.
- The badge cap is arithmetic and a unit test; no stitch was composed from pieces small enough to
  trigger it.
- The colour rule was driven for an arrow and for an unfilled rectangle. Text, and a filled shape,
  keep the old whole-box path and were not re-driven.
- `ViewResult`'s mismatch line has never fired, which is the point; it is a report, not a fix.
- Two pieces of the review's own "checked and found sound" list stay open, unchanged by this round:
  `Stitch.compose` still holds every piece decoded at once with no cap, and a card whose file will
  not decode still leaves the column when the stitch converges even though it is not in the picture.

### The behaviour change to decide

Hiding the strip costs the only in-session route to Stitch and Annotate. Keys are released while an
annotation is open, so with the strip gone there is nothing to press: mid-annotation, a second
image can be reached only by finishing first. The queue covers the common case — Annotate on a
selection runs them one after another — but stitching the selection you are looking at now waits
for Done. The alternative is to let the strip show and to move the annotator instead, which means
the room would have to depend on the selection and the frame would move under the image while it is
being drawn on. Say which you want.

### Incidents in the review round

macOS asked for Accessibility for my build while the round was running — a system prompt over the
cards, which I left alone; it went when my build quit, and neither button was pressed, since that
row is keyed by bundle id and is your build's row too. The clipboard held a stitch of six fixtures
at the end of the round and I cleared it (`pbcopy < /dev/null`), so it is empty rather than holding
anything of yours. Two drafts were made and both were swept when their fixtures went: your build
came back up on `[drafts] 15`, the same count it had before. `integration-scratch/shots` is empty
again, your build is running from `~/.config/shotnote/settings.json` on
`~/Dropbox/Screenshots`, and the launch lock is released.
