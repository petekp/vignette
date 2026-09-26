# TODOs

Things decided or raised but not built. Each entry says what, why, and what it waits on.

## Publish the skill on skills.sh (raised 2026-09-19)

0.1.0 went out on 2026-09-24. Publish `skills/vignette/SKILL.md` on skills.sh from the public repo,
as herdr does, so Cursor and other agents can install it without the app.

## A nicer disk image window (raised 2026-09-25)

The window the disk image opens, where you drag Vignette to Applications, should look better. Today
`scripts/release.sh` lays it out with Vignette on the left and Applications on the right, and
nothing else. The look is Pete's to choose. The change is to the release script, so it needs his
approval for that change before it is made.

## A new demo video (raised 2026-09-24)

The tldraw-era video left the site and the README with the native editor, and a still of the stack
and the editor leads in its place (`site/stack-and-editor.png`). A new recording replaces the still
when Pete makes one.

## The annotator's redesign: agent controls and comments (raised 2026-09-24)

Pete wants Send to be first-class and Done to stop being ambiguous, and proposed comments pinned to
the image, as in Figma, that agents leave and answer too. The design so far: the tools in a rail on
the left, the comments listed on the right, and along the bottom Copy (in place of Done, on Return)
beside session tabs, a message field and Send (Cmd+Return). Paused on 2026-09-24 for the promo
videos. The bar's Send and Reply came forward the same day, with a target beside Send in place of
tabs: `docs/send-and-reply-2026-09-24.md`. `docs/annotator-redesign-2026-09-24.md` has what's decided, what's open and a mockup. When
it resumes, settle the Return rule first. It would change the site's pitch and the recordings.

## Agents' marks in their own typeface (raised 2026-09-24)

Tell an agent's marks from a person's by typeface, not colour. Colour stays with the colour pass,
which picks whatever stands out against the image, and a colour reserved for agents would work
against that. Since 2026-09-26 an agent's texts are set in SF Mono (`TextStyle.forAgent`). Open:
what marks the difference on a box or an arrow, which have no typeface.

## Xcode's JSON project format (raised 2026-09-21)

Xcode 27 stores the project configuration as JSON: `project.xcproj` inside the `.xcodeproj`,
in place of `project.pbxproj`. It is the default in 27.2 and readable by 27 and later. Apple's
note is "Updating your Xcode project configuration file format"; the point of it is a committed
project file with readable diffs, fewer merge conflicts, and edits an agent can make.

Nothing to adopt as the repo stands. `Vignette.xcodeproj/` is gitignored and `scripts/build.sh`
regenerates it with `xcodegen generate` on every build, so the project is a build artifact.
`project.yml` is the committed source of truth and already gives all three of those things.
Changing the artifact's format would change a file nobody reads and nobody merges.

The decision that would mean something is dropping XcodeGen: commit a native Xcode project as
the source of truth and delete `project.yml`. Not decided. What it would cost:

- `Info.plist` is generated from `project.yml` and gitignored today. It becomes a committed file.
- The reasons travel in `project.yml`'s comments and would have nowhere to live in project
  settings: the "Stamp git state" build phase, `ENABLE_DEBUG_DYLIB: false`, the ad-hoc default
  with `scripts/signing.env` overriding it, and the test target compiling `Sources/` rather than
  hosting the app.
- `scripts/build.sh` and `scripts/run.sh` read the scheme name out of `project.yml`.
- AGENTS.md documents the generate step in several places.

Waits on two things, either way:

