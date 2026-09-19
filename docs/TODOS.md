# TODOs

Things decided or raised but not built. Each entry says what, why, and what it waits on.

## Ship the agent skill with the app (decided 2026-09-16)

Built on 2026-09-18 on branch `todo6/integration` (`skills/shotnote/SKILL.md` bundled, the
`agentSkill` setting with the Agents section, `shotnote://install-skill`, the ownership marker,
a root whose `skills` directory is a link refused); docs/agent-skill-2026-09-18.md has the
design as built and docs/run-2026-09-18.md the verification. Publishing on skills.sh still
waits on the public repo.

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

- Drawing on the live screen, both directions: an agent pointing at a window, an element, or a
  phrase on the real screen (demoed 2026-09-18, source in docs/live-screen-demo/), and a person
  drawing on the live screen so the agent gets a crop plus what the mark is on.
  docs/live-screen-2026-09-18.md has the demos, the three anchors, the limits, and the tradeoffs.
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

## Queued by Pete, 2026-09-18 (morning, on the todo5/integration build d1870d3)

All three landed on 2026-09-18 on branch `todo6/integration` (tip 4d96079), with the agent
skill above, the architecture sweep's refactors R1 to R4, the palette removal (D6), and the
preview cap (D3); docs/run-2026-09-18.md on that branch has the verification, the review, and
the open questions; merged into `foundation` that afternoon (f57c330). Still open from the sweep: D1 (after a park timeout the app
believes the canvas is free while the page still holds the image; two lines) and D5 (AGENTS.md's
length). Discussed, not decided: folding Copy Drawing into Copy, so one Copy gives the image as
the card shows it.

23. The zoom's edge hold works on the left and right edges only. Pete: "the zoom anchoring --
    where we have the image stick to one side of the frame while zooming -- is great but only
    seems to be working on the left and right edges. we want it on the top and bottom too. i'd
    also like to be able to adjust the parameters / thresholds for this behavior." The pull
    (`Zoom.pulledToEdges`) is the same code in x and y, but the band is a fraction of each side
    of the window, so on a wide screenshot the vertical band is a fraction of a short height:
    about 45 points on a 300-point-tall frame against 148 on its 986-point width. Candidate: make
    the band a fraction of the shorter side, or a number of points, so the reach is the same on
    every edge; measure `page.visible` at the top and bottom edges on a wide fixture before and
    after. The parameters exist as `ui.zoomEdgeBand` and `ui.zoomEdgePull` with sliders in the
    tweak panel (`open -g shotnote://tweaks`, needs `"debug": true`), and in settings.json; if the
    band changes unit, rename the key and its slider to say the unit.
24. More space between the selection strip and the thumbnail column, specifically beside the
    wider thumbnails. Pete: "add a bit more space between the thumbnail select toolbar and the
    thumbnail column -- specifically the wider thumbnails." The strip is placed against the widest
    selected card by `ui.selectionStripGap` (8 points), so a wide card has exactly that gap and a
    narrow one has more. Raise the default, or measure the gap from the widest card in the
    column rather than the widest selected one, so the strip does not step sideways when the
    selection changes; say which in the doc.
25. Double-click with the select tool zooms into that part of the image. Pete: "enable double
    tapping with the selection arrow tool in the annotator to zoom into that part of the image."
    Today a two-finger double tap (`smartMagnify`) zooms twofold at the tap or back to the fitted
    size; a mouse double-click reaches tldraw, which on empty canvas does nothing useful with
    the tools the toolbar shows. Send a double-click on the select tool through the same path as
    the smart zoom (the page reports it, or the host sees it first), aimed at the click, with the
    same twofold step and the same return home from above the fitted size; a double-click on a
    shape keeps tldraw's meaning (a text shape edits) so drawing is not disturbed.
## Queued by Pete, 2026-09-18 (afternoon, on the todo6/integration build 4d96079)

Items 26 to 28 landed overnight on 2026-09-19 on `todo8/integration` and were merged into
`foundation` that night (merge 6e0d622); docs/run-2026-09-19.md has what landed, how it was driven,
the decisions, the open questions, the incidents, and the Review section with the three findings the
reviewer confirmed and the integrator fixed.

