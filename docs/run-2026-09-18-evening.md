# Run 2026-09-18 evening: three branches merged into `todo7/integration`

Three agents worked in parallel this evening. Everything they built is merged, builds, passes the
tests, and was driven in one combined build. Nothing is left half-merged.

The branch to take is `todo7/integration`. Section 3 says how.

Merge commits, in order, and one commit of my own on top:

| commit | branch | what it brings |
| --- | --- | --- |
| `cd0321f` | `todo7/stack` | the column runs to the screen's bottom around the Dock, a keyboard selection brings the strip's labels out with their shortcuts, and the Draw hint steps aside for the two corner buttons |
| `4386e3f` | `todo7/transition` | a card on its way to the annotator turns around where it is, and the annotator takes the keyboard and the pointer as the card lands |
| `393cee2` | `todo7/site` | a one-page site says what the app does and shows the stack beside the editor |
| `aecbc5f` | — | three AGENTS.md lines the two branches left naming things the merged code no longer has |

`./scripts/build.sh --test` passed after every merge, and again at the tip: **194 tests**, up from
foundation's 188. `todo7/stack` brings one and `todo7/transition` five; `todo7/site` brings none, so
the count is the same after the second and third merges. **One conflict**, in `AGENTS.md`, resolved
by keeping both sides. Three files
were changed by more than one branch; section 5 says what was read by hand and what was checked.

The bridge protocol is untouched at 11 on both sides: no branch changed `Bridge.swift` or
`bridge.ts`.

---

## 1. What landed

### The stack runs to the bottom of the screen and steps around the Dock
`todo7/stack`, `38e8989`.

`StackArea` (new, in `StackLayout.swift`) is where the stack may draw: `bounds` plus `safeBottom`.
`StackLayout.area(visibleFrame:screenFrame:dock:)` is the only place it is built. `bounds` takes its
sides and top from `visibleFrame` — the menu bar and a Dock on a side keep their room — and its
bottom from the screen's own `frame`. `safeBottom` is the height AppKit reserves for a bottom Dock,
and zero unless the Dock's tiles reach into the column's strip of the screen. The panel runs down to
the screen's edge; the column, its mask, the toast, the strip and the hair of alpha that catches
clicks are all lifted by `safeBottom`, so a click on a Dock icon under the column still reaches the
Dock. `Sources/Dock.swift` (new, 62 lines) reads the tiles from the Dock process's one `AXList`,
with a 0.25 s messaging timeout and the element cached by pid. `annotatorRoom` and `annotationFrame`
keep reading `visibleFrame`: the annotator must not go under the Dock. `[state] stack.safeBottom` is
new.

Stack's numbers, twelve fixtures, built-in display 1512 x 982:

| | Dock clear of the column | Dock under the column | Dock hidden | Dock on the left |
| --- | --- | --- | --- | --- |
| `tilesize` | 51 | 72 | 72 | 72 |
| tiles (`Dock.tiles`) | `(273, 906, 966, 66)` | `(90, 885, 1332, 87)` | `(90, 982, 1332, 87)` | `(10, 77, 60, 865)` |
| `stack.safeBottom` | 0 | 93 | 0 | 0 |
| `stack.viewport` | 910 | 817 | 910 | 910 |
| newest card | `[1307, 845, 188, 120]` | `[1307, 752, 188, 120]` | `[1307, 845, 188, 120]` | `[1307, 845, 188, 120]` |

The panel's bottom edge reads 984 in every one. Where the Dock is under the column the card's bottom
edge is 872, 17 points above the Dock's top at 889; where it is not, the card's bottom edge is 965,
the same 17 above the screen's edge. Scrolled, the card ends exactly at the Dock's top edge with the
Dock whole below it. A scroll with the cursor inside the Dock's room under the column moved nothing;
thirty points higher, on the column, the same scroll moved it. The Dock read costs 0.34 ms, median
of 40 warm.

My own round reproduced this on five fixtures with the Dock widened to `tilesize 72`:
`safeBottom 93`, `viewport 707`, panel `[1288, 146, 226, 838]`, newest card `[1307, 738, 188, 134]`
— bottom edge 872, again 17 points above the Dock's top at 889. The capture shows clear screen
between the card's shadow and the Dock's shelf.

**First open after a Dock restart.** I killed the Dock and opened the stack on the new process:
`safeBottom 93`, the same card frame. The element is cached by pid, so a new Dock is read afresh.

Not verified: a second display; an app untrusted for Accessibility (unit test only, nobody revoked
the real trust).

### Selecting from the keyboard brings the strip's labels out, with the shortcuts
`todo7/stack`, `e9462b0`.

`model.stripHovered` (a bool) becomes `model.stripRevealed: StripReveal?` — `nil`, `.hover` or
`.keyboard`. Set by Shift+arrow, Space and Cmd+A; cleared by the pointer moving onto a card, by the
strip's own hover leaving, by `releaseKeys` and by the strip's `onDisappear`.
`ShotAction.Key.glyphs` (`Config.swift`) is now the one renderer of ⌘C, ↩, ⌘⌫, read by both the row
and its tooltip. `StackLayout.stripReveal(rows:)` measures the widest label, `stripShortcutGap` (12
points) and the widest shortcut; `stripLabelBox(reveal:)` is the box every row's text shares, so the
shortcuts line up in a column. **`[state] stack.stripHovered` becomes `stack.stripRevealed`**,
carrying `"hover"`, `"keyboard"` or null. That is a contract change for anything reading the state
line.