- Xcode 27. This Mac has 26.3 and no other Xcode, and Xcode 26 cannot open a `.xcproj`.
- XcodeGen emitting the format, if `project.yml` stays. Tuist's XcodeProj has an experimental
  pull request for it (tuist/XcodeProj#1177); XcodeGen itself has nothing yet. Until then there
  is no path from `project.yml` to a `.xcproj` at all.

## Vignette without the agent features (raised 2026-09-26)

Pete wants an option to leave out the agent features altogether and use Vignette only as a
replacement for macOS's screenshot thumbnail. With it on, nothing about agents would show: Send,
Reply, the target menu and the message box in the editor's bar, the Agents tab, setup's skill page,
and the "From <Name>" tab on a pushed card. Vignette would also stop asking herdr and Codex for
sessions, which today happens at launch, on a capture and when the stack opens. Open: where the
switch lives (setup, Settings, or both), and whether `vignette://add` and the skill still work
while it is on.

## No "Draw" hint on a hovered card (raised 2026-09-26)

Pete wants the hint that appears over a hovered card, "Draw" on a screenshot and "Open" on a
recording, removed. It is `showsClickHint` in `StackView.swift`, and AGENTS.md describes how it
avoids the card's corner buttons, so that rule goes with it.

## Discussed, not decided

- Drawing on the live screen, both directions: an agent pointing at a window, an element, or a
  phrase on the real screen (demoed 2026-09-18, source in docs/live-screen-demo/), and a person
  drawing on the live screen so the agent gets a crop plus what the mark is on.
  docs/live-screen-2026-09-18.md has the demos, the three anchors, the limits, and the tradeoffs.
- A drawing's marks as text for an agent: one line per mark with its kind and its position as a
  fraction of the image, from a command or on the clipboard beside the PNG. That is enough to crop
  the marked region from the original; a crop per mark would follow. Pete: keep using the app and
  see whether the need shows up.
- Vendor logos on the agent badge. Claude's is in (`Resources/agents/claude.svg`, Pete's call on
  2026-09-20). ChatGPT's and others wait on the same review. One `<name>.svg` in that folder per
  `agent=` value is all `Agent.logo(for:)` needs.
- Agent pushes piling up in the screenshots folder: a name rule or a second watched folder. Only
  if the push loop proves itself in use.
- A name convention for pushed files, `Agent <what> <state>.png`, so the card reads at a glance.
- Folding Copy Drawing into Copy, so one Copy gives the image as the card shows it.
- Reorganising AGENTS.md. It is 782 lines, and a rule in it is easy to miss. The final docs review
  of 2026-09-23 proposed:
  - Open The loop with a short "Before you drive the app" list: use a scratch settings file; check
    `app.bundle` and `app.settingsFile` in `[state]`; launch one at a time behind the lock; send no
    synthetic Esc; delete test files from the real watch folder.
  - Move the rules it found buried: never testing against the real settings file, now mid-bullet in
    Layout; the lock for parallel agents and putting the user's build back, mid-step 3; never
    sending Escape to close the stack, inside step 4; and a swap keeping the slot drawn empty, in
    the toolbar rule, which belongs in the transition or queue rule.
  - Group the rules under subheadings: Shortcut and capture; The stack; Flights and presses; The
    annotator and its reducer; The editor and drawings; Zoom; Memory; Build, signing and Apple
    defaults; Agents.
  - Merge the build bullets (Swift mode, signing, `Info.plist`) into one. They repeat `project.yml`,
    `.gitignore` and `docs/building.md`.

  Pete, 2026-09-23: later.

## Known costs, left alone

- Opening the stack reads one extended attribute per card on the main thread (`Agent.of`), about
  4 µs each on APFS. The card already reads each file's pixel size on the same path. If
  online-only Dropbox placeholders at a large `recentCount` ever make it show, read the attribute
  where the thumbnail decodes, off the main thread, and let the badge appear with the image.
  Measure on the real folder first.
- A stitch draws a piece with an orientation flag unturned, and skips that piece's marks, because
  the drawing's size is the turned one. `Rendering` applies the flag; `Stitch` does not. Only an
  image pushed through `add` can carry one: screenshots never do. Pete, 2026-09-23: left for now.
- The stack drops frames while it narrows to make room for the editor, and while it widens back.
  After a click, the pointer rests on the column, so SwiftUI re-checks hover and redraws cards on
  every frame. Every card is also laid out on every frame, though only about six are in view.
  `docs/stack-narrowing-2026-09-23.md` has the measurements and five options. The recommended pair
  is to pause hover while the column moves and to lay out only the visible cards. Pete, 2026-09-23:
  left for now, to take up later.
