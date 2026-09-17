# Run 2026-09-17, daytime: four branches merged into `todo2/integration`

Four agents worked in parallel this morning. Everything they built is merged, builds, passes the
tests, and was driven in one combined build. Nothing is left half-merged.

The branch to take is `todo2/integration`. Section 3 says how.

Merge commits, in order:

| commit | branch |
| --- | --- |
| `0637fa9` | `todo2/page` |
| `c6ce843` | `todo2/zoom` |
| `b8ea131` | `todo2/select` |
| `97ce520` | `todo2/transitions` |
| `3872717` | AGENTS.md lines for the transitions work (mine, not a merge) |

Git auto-merged all four. No file came out wrong, but five files needed reading by hand because
more than one branch changed them; section 4 says what I checked. `./scripts/build.sh --test`
passed after every merge and at the final commit. 146 test methods.

---

## 1. What landed

### Reopening an annotated image starts on the selection tool
`todo2/page`, `f760406`.

A card with annotations reopens on the selection tool, with nothing selected. A fresh image still
opens on the circle tool. The stored draft's own selection is cleared as it loads, so pressing a
colour changes the next shape instead of repainting the last one.

Verified: a fresh open reported `tool: ellipse`. After one ellipse and `cancel`
(`[draft] parked Screenshot test 8.png`), the reopen reported `tool: select`, `selected: 0`,
`shapes: 2` (the screenshot plus the ellipse), `canUndo: false`.

Not verified: nothing. This one is fully exercised.

One correction to the smoke-test script I was given: it expected `select` after opening an image,
drawing nothing, and reopening. That is not what the code does, and the code is right. With no
draft there is nothing to pick up, so the image opens on the circle tool. I saw `ellipse` there,
as designed.

### Every call that touches the canvas runs in the order the host made it
`todo2/page`, `16a7581`.

`load` and `reset` joined the queue that `park`, `export` and `build` were already in. Before this,
an image loading while a rendering was in flight could wipe that rendering's shapes.

Verified by the agent live and by a new test, `testAnImageLoadedDuringABuildStaysOnTheCanvas` in
`RenderTests.swift`, which fails if the load is taken back out of the queue. In my combined build
a marked push and an annotate ran back to back with no interference.

Not verified: `finish()` (Done) is still outside the queue. It only reads the canvas, so nothing
went wrong, but it is the last call standing outside the rule.

### A draft whose preview was cleared gets one back at launch
`todo2/page`, `a3d9562`.

`~/Library/Caches` is the system's to clear. When it does, the card used to lose its annotated
thumbnail until you opened it. Now the page renders the missing previews once it reports `ready`
and nothing else owns its canvas.

Verified: parked a draft, quit, deleted exactly that draft's preview PNG
(`d76a5c47…`, 1200x1120, the parked image), relaunched. One line,
`11:44:26.651 [draft] preview Screenshot test 8.png`, and the PNG was back.

Not verified: a *failing* regeneration, and many missing previews at once. Ten would be ten
sequential renderings right after launch, and a Copy Annotated in that window would be refused.

### Zoom holds the point under the cursor
`todo2/zoom`, `bc847d7`.

Cmd+wheel, a pinch, and a two-finger double tap now keep the point under the cursor in place,
through the window's growth and the page's magnification. Keyboard steps still hold the middle,
and cmd+0 fits. New `Sources/Zoom.swift` holds the geometry.

Verified in the combined build: the annotator opened fitted at `[386,103,740,689]` with anchor
`[0.5, 0.5]`. Two cmd+wheel steps at (0.2, 0.2) of the window gave frame `[346,38,938,872]` and
anchor `[0.200, 0.202]` — the point asked for, not the middle. Cmd+0 put the frame back to exactly
`[386,103,740,689]`. `[web] ready protocol=7` on both sides.

Not verified: the pinch and the two-finger double tap. Neither can be synthesised, and you were
using the Mac. Both funnel into the same call the wheel uses.

### The selection is an ordered list
`todo2/select`, `1d5bce6`.

Circle numbers, the order actions receive cards, and the stitch badges are now one thing: the order
you picked the cards. Cmd+A has nobody's order to follow, so it takes the column's, oldest first.
`annotate` on a multi-card selection opens the last of the list and says so.

Verified: clicked three circles in a non-column order. `[state]` came back
`["Screenshot test 5.png", "Screenshot test 7.png", "Screenshot test 3.png"]` — click order.
Crops of the three circles read **1**, **2**, **3** in that order. Clicking Stitch in the strip gave
`[stitch] ok … from 3 images, 2708796 bytes, copied` and `[stack] stitched cards=3`; crops of the
finished image's three badges read **1**, **2**, **3** top to bottom, and the piece widths run
960, 880, 820 points, which is those three fixtures in that order.

