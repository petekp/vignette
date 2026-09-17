# Overnight, 2026-09-16 into 2026-09-17

Nine of the ten queued items landed. Four agents worked in parallel on four branches. All four are
merged into `todo/integration`, which builds and passes the tests, and which I drove live to check
the combined behavior.

Branch and merge commits:

| Branch | What it is | Merge commit |
| --- | --- | --- |
| `todo/stack` | items 1, 3, 5, 6 | `c0cb383` |
| `todo/agent-marks` | items 8, 4 | `aa9ce04` |
| `todo/send-to-agent` | item 9 | `66a3499` |
| `todo/motion` | items 2, 7 | `1dd292a` |

`./scripts/build.sh --test` passes on `todo/integration` at every merge and at the tip.

## 1. What landed

### No placeholder outline when a card leaves the stack (item 1)

A card in the annotator now leaves a plain empty gap. The slot itself stays, so the card flies back
to the same place. `todo/stack` commit `8dcf523`, in `StackView.swift`.

Verified in the combined build: `annotate?file=Screenshot test 1.png`, then a crop of the slot.
`[state]` had `out: true` for that card and the crop showed nothing in the gap, no outline and no
fill. `cancel` returned the card into the same frame, `[1307, 193, 188, 120]` before and after.

### The orange draft badge is gone (item 3)

A card whose annotations you parked shows them in its thumbnail instead of wearing a pencil badge.
The draft, the preview, and Copy Annotated are untouched. `todo/stack` commit `08b62ae`.

Verified: after `add?…&marks=…` built a draft, the card showed the three marks in its thumbnail and
carried only the purple agent badge. No orange badge anywhere in the round.

### The selection controls stand in a strip beside the cards (item 5)

The bar under the stack is gone. Selecting cards opens a vertical strip of buttons (copy, copy
annotated, stitch, delete) to the left of the selection, centered on the span from the topmost to
the bottommost selected card. The panel widens to the left to hold it; its right edge never moves,
so the cards stay where they are. The geometry is `StackLayout.stripPlacement`, the number is
`ui.selectionStripGap`, and `[state]` reports the strip's frame. `todo/stack` commit `1eca607`.

Verified: three cards selected by clicking their circles. The panel went from `[1288, 36, 226, 876]`
to `[1245, 36, 269, 876]` — 43 points wider on the left, which is the strip's 35 plus the 8 point
gap — and every card frame was unchanged. `strip` was `[1264, 591, 35, 128]`, centered on the
selected span. The crop shows the four buttons in one vertical strip to the left of the three
selected cards.

### The selection count moved into the card's circle (item 6)

A selected circle carries that card's number in the selection, counting from the oldest, which is
the order actions receive them and the number Stitch draws on the badge. `todo/stack` commit
`314a63e`, with `StackModel.selectionNumber(of:)` and `Tests/StackModelTests.swift`.

Verified end to end: the crop of three selected cards showed 1, 2, 3 top to bottom, and the stitched
output carried red badges 1, 2, 3 on the same three images in the same order.

### A purple badge for an image an agent pushed (item 8)

`add?file=…&agent=<name>` records the name on the copied file as the
`com.petepetrash.shotnote.agent` extended attribute, so it survives a rename or a move on the same
volume. The card shows a purple `cpu` badge in its top-right corner, and `[state]` reports `agent`
per card. `todo/agent-marks` commit `9566bd6`, `Sources/Agent.swift`.

Verified: `[add] ok Agent push.png agent=claude marks=3`,
`xattr -p com.petepetrash.shotnote.agent` returned `claude`, `[state]` had `agent: claude`, and the
crop shows the purple chip badge in the corner.

Vendor logos (Claude, ChatGPT) are not bundled. `Agent.symbol(for:)` is the lookup and it is empty
today; every vendor falls back to `cpu`. The reason is in `docs/TODOS.md`: those logos are trademark
assets you have to review.

### An agent pushes its own annotations (item 4)

`add?file=…&marks=<json file or inline json>` turns an agent's marks into a real draft before the
card appears. The marks are fractions of the image, so they do not depend on its pixel size. Types
are ellipse, rectangle, arrow, and text; colors come from `web/src/config.ts`. The page builds the
draft on its own canvas through a new `PageAPI.build` (`window.shotnote.build`), so the snapshot is
tldraw's own schema and not hand-written Swift. Protocol 5 became 6 on both sides. A bad `marks`
value answers with the new `invalid-marks` code. `todo/agent-marks` commit `11c359d`.