26. The annotator's frame stops keeping the image's aspect ratio while zooming. Pete: "the
    zooming feels great. one thing i'd like to change: instead of keeping the aspect ratio
    locked, i'd prefer that we unlock it and allow the height or width to change to optimize
    the visible surface area of the image, within the constraints of the space available to the
    annotator. for example, if we're annotating a very tall and narrow image, right now if i zoom
    in, it remains narrow, and large chunks of the left and right of the image are cropped. i'd
    prefer the image width continue to grow up until the image is all the way zoomed in, or it
    hits the boundaries." Today `Zoom.split` divides the level between one uniform window scale
    and the camera, so the frame keeps the image's shape and stops growing when the first axis
    reaches the room. Instead the picture is magnified uniformly by the level and each axis of
    the frame grows with it until that axis reaches the room: width `min(fitted.width * level,
    room.width)`, height `min(fitted.height * level, room.height)`, so a tall image's frame
    widens to the room's width while the picture is still entirely inside it, and only then is
    it cropped in that axis. Touches: `Zoom.split`, `Zoom.frame`, `Zoom.reach` and the anchor
    arithmetic (a reach per axis; the room binds one axis at a time), the pull below the fitted
    size, the stand-in's picture rect, `setView` and `page.visible` (the visible part is no
    longer the same fraction in both axes; "zoom 1 = the image fills the window" has to be
    restated), `fitBeforeHide` and the flight's start frame, `annotatorRoom` and the stack's
    `widthScale(clearing:)`, the edge hold (a band in points still works), and the zoom doc.
    Acceptance is a tall narrow screenshot and a wide short one on Pete's trackpad: zooming in
    grows the frame in both directions until each hits the room, the picture is never stretched,
    Cmd+0 comes home to the fitted frame, and the stand-in and the page agree at every rest.

27. The annotator's toolbar stays put across a swap and slides to the next image. Pete: "when in
    the annotator, if the user switches between images, let's try to keep the tldraw controls
    stable between images and just have it translate up or down depending on the height of the
    incoming image, as opposed to rendering brand new control element each time." The controls
    are the native toolbar panel (`AnnotatorToolbar.swift`), placed under the window by `prepare`
    and taken down with the window, so a swap (a click on another card, or the queue moving on)
    hides one toolbar and raises a new one with the next image. Instead, while one session
    follows another with no gap, the toolbar panel stays on screen and its frame springs to the
    next image's place (down or up with the height, sideways if the fitted frame's centre moves),
    through the motion scale, timed with the two flights so it arrives as the window comes up.
    It comes down only when the session ends (Esc, Done on the last image, a dismissal). Its
    tool state follows the incoming image as today (the rectangle for a fresh image, select for
    one with a draft). Touches `AnnotationController.prepare`/`show`/`hide`, the transition
    reducer's swap effects (a sequence in `AnnotatorTransitionTests` before changing the table),
    and the annotator's docs.

28. A pushed text mark wraps inside the image and is sized for it. Pete, on the first real
    push from an agent (2026-09-18): "your text got cut off. how can we avoid that?" `build` in
    `web/src/App.tsx` creates a text shape with no width, so tldraw auto-sizes it as one line
    that grows to the right and runs off the image, and with `DEFAULT_SIZE` whatever the image's
    pixel size, so a sentence on a 900-px crop is huge and on a 5K capture is tiny. Fix: a text
    mark takes `w` (a fraction of the image, like the shapes; the README and the skill say so),
    defaulting to the room between `x` and the right edge less a margin, created with
    `autoSize: false` so it wraps, and its font size chosen from the image's pixel width so it
    reads the same on a crop and a full capture; a mark whose box would leave the image is
    pulled back inside. The export and the preview then never crop a pushed text. Verify with
    the exact marks that produced the cut-off (`[add] ok Agent strip labels, gap to the card.png
    agent=claude marks=3`, text at x 0.30 on a 900x1087 image).


## Queued by Pete, 2026-09-18 (evening, on the foundation build f57c330)

Items 29 to 34 landed on the night of 2026-09-18 on `todo7/integration` and were merged into
`foundation` on 2026-09-19 (merge 6e0d622); docs/run-2026-09-18-evening.md has what landed, how it
was driven, the decisions, the open questions, the incidents, and the Review section with the six
fixes that followed the review. Item 35 is not landed: the video was cut on the merged build and
lives outside the repository, with its notes, because a video file is not something to commit
without Pete's say.