Not verified: nothing new. The keyboard paths (Shift+arrow, Cmd+A) were verified on the branch,
not re-run here.

### A drag-select scrolls the column at its edges
`todo2/select`, `25b2977`.

Drag from a circle into the band at the top or bottom of the column and it scrolls on its own,
faster the closer to the edge, selecting what comes past. It stops at the ends, when the drag
leaves the band, and when you let go.

Verified: dragged from the newest card's circle to 10 points inside the top band and held two
seconds. `stack.scroll` went 0 -> 251 -> 540 -> 834 -> 1003 and the selection grew from 5 to 12, in
travel order. Cards that were 1000 points above the viewport ended up selected.

### A spring step lands where the spring is, however late the tick
`todo2/transitions`, `5379877`.

This is the fix for the blurred band that swept across the screen left of the stack. The cause was
not the backdrop. `Tween` integrated a stiff spring by hand, so one late tick threw the value
hundreds of points past its target and it visibly swept back. It is now the closed form of a
critically damped spring, so a late tick lands where the spring really is and a stalled main
thread simply finds it settled.

Verified in the combined build: three trials of a summon carrying a four-image stitch in the same
`open`, each with fourteen captures of a band across the full screen width. Every frame-to-frame
change sat at x >= 1324. The strip rests at x >= 1282. Zero changed columns left of x = 1270 in
trials 2 and 3. Trial 1 had one change further left; I looked at those frames and it was a
scrollbar appearing in your Slack sidebar, not a band.

This one reaches further than its item: every AppKit tween in the app used that integrator.

### A flight carries its own shadow
`todo2/transitions`, `bb9fedc`.

A card flying to or from the annotator now animates its corner and shadow along the path instead
of swapping them at the end, and the flight's shadow is dropped in the same run-loop turn the card
appears. That fixes both the shadow popping in after a fly-back and the annotator frame being
shadowed twice while the flight sits over it.

Verified on the branch photometrically, before and after. I did not re-measure it here; what I saw
in the combined build is that flights and card landings looked right and nothing regressed.

Not verified, on the branch or here: the doubled-shadow flicker as a visible frame at natural
speed. The mechanism, the code and the measurement agree, but the flicker as you see it is
inferred.

### A card landing under the cursor takes its hover state with it
`todo2/transitions`, `be17bd6`.

A single `showsHover` now drives the scale, z-order and buttons, and the dim fades in with them
instead of appearing at full strength. Before, a card landing under a waiting mouse flashed dark
for one frame.

Verified here indirectly: I parked the cursor on a card and captured it, and the dim, the Draw
hint, the Copy and trash buttons and the selection circle all rendered correctly together. The
one-frame flash measurement is the branch's.

### Dismissing the stack ends a stitch in flight, with a toast
`todo2/transitions`, `d85000f`.

Before, the pieces kept flying over whatever app came forward, and the stitch finished in silence.
Now `dismiss()` ends every flight and the stitch says what it did.

Verified: with the stack up, a two-file `stitch` followed 200 ms later by `dismiss`.
`[stitch] ok … from 2 images`, `[stack] stitched cards=2`, `[dismiss] ok`, and then `[state]`
read `visible: true, isStack: false, forming: 0 cards, feedback: "Stitched 2 images, copied"`.
A capture shows the toast.

### A pushed image with marks
Already on `foundation`, re-checked here because three branches touch that path.

`add?file=…&marks=…` still works end to end in the combined build:
`[draft] built push.png`, `[add] ok push.png agent=integrator2 marks=1`, and the card came up with
`draft: true`, `agent: integrator2`, the purple badge, and the red ellipse visible in its thumbnail.

---

## 2. Decisions made without you, and open questions

### Reopening on the selection tool
- The load also clears the draft's stored selection. A tldraw snapshot carries `selectedShapeIds`,
  so a parked draft restored its handles. On `select` that shows, and a colour press would have
  repainted the last shape instead of setting the next one.
- The colour is untouched. Every load resets it to red, fresh or reopened.

### The page's queue
- Only the canvas change waits in the queue. `loaded` still comes two frames later, outside it.
  Waiting inside would deadlock whenever WebKit pauses frames (hidden window, locked screen).