Verified: a push with an ellipse, an arrow, and a text answered
`[add] ok Agent push.png agent=claude marks=3` and `[draft] built Agent push.png`. The card's
thumbnail showed all three marks. Opening it reported `page shapes: 4` (the image plus three marks)
and `canUndo: false`, so loading the draft stayed out of undo history. Return exported
`Agent push-annotated.png` at 1760x1080 with all three marks in place.

Because the page borrows its canvas to build, a marked push is refused with `page-not-ready` while
you have an image open in the annotator. That is by design and is in the README.

### Send a screenshot to a coding agent (item 9)

The research is `docs/send-to-agent-exploration-2026-09-17.md`: what Claude Code and Codex accept
today, herdr, the desktop apps, the Accessibility last resort, and what an image costs in tokens.
The recommendation is herdr, because it is the only route where Shotnote knows which agent it is
talking to, aims the delivery at that pane, and gets told when it fails.

The prototype is behind `debug`: `shotnote://send?file=…&to=<agent or pane>&text=<words>` runs
`herdr agent list`, picks the target by name or pane id (the focused pane's agent without `to=`),
and submits one line with the path. Codes `no-agent` and `send-failed`. `Sources/Send.swift`,
`Tests/SendTests.swift`. `todo/send-to-agent` commit `eafd79b`.

Verified in the combined build with a target that matches nothing:
`[send] error no-agent no agent "nobody"; herdr has: herdr-config-names(claude) …` — seventeen real
agents listed and nothing sent to any of them. I did not send to a live pane.

The CTA itself is not built. The exploration describes where it would sit (next to Done in the
annotator toolbar, naming the agent it will hit) and what has to be true for it to feel good.

### Arc and depth on a card's flight (item 2)

A card no longer runs down a straight line into the annotator. `Sources/FlightCurve.swift` bows the
path to one side and swells the card, both peaking in the middle and both exactly zero at the ends,
so the card still leaves and lands where the layout puts it. `ui.flightArc` (0.08), `ui.flightArcMax`
(64 points), and `ui.flightDepth` (0.05) are the numbers, with sliders under Flights in the tweak
panel. The motion scale multiplies the arc and the depth, so `motion: 0` and Reduce Motion give a
straight line. `todo/motion` commit `7f12674`.

The motion agent measured it: twelve mid-flight captures with `expandDuration` at 1.2 s matched the
curve within about a point at every sample, endpoints exact, apex 49 to 50 points on a 652 point
flight, swell peaking at 1.048. With `motion: 0` the flight is instant, 7 ms.

I re-checked it in the combined build rather than re-measuring: three full-screen captures during
one flight show the card off the straight line between corner and center, growing as it goes, and
the transition log reads `annotate → flyingOut → shown → annotating` with `[annotate] loaded 1511ms`.

### The stitch conjoins its cards (item 7)

Stitching from the stack is one motion now. The selected cards leave the column, fly into the slot
the new card holds at the bottom, and the finished image fades in under them. Both sets sit in
`model.forming` while their image is in the transition layer, so a slot keeps its place and draws
nothing and no image is ever on screen twice. The watcher's later report of the file is a no-op
because the card is already there; with `annotateOnCapture` on, that same report carries the new
card into the annotator. `todo/motion` commit `6e21f13`.

Verified in the combined build, and this is the one path that crosses two branches: I selected three
cards (the strip out, circles numbered 1, 2, 3) and pressed Cmd+S on the keyboard, which the motion
agent had not tried — it drove the URL instead. `[stitch] ok … from 3 images, 265816 bytes, copied`
and `[stack] stitched cards=3 into=Stitch ….png`. Two mid-flight captures show the three pieces
converging on the bottom-right slot with the tall stitched image fading in behind them. Afterwards
the new card sat at the bottom, `[1375, 740, 120, 153]`, the three originals were out of the stack,
and no card was left `forming`.

### What stayed unverified

- Live Reduce Motion switching, an interrupted flight retargeted mid-air, overlapping stitches,
  dismissing the stack mid-converge, and stitches of more than three cards.
- The `send` success path. Nothing was sent to a live agent on purpose, so only the `no-agent`
  branch is exercised end to end. The success path has unit tests and the exploration's manual
  probes behind it.
- Everything above was checked on one screen, at one scale, with `motion: 1`. I did not repeat the
  round on the Studio Display.

## 2. Decisions made without you, and open questions

I had the motion agent's decisions by message. For the other three branches I took the decisions
from the code and the docs on each branch; they are described as what the code does.

### Stack (items 1, 3, 5, 6)

Decisions:

- The strip holds the actions whose placement is `.strip` or `.everywhere`, in the order they appear
  in `Config.actions`: copy, copy annotated, stitch, delete. The `.bar` placement was renamed
  `.strip` throughout.
- The strip is clamped inside the visible column. A strip taller than the visible column centers on
  it instead of hanging off an edge.
- Only the column carries the hair of alpha that catches clicks and scrolls. The strip's side of the
  widened panel stays clear, so a click there still reaches the window underneath.
- Numbering counts from the oldest selected card, so the circle predicts the badge Stitch will draw.

Open questions:

- `ui.selectionBarHeight` still exists and now means only the toast row under the column. Two
  numbers with similar names is a smell; merge or rename when you next touch that code.
- The strip's 8 point gap and its centering rule are a first pass. The slider is Selection strip gap
  in the tweak panel.

### Agent marks (items 8, 4)

Decisions:

- The agent name lives on the file as an extended attribute, not in a database. It survives a rename
  and a move on the same volume and needs no sweep; a copy through a tool that drops attributes
  loses it and the card is then plain.
- `agent` given with no name still marks the card. A name is trimmed to one line and 64 characters.
- The page builds the draft, Swift never writes tldraw records. `park`, `export`, and `build` run one
  at a time on the page, and a build is refused while an image is open in the annotator.
- `render()` waits 250 ms for the first font, so a text mark does not export in the fallback face.
- The transition reducer knows nothing about a build. Nothing is shown, so no card, dim, or flight
  is involved.

Open questions:

- Vendor logos need your trademark review before `Agent.symbol(for:)` can return anything but `cpu`.
- Agent pushes will pile up in the screenshots folder. A name rule or a second watched folder is in
  `docs/TODOS.md`, parked until the loop proves itself in use.
- The mark vocabulary is four types. Per-mark crops (sending an agent only the marked region) are
  noted in TODOS as the follow-on.

### Send to an agent (item 9)

Decisions:

- herdr over every other route, and the image travels as a path rather than through the pasteboard.
  The pasteboard variant stays as the answer for a file the agent has no permission to read.
- `send` is debug-only. Without herdr it is one `no-agent` error and nothing else in the app depends
  on it.
- No CTA in the toolbar yet. The exploration argues for one next to Done, but it wants a
  `herdr agent list` call when the annotator opens, which is a design decision rather than a patch.

Open questions, from the exploration:

- Does a send carry the annotated export or the original? The prototype takes `file=` explicitly.
- Should the send wait for the agent to settle (`herdr agent prompt --wait`) so a toast can say
  "answered" or "asked for permission"? It blocks for as long as the agent thinks.
- Should Shotnote only offer agents you have named in herdr? Names are what make the list readable;
  there were seventeen agents running tonight.
- Is the focused pane the right default, or the most recently idle agent?

### Motion (items 2, 7)

Decisions:

- The bow's side is a property of the line, not of the direction of travel: up for a mostly
  horizontal path, left for a mostly vertical one, with the boundary at 45 degrees. A flight that
  turns around mid-air therefore stays continuous.
- Scale, not shadow, as the depth cue.
- The defaults 0.08 / 64 / 0.05 were chosen by reasoning, not tuned live.
- The stitched originals leave the stack and do not come back until the next open. Their files are
  untouched on disk.
- "Copied" on the new card replaces the "Stitched N images, copied" toast.
- No stagger between the pieces in this pass, and no change to the transition reducer.

Open questions:

- Is 8 percent bow and 5 percent swell right? The sliders are under Flights in the tweak panel.
- Should the stitched originals come back into the stack?
- Keep the toast removal?
- Should the arc apply to the stack's slide-in? It was left alone on purpose: thirty staggered
  bowing cards would read as wobble.

Second-pass ideas the motion agent listed: map each piece to its own band in the new image, stagger
oldest first, let the merged image show its tall aspect for a beat, hand the card straight to
`annotate` instead of waiting for the watcher, and revisit the crossfade timing.

## 3. How to take it

Your checkout has the `add` change uncommitted. It is identical to commit `7977453` on `todo/base`,
so it is already in the merge. Clear it, then merge:

```sh
cd ~/Code/shotnote
git stash                       # or: git checkout -- . && rm docs/TODOS.md
git merge todo/integration
./scripts/run.sh
```

`git checkout -- .` leaves `docs/TODOS.md` behind because it is untracked in your checkout; remove it
first or the merge will refuse to overwrite it.

To take the branches one at a time instead, cherry-pick or merge them in this order: `todo/stack`,
`todo/agent-marks`, `todo/send-to-agent`, `todo/motion`. That is the order the conflicts were
resolved in, and out of order they conflict differently.

When you are done:

```sh
git worktree remove ~/Code/shotnote-todo/<each>
git branch -d todo/<each branch you do not keep>
```

## 4. Incidents

**Worktree builds ran against your real settings file.** Four worktrees build the same bundle id,
so a bare `open -g shotnote://…` goes to whichever copy LaunchServices registered last, and that
copy's launch replaces the running instance. Two agents hit this: roughly 23:35 to 23:54, and once
at 00:14:56. The builds involved were the stack and motion worktrees.

**Three settings keys were added to your real file.** `Settings.bootstrap` rewrites the settings file
whenever the encoded form differs from the file, which is how a missing key gets filled in. A build
carrying new `ui` keys that launches against your real file therefore adds them silently — there is
no `[settings] wrote ui.…` line for it. The three keys are `ui.flightArc`, `ui.flightArcMax`, and
`ui.flightDepth`. Nobody removed them. To remove them:

```sh
jq 'del(.ui.flightArc, .ui.flightArcMax, .ui.flightDepth)' ~/.config/shotnote/settings.json > /tmp/s.json && mv /tmp/s.json ~/.config/shotnote/settings.json
```

Worth knowing: once you merge `todo/motion` and relaunch your real build, those three keys come back
legitimately, with the same values. Removing them is only worth doing if you want to see the file
the way it was before the night.

I did not read or write that file, so I have not confirmed the keys are there. The `jq` above is
safe either way.

**The clipboard holds a test image.** The last thing the smoke round copied was
`Agent push-annotated.png` from my scratch folder: a screenshot of your own screen with three test
marks on it. Copy anything to clear it.

**Drafts.** My round left one draft for a fixture I then deleted; I relaunched once so the
launch-time sweep removed it (`[draft] swept Agent push.png`), and the store is back to your ten
real drafts. Earlier agents may have left similar entries; any draft whose file is gone is dropped at
the next launch.

Nothing was written to `~/Dropbox/Screenshots` or `~/.config/shotnote/` by me. Every fixture I made
is in `~/Code/shotnote-todo/integration-scratch/`.

## 5. Merge notes

Git stopped on fifteen conflict hunks across six files, and two more places stopped compiling
afterwards. Every resolution kept both sides:

- `Sources/Commands.swift`: `CommandRequest` carries `agent`, `marks`, `to`, and `text`; the error
  codes carry `invalid-marks`, `no-agent`, and `send-failed`.
- `Sources/StackView.swift`: the card's top-right badge is the agent badge only, since the draft
  badge was removed on purpose. A card that is `out` or `forming` draws an empty slot — the same
  answer for both, which is what the stack branch wanted for the annotator and the motion branch
  wanted for a stitch.
- `Sources/ThumbnailController.swift`: `[state]` cards report `out`, `forming`, `draft`, and `agent`;
  the stack section reports `strip`. `makeStitchedCard` reads the agent attribute like every other
  card, so the rule stays one rule.
- `Tests/StackModelTests.swift` and `Tests/CommandsTests.swift`: the new `Card` field and both new
  parse tests.
- `AGENTS.md` and `README.md`: every branch's sentences, merged into one description per behavior.

Two doc corrections came out of the merge: `AGENTS.md` named `StackLayout.selectionStrip`, which does
not exist (`stripPlacement` does), and the send exploration named `placement: .bar`, which the stack
branch renamed to `.strip`.