Stack's round: two Shift+Ups with the cursor parked at (400, 400) gave three selected,
`stripRevealed keyboard`, `stack.strip [1171, 711, 120, 128]`, panel `[1152, 36, 362, 948]`. The
strip's right edge is 1291 both at rest and grown, so it grew 85 points to the left into room the
panel already held. ⌘C then ran on all three (`items=3` on the pasteboard). Moving the mouse onto a
card cleared it to null; onto the strip set `hover`.

My round: the same sequence gave `selected` three, `stripRevealed keyboard`,
`strip [1171, 318, 120, 128]`, panel `[1152, 146, 362, 838]`. The capture reads **Copy ⌘C, Draw ↩,
Stitch ⌘S, Delete ⌘⌫**, labels left, shortcuts right-aligned in a column, dimmer. The mouse never
moved.

Not verified: the reveal's spring at `motion: 1` frame by frame; a keyboard selection while the
column is scrolled. No test covers the reveal's transitions — they need panels and a key window.

### The Draw hint's dead zone is the two corner buttons
`todo7/stack`, `b77551c`.

`CardView.inButtonRow` becomes `CardView.overCornerButton`: the pointer is in the bottom band **and**
within `ui.buttonSize + CardView.buttonPad * 2` of the card's left or right edge. `buttonPad` (6) is
now named and used by all four corner overlays.

My round walked the cursor along y = 862 on the newest card, resting above the Dock
(`[1307, 738, 188, 134]`), with `stack.hovered` confirming the card at every step:

