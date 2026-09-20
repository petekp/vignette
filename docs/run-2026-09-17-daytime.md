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
git worktree remove /Users/petepetrash/Code/vignette-todo/page
git worktree remove /Users/petepetrash/Code/vignette-todo/zoom
git worktree remove /Users/petepetrash/Code/vignette-todo/select
git worktree remove /Users/petepetrash/Code/vignette-todo/transitions
git worktree remove /Users/petepetrash/Code/vignette-todo/integration2
git branch -d todo2/page todo2/zoom todo2/select todo2/transitions todo2/integration
```

The scratch folders under `vignette-todo/*-scratch` hold each agent's fixtures, captures and
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
`~/.config/vignette/settings.json`, watching `~/Dropbox/Screenshots`. One launch round covered the
whole smoke test.

**Your clipboard held three screenshots of your own screen** for a few minutes: stitching in the
smoke test copies its result. I put an empty string on it at the end, so the images are gone.

**The stack was dismissed twice mid-test by activity that was not mine** — no `[dismiss]` command in
the log at those moments. I treated it as yours and re-ran. The drag-select test looked like a
failure twice for that reason and passed cleanly on the third run.

**Nothing of mine is left behind.** Fixtures were only ever in
`vignette-todo/integration2-scratch/shots`, and that folder is now empty. My two drafts were
forgotten when their files went (`[draft] forgot push.png`,
`[draft] forgot Screenshot test 8.png`), and the store is back to the same 12 keys it had before I
started. Nothing was written to `~/Dropbox/Screenshots` or `~/.config/vignette/`.

**One pre-existing oddity, not from this run:** `~/Library/Caches/com.petepetrash.vignette/drafts/`
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
Your build is back on `~/.config/vignette/settings.json` and the lock is released.

---

## Round 3 (Pete's feedback on c43304a)

Pete tried the merged run-2 branch and reported four things. Four agents fixed them on branches off
`c43304a`; all four are merged, build, and pass the tests. The branch to take is still
`todo2/integration`, now at `ad31403`.

| commit | branch | what |
| --- | --- | --- |
| `0786fa2` | `todo3/reopen` | a reopen picks up the mark drawn last |
| `73412c1` | `todo3/select` | a card takes hover and clicks over its own frame |
| `fc97e81` | `todo3/shadow` | nothing takes a flight's place until it has arrived |
| `ad31403` | `todo3/zoom` | zoom is one number carried by one spring |

### Reopening selects the last mark
`todo3/reopen`, `e9416d2`. Pete: "instead of just reopening to the select tool, let's also
auto-select the last added shape."

The load now selects the top of the page's z-order excluding the screenshot, which is where tldraw
puts each new shape. A fresh image still opens on the circle tool with nothing selected.

Measured on the merged build: drew an ellipse then a rectangle, cancelled, reopened.
`annotator.tool` is `select`, `getSelectedShapeIds()` is exactly the rectangle's id — the second
shape, and only it — `shapes` 3 (screenshot plus two), `canUndo` false. The selection change stays
out of undo history.

Unverified: nothing.

### A card under a selected card answers again
`todo3/select`, `cd9661d`. Pete: "thumbnails don't respond to clicks or hover when underneath a
selected thumbnail."

The cause: a card's thumbnail fills the card, so a screenshot whose shape differs from the card's
box hangs outside that box, and the clip that hides it does not shrink the hit area. A card took
hover and clicks everywhere its image reached, and `zIndex` raises a hovered card over the one below
it, so the card just selected swallowed its neighbour's face, circle included. One
`.contentShape(Rectangle())` in `CardView` holds each card to its own frame. `[state]` now also
names the hovered card, which is the only sign of hover while the buttons are away.

Measured on the merged build, Pete's exact repro: eight cards, clicked the circle of the second
newest, walked the cursor onto the newest — `[state] hovered` is the newest — and clicked its
circle. `selected` came back `["Screenshot test 7.png", "Screenshot test 8.png"]`, both of them, in
click order. A crop shows the selection circle drawn on that unselected card while its neighbour
above is selected.

One correction to the smoke script: it asked for hover *buttons* on an unselected card beside a
selected one. Buttons never show while anything is selected (`showsButtons` excludes selection
mode), and that is older than this round. In selection mode the affordance is the circle, and the
circle appears.

Unverified: I could not get a clean capture of the hover buttons with nothing selected on this
build. `scripts/input.sh move` fired hover three times and then stopped firing it, which is the
known flake, and Pete was using the mouse. The buttons live inside the card's own frame, which is
the only thing `contentShape` narrows.

### One shadow, and nothing steps at a handoff
`todo3/shadow`, `7e0662e`, with `docs/shadow-2026-09-17.md`. Pete: "thumbnail shadows still flicker
once the annotator transitions back into a thumbnail; when a thumbnail transitions to the annotator,
the shadow under the annotator also flickers."

The agent's camera found that the handovers themselves are atomic — never two shadows, never none.
The flicker was the picture and its shadow *stepping* at the moment one drawer took over, for two
reasons: the flight handed over on a timer while its spring was still about 3 pt short, and the
column's bottom fade ate exactly the newest card's shadow, so the card at rest drew a weaker shadow
than the flight did (0.77 to 0.98 of it, measured 1 to 8 pt below the edge).

So `fly` got two callbacks. `arrived` runs when `Anim.settle` says the spring is within half a
point, and puts the flight exactly on target in that turn; everything that becomes visible waits for
it. The column's bottom fade starts below the card's shadow (`StackLayout.cardShadowRoom`), and the
flight's shadow is cast by the clipped image before its ring, the way a card casts its own.

Measured on the merged build, at 60 fps over the newest card's slot, a card annotated from the stack
and cancelled at natural speed: the card's bottom edge flies in at 53, 16, 21, 12, 15, 9, 7, 3, 6,
3, 2 px a frame — the spring decelerating — and then **every frame after it lands moves by 0.07 px
or less** (0.035 pt). No one-frame jump at the handoff. The shadow band 1 to 12 pt below the card
settles from 20.06 to 20.30 grey levels with no frame changing by more than 0.36, against the 1.86
jump the agent measured before.

Unverified: the agent reports one frame, unexplained, with no shadow, which it could not reproduce
or account for. I did not see one in 174 frames, but I recorded one landing, not six.

### Zoom, rebuilt from the bottom up
`todo3/zoom`, `17ce3a4`, with `docs/zoom-2026-09-17.md`. Pete: "the image within the frame is often
out of sync with the frame, or does these layout jumps and skips while zooming, sometimes getting
stuck at a position or size that doesn't match the frame."

The agent measured all three of those, with numbers: a stream that mixed step sizes teleported the
window 48 points in one frame, because the host chose between a spring and an immediate set per
message; the camera ran 2.7x while the window ran 1.03x in the same flick, because the split was
decided against the window's target rather than the window on screen; and the image was 0.2 to 2.0
points smaller than its frame on 57 of 63 ticks.

Now a zoom session is one number. `Zoom.split` divides it into the window's scale and the page's
camera in one place, so `window × camera` is the level by construction. One spring carries it,
ticked by the display link. Each tick sets the frame from `Zoom.frame` and then scales the web
view's layer by the frame's own bounds over the size the page was laid out at, so the image's edges
are the frame's edges because they are derived from them. The page is relaid out once, at rest,
under a cover that comes down when the page says it has painted rather than on a timer.

Measured on the merged build, with the agent's own trackpad-shaped wheel stream:

- **Fitted**: frame `[386,103,740,689]`, `page.inner` `[740,689]` — equal.
- **A smooth stream at (0.22, 0.30)**: at rest, frame `[343,38,937,872]`, anchor `[0.219, 0.299]` —
  the point asked for — level 2.0138, window 1.2656, camera 1.5912, and 1.2656 × 1.5912 = 2.0138
  exactly. The window had hit the screen, so the camera took the rest, with no boundary visible.
- **cmd+0**: frame exactly back to `[386,103,740,689]`, level 1, window 1, camera 1, anchor
  `[0.5, 0.5]`, `page.inner` `[740,689]`.
- **A stream at (0.70, 0.60)**, at rest: frame `[63,38,1278,872]`, anchor `[0.700, 0.470]` — x
  exactly, y given way at the screen's edge, as documented — level 1.8221 = 1.2656 × 1.4397 exactly.
- **A swap while zoomed**: annotating another card from there landed it at `[288,103,936,689]`,
  level 1, `page.inner` `[936,689]` — fitted, and agreeing exactly.

On frame versus `page.inner`: the frame is no longer rounded to whole points, so at a zoomed rest
the frame is 936.55 × 872.00 while the page is laid out at 936 × 871 and the layer scale (1.0006,
1.0011) makes up the fraction. They agree to within the layout's own rounding, by design rather
than by drift, and captures of both frame corners show the page's content flush to the frame with
no gap.

Unverified, and worth saying plainly: **a real trackpad**. Every measurement here and on the branch
is a synthetic wheel stream dispatched into the page. A real pinch (`magnify` with its phases), a
two-finger double tap (`smartMagnify`) and a hardware cmd+wheel all funnel into the same
`zoom(by:at:as:)`, but AppKit delivering those events is untested. Also unverified: the Studio
Display, and the screen-edge give-way on a second display.

### Decisions made without Pete, and open questions

- **Zoom's springs are in code, not in the tweaks**: 0.1 s while a gesture is tracking, 0.3 s for a
  key, a double tap or a fit, both multiplied by the motion scale. No new settings key, so nothing
  is written into the real settings file. **Open**: worth tuning by feel.
- **The screen-edge give-way is unchanged.** When the window reaches the screen in one axis the
  anchor cannot be honoured and the content slides under the cursor. It is visible in the numbers
  above as y going from 0.60 to 0.470.
- **Smart zoom still goes to twice the fitted size.** Preview picks a level from the content.
- **`Look.annotator` is still hard-coded** at `0.45 / 24 / y10`. It is now the single source for the
  card, the flight and the annotator window, but it is not in `UITweaks`, so it cannot be tuned
  without a build.
- **The column's bottom fade is now 7 pt on your numbers** (19 pt of inset, 12 pt of it reserved for
  the card's shadow). A card scrolled out of the bottom of the column fades over 7 pt instead of 19.
  That is the price of the card and the flight casting the same shadow. The top fade is untouched.
- **A flight stands still on its target for 0.14 s** between `landed` (0.46 s) and `arrived`
  (0.60 s). On a warm page the live editor could have taken over at the earlier moment. The toolbar,
  which sits below the frame and outside the flight image, appears at the later one.
- **My own decision, as integrator**: both `fly` call sites used an unlabeled trailing closure,
  which Swift binds to the *last* closure parameter — `arrived`, not `landed` — with a deprecation
  warning the branch did not act on. So the annotator window was already coming up on `arrived`,
  and that is what the branch's own "after" frames measured; putting it up on `landed` would step
  it 3 pt against the picture the flight is still showing. I labelled both call sites `arrived:`,
  which changes nothing and removes the ambiguity, and corrected the two places that said otherwise
  (the design note and the AGENTS.md bullet). **Open**: `landed` now has no caller at all, and
  neither does `frameDidChange`, the callback the two agents were told to publish so a shadow could
  follow the frame — the single-owner shadow it was for was weighed and not built. Both are seams
  kept for a design that is not there. Say the word and they go.

### Incidents

- Two agents contended for the launch lock during the round.
- Twice a build ran against the real settings for about fifteen seconds. Nothing was written to
  `~/.config/vignette/settings.json` either time.
- Before anything was rebuilt, the app Pete was running was copied out of
  `integration2/build` to `vignette-todo/pete-build/Vignette.app` and relaunched from there, because
  a rebuild rewrites a bundle under its own running process. Every restore this round went to that
  copy, and at the end the copy was replaced with the merged build.
- My smoke round held the lock from 15:21 to 15:32 and drove nothing but its own build on its own
  scratch settings. No stitch ran, so the clipboard was not touched. The stack was dismissed once by
  activity that was not mine; I re-ran.
- Fixtures were only ever in `integration2-scratch/shots`, which is empty again.

### Review

An adversarial review of `d87059a` found one bug on screen and seven smaller things. All eight are
fixed in `607a4ae`, and `./scripts/build.sh --test` passes at that tip.

**The bug: a card flew back from the wrong place.** With the annotator zoomed, closing it ordered
the window out at its zoomed rect and started the card's flight from the fitted rect: a 200 pt step
in one frame, on every Esc, Done and dismiss from a zoomed image. It also swapped the picture at
that instant, because a zoomed window shows a crop of the screenshot and the flight image is the
whole of it.

`hide` now springs the level back to 1 first — 0.2 s, motion-scaled — and the window comes down
once that has arrived, so the frame the flight starts at is the frame the window was last at. A
0.3 s deadline still brings the window down if a zoom arriving mid-fit takes the spring's
completion with it.

**The seven others, in the same commit.**

- `hideWindows` stops the zoom spring and drops the pending relayout and cover. Measured before:
  after a cancel mid-gesture the spring kept ticking on a hidden window, `applyZoom` kept calling
  the page's camera after `reset` had emptied it, and the at-rest relayout ran a snapshot, a cover
  and a web-view resize on a hidden container.
- The relayout's snapshot completion checks that the spring is still at rest. The snapshot is a
  round trip to the web process, and a momentum tail resuming while it is out would have laid the
  page out under a moving frame.
- Camera calls go out one at a time with the latest value waiting, instead of one per display-link
  tick into a channel that answers slower than 120 Hz.
- `StackLayout.inset` is now at least the card's shadow plus a 7 pt fade. Before, a `cardShadowY`
  and `cardShadowRadius` adding up to more than `ui.panelInset` left no room for the fade and the
  column cut the shadow off with a hard edge. The panel grows around the column instead, so the
  cards do not move. On Pete's numbers nothing changes; on the shipped defaults the inset goes from
  19 to 21. A test covers it.
- A flight's generation is monotonic. It used to be per id, so a timer from a removed flight could
  snap the flight that took its id next.
- `fly`'s `landed` callback and `AnnotationController.frameDidChange` are gone. Neither had a
  caller, and both were seams for the single-owner shadow that was weighed and not built.
- The AGENTS.md memory bullet now names the cover snapshot: one screen-sized bitmap at a time,
  about 59 MB at 2x on a 5K display, freed when the page reports it has painted or after two
  seconds.

**Checked live**, my own build on my own scratch settings, five fixtures, nothing else driven.

- *The fly-back.* Opened from the stack at the fitted `[165, 103, 1182, 689]`, zoomed by a wheel
  stream to level 2.23 at `[16, 38, 1496, 872]`, then `cancel`. A 60 fps recording of a
  300 x 100 pt strip across the window's left edge, read back frame by frame to sub-pixel
  precision: the edge stands at 15.6 pt for ten frames, then walks 59.7, 95.7, 119.6, 141.6,
  150.1, 153.1, 157.6, 160.1, 162.6, 163.1, 163.6, 164.2, 164.1, 164.6, 164.6 — a decelerating
  spring whose last steps are under 0.6 pt — and lands on the fitted edge at 165. The flight leaves
  from there. Before the fix that whole walk was a single frame. The log times it: `close ->
  parking` at 16:06:34.888, `parked -> idle` at 16:06:35.224, 0.336 s apart, which is the park
  round trip plus the fit.
- *Nothing left running.* Same setup, `cancel` 0.03 s after the wheel stream stopped, with the
  spring still mid-flight at level 7.07 and the window at the screen's own rect. 0.2 s later the
  level reads 1.0006 at `[165, 103, 1183, 689]`; the window goes 0.39 s after the cancel, at
  exactly `[165, 103, 1182, 689]`. From there the level, the frame and the page's
  `innerWidth`/`innerHeight` are frozen for as long as they were polled — eight readings over
  1.6 s — and the log has no line of any kind after `[focus] annotator closed`, no
  `[web] error call failed` among them.
- *One edge, recorded.* If zoom input keeps arriving after the close, each message takes the fit
  spring's completion with it and the 0.3 s deadline brings the window down from wherever the frame
  is: measured, the level stayed at 6.64 and the window left at the screen's rect, 0.53 s after the
  cancel. A synthetic stream can do that; a hand on Esc cannot, and neither can Done.

**Recorded, not changed.** Six things the review named and asked to leave alone.

- `ui.motion: 0` lays the page out once per zoom message, because every step arrives at once. That
  is the scripting path. A person with Reduce Motion on moves the level in far fewer steps.
- The annotator takes key focus about 0.14 s later than it did before Round 3, because `show` runs
  on `arrived` instead of on the old timer. Nothing is typed into the page in that window.
- The column's mask fades over 19 pt at the top and 7 pt at the bottom. The asymmetry is the card
  shadow's room; it is numbers, not a second rule.
- A real trackpad pinch, a two-finger smart zoom, and the Studio Display above the primary screen
  are all unverified. Every zoom measured here was a synthetic wheel stream or a key, and nothing
  was driven on the second display. So are the hover buttons under a card since
  `contentShape(Rectangle())` was added: the one capture of them in the smoke round was never
  confirmed by a `[state]` line saying the card was hovered.
- `page.inner` at a zoomed rest is one point smaller than the frame — `[1495, 871]` inside
  `[16, 38, 1496, 872]` — which is the layout rounding that the layer transform makes up. It is not
  drift.
- After the window hides, the page keeps the size it was last laid out at, so a state dump taken
  then can show a `page.inner` that has nothing to do with the fitted frame. The next `prepare`
  lays it out for the image it is about to show.

**What is left.** The Round 3 open questions above are unchanged. `landed` and `frameDidChange`
are now gone rather than unused, so a single-owner shadow, if it is ever built, starts from
nothing.

### How to take it

Unchanged from section 3 above: `git merge todo2/integration` on `foundation` in your own checkout,
then `./scripts/run.sh`. Your `docs/TODOS.md` is uncommitted and no branch touches it. The worktrees
and `todo3/*` branches can go the same way as the `todo2/*` ones, and `vignette-todo/pete-build` is
a throwaway copy you can delete once `run.sh` has built your own.