- `reset` was queued too, so the rule is simply "every call that touches the canvas runs in order".
- That made two guards in `build` dead code; they were removed.
- **Open:** `finish()` (Done) is the one call still outside the rule. It would be a one-line change.
- **Open:** `load` now returns before the image is on the canvas, so a `[state]` taken between an
  `annotate` and its `loaded` line reports the previous canvas. Nothing in the app depends on it;
  an agent scripting the page might.

### Regenerating previews
- The trigger is the page's `ready`, not a timer. It fires after a web process restart too, where
  there is normally nothing to do.
- It runs only when nothing else owns the canvas, one key at a time, and a refusal leaves the rest
  for the next launch.
- **Open:** if the watch folder changes with `debug` off, old drafts point outside it and each will
  log one `preview-failed` line at launch.

### Zoom
- The anchor is a fraction of the **window**, not of the image. During growth they are the same;
  once magnified the window fraction is what both sides can read in their own space.
- The anchor is read back off the frame on screen at every step, so a frame the screen edge nudged
  does not accumulate error.
- A step aimed somewhere else mid-spring blends to the new anchor instead of stepping sideways.
- Zoom's springs now go through the motion scale. They were hardcoded and ignored Reduce Motion.
  They were **not** moved into `UITweaks`, so no new settings key is written into your file.
- **Open:** at the screen edge the anchor has to give way and the content slides under the cursor.
  The alternative is to stop the window growing early and leave it smaller than the screen. The
  screen-filling window was chosen.
- **Open:** smart zoom goes to twice the fitted size. Preview picks a level from the content.
- **Open:** the toolbar stays where `prepare` put it, so an off-centre grown window is no longer
  centred over it. Left alone deliberately.

### Ordered selection
- Cmd+A takes the column's order, oldest first, because nobody picked one.
- Shift+arrow follows the direction of travel. Turning back drops the card it added last.
- Toggling a card off and on puts it last, and removing one closes the gap, so numbers are always
  1..n with no holes.
- `annotate` opens the **last** of the list, not the newest by age, and its `ok` line says "the
  last of N". With the list no longer sorted by age, "newest" no longer meant anything.
- **Open:** is "the last of them" the right card for `annotate` on a multi-card selection, or would
  you rather it stayed the newest by age?

### Drag-select auto-scroll
- 44 pt band and 600 pt/s were chosen by reasoning, not tuned by eye. Sliders are under Hover
  buttons in the tweak panel. **Open:** worth a look.
- The auto-scroll is **not** scaled by `ui.motion`: it is the user's own hand driving it.
- A sweep now ends when a card arrives or leaves mid-drag, because that moves the anchor onto a
  different card. **Open:** re-anchoring on the same card by id is the alternative, and more work.
- `scripts/input.sh drag` gained an optional hold, and posts nothing while holding.

### Transitions
- **Open:** `Look.annotator` hard-codes `0.45 / 24 / y10` to match what the annotator already drew.
  Those three numbers now live in one place but still not in `UITweaks`. Moving them there would
  make the annotator's shadow tweakable like the card's; it changes the settings schema.

### Mine, as integrator
- I added three short passages to `AGENTS.md` (`3872717`) for behavior the transitions branch
  changed but did not document: the closed-form spring and why not to step it by hand, the flight's
  `Look`, and the dismissed stitch's toast. AGENTS.md is a contract and those lines were missing.
  No wording of anyone else's was changed.
- I rewrapped three lines in `AGENTS.md` where the page and zoom paragraphs met mid-sentence. No
  words changed. That is inside the zoom merge commit.
- Nothing else was edited beyond the merges.

---

## 3. How to take it

From your own checkout, on `foundation`:

```
git merge todo2/integration
./scripts/run.sh
```

`docs/TODOS.md` is uncommitted in your checkout and no branch touches it, so the merge will not
disturb it.

Then, when you are happy with it:

```
git worktree remove /Users/petepetrash/Code/shotnote-todo/page
git worktree remove /Users/petepetrash/Code/shotnote-todo/zoom
git worktree remove /Users/petepetrash/Code/shotnote-todo/select
git worktree remove /Users/petepetrash/Code/shotnote-todo/transitions
git worktree remove /Users/petepetrash/Code/shotnote-todo/integration2
git branch -d todo2/page todo2/zoom todo2/select todo2/transitions todo2/integration
```

The scratch folders under `shotnote-todo/*-scratch` hold each agent's fixtures, captures and
scripts. They are outside the repository and can go whenever you like.

---

## 4. Incidents, and what I checked by hand

**The merges were clean, but five files needed reading.** Git auto-merged everything. These are the
overlaps I checked rather than trusted:

