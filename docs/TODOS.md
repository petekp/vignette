# TODOs

Things decided or raised but not built. Each entry says what, why, and what it waits on.

## Before the public release

### A scheduled update check can miss a new release (raised 2026-09-30)

The feed is kept in URLCache for about a tenth of its age when fetched, so after a month-old release
a daily check can likely miss the next one for days (`docs/updater-2026-09-27.md`). Check for Updates…
is not affected. The fix is a URLCache with no storage, set before the updater starts; nothing else
in the app uses it. Waits on Pete's approval, and needs a test release to verify.

### The move alert's wording for a translocated app (raised 2026-09-30)

An app put in Applications with its quarantine flag but not by Finder (`cp`, `ditto`, some
unarchivers) is translocated by macOS, and Vignette offers to move it. The move works and leaves
an unquarantined copy in Applications, but the alert says "Vignette is running from the disk
image", which is wrong there. It could say that macOS is running a temporary copy.

### Testing on the second MacBook from this one (raised 2026-09-30)

A Tailscale link between the two MacBooks, so an agent here can test on a Mac that never ran
Vignette. A Tart VM covers fresh installs now (`docs/install-setup-hardening-2026-09-30.md`). Real
hardware would add what the VM lacks: a Touch Bar, a Dropbox folder, a real Dock and trackpad.

- **Pete:** signs into Tailscale on both Macs (installed and stopped on this one), and on the
  second Mac turns on Remote Login for his user only and Screen Sharing (System Settings > General >
  Sharing). Tailscale's own SSH server is not in its Mac app, so Remote Login serves SSH.
- **The agent:** puts this Mac's key in the second Mac's `authorized_keys`, and writes a script
  that resets it to "never ran Vignette": the app, `~/.config/vignette`, the Application Support
  folder, the log, `tccutil reset` for the bundle id, and Apple's screenshot defaults.
- **A test round:** the agent copies a disk image over and reads the log over SSH; Pete installs it
  and answers macOS's prompts over Screen Sharing.
- **Not over SSH:** posting keys or taking screenshots. Both need the second Mac to grant
  Accessibility and Screen Recording to the SSH server, which would let anything that logs in
  control the whole Mac.

## Not placed yet

### Apple's original values after a crash and a deleted settings.json (raised 2026-09-30)

A launch that finds no settings.json records `appleOriginal` from macOS's current screenshot
settings. Vignette hands Apple's thumbnail back when it quits, so that record is right unless the
last run crashed or was force quit, which leaves the thumbnail off. Then Restore would leave it off.
The fix: keep a second copy of `appleOriginal` in the app's own defaults, and read it when
settings.json is missing. Rare, and macOS's ⌘⇧5 Options menu still turns the thumbnail back on.

### The stitch layout (raised 2026-09-27)

`docs/stitch-layout-2026-09-27.md` proposes three changes: size a stitch for Claude Code on current
models, lay the pieces out in rows that wrap in reading order, and warn when a stitch would make text
too small for the model to read. It waits on Pete's decision. The warning's wording needs his
approval, and the 10 px threshold should first be checked by pasting a few stitches into Claude Code.

### The trailer's camera (raised 2026-09-29)

The v3 trailer is live (`8bc1aad`, `docs/trailer-v3-overnight-2026-09-29.md`). Pete's notes on it,
all in the cut, so `trailer.py cut` from the same take shows each fix without a new recording:

- **The slow zoom on the editor distracts.** While the camera holds, it creeps in (`drift` and
  `drift_most` under `[camera]` in `beats.toml`). Pete finds it unnecessary. Setting `drift = 0`
  is the likely fix.
- **Claude's card is cut off on the right** when it lands in the corner. The card's right edge is
  about 17 points from the screen's edge, and the same slow zoom crops more than that, so the
  first fix may cure this too. Not yet checked.
- **The camera drops a few pixels** when the first drawing's editor appears and the zoom in on it
  begins. Not yet measured. The camera move toward `editor` at `editor.landed` is where to look.

`site/stack-and-editor.png` is no longer used by the page and is still deployed.

### The annotator's redesign: agent controls and comments (raised 2026-09-24)

Pete wants Send to be first-class and Done to stop being ambiguous, and proposed comments pinned to
the image, as in Figma, that agents leave and answer too. Part of it is built: Copy in place of
Done on Return, a message field, Send on Cmd+Return with a target beside it, and Reply on an
agent's card (`docs/send-and-reply-2026-09-24.md`). What is left: the comments, listed to the right
of the image, the tools in a rail on the left, and session tabs in place of the single target.
`docs/annotator-redesign-2026-09-24.md` has what is decided, what is open and a mockup. It is
paused until Pete picks it up again, and it would change the site's pitch and the recordings.

### Xcode's JSON project format (raised 2026-09-21)

