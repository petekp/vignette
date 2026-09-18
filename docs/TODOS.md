# TODOs

Things decided or raised but not built. Each entry says what, why, and what it waits on.

## Ship the agent skill with the app (decided 2026-09-16)

Someone who downloads the app needs their agent to learn the `shotnote://` contract, and the
app is the only thing they are guaranteed to have and the only thing that knows which commands
its version supports. So the app is the source of the skill.

- Bundle `skills/shotnote/SKILL.md` in the app the way `LICENSE-tldraw.md` is bundled (project.yml).
  The draft is in the appendix below; its repo home is `skills/shotnote/SKILL.md`.
- Offer it once. On first launch, when `~/.claude` or `~/.codex` exists, the first-launch toast
  offers the skill. A toggle in Settings, in a new "Agents" section, does the work: copy the skill
  into `~/.claude/skills/shotnote` and `~/.codex/skills/shotnote`, rewrite it on launch when the
  app is newer, remove it when the toggle goes off. `shotnote://install-skill` does the same for
  scripts and answers with one `[install-skill] ok|error` line.
- The installer never touches a skill directory it did not create. Mark its own copies (a
  sidecar version file) so a hand-linked copy is left alone.
- Publish the same file on skills.sh from the public repo, as herdr does, for Cursor and whatever
  else people run. Waits on the public repo.
- Default: detected and offered, not silently installed. Writing into another tool's config
  directory needs a yes, even if the yes is one click on the toast.
- Not doing: an MCP server (a config step in every agent and a second protocol beside the URLs;
  revisit if a non-Claude, non-Codex user asks) and writing into anyone's CLAUDE.md.
- On this machine the installer replaces the manual link. Until it exists, link
  `claude-code-setup/skills/shotnote` to `~/Code/shotnote/skills/shotnote` and run
  `gen-skills-manifest.sh`; the agent-browser skill is owned by skills.sh and must not carry this.

## Open from the same session

- `shotnote://add?file=<path>[&annotate]` is built, unit-tested, and verified live, and not yet
  committed (Commands.swift, AppDelegate.swift, CommandsTests.swift, README.md, AGENTS.md).
- The skill checks the `help` list for `add` and falls back to saving into the watch folder, so a
  newer skill on an older app still works.

## Discussed, not decided

- `shotnote://marks?file=`: print the stored draft's shapes as markdown, one line per shape with
  its type and percent position, and put the same block on the pasteboard beside the PNG in Copy
  Annotated. Verified by hand on 2026-09-16 with `jq` over a draft: one ellipse, center x 26%,
  y 30%, enough to crop the marked region from the original. Per-mark crops are the follow-on.
  Pete: keep using the app and see whether the need shows up.
- A vendor's own logo on the agent badge (Claude, ChatGPT) instead of the one fallback glyph.
  `Agent.symbol(for:)` is the lookup, empty today. Those logos are trademark assets Pete has to
  review before they ship, so it waits on that, not on code.
- Agent pushes piling up in the screenshots folder: a name rule or a second watched folder. Only
  if the push loop proves itself in use.
- A name convention for pushed files, `Agent <what> <state>.png`, so the card reads at a glance.

## Queued by Pete, 2026-09-16 (before sleep)

All nine landed on 2026-09-17 and are merged; docs/overnight-2026-09-17.md has the verification
and the open questions.

1. Remove the dotted outline placeholder when an image leaves the stack. A blank space is fine.
2. Add nuance to the spatial transitions: arc and depth, so a card does not move on a single
   vector but has subtle character, charm, and elegance.
3. The orange "edited" badge is probably not needed. Remove it for now.
4. Let agents annotate when they add an image, in a way the human can edit afterward, the same
   way user-annotated images work (go back and edit the shapes and text).
5. The control bar under the stack gets lost. Position it closer to the selected thumbnails: to
   the left, vertically centered between the topmost and bottommost selected card, with the
   controls arranged vertically.
6. Drop the count from the control bar; put the count in the circular selection indicator on
   the cards instead.