29. The card-to-annotator transition can be interrupted. Pete: "make the thumbnail -> annotator
    transition interruptible." Today `prepare` flies the card and the reducer sits in
    `flyingOut` until the flight's `arrived` sends `shown`; an Esc, a click on another card, or a
    click outside during the flight still goes through `park` on a page whose window has not
    come up, so the card finishes its outbound flight before anything turns it around. Instead a
    `close` or an `annotate(other)` in `flyingOut` turns the flight around where it is: the same
    `fly(id:to:)` re-aim the zoom already uses (the `Bow` blend keeps the curve continuous), the
    dim comes down with it, and the page's `load` is either cancelled or left to finish and
    parked with nothing drawn. A swap mid-flight sends the second card out while the first flies
    home, the same two flights as a queue swap. Touches the reducer's `flyingOut` branch (a
    sequence in `AnnotatorTransitionTests` before changing the table: `annotate, close` with no
    `shown` between them, and `annotate a, annotate b` likewise), `perform(.prepare)`, the
    `arrived` guard, `loadedKeys`, and `AnnotationController.hide` (a park for a page that never
    showed answers at once). Acceptance is Esc pressed halfway through the flight on Pete's
    machine: the card comes straight back with no pause at the annotator's frame, and the window
    never flashes up.

30. The wait between the card landing and the image being editable is shorter. Pete: "see what we
    can do to decrease the time between the thumbnail -> annotator transition coming to a rest
    and being able to draw/manipulate the image; there's a noticeable delay here possibly due to
    our easing transition and gating interaction." Two gates today: the window comes up at
    `Anim.settle` (the spring within half a point of the target), which for `expandDuration`
    0.4 is well past the visible motion, and the flight image stays on top until the page
    reports `loaded` (`show` lifts it only when `loadedKeys` has the key, else `pageLoaded`
    does). Until the lift the flight image sits over the web view, and the key window and the
    outside-click monitor start only in `show`. First measure it: on the driven sequence, the
    gap from the last frame the card moved to `[annotate] loaded` and to the first pointer event
    the page accepts (an `eval` that reads a hovered shape, or a `drag` from `scripts/input.sh`
    followed by `page.shapes`), and the `settle` time against the frame at which the eye sees
    the card stop (`screencapture -v` and the edge position per frame, as in the shadow doc).
    Then whichever is the larger part: put the window up and hand the keys over earlier,
    accepting the sub-point step, or make the step invisible by having the window take the
    flight's exact last frame; send `load` earlier (it is sent in `prepare`, so the page's own
    decode is the floor); or tighten the spring's tail (`bounce` 0.15 and the tolerance in
    `TransitionLayer.arrivalTolerance`) so `settle` comes sooner. Report the before and after
    numbers in the doc. Acceptance is that a rectangle dragged the moment the card looks still
    lands on the page.

31. The stack runs to the bottom of the screen and the newest card steps around the Dock. Pete:
    "see if we can avoid cutting off the thumbnail stack near the top edge of the dock and
    instead have it continue all the way down to the bottom of the screen; if it collides with
    the dock, the bottom most thumbnail should 'avoid' the dock as if there were a safe area."
    Today `StackLayout.panelFrame` and `viewportHeight` are measured from the screen's
    `visibleFrame`, which stops at the Dock's top edge, so with the Dock at the bottom the
    column ends `screenMargin` above it and the cards below that line are simply not there.
    Instead the column is measured from the screen's full `frame` (the menu bar still excluded),
    so the viewport and the column mask run to the bottom of the screen, and the cards keep a
    safe area around the Dock: the newest card rests above the Dock by the margin when the
    column's right edge is over the Dock, the way it rests on the viewport's bottom edge today,
    and the older cards scroll behind the Dock's top edge rather than stopping at it. A Dock on
    the left or right, or hidden, changes nothing (the column is not over it). The bottom fade
    in `StackView.column` and `cardShadowRoom` move with the newest card, so its shadow is still
    whole. Touches `panelFrame`, `viewportHeight`, the strip and the annotator's room
    (`annotatorRoom` and `annotationFrame` keep using `visibleFrame`, since the annotator must
    not go under the Dock), `TransitionLayer`'s slot frames, and the backdrop strip's height.
    Verify with the Dock at the bottom, magnified and not, and with it hidden, and with a stack
    long enough to scroll; the `[state] stack.viewport` and the card frames say where the
    column ends.