- `Sources/AnnotationController.swift` carries page's `onPageReady` and `canvasRefusal`, zoom's
  `zoom(by:at:animated:)`, `applyZoom` and `setCanvasZoom(_:at:)`, and transitions' frame shadow
  read from `Look.annotator`. All three are present and none overwrote another.
- `web/src/App.tsx`: zoom's `setCanvasZoom` and its resize handler move the camera. That is a
  store write — `setCamera` records a camera, and a snapshot carries session state — so the reason
  they are safe is not that they leave the store alone. It is that no rendering reads the camera:
  `render()` exports from explicit shape bounds, and `fitCamera` sets the camera again on every
  load. Zoom therefore correctly stays **outside** the page's one-at-a-time queue. Putting it in
  would make a zoom wait behind a fifteen-second export and protect nothing.
- `Sources/ThumbnailController.swift` carries select's ordered selection, display link and
  `endSweep`, and transitions' `dismiss()` ending flights plus the converge completion's toast.
  Select never put an `endSweep()` in `dismiss()`, so nothing was lost there: the auto-scroll's own
  tick stops as soon as the stack is not visible.
- `Sources/StackView.swift` carries select's numbered circle and transitions' `showsHover` and dim
  overlay together.
- `AGENTS.md` and `README.md` keep every branch's wording for its own behavior.

Only zoom changed the bridge, so the protocol is 7, one bump, on both sides.

**Your build was replaced for eleven minutes** (11:34 to 11:45) and is back on
`~/.config/shotnote/settings.json`, watching `~/Dropbox/Screenshots`. One launch round covered the
whole smoke test.

**Your clipboard held three screenshots of your own screen** for a few minutes: stitching in the
smoke test copies its result. I put an empty string on it at the end, so the images are gone.

**The stack was dismissed twice mid-test by activity that was not mine** — no `[dismiss]` command in
the log at those moments. I treated it as yours and re-ran. The drag-select test looked like a
failure twice for that reason and passed cleanly on the third run.

**Nothing of mine is left behind.** Fixtures were only ever in
`shotnote-todo/integration2-scratch/shots`, and that folder is now empty. My two drafts were
forgotten when their files went (`[draft] forgot push.png`,
`[draft] forgot Screenshot test 8.png`), and the store is back to the same 12 keys it had before I
started. Nothing was written to `~/Dropbox/Screenshots` or `~/.config/shotnote/`.

**One pre-existing oddity, not from this run:** `~/Library/Caches/com.petepetrash.shotnote/drafts/`
holds one orphan PNG from 2026-09-15 (`e357b1b9…`) whose draft no longer exists. Nothing reads it.
Deleting it is safe.

**Closing state:** no agent instance is running, your build is running on your real settings, and
the launch lock is released.

---

## Review

An adversarial review of `todo2/integration` ran after the merges. It found six real defects. All
six are fixed, plus the two it offered as optional. `./scripts/build.sh --test` passes at the
branch tip.

Fixes are in two commits:

- `f8c00b4` — the six confirmed findings.
- `f3de5ba` — Done joins the page's queue.

### What was found and fixed

**A stitch left a live drag-select pointing at cards that had gone.** `stitched` removed the pieces
from the column and inserted the new card without ending the sweep, so the sweep's anchor named an
index that no longer existed. The auto-scroll's display link calls `select()` every frame while the
drag sits in a band, so the next tick read `model.cards[anchor]` past the end: a crash, or a
selection from the wrong card. `stitched` now calls `endSweep()` next to `clearSelection()`, the
same as `remove`, `present` and `insert`. This was the one missing site: I read every path that
changes `model.cards`, and the rest either keep the count and order (`applyTweaks`, `replaceImage`)
or already end the sweep, and the ones that clear the column do it with `isStack` false, where a
sweep cannot run.

**The refusal for a borrowed canvas named the wrong caller.** `canvasRefusal` said "Copy Annotated
is still rendering" whenever an export was in flight. Since a launch now regenerates missing
previews through the same export, an `add?…&marks=` in the first seconds after such a launch was
refused with a message that was not true. It says "the page is rendering", which is true of either.

**Cmd+0 left the zoom anchor where the cursor last put it.** `[state] annotator.zoomAnchor` kept
reading, say, `[0.206, 0.209]` on a window that was back at its fitted frame. The fit now aims the
anchor home. Not as a hard reset: it blends from the anchor the window has to the middle, because a
hard reset would step the frame sideways on the next tick by the width the old anchor was holding —
the bug `ZoomAim` exists to prevent. The endpoint is the same either way, since at scale 1 the frame
is the fitted one whatever the anchor.