7. Stitch animation: the selected thumbnails leave the stack and conjoin into the stitched
   image, which takes its place at the bottom of the stack, or opens in the annotator when that
   is enabled. The choreography needs more thought; do an initial pass.
8. A purple robot icon on images an agent added, or the vendor's logo (Claude, ChatGPT) with the
   robot as the fallback for unknown vendors. Probably an `agent` parameter on `add`.
9. A way to send an image to Claude or Codex automatically instead of copy and paste: in the
   annotator, a call to action to send it to an agent the app detects. Explore how to do this
   robustly, with high confidence, before building.

## Queued by Pete, 2026-09-17

Items 1 to 6 landed on 2026-09-17 on `todo2/integration` and were merged into `foundation` that
evening; docs/run-2026-09-17-daytime.md has the verification, the open questions, and the review.
Items 7 to 17 landed on the evening of 2026-09-17 on `todo4/integration` and were merged into
`foundation` that night; docs/run-2026-09-17-evening.md has what landed, how it was driven, the
decisions, the open questions, the incidents, and the review. Items 19 to 22 landed in the night
of 2026-09-17 to 18 on branch `todo5/integration` (tip d1870d3, worktrees under
`~/Code/shotnote-todo/`), reviewed and fixed, with an architecture sweep of everything since the
foundation review, not yet merged; docs/run-2026-09-17-night.md on that branch has the
verification, the open questions, the review, and the sweep's refactors and design questions
for Pete. Item 18 is written as a draft skill, `shotnote-todo-run`, in the setup repository
(`~/Code/claude-code-setup/skills/shotnote-todo-run`, uncommitted, awaiting Pete's review of
its outline).

1. Drag-selecting in the stack should auto-scroll when the drag nears the top or bottom edge of
   the column, so cards that are off screen can be selected in one gesture, the way iOS does it.
2. Transition imperfections. Thumbnail shadows appear suddenly after a card returns from the
   annotator to the stack. If the cursor is over a thumbnail when a card lands in the stack, it
   flickers or flashes. On the way into the annotator, the shadow under the annotation image's
   frame flickers.
3. Selection numbers should count in the order the cards were selected, not top to bottom. Today
   the number is the card's position oldest-first so it matches the stitch badge; decide whether
   stitch order follows selection order as well.
4. A strange sweeping blur element appears to the left of the stack and sweeps to the right. To
   reproduce: summon the stack, hover over some thumbnails, dismiss it, summon it again, keeping
   the cursor inside the stack area throughout; sometimes it takes one more dismiss and summon.
5. Zoom in the annotator should zoom toward the cursor, not always the image's center: with the
   cursor near the top left, the image should zoom into that area. Look for other zoom nuances
   worth matching too; the goal is to feel like macOS's native image zooming.
6. After annotating an image, dismissing it, and reopening it, be more deliberate about which
   tldraw tool starts active. Proposal: always default back to the selection cursor. Today
   `REOPEN_TOOL` in `web/src/config.ts` is the arrow.

7. Summoning the stack should focus the newest card at once, so keyboard navigation works
   immediately without a first click or arrow press.
8. The number inside a selected card's circular badge looks too heavy and too widely spaced.
   Use a tighter, crisper numeric style (a font designed for integers, with tabular or
   proportional digits as appropriate) so the digit reads cleanly at that size.
9. While annotating, the stack should shrink to make room when the annotation image's frame
   grows far enough to touch it. The stack has a minimum width of about half its default width
   so it never shrinks too far, and the image frame never grows into that minimum.
10. Annotation queue. Selecting several cards and pressing Return, or clicking the annotate
    button, queues them: finishing one moves on to the next in the list until all are done. The
    cards stay selected throughout so the user can copy or stitch them afterwards.
11. Pressing Space while hovering a card selects it, and Space over each further card adds that
    card to the selection, so a selection can be built from the mouse position without clicking.