| x | over | hint |
| --- | --- | --- |
| 1320 | Copy (card's left edge 1307, dead zone to 1346) | gone, Copy's label out |
| 1360 | the band, just right of Copy | **up** |
| 1440 | the band, just left of Delete | **up** |
| 1470 | Delete (dead zone from 1456) | gone |

A click at (1400, 862), the middle of the band, still drew: `[annotate] ok Screenshot i5.png`,
`flyingOut`, `shown` 333 ms later.

### A card on its way to the annotator turns around where it is
`todo7/transition`, `c744faf`.

`AnnotatorTransition` gets a `flyingOut` branch of its own. In it, `close` from the stack answers
`abandon(a) returnCard(a)`; `close` from a lone thumbnail answers `abandon(a) hideAnnotator`; and
`annotate(b)` answers `abandon(a) returnCard(a) prepare(b)`. `abandon` is a new effect:
`AnnotationController.abandon()` clears `current`, ends the stand-in's session, resets the page's
canvas and takes the window down, asking the page for nothing. No park, because a park is a round
trip that can sit behind an export while the card hangs in the air. `dismiss`, `remove` and `finish`
still park from `flyingOut`.

Transition's round, 175 ms in: before, `close -> parking -> parked -> idle` and the card's leading
edge reached capture column 514 before reversing; after, one line —
`close -> idle effects=abandon(…) returnCard(…)` — and it turned 66 points sooner, same shape. At
511 ms, deep in the flight, the edge reached the frame and its overshoot and reversed two frames
after the `close`, with no pause at the frame. A draft parked earlier survived a cancelled reopen
with no `[draft]` line at all.

My round, on the merged build, twice from a Dock-adjacent slot:

```
22:59:15.181 [transition] annotate(Screenshot i4.png from stack) -> flyingOut(Screenshot i4.png) effects=prepare(…)
22:59:15.230 [transition] close -> idle effects=abandon(Screenshot i4.png) returnCard(Screenshot i4.png)
```

and again at 173 ms in, past half the flight. Both times no `-> annotating` and no `effects=show`
line, which is the only thing that orders the window in; `annotator.windowVisible` read False after
each, no card was left in `out` or `forming`, and every card sat in its Dock-adjacent slot.

Not verified: the slow park this protects against (an Esc during a Copy Drawing); a click outside
during the flight.

### The annotator takes the keyboard and the pointer as the card lands
`todo7/transition`, `f98ef62`, `a2bcd18`, `5843d5e`.

`fly` now answers twice. `Anim.passesTarget(duration, bounce:)` (`Settings.swift`, no new `ui` key)
returns when a spring first reaches its target; from there until it settles the rect contains the
target on every side. `TransitionLayer.fly` takes `covered:` beside `arrived:` and fires it at
`min(settleTime, Anim.passesTarget(expandDuration, bounce: 0.15))` — 0.313 s against `arrived`'s
0.604 s for a card-to-annotator flight. `perform(.prepare)` sends `.shown` from `covered`;
`arrived` now carries `onAnnotatorLanded?()`, `dropShadow` and the lift. `AnnotationController.show()`
puts the window up with its shadow off and `landed()` turns it on, because a shadow is the one thing
that falls outside the frame the flight image covers. A third callback, `dropped:`, runs for a
flight removed before it arrives, so the window never keeps a shadow that is switched off.

Transition's measurements, three runs each, same driven sequence:

| | `annotate` → `show` | `annotate` → `loaded` |
| --- | --- | --- |
| before | 642, 642, 644 ms | 692, 693, 696 ms |
| after | 337, 327, 330 ms | 370, 371, 374 ms |

`loaded` cannot precede the window: it is posted from a double `requestAnimationFrame` and WebKit
pauses frames for a hidden window (`[eval] ok NO raf within 1500ms, hidden=true`). A CGEvent drag
posted at a measured instant landed on the page from +342 ms onward, against a `show` at +327; before
the change, the same drag at +604 and +639 ms threw the session away. The shadow band across the
handover changed by 0.03 before and 0.28 after, against the 1.85 grey levels the shadow doc fixed.
**One number got worse**: the picture's step at `arrived` grew from 0.45 to 0.85 points.

My round, on the merged build, nine flights out of a Dock-adjacent stack: `annotate` → `show` read
**333, 336, 336, 331, 328, 324, 333, 333, 330 ms** and `[annotate] loaded` **368 to 421 ms**. With
`ui.motion: 0` the same pairs read **9, 7, 24, 20 ms** and `loaded` landed at 65 ms.

Not verified: a trackpad, a second display, Reduce Motion (only `ui.motion: 0`), and the handover
under load.

### A one-page site
`todo7/site`, `b0a92e2`.

`site/index.html` (5.2 KB, hand-written, one `<style>` block, no framework, no build step, no
JavaScript) and `site/stack-and-editor.png` (1200 x 668, 209 KB). One font size throughout, one
column at `max-width: 34rem`, two colours as channel triples swapped by `prefers-color-scheme`.
Seven features in the README's user words. `grep -o -i annotat site/index.html` counts 0; `draw`
counts 12.

The picture is a real `screencapture` of the real running app; only what is inside the cards is
synthetic (four generated HTML pages rendered headlessly), so nothing of yours is in it. The tldraw
watermark is kept on purpose.

My checks on the merged build: `project.yml` and `scripts/` are untouched by the branch, and the
built bundle's `Contents/Resources` holds `dist`, `LICENSE`, `LICENSE-tldraw.md` and `vignette` and
nothing else — `find` for `site` or `stack-and-editor` in the bundle returns nothing. The page
renders from the merged checkout in headless Chrome 153: one column, one font size, the picture and
its caption, the seven bullets, the two placeholder paragraphs and the footer, image loaded from its
relative path.

Not verified: never served by GitHub Pages, only by `python3 -m http.server`; no real phone
viewport (Chrome clamps a headless window to 500 CSS px); only Chrome.

---

## 2. Decisions made without you, and open questions

### The stack

- **The Dock's tiles come from Accessibility, not the window list.** `CGWindowListCopyWindowInfo`
  reports the Dock's window as the whole screen on macOS 15 — `(0, 0, 1512, 982)` while the tiles
  were 966 points wide — so it says nothing. The `AXList` gives them exactly; a brightness scan put
  the Dock's visible edges at 273.0 and 1239.0, the `AXList` rect to the point. **The safe area now
  depends on a permission the app already asks for** (the modifier-tap hotkey). Untrusted,
  `Dock.tiles()` is nil, the Dock is taken to span the whole edge, and that is exactly the old
  layout: an untrusted app loses the gain and nothing else.
- **Only the horizontal extent is Accessibility's.** The height is AppKit's, so it cannot move while
  a tile magnifies. A magnified Dock's `AXList` went `(90, 885, 1332, 87)` → `(16, 885, 1480, 87)`
  under the cursor: wider, same top and height. **Open:** a Dock whose resting right edge is just
  short of the column can therefore gain the safe area while the cursor is on it, until the next
  layout pass. Left as is; the alternative is ignoring the reading whenever the cursor is over the
  Dock.
- **A hidden Dock keeps no safe area**, as your note said. When it slides up under the cursor the
  newest card is drawn over it, because the panel is above the Dock's level. **Open:** leave it, or
  should a revealed Dock push the column up?
- **The strip keeps its four rows**, each showing its own shortcut. **Open:** Copy Paths (⌥⌘C) and
  Copy Drawing (⇧⌘C) are `.shortcut` actions with no row, so their keys are shown nowhere in the
  strip. Add rows, list them elsewhere, or leave them.
- **Cmd+A also reveals the labels.** Your item named `moveFocus` and the Space branch; Cmd+A is the
  same act, so stack included it. One line, flagged.
- **Item 33's dead zone uses the buttons at rest, not the grown Copy.** The label only comes out once
  the button is hovered, and `model.overControl` already hides the hint for as long as it is, so a
  grown rect would be dead logic. A deliberate deviation from the item's wording.
- **The state key was renamed rather than kept as `stripHovered` with a string value.** It is no
  longer about hovering.

### The transition

- **The cover moment is the crossing, not a tolerance.** A tolerance of 4 points bought 150 ms and
  left a tuned number; the crossing has no number, is the exact condition that makes the window
  invisible, and buys 312 ms. The cost is that the toolbar appears while the card still has its
  5-point overshoot to finish, at under one device pixel a frame. **Open:** watch whether the
  toolbar reads as early.
- **The 0.85-point step at `arrived`**, up from 0.45. If it shows, the fix is one line: let `arrived`
  wait for the spring's own `settlingDuration` instead of `Anim.settle`. That is 113 ms later and
  nothing you wait for is behind it any more.
- **A press in the first ~20 ms after the window appears can still close the session** — one of six
  probes. `OutsideClick` asks the window server which window is under the cursor, and for a window
  ordered in a moment ago the answer can still be the one behind it. The race is not new; with the
  window ordered in 310 ms earlier it now sits where a hand might actually be. Fixing it means
  teaching `OutsideClick` to ignore a click while the window it guards has just been ordered in, and
  the stack owns the other instance of that class. **Not fixed in this merge**; it is a question for
  you and a finding for the reviewer.
- **`dismiss` and `remove` still park from `flyingOut`.** `ThumbnailController.dismiss` aims that
  same flight at the card's offscreen slot before it sends the event, so an immediate turnaround
  would make a dismissed card vanish instead of sliding out. **Open:** if you want the stack's
  dismissal to turn the card around too, that is a change in `dismiss`.
- **A stale `loaded` is known and unfixed.** An abandoned load leaves its double
  `requestAnimationFrame` pending; it fires when the window next appears and posts `loaded` for a key
  no longer in the annotator. **I saw it in my smoke round**, in the swap-mid-flight path:

  ```
  23:00:43.182 [transition] annotate(i2) -> flyingOut(i2) effects=abandon(i4) returnCard(i4) prepare(i2)
  23:00:43.568 [annotate] loaded 421ms Screenshot i4.png
  23:00:43.568 [annotate] loaded 380ms Screenshot i2.png
  ```

  It is harmless — `pageLoaded` lifts a flight only for the key the reducer says is `annotating`, and
  `prepare` clears `loadedKeys` — but it makes the log lie about which image was loaded. The fix is
  one line in `web/src/App.tsx`, which was outside that agent's files.

### The site

- **Both links are placeholders, not live `<a>`.** The repository is not public and there is no
  binary, so a live href would 404. Each paragraph carries, in an HTML comment directly above, the
  exact line that replaces it. **Do not "fix" them.**
- **The owner in those URLs is a guess.** The checkout has no git remote; `gh api user` says
  `petekp`, so the placeholders say `petekp/vignette`. **Open:** correct them if the repo lands
  elsewhere.
- **No Pages route was configured and no workflow was written.** Pages' "Deploy from a branch" offers
  only `/ (root)` or `/docs`, so `site/` cannot be served as named. The route that needs no approval
  and no restructuring is pushing the *contents* of `site/` to the root of a `gh-pages` branch.
  **Open:** which route.
- **Open:** keep the tldraw watermark in the picture, or retake it once the Hobby key lands? A
  favicon? Should AGENTS.md's Layout list gain a `site/` line? The agent was scoped to `site/` and
  did not touch it; nothing in AGENTS.md or README became false.

### Mine, as integrator

- **I fixed three AGENTS.md lines in a commit of my own** (`aecbc5f`), not in a merge commit, because
  none of them was broken by the merge and the run's rules forbid amending. Section 5 lists them.
- **I widened your Dock to `tilesize 72` for the smoke round and put it back.** Smoke path 1 is the
  one place item 31's geometry meets item 29/30's flight, and neither agent drove it; at your
  resting `tilesize 51` the Dock ends 68 points short of the column, so `safeBottom` is 0 and there
  is nothing to test. Recorded before and restored after, verified by re-reading the four keys.
- **I did not touch the outside-click race or the stale `loaded`.** Both are one-line changes in
  files this run's agents owned or in the page; both are reported above rather than slipped into a
  merge.
- **README overstates one half of the interrupt bullet.** `README.md` now says "Esc, or clicking
  another card, sends it straight home from wherever it is". Clicking another card does exactly
  that — I drove it. **A physical Esc does not reach the app during the flight at all.** `prepare`
  calls `releaseKeys`, and the annotator's window is not up yet, so in `flyingOut` the state reads
  `stack.key False`, `annotator.windowVisible False`, `app.isActive False`: no Vignette window can
  receive the key, and it goes to whatever you are in front of. The reducer branch is reached by a
  click on another card, by `vignette://cancel`, or by an Esc that arrives after the window is up —
  which is then an ordinary close and parks. **I left both the wording and the behaviour alone**,
  because the fix is either a README edit or a real change (keeping the panel's keys through the
  flight) and that is your call.

### What my smoke round drove, and what it showed

One launch round, 22:55 to 23:06, my build `aecbc5f` on
`integration-scratch/settings.json`, five fixtures, the Dock widened so its tiles reach under the
column (`safeBottom 93`). Every URL went through a wrapper that refuses unless `pgrep` finds my
worktree's binary, `ps -wwE` on that pid shows my `VIGNETTE_SETTINGS`, and a tagged `[state]` answer
names my settings file.

1. **A card annotated out of a Dock-adjacent stack, and back.** Cursor walked onto the newest card
   (`hovered` confirmed), clicked: `[annotate] ok`, `flyingOut`, `shown` at +333 ms,
   `loaded 378ms`. The slot the Dock rule placed was held (`out: true`,
   `[1307, 738, 188, 134]`) and `annotator.room` read `[0, 38, 1377, 851]` — the annotator does not
   go under the Dock. Done: `finish -> parking`, `parked -> idle effects=returnCard markCopied`, and
   the card came back to **the same frame**, `out: false`, with the stack holding the keys again.
2. **Cancel halfway through that flight.** At +49 ms and again at +173 ms:
   `close -> idle effects=abandon returnCard`, no park, no `show`, `windowVisible False`, nothing
   left in `out` or `forming`. Sampled during a wide image's flight, `widthScale` was already 0.81
   with `windowVisible False` — the stack narrows in the same turn the flight is aimed, before the
   window comes up — and it was back at 1 after the turnaround.
3. **A queue of three, selected from the keyboard.** Two Shift+Ups with the cursor parked away:
   three selected, `stripRevealed keyboard`, `strip [1171, 318, 120, 128]`, labels and shortcuts out
   in the capture. Return: `[annotate] ok … 1 of 3`, `strip null` and `stripRevealed null` while
   each card was in the annotator, `[annotate] next … 2 of 3` and `3 of 3`, each handover one turn
   (`parked -> idle effects=returnCard markCopied` and `annotate -> flyingOut` in the same
   millisecond — the swap's two flights). All three still selected at the end, strip back at
   `[1256, 318, 35, 128]`, nothing in `out` or `forming`.
4. **A swap mid-flight while the stack is narrowed.** Two `annotate` URLs 41 ms apart:
   `annotate(i2) -> flyingOut(i2) effects=abandon(i4) returnCard(i4) prepare(i2)` in one turn,
   `shown` 336 ms later, `widthScale` back to 1, only i2 `out`, i4 home in its Dock-adjacent slot,
   `forming` empty. (A first attempt drove this with two clicks and the second click missed, because
   the layout moves as the width scale changes mid-swap. That is the harness, not the app.)
5. **The Draw hint above the Dock.** The four-position walk in section 1, plus a click in the middle
   of the band that still drew.
6. **`ui.motion: 0`.** Path 1: `annotate -> flyingOut` and `shown -> annotating` 9 ms apart,
   `loaded` at 65 ms, the card back in its slot on Done with nothing left on screen — the capture
   shows the column and the Dock and no stray flight image. Path 3: three cards, each
   `flyingOut` → `shown` in 7 to 24 ms, and 90 ms after the second Shift+Up the strip was already at
   its full grown width with the labels and shortcuts out.
7. **The state report.** One `[state]` line from build `aecbc5f` parses and carries every stack key
   — `cards, feedback, focused, hovered, isStack, key, panel, queue, safeBottom, scroll, selected,
   strip, stripRevealed, viewport, visible, widthScale` — and every annotator key —
   `canvasZoom, color, current, frame, overlay, pageState, port, room, standIn, tool, webPid,
   windowVisible, zoom, zoomAnchor, zoomCenter, zoomLevel`.
8. **The site against the build.** Section 1.

**Nothing failed.** One oddity: a `[state]` read about 1.5 s after the very first `recent` reported
`visible False` with the cards still laid out, and the next `recent` showed the stack rather than
toggling it — so something dismissed it silently in that window. It never recurred across the
remaining twenty-odd rounds, no `[dismiss]` line was logged, and I could not reproduce it. Most
likely an outside click landing while the desktop settled after my own launch. Recorded rather than
explained.

---

## 3. How to take it

```
git -C ~/Code/vignette checkout todo7/integration
./scripts/run.sh
```

Nothing in your `~/.config/vignette/settings.json` goes stale: no branch added, removed or renamed a
settings key, and no new `UITweaks` number was introduced. `Anim.passesTarget` is code, not a tweak.

Two things to know before you drive it:

- **`stack.stripHovered` is gone from the state report.** Anything you have that reads it wants
  `stack.stripRevealed`, which is `"hover"`, `"keyboard"` or null.
- **The Dock only matters when it is under the column.** At your resting `tilesize 51` the Dock ends
  68 points short of the stack, so `safeBottom` is 0 and the column runs to the screen's bottom edge
  — which is the visible change. Widen the Dock, or add enough to it, to see the newest card step up
  and rest above it.

---

## 4. Incidents

**Your settings file was never written.** `stat -f %m /Users/petepetrash/.config/vignette/settings.json`
read **1789794952** at every check: before and after each of my four `./scripts/build.sh --test`
runs, before and after seeding my scratch file, before and after the smoke round, and at the
restore. That timestamp is 22:15:52, from before I started — your own build relaunching at the end
of `transition`'s round, as both that agent and `site` recorded. Reading it once, to seed the
scratch copy with `jq`, is the one contact I had with it.

**Your screenshot folder was not touched.** My five fixtures lived in `integration-scratch/shots`
and are deleted; `[watcher] removed Screenshot i1.png, Screenshot i2.png, Screenshot i3.png,
Screenshot i4.png` and `[watcher] removed Screenshot i5.png`. No draft or preview of mine was ever
created — nothing was drawn on any fixture — and `[state] drafts` read **20** throughout, which is
your count and the one the other two agents left.

**Your Dock was widened and put back.** Before: `orientation=bottom autohide=0 tilesize=51
magnification=0 largesize=16`. I set `tilesize 72` and `killall Dock` for the round, and restored
`tilesize 51` afterwards; re-read: `orientation=bottom tilesize=51 autohide=0 magnification=0
largesize=16`. I also restarted the Dock once more, deliberately, to check the first stack open
against a new Dock process.

**The clipboard.** Five `Done` renderings went on it during the round (my own fixtures, never
anything of yours). I cleared it with `pbcopy < /dev/null`; `scripts/input.sh pasteboard` now reports
`items=1 / 0: public.utf8-plain-text`, one empty text item.

**The lock.** Free when I asked. Taken at 22:54:24 with `owner` = `integration`, released at 23:06:28
after your build was back. One round, about twelve minutes. Your build (pid 16575) was killed only
while I held it.

**No interference.** Nothing dismissed my stack, cancelled my annotator or took my focus that I did
not cause, apart from the single unexplained early dismissal in section 2. The other three agents
were finished before I started.

**The state of the Mac.** Your build (`f57c330`, pid 45284) is running on
`/Users/petepetrash/.config/vignette/settings.json`, watching `~/Dropbox/Screenshots`, `[app] ready`
at 23:06:24. `pgrep -f vignette-todo/integration/build` prints nothing. The lock is released. The
scratch shots folder is empty. My scratch `settings.json` is back at `ui.motion: 1` after the
motion-off runs. Captures and the two driving wrappers are in `integration-scratch/captures`.

---

## 5. Merge notes

### Conflicts

**One.** `AGENTS.md`, in the flight-arrival bullet: `todo7/stack` had added its Dock bullet directly
after the line naming `docs/shadow-2026-09-17.md`, and `todo7/transition` had rewritten that same
line to name both `docs/shadow-2026-09-17.md` and its own `docs/handover-2026-09-18.md`. Resolved by
keeping both: transition's two-document sentence, then stack's Dock bullet. Neither side was dropped.

`README.md` and `Sources/ThumbnailController.swift` auto-merged and were read by hand afterwards.

### Files read by hand, and what was checked

**`Sources/ThumbnailController.swift`** — the one file both code branches changed, read in full
(1167 lines). Stack's edits are all present: `StripReveal`, `StackModel.stripRevealed` and
`.safeBottom`, the `area`/`readArea()` pair, `stripFrame`'s `safeBottom:`, the `[state]` keys,
`cardFrame`'s `safeBottom:`, `present(toast:)`, `layoutPanel`, the key handler's Space, Cmd+A and
arrow branches, `releaseKeys` and the hover callback. Transition's are all present: the
`onAnnotatorLanded` and `onAnnotatorAbandon` callbacks, `perform(.prepare)`'s
`covered:`/`arrived:`/`dropped:` closures, the removal of the shadow and lift work from `.show`, and
the new `.abandon` case. They meet in two places and both hold:

- **`dismiss()`** aims the annotator's flight at `cardFrame(of: card)` — which now carries
  `area.safeBottom` — and only then sends `.dismiss`, which the reducer still answers with a park.
  The slide-out therefore still carries the card, as `todo7/transition` intended, and it carries it
  to the slot the Dock rule placed.
- **`returnCard`** aims at `cardFrame(of: card)` too, so an abandoned flight turns around toward a
  Dock-adjacent slot. Re-aiming a flight replaces its `dropped` handler with the new call's (nil
  here), so a turned-around flight cannot also hand the shadow to a window that never came up.

`area` is read only in `layoutPanel` and `present(toast:)`, and `makeRoom` changes only
`model.widthScale` and `model.scroll`, neither of which `area` depends on, so a swap's width change
cannot desynchronise the slot from the panel.

**`AGENTS.md`** — read in full. The two branches' rewrites sit in six bullets and do not contradict
each other after the conflict resolution. Three lines were left naming things the merged code no
longer has, and I fixed them in `aecbc5f`:

- the strip bullet's last line still said `stack.stripHovered` after `todo7/stack` renamed the key,
  while the `[state]` list 230 lines above already said `stripRevealed` — the file contradicted
  itself;
- the same bullet still said `stripReveal` measures "the widest label plus the room beside the
  icons", two sentences after the branch's own new text says it measures the label *and the
  shortcut*;
- the `dropShadow(id:)` line still said a flight drops its shadow "in the same run-loop turn … the
  annotator window comes up", which `todo7/transition` made false: the window comes up at `covered`
  with its shadow off, and the flight drops its own at `arrived`, when `landed()` turns the window's
  on.

I checked the rest of the file for the same class of miss: no bullet states a fact twice, and no
bullet names a symbol the merge removed. `docs/hover-reveal-2026-09-17.md` line 75 also says
`stripHovered`, correctly — it is the dated note recording the rename. `docs/run-*.md` and
`docs/TODOS.md` mention the old name as history and were left alone.

**`README.md`** — read in full. Stack's two additions (the keyboard reveal inside the strip bullet, a
new bullet on the column running to the screen's bottom) and transition's one (a new bullet on a
flight being turned around) landed in the same list, in different bullets, with nothing stated
twice. The one problem is the Esc half of transition's bullet, in section 2.

**Checked across branches, though only one branch changed each file:**

- No caller of the old `stripReveal(labels:)` survives: `Sources/StackView.swift` (two sites),
  `Sources/ThumbnailController.swift` (two sites) and `Tests/StackLayoutTests.swift` all pass
  `rows:`, and the only definition takes `[StripRow]`.
- `grep -rn stripHovered` over `Sources/`, `Tests/`, `web/` and `skills/` returns nothing.
  `skills/vignette/SKILL.md` names no individual state key, so the rename does not reach it.
- `Sources/Settings.swift` — only `todo7/transition` touched it, adding `Anim.passesTarget` and no
  `ui` key. `Sources/DebugPanel.swift` is untouched by every branch, which is consistent: no new
  tweak was added, so no slider is missing.
- `Sources/Config.swift` (stack) gained `ShotAction.Key.glyphs`, and `StackView.shortcutHint` is now
  its only other reader, so a row and its tooltip cannot disagree.
- `Sources/Bridge.swift` and `web/src/bridge.ts`: untouched by all three branches;
  `bridgeProtocolVersion` and `PROTOCOL` are still 11.
- Tests: `Tests/StackLayoutTests.swift` (stack) and `Tests/AnnotatorTransitionTests.swift` plus
  `Tests/MotionTests.swift` (transition) do not overlap. 194 tests pass on the merged tree.
- `project.yml` and `scripts/` are untouched by `todo7/site`, and the built bundle carries no `site`
  folder.

---

## 6. Review

An adversarial review of `foundation..fa842ce` found seven things, and an architecture sweep added
its own list. Six changes landed, one commit each, on top of `fa842ce`. `./scripts/build.sh --test`
passes before each: **194 tests**, the same count — one assertion went and none was added.
`stat -f %m /Users/petepetrash/.config/vignette/settings.json` read **1789794952** before and after
every build and at every point of the round.

| commit | what it does |
| --- | --- |
| `0bec673` | a failed Dock read no longer decides where the column sits |
| `6b11e8f` | Esc turns a card around while it is still flying |
| `b8bc69a` | the bridge protocol goes to 12 |
| `aaa054b` | the site's Download line is one line |
| `114acdd` | the Dock's timeout covers every read it makes; two claims match their code |
| `813d653` | the annotator ignores clicks for the first moments after its window appears |

### What was found and fixed

**R1 (high): a Dock restart moved the whole column and it stayed moved.** `Dock.tiles()` returns nil
on any failure and `StackLayout.area` then takes the Dock to span the whole bottom edge; `readArea`
runs only on a layout pass, so the bad reading was sticky. The reviewer drove it 3 of 3 on Pete's own
Dock: `killall Dock`, open the stack, `safeBottom 72` and the newest card at `[1307, 767, …]` instead
of `[1307, 839, …]`. My own smoke round missed it because I had widened the Dock to `tilesize 72`,
where the fallback and the true reading agree.

A standalone probe of the same four Accessibility calls shows the failure exactly: after a
`killall Dock` the read answers `kAXChildren` with `kAXErrorCannotComplete` for about 180 ms, then
comes back. (It also shows the Dock's tiles animating up — y 982 settling to 906 over 1.3 s — while
their x extent never moves, which is why only the horizontal reading is Accessibility's.)

`readArea` now keeps the tiles from the last read that answered and builds the area from those, and
`scheduleDockRead` asks again every half second, up to eight times, laying out once the Dock answers.
Both halves are needed and both were driven, at Pete's own `tilesize 51`:

| | before | after |
| --- | --- | --- |
| `killall Dock`, open the stack, read at ~150 ms (3 tries) | `safeBottom 72`, card `[1307, 767, …]` | `safeBottom 0`, card `[1365, 812, …]` — 3 of 3, no visible move at all |
| the app's **first** read fails (Dock suspended, nothing remembered) | — | `safeBottom 72`, card `[1365, 740, …]`: the conservative fallback, as designed |
| the Dock is resumed, **no further interaction** | — | `safeBottom 0`, card `[1365, 812, …]`: the retry corrected it on its own |

So the fallback still applies when nothing is known — which is right, and what the unit test covers —
and it can no longer outlive the failure that caused it. An app untrusted for Accessibility never
gets an answer and settles on that fallback, which is the correct layout for it.

The retry cadence is in code, not `UITweaks`: it is a retry for a failed system read, not a number a
user would tune. No test was added — the layout function is unchanged, and a test of
`Dock.tiles() ?? lastGood` would mirror the implementation, which is what R6 is about.

**R2 (high): Esc could not turn a card around, though the README said it could.** Pete's acceptance
for item 29 was "Esc pressed halfway through the flight", and the reviewer confirmed with measured
timestamps over four runs — including one with the app already active — that nothing happened.
`perform(.prepare)` called `releaseKeys()`, so through the whole of `flyingOut` no window of this app
could take a key.

Pete chose the real fix over a README edit. `releaseKeys()` moves to `perform(.show)`, after
`onAnnotatorShow?()` has put the window up and taken the key, so the keys pass from the stack to the
annotator instead of being nobody's for the length of the flight. In `handleKey`, Esc while the
reducer is in `flyingOut` means `annotationEnded()`.

Driven with a real synthetic Escape, never `vignette://cancel`, with `[state]` read first to confirm
the stack was key:

- **Seven runs turned the card around**, at +58, +62, +58, +58 ms (CGEvent) and +223, +245, +285 ms
  (System Events, past halfway). Every one logged
  `close -> idle effects=abandon(…) returnCard(…)`, no park, no `show`.
- **The keys pass cleanly.** During `flyingOut`: `stack.key True`, `windowVisible False`. After
  `show`: `stack.key False`, `windowVisible True`. Never both, never neither. An Escape after `show`
  is an ordinary close of a visible editor and parks, as before.
- **A turnaround leaves the stack usable.** `key True`, focused, the selection untouched
  (`['Screenshot f3.png', 'Screenshot f2.png']` before and after), the strip back at its grown width,
  nothing in `out`. A second Escape then dismissed the stack, so `takeKeys()` after `returnCard` is
  still right when the keys were never released.
- **What the other keys do now that they reach the stack mid-flight**, all driven: a second
  `annotate` of the same key is a no-op (`effects=` and nothing else); Return opens the focused card,
  which is the swap that clicking another card already gave
  (`abandon(f1) returnCard(f1) prepare(f3)`); Space toggles the focused card's selection; an arrow
  moves the focus, which `releaseKeys` at `.show` then clears. None of them disturbs the flight.
- **`ui.motion: 0`:** `flyingOut` → `show` in 6 ms, `stack.key False` with the window up, and Escape
  there is an ordinary close after which the stack takes the keys back. Nothing is left holding them.

One deliberate consequence: a keyboard reveal of the strip's labels now survives the flight, because
`releaseKeys` is what clears it and it runs later. The labels go in when the annotator's window
appears rather than when the card leaves.

This is the recent stack only. `handleKey` guards on `model.isStack` and a lone thumbnail's panel
never takes keys, which matches Pete's acceptance; the README bullet now says so.

**R3 (medium): the bridge protocol was 11 on both sides though `LoadPayload` had changed.**
Both sides go to 12. Verified both ways: the happy path logs
`[web] ready protocol=12 tools=4 markColors=5`, and a build made with a deliberately stale page
(`PROTOCOL = 11`, app at 12) logs

```
00:57:06.666 [web] error protocol-mismatch page=11 app=12; rebuild with scripts/build.sh
00:57:06.863 [eval] error page-not-ready the editor page is unavailable; see the [web] lines
```

with `page: unavailable` in the state report. The tree was put back and rebuilt afterwards; the
working copy is clean and the bundled page is 12. No cross-side test was added: Pete declined that
version.

**R4 (medium): the site's Download paragraph explained the licence chain.** It is now
"Download Vignette — not released yet." The replacement anchor stays in the comment beside it and the
GitHub paragraph is unchanged. Re-rendered headlessly and read back.

**R5 (low–medium): `Dock.swift`'s timeout covered one of its four Accessibility calls.** A messaging
timeout belongs to the object it is set on and is not inherited by children that come back from it,
so the three child reads — each candidate's role, then the list's position and size — used the
process-wide default on the main thread, in the layout path. I extended the protection rather than
weakening the comment: the read is on the main thread on every stack open, so a wedged Dock stalling
it is exactly what the comment was written to prevent. It is now set from one named constant on every
element the file reads. The Dock still reads correctly afterwards (`safeBottom 0`, card
`[1365, 812, 130, 153]`).

**R6 (low): two assertions restated the source expression.** The `stripLabelBox` one is gone. The
other becomes the behaviour it was reaching for — a row with a shortcut needs more room than the same
row without one — which cannot be satisfied by an implementation that ignores shortcuts and does not
recompute the formula. The five-Dock-configuration block was left alone.

**R7 (low): a click in the first moments after the annotator's window appeared ended the session.**
Pre-existing, but item 30 moved that window 310 ms earlier and put the race where a fast hand now is:
the user draws as the card lands and loses the drawing. The coordinator's judgement, taken for Pete:
fix it narrowly, in the annotator's own monitor only, as a fixed interval.

`OutsideClick.start(settling:)` ignores clicks for that long after it is called. Only the annotator
passes one, 0.15 s; the stack's instance keeps the default of none and its call site is unchanged.
The interval is a race with the window server rather than an animation, so it is a constant in code
and the motion scale does not touch it.

Measured on one driven sequence, a click aimed by the log at the flight's start plus a fixed offset,
so it lands a few milliseconds after `show`:

| | clicks landing 12–25 ms after `show` | sessions lost |
| --- | --- | --- |
| before | 4 | **3** |
| after | 20 | **0** |

And the guard is narrow: an outside click at `show` + 190 ms — 40 ms past the interval — still closes
the annotator, 3 of 3, and a settled outside click seconds later logs `[annotate] cancelled` →
`close -> parking` → `parked -> idle effects=hideAnnotator` as it always did.

An alternative I considered and did not take: the annotator could ask whether the click is inside its
own frame, which needs no interval at all. It does not cover the toolbar, which is a separate child
window with its own rect, and the coordinator specified the interval with its reasoning. Worth
raising if the interval ever proves awkward.

### Left for Pete, with the evidence intact

Both are pre-existing, neither is this run's doing, and the standing rule is that a small unrelated
fix still needs his approval.

- **`copyAnnotated` has no `canvasRefusal` guard** (`AppDelegate.swift:390`). Its two siblings have
  one, and `exportDrafts` only checks `pendingExport == nil`. The reviewer drove it: with a card in
  the annotator and its window up, `vignette://copy-annotated` on another file answered
  `[copy-annotated] ok … 1 with annotations` — no refusal — while the live session owned the canvas.
  It breaks the rule AGENTS.md states about who owns the canvas. One line, matching its siblings.
- **The page's `quiet` flag is released outside the queue** (`web/src/App.tsx:336`, `:381`,
  `:89-93`). `quietly`'s `finally` sets the flag flat rather than restoring it, unlike the colour
  pass, so an export landing in the two frames after a load can have its canvas changes reported as a
  draft under the wrong key. Read-only finding: the window is about two frames and the reviewer's
  harness could not land in it. Its only reachable caller is the missing guard above.

### Refuted, and left as it was

`converge` removing a flight without running its `dropped` handler cannot be reached:
`ThumbnailController.stitched` refuses while the annotator has anything in flight, and `converge`'s
result card is a fresh `UUID`. The comment claimed the invariant anyway, so the comment was corrected
(`114acdd`) and the code was not.

### Incidents in the review round

- **Pete's settings file was never written.** `stat -f %m` read **1789794952** before and after all
  eight `./scripts/build.sh --test` runs of this pass, before and after the round, and at the
  restore.
- **The Dock was suspended for about fifteen seconds** (`killall -STOP Dock`, then `-CONT`) to hold a
  failed read open long enough to test the first-open case, and restarted four times with
  `killall Dock`. It is back at Pete's values — `orientation=bottom autohide=0 tilesize=51
  magnification=0 largesize=16` — and reads `(273, 906, 966, 66)` again. His Dock was not widened
  this round: R1 had to be verified at his own size.
- **The clipboard** held a Done rendering of my own fixture; cleared with `pbcopy < /dev/null` and it
  now reports one empty text item. Note that the reviewer's round replaced a `public.url` item of
  Pete's with plain text, which is recorded in their report.
- **Fixtures.** Three in `integration-scratch/shots`, plus one `-annotated.png` output and one draft
  created by the race probes' clicks landing inside the editor. All deleted; `[watcher] removed`,
  `[draft] forgot Screenshot f1.png`, `[drafts] 20` — Pete's count, none of mine left.
- **The lock.** Taken at 23:46:45, released at 00:15:56. One round. Pete's build (pid 57473) was
  killed only while I held it.
- **The state of the Mac.** Pete's build (`f57c330`, pid 71603) running on
  `/Users/petepetrash/.config/vignette/settings.json`, watching `~/Dropbox/Screenshots`,
  `[app] ready` at 00:15:56. No instance of mine. The lock is released. The probes
  (`dockprobe`, `raceprobe`, `raceround.py`) are in `integration-scratch/captures`.