Xcode 27 stores the project configuration as JSON: `project.xcproj` inside the `.xcodeproj`,
in place of `project.pbxproj`. It is the default in 27.2 and readable by 27 and later. Apple's
note is "Updating your Xcode project configuration file format". The point of it is a committed
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
  pull request for it (tuist/XcodeProj#1177). XcodeGen itself has nothing yet. Until then there is
  no path from `project.yml` to a `.xcproj` at all.

### Vignette without the agent features (raised 2026-09-26)

After the first public release (decided 2026-09-29): it is a new setting that reaches the editor's
bar, setup and the stack, and nothing in the release depends on it.

Pete wants an option to leave out the agent features altogether and use Vignette only as a
replacement for macOS's screenshot thumbnail. With it on, nothing about agents would show: Send,
Reply, the target menu and the message box in the editor's bar, the Agents tab, setup's skill page,
and the "From <Name>" tab on a pushed card. Vignette would also stop asking herdr and Codex for
sessions, which today happens at launch, on a capture and when the stack opens. Open: where the
switch lives (setup, Settings, or both), and whether `vignette://add` and the skill still work
while it is on.

### A glint around a new thumbnail (raised 2026-09-26)

Pete wants a new thumbnail to arrive with a glint: a highlight that travels around the image's
border, with a faint bloom around it. Like every animation it goes through `Settings.motionUI`, so
motion 0 and Reduce Motion show none. Open: whether it plays only on a capture's thumbnail or also
on a card that arrives in an open stack, such as an agent's push or reply; how many laps it runs;
and which of its numbers become `ui` tweaks.

### Sound effects (raised 2026-09-26)

Pete wants sound effects, with settings to turn them on and off. Open: which moments get a sound
(a capture landing, a copy, a send, an agent's reply arriving, a stitch); one switch for all of them
or one per sound; system sounds or Vignette's own; and whether they follow macOS's "Play user
interface sound effects" setting.

### A 3D logo with PBR materials (raised 2026-09-26)

Pete wants a 3D version of the Vignette logo, with physically based materials, on setup's welcome
page, where the app icon sits today (`SetupWindow.swift`, 96 pt). The same logo should work
elsewhere, possibly on the website with three.js, so it needs to support more than one renderer.

Recommended: one set of source files, and a renderer native to each place.

- **Source.** The mark is one filled path in `docs/logomark.svg`. Extrude and bevel it once, in
  Blender, and export a glTF binary (`.glb`) with metallic-roughness materials. Commit it beside
  one HDR environment map for the lighting and a small JSON file with the scene's numbers: camera,
  exposure, tone mapping and the idle motion. Every renderer reads those three files, so the look
  has one definition.
- **Web.** three.js loads the `.glb` with `GLTFLoader` and the map with `RGBELoader` and
  `PMREMGenerator`. The site is a static `index.html`, so three.js comes in as an ES module through
  an import map. Without WebGL, or with reduced motion, the page shows the SVG.
- **App.** RealityKit, since Apple deprecated SceneKit in 2025. RealityKit does not read glTF, so
  the `.glb` is converted to `.usdz` once and committed. `RealityView` needs macOS 15, and Vignette
  supports 14: macOS 14 keeps today's icon. The motion goes through `Settings.motionUI`, so Reduce
  Motion shows it still.
- **The risk is a mismatch.** three.js and RealityKit tone-map and light differently. The same HDR,
  the same exposure and three.js's neutral tone mapping get them close. Then compare the two side
  by side and tune the JSON, not either renderer's code.

The alternative is a video rendered in Blender, with alpha, played in both places. It gives the
richest look for the least runtime work, but it cannot turn toward the pointer. It also needs one
render per appearance, light and dark.

Open: whether the logo reacts to the pointer (which rules out the video), and whether the website
wants it in the hero or somewhere smaller.

## Discussed, not decided

- Drawing on the live screen, both directions: an agent pointing at a window, an element, or a
  phrase on the real screen (demoed 2026-09-18, source in docs/live-screen-demo/), and a person
  drawing on the live screen so the agent gets a crop plus what the mark is on.
  docs/live-screen-2026-09-18.md has the demos, the three anchors, the limits, and the tradeoffs.
- A drawing's marks as text for an agent: one line per mark with its kind and its position as a
  fraction of the image, from a command or on the clipboard beside the PNG. That is enough to crop
  the marked region from the original; a crop per mark would follow. Pete: keep using the app and
  see whether the need shows up.
- Vendor logos on the agent badge. Claude's is in (`Resources/agents/claude.svg`), and Codex shows
  the ChatGPT logo (`codex.svg`). Other agents' logos wait on the same review. One `<name>.svg` in
  that folder per `agent=` value is all `Agent.logo(for:)` needs.
- Agent pushes piling up in the screenshots folder: a name rule or a second watched folder. Only
  if the push loop proves itself in use.
- A name convention for pushed files, `Agent <what> <state>.png`, so the card reads at a glance.
- Folding Copy Drawing into Copy, so one Copy gives the image as the card shows it.

## Known costs, left alone

- Opening the stack reads one extended attribute per card on the main thread (`Agent.of`), about
  4 µs each on APFS. The card already reads each file's pixel size on the same path. If
  online-only Dropbox placeholders at a large `recentCount` ever make it show, read the attribute
  where the thumbnail decodes, off the main thread, and let the badge appear with the image.
  Measure on the real folder first.
- A stitch draws a piece with an orientation flag unturned, and skips that piece's marks, because
  the drawing's size is the turned one. `Rendering` applies the flag; `Stitch` does not. Only an
  image pushed through `add` can carry one: screenshots never do. Pete, 2026-09-23: left for now.
- The stack's narrowing for the editor, and its widening back, lay out every card on every frame,
  though only about six are in view. Measured on 2026-09-26: a Release build drops at most one frame
  per narrowing, and a Debug build up to four. Holding the hover still made no difference. Laying
  out only the cards in view is what is left (`docs/stack-narrowing-2026-09-23.md`, option B, and
  `docs/prerelease-fixes-2026-09-26.md`).