12. Hovering the vertical selection strip (the toolbar beside the selected cards) grows it to the
    right to show a label next to each icon. The button under the cursor must stay under the
    cursor while the strip grows: hover Copy, and Copy is still under the mouse once the labels
    are out. Open question: the strip sits to the left of the cards, so labels to the right of the
    icons run toward the column; decide whether the icons shift left to make room or the labels
    overlay the gap.
13. The Copy button among a card's hover actions shows only its icon; its label appears on hover.
    The reveal must be refined and additive, per the product's motion principles (a spring that
    keeps its velocity when interrupted and blends into the new target, through the motion
    scale), so a cursor that passes over and leaves mid-reveal never jumps.
14. Remove the circle (ellipse) tool. It is redundant with the rectangle: on software
    screenshots most things are boxes, so there is no reason to reach for a circle. The tool list
    is `web/src/config.ts`; the native toolbar takes its tools from the page's `ready` message.
15. Hide the colour palette by default and draw in red only. Then look into a heuristic that picks
    a different colour from the background under the drawn shape, so a minimum contrast ratio is
    always met (red on a red or dark-red region would switch), without the user choosing.
16. Look into the most legible way to compose a stitched image for an LLM (vertical or grid
    layout, gap and padding, badge size and placement, separators, downscaling limits, whether a
    label per piece helps) and let that inform how `Stitch.swift` composes the output. Today the
    gap, padding, and badge are fixed numbers in code.