32. Selecting cards from the keyboard brings the strip's labels out, with each action's shortcut
    beside its label. Pete: "when selecting thumbnails in stack mode with a keyboard using
    directional arrows, we should auto-expand the selection toolbar to show the labels along
    with keyboard shortcuts to perform the particular functions." Today the labels come out on
    hover only (`model.stripHovered`, set by `onHover` in `StackView`'s strip), and the shortcut
    is a tooltip (`shortcutHint`), so someone building a selection with Shift+arrows or Space
    sees six icons and no hint of what a key would do. Instead a selection made from the
    keyboard (`moveFocus(toward:extend:)` and the Space branch of the key handler) reveals the
    labels the way the hover does, and each row shows its shortcut after the label in the
    tooltip's glyphs (⌘C, ↩, ⌥⌘C, ⇧⌘C, ⌘S, ⌘⌫), dimmer than the label. The reveal stays
    while the stack holds the keys and the selection came from them; the mouse moving onto a
    card or the strip takes over as today. One state says why the labels are out (`stripRevealed`
    with a reason, hover or keyboard, replacing the bool), and `[state] stack.stripHovered`
    becomes that. `stripReveal(labels:)` measures the widest label plus its shortcut, so the
    panel already holds the room and nothing is resized. Touches the strip in `StackView`,
    `StackLayout.stripReveal`, `stripPlacement`, the key handler in `ThumbnailController`, and
    docs/hover-reveal-2026-09-17.md. Acceptance: open the stack, press Shift+Up twice, and the
    strip's labels and shortcuts are out without the mouse moving; press ⌘C and the copy runs.

33. The card's Draw hint stays up except over the corner buttons themselves. Pete: "change the
    thumbnail tooltip deadzone so that it only affects the buttons in the corners and not the
    entire bottom third of the thumbnail." Today `inButtonRow` in `CardView` (`StackView.swift`)
    hides the hint whenever the pointer is in the band along the card's bottom, `buttonSize` plus
    the 6-point padding tall and the card's full width; on a short card that band is a third of
    the picture, and the middle of it holds no button. `overControl` already goes true on the
    buttons' own hover, so the band's only job is to cover the moment before that hover lands.
    Instead the dead zone is the two corner rects (each button's frame plus its padding, bottom
    left for Copy and bottom right for Delete, and the grown Copy while its label is out), so
    the hint shows across the middle of the band and a click there still draws as it does today.
    Touches `inButtonRow` (renamed for what it is), `showsDrawHint`, and the hover-reveal doc.
    Acceptance: on the shortest card in the stack, walk the cursor along the bottom edge from
    left to right; the hint goes only over the two buttons.

34. A one-page static site for the app. Pete: "create a stupid simple static site to advertise
    this app that enumerates the features and provides a link to download as well as a link to
    the github." And: "the static site should be like one font size, very very simple and low
    key. no silly frills." One HTML page, hand-written, no framework and no build step. One font
    size throughout, no headings larger than the text, no hero, no gradients, no icons, no
    animation, one column of text at a readable measure. The name, one sentence, one picture
    (the stack beside the annotator), the features as a list in the README's user vocabulary
    (draw, not annotate: the stack, draw and copy, stitch, the queue, zoom, drafts that survive
    a relaunch, the agent skill and `add?marks=`), a Download link, and a GitHub link, both as
    plain links in the text. It lives in the repo (`site/`) so GitHub Pages can serve it from the
    public repo with nothing else to host. What it waits on: the GitHub link needs the public
    repo, and the Download link needs a binary release, which needs the tldraw Hobby key
    (docs/foundation-review-2026-09-15.md, step 1: no binary release before the key lands) and
    a notarized build (the hardened runtime is already on, so notarizing is a signing step, not a
    code change). Until then the page can be written and previewed locally with both links
    pointing at placeholders, and the Download link says what it waits on rather than 404ing.

35. A demo video of the app. Pete: "create a well edited video for the app that shows off many
    of the features along with nicely done transitions, mock example photos, and a mock back and
    forth between the human and agent." Under two minutes, no narration needed, captions at
    most. The screenshots in it are mock: staged windows made for the video (a terminal, a
    browser page, a design), never Pete's real folder, so the run happens on a scratch watch
    folder and a scratch settings file (`SHOTNOTE_SETTINGS`), with the real folder untouched.
    The beats: a capture landing as a thumbnail; the double tap opening the stack; drawing and
    Return copying; a selection, the strip's labels coming out, and Stitch; the queue moving
    through three cards; a zoom; and the exchange with the agent, which the app can already
    stage on its own: the human draws on a screenshot and sends it, and the agent's answer
    arrives through `add?file=&agent=claude&marks=` so its purple badge and its own marks land in
    the stack as a draft the human then edits. Both halves are real app behaviour driven from a
    script, so the video shows nothing the app cannot do. Record with `screencapture -v` on a
    region at 60 fps, or the whole display, and cut in a video editor; the transitions between
    beats are the editor's, the motion inside a beat is the app's own. Waits on the mock
    screenshots and on the site (34) for a place to put it; it is also the clip the site's
    picture can be a still from.


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