**A re-aimed flight lost its shadow in mid-air.** The stitch converge dropped the new card's flight
shadow unconditionally, while the sibling `end(id:)` two lines later was guarded by the flight's
generation. With Annotate New Captures on, the watcher reports the stitched file and the flight is
re-aimed at the annotator inside that window, so it kept flying with no shadow and never got one
back. `dropShadow` is now guarded the same way.

**The hover dim painted over a card's ring.** The dim became a sibling overlay so it fades in when a
card lands under a waiting mouse, but it was applied after the ring stroke, so a focused card's 2 pt
white ring went under it. The ring moved out of the image chain to a sibling overlay applied after
the dim. It keeps its own guard, so an empty slot still draws nothing.

**The page could log the server token.** `load failed:` logged `err.stack`, and a WebKit stack names
the served bundle URL, which begins with the per-launch token. It logs `err.message` now. The same
concern reaches the page's error text, which `[draft] error preview-failed` and
`[copy-annotated] error` both echo, so `exportDrafts` now takes every error through a new
`LocalServer.redacted(_ text:)` that replaces its own token. That was the review's optional item 8.

**Done joined the queue** (the review's optional item 7). It was the last call that renders after an
`await` outside the page's one-at-a-time queue. The wrapper went on the function rather than on one
caller, because Return inside the page calls it directly and would otherwise have stayed outside.
`AGENTS.md` now names `finish` in that list.

### How the fixes were checked

`./scripts/build.sh --test` passed before each commit and at the tip. One launch round, 12:21 to
12:24, on my scratch settings:

- **Done through the queue:** Return in the annotator gave `[annotate] done Screenshot test
  5-annotated.png 210543 bytes, copied`, `[transition] finish -> parking(…) effects=park(…)`,
  `[draft] parked`, `[transition] parked -> idle effects=returnCard(…) markCopied(…)` — the same
  sequence as before, with the park now running behind the rendering in the queue.
- **Cmd+0:** three cmd+wheel steps at (0.15, 0.80) gave anchor `[0.151, 0.665]` (y gave way at the
  screen edge, as documented) and frame `[16,38,1496,872]`. Cmd+0 gave anchor exactly `[0.5, 0.5]`
  and frame exactly the fitted `[165,103,1182,689]`.
- **The ring over the dim:** a focused, hovered card outside selection mode. The capture shows the
  Draw hint, Copy and trash over a dimmed card, with the white ring unbroken all the way round.
- **The stitch repro:** ten cards, a drag-select held in the top band with the auto-scroll running
  (scroll 303, eight cards selected), then a two-file `stitch` fired from under it. The column went
  to nine cards, the sweep ended, the selection cleared, and the app answered `[state]` throughout
  on the same pid. No crash. On the fixed build this proves only that the fix holds; the reviewer
  found the defect by reading.

### What is left, and what is not proven

- The smoke round in this report ran a binary stamped `b8ea131-dirty`, because the build preceded
  the merge commit. The code was identical to the commit — the merge was in the working tree — but
  the stamp did not say so. The reviewer rebuilt at `40a853e` and re-ran it: 146 tests,
  `[app] ready build=40a853e`, `[web] ready protocol=7`, and reopen, zoom, the `annotate` wording
  and the silent preview regeneration all re-verified there.
- The transitions A.3 fix, the annotator frame's doubled shadow, is inferred. It was measured
  photometrically before and after under a 1.6 s artificial stall, never caught as a visible frame
  at natural speed.
- `MotionTests`' spring-step test starts from rest only. A step retargeted while the spring still
  has velocity is covered by reading the closed form, not by a test.
- The corrected `scroll` comment in `scripts/input.swift` describes this Mac, where "natural
  scrolling" is on. With that preference off the sign is the other way round.
- Unverified: zoom on the Studio Display, and the screen-edge give-way on a second display. The
  display link's lifetime over many repeated drags was not measured with `[state] memory`.
- The pinch and the two-finger double tap are still unverified, for the reason in section 1.

### Incidents in the review round

Stitching in the repro copied its result, so your clipboard holds a stitched image of two
screenshots of your own screen; Done in the queue check copied its annotated PNG before that. I left
the clipboard alone afterwards. Fixtures were only in `integration2-scratch/shots`, which is empty
again, and my one draft was dropped when its file went (`[draft] forgot Screenshot test 5.png`).
Your build is back on `~/.config/shotnote/settings.json` and the lock is released.