17. Zoom the annotator the way Photos and Quick Look do: a native stand-in during the gesture,
    the page only at rest. Decided 2026-09-17 after three passes on the current design (window
    frame in Swift, picture in WebKit's process, stretched bitmap between relayouts) left it
    janky; those two drawers have no shared frame clock, so they can never be perfectly aligned.
    Design:
    - At rest the page is what is seen and edited, as now, with its web view sized to the frame.
    - The first zoom input covers the page with a native stand-in inside the frame: the screenshot
      at its native pixels, the annotations as a transparent overlay the page exported earlier,
      the frame's rounded mask and shadow. One Core Animation layer tree, scaled by the existing
      zoom spring at the display's rate, so frame and picture are one thing.
    - `Zoom.split` stays the single mapping from level to (frame scale, picture scale); the
      stand-in and the page both render from it. The pull below the fitted size stays.
    - When the spring arrives, the web view is resized to the frame and the page is given the
      exact camera; when it confirms the paint, the stand-in crossfades out (short, motion
      scaled; a hard swap with motion off). The page is covered, never hidden, so its frame
      callbacks keep running.
    - The overlay is the existing export's "annotations alone on a transparent canvas", at a
      capped pixel size, re-exported after each change and at load; the last one is used if a
      new one is still rendering; with no annotations there is no overlay.
    - Esc, Done, and a swap from a zoomed state spring home first, then fly, as today.
    Deleted: the web view's transform scaling, the relayout cover and its deadline. Kept: the
    transition reducer, `OutsideClick` against the frame, `[state]` keys, protocol bump on both
    sides for the new page calls. Acceptance is Pete's own trackpad: pinch and Cmd+scroll track
    the fingers with no lag, no misalignment, crisp throughout, and an invisible swap at rest.
    The working brief, with the order of work and the acceptance bar, is
    docs/zoom-native-brief.md.
18. A skill that automates the multi-agent run used on 2026-09-16 and 2026-09-17: Fable plans,
    briefs, orchestrates, and reviews; Opus subagents do the code and the verification. The skill
    takes a base branch and a list of TODO items, groups them by the files they touch, creates a
    folder outside the checkout with one worktree and one scratch settings file per agent (seeded
    from the real settings, own shots folder, debug on, Apple sync off), writes the shared brief
    and the item files from templates carrying the rules now in AGENTS.md (one launch at a time
    behind a lock, address URLs to your own build, check the settings file in the state line
    before any action, restore the user's build after every round), spawns the agents, then an
    integrator (merge in order, build and tests after each merge, smoke round), then an
    adversarial reviewer, routes confirmed findings back as review-fix commits, commits a run
    report under docs/, hands the branch over, and prunes worktrees and branches once merged.
    Shared between Codex and Claude Code through the setup repository's manifest, with the
    Claude-only launcher scoped to Claude. Bootstrap prompt from 2026-09-17 is the first draft of
    its instructions.

19. Zoom should keep the edge or corner under the cursor in view. Pete, 2026-09-17 evening, on
    the todo4 build: "even when putting my cursor near a corner and zooming, the corner of the
    image I'm hovering still gets pushed out of frame; I'd probably need my mouse to be within a
    few pixels of the corner to keep the corner from getting cropped. Can we somehow bias towards
    keeping the edges/corners anchored so it's harder for them to get cropped?" Today the anchor
    is the cursor's fraction of the window (`ZoomAim`, `ZoomPan` in `Sources/Zoom.swift`), so a
    cursor near a corner but not on it lets the corner slide out once the picture magnifies past
    the window. Bias the anchor toward the nearest edge or corner when the cursor is within a band
    of it, so the edge stays in view; the band and the pull are numbers a user would tune.
20. The selection strip's hover reveal slides left as it grows. Pete: "the hover transition is
    great. The only change we need is that it also translates to the left in tandem with the width
    increase, so that it doesn't overlap the thumbnails." The strip keeps its right edge where it
    is and extends to the left, so the labels never cover a card. The icons move left by the reveal,
    and the row under the cursor is still the same button because the label is part of it.
21. "Draw" replaces "Annotate" in user-facing language: the strip's button, the settings window,
    the menu, the README's user-facing lines, and any toast. The card's hover hint already says
    "Draw". URL ids (`shotnote://annotate`), log tags (`[annotate]`), and code identifiers stay
    unless a rename is trivial and touches nothing an agent or script depends on.

22. Zooming the annotator image looks like it arcs near the start. Pete, 2026-09-17 evening, on
    the merged build: "when zooming the annotator image, it seems to be doing the arc motion near
    the beginning of the transition. In this specific interaction we do not want any arc. If this
    isn't the arc, then there's some kind of unexpected jerkiness near the beginning we need to
    address." The flight arc (`FlightCurve`, `ui.flightArc`) is applied only to card flights in
    `TransitionLayer`; the zoom's frame comes from `Zoom.frame` under one spring, so the cause is
    somewhere else. Candidates: the anchor blend from the previous aim to the cursor on the first
    step (`ZoomAim`), the stand-in going up on the first input (a mismatch between the page and the
    stand-in for a frame), or the spring's start. Measure with the 60 fps method from
    docs/zoom-2026-09-17.md (per-frame position of the frame's edge and of a stroke inside the
    picture) before changing anything, then remove whatever moves sideways or steps.

## Feedback on the run-2 branch (Pete, 2026-09-17 afternoon, on `todo2/integration` c43304a)

All four landed the same afternoon on `todo2/integration`, reviewed and fixed (tip f59cec8); the
Round 3 section of docs/run-2026-09-17-daytime.md on that branch has the measurements, the
review, and the open questions. Pete runs that build from `~/Code/shotnote-todo/pete-build/Shotnote.app`.

1. Reopening an annotated image should start on the select tool and also select the last shape
   that was added, so the next colour press or delete acts on it.
2. Zooming the annotator is still janky: the image inside the frame is often out of sync with
   the frame, the layout jumps and skips while zooming, and it sometimes sticks at a position or
   size that does not match the frame. Re-evaluate how zoom is done from the bottom up.
3. The transition glitches are still there: thumbnail shadows flicker once the annotator
   transitions back into a thumbnail, and on the way in the shadow under the annotator flickers.
   Direction: keep the same shadow across states and give each state its own shadow values,
   instead of handing the shadow from one thing to another.
4. In selection mode a card under a selected card does not respond to hover or clicks. Repro:
   select the second most recent card, then hover or try to select the most recent one.

## Open review findings from the overnight run, with the suggested fix (2026-09-17)

The reviewer's reasoning is in docs/overnight-2026-09-17.md, section 5. In priority order.
Findings 1 to 3 landed on `todo2/integration` on 2026-09-17 (1 and 2 through the page item, 3
through the transitions item); 4 stays as written.

1. The annotator can take the canvas while a `marks=` build is running. The page's `load` is
   fire-and-forget and sits outside the `oneAtATime` queue that `park`, `export`, and `build`
   share, so a `load` landing inside a build's render is undone when the build restores the
   canvas. Fix: queue `load` through `oneAtATime` too. It then runs after the build has put the
   canvas back, and `loaded` arrives a little later, which the flight already waits for before it
   lifts. Page only; no Swift or reducer change; the wait is bounded by the build's 15 s watchdog.
2. A draft whose preview PNG was purged from `~/Library/Caches` is invisible on its card now that
   the badge is gone. Fix: regenerate, do not restore the badge. At launch, after `[web] ready`
   and while the annotator is idle, run the headless export Copy Annotated already uses for every
   draft with no preview file, at preview size, and store the result. Normally that is zero
   renders. The preview stays a cache in Caches; the draft in Application Support stays the source.
3. Dismissing the stack mid-stitch leaves the pieces flying over the next app and suppresses both
   the Copied mark and the toast, so a successful stitch shows nothing. Fix: when the stack is
   dismissed while cards are converging, end those flights with it; and in the converge's
   completion, when the stack is no longer visible, show the existing "Stitched N images, copied"
   toast instead of skipping the Copied mark.
4. One `getxattr` per card on the main thread at stack open (`Agent.of`), about 4 µs each on APFS.
   Leave it. The card already stats each file for its pixel size on the same path. Measure on the
   real Dropbox folder before touching it; if online-only placeholders at a large `recentCount`
   ever make it show, read the attribute where the thumbnail decodes, off the main thread, and let
   the badge appear with the image.

## Appendix: skill draft (2026-09-16)

    ---
    name: shotnote
    description: Show the user an image through Shotnote, the screenshot tool on this Mac, and read back what they marked on it. Use when you want the user to see a screenshot or rendering you produced (agent-browser, screencapture, a before-and-after), when they ask to see what something looks like, or when you need their circled answer. Not for images the user captured themselves; Shotnote already shows those.
    ---
    
    # Shotnote
    
    Shotnote watches the screenshots folder, shows each new image as a thumbnail in the corner,
    keeps the last thirty in a stack, and lets the user circle things and press Return. Every command
    is a `shotnote://` URL that answers with one line in `~/Library/Logs/Shotnote.log`.
    
    ## Show the user an image
    
    ```sh
    open -g "shotnote://add?file=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "/abs/path/Agent checkout 390px.png")"
    ```
    
    - `add` copies the file into the watch folder and shows its thumbnail. It leaves the clipboard
      alone and does not open the editor, whatever the user's capture settings say. Add `&annotate`
      to open the editor instead, only when you are asking for marks right away.
    - `open -g` keeps focus where it is. Always percent-encode the path; `open` does not.
    - Wait for `[add] ok <name>` and then `[watcher] new <name>` in the log. The name gains a counter
      (`x 2.png`) when one already exists. Errors end with one of `missing-file`, `unreadable-image`,
      `unsupported-type` (png, jpg, jpeg, or heic only, never a `-annotated` name), `write-failed`.
    - Push what the user should see, not every screenshot you take. Name the file for them: what it
      shows, at what size or state.
    
    ## Read back what they marked
    
    When the user annotates the image and presses Return, Shotnote writes `<name>-annotated.png`
    beside the copy in the watch folder and logs `[annotate] done <name>-annotated.png`. Read that
    file. The folder is `screenshotsFolder` in `~/.config/shotnote/settings.json`.
    
    ## Is Shotnote running, and does it have `add`
    
    `open -g shotnote://help` logs a `[help]` line per command; none within a second means it is not
    running. If the list has no `add`, the app predates this skill: save the file straight into
    `screenshotsFolder` instead, which any version shows as a capture. `open -g
    "shotnote://state?tag=<id>"` logs one `[state] {json}` line carrying the tag.
