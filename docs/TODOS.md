# TODOs

Things decided or raised but not built. Each entry says what, why, and what it waits on.

## Product

### Marks sized to the screenshot (raised 2026-10-01)

On a small capture, the shapes and notes take up too much of the picture. A mark's sizes, its
stroke and edge widths and its text, are in points of the drawing's `pointScale`. So a capture of
one button gets the same 3.5 pt stroke and the same note text as a capture of the whole screen.
Marks should scale down with the screenshot's size, to a minimum below which a note's text or a
stroke would be hard to read.

Still to decide:

- **The measure of "small":** the capture's size in points, its shorter side, or its size against
  the screen it was taken on.
- **The minimum:** the smallest text and stroke that stay legible at the editor's fitted size, and
  whether that is a `UITweaks` value with a slider.
- **Where the scale lives:** fixed in the drawing when it is made, or worked out from the image each
  time a mark is drawn, so it applies the same in the editor, on cards, in flights and in the PNG.
  Old drawings need not keep their look.
- **Agent marks:** whether a pushed note scales the same way, since its width cap and line breaks
  depend on its text size.

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

### The annotator's redesign: agent controls and comments (raised 2026-09-24)

Pete wants Send to be first-class and Done to stop being ambiguous, and proposed comments pinned to
the image, as in Figma, that agents leave and answer too. Part of it is built: Copy in place of
Done on Return, a message field, Send on Cmd+Return with a target beside it, and Reply on an
agent's card (`docs/send-and-reply-2026-09-24.md`). What is left: the comments, listed to the right
of the image, the tools in a rail on the left, and session tabs in place of the single target.
`docs/annotator-redesign-2026-09-24.md` has what is decided, what is open and a mockup. It is
paused until Pete picks it up again, and it would change the site's pitch and the recordings.

### The stitch layout (raised 2026-09-27)

`docs/stitch-layout-2026-09-27.md` proposes three changes: size a stitch for Claude Code on current
models, lay the pieces out in rows that wrap in reading order, and warn when a stitch would make text
too small for the model to read. It waits on Pete's decision. The warning's wording needs his
approval, and the 10 px threshold should first be checked by pasting a few stitches into Claude Code.

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

### A more fluid session menu (raised 2026-10-03)

Pete wants the toolbar's session menu, "Send to", to open with motion. Today it appears in one
frame, which jars against the target button's own springs. The menu is AppKit's `NSMenu`
(`AnnotatorToolbar.showTargetMenu`), because SwiftUI's `Menu` cannot be opened from a key, and
`NSMenu` draws itself with no way to animate its opening. A menu that grows out of the target would
be Vignette's own panel. It would then have to do what `NSMenu` does now: arrow keys, Return, Esc,
type-to-select, closing on a click outside, and VoiceOver. Open: whether that is worth giving up the
system menu, and how it opens: growing from the target, sliding down from it, or fading in.

## Fixes

### Apple's original values after a crash and a deleted settings.json (raised 2026-09-30)

A launch that finds no settings.json records `appleOriginal` from macOS's current screenshot
settings. Vignette hands Apple's thumbnail back when it quits, so that record is right unless the
last run crashed or was force quit, which leaves the thumbnail off. Then Restore would leave it off.
The fix: keep a second copy of `appleOriginal` in the app's own defaults, and read it when
settings.json is missing. Rare, and macOS's ⌘⇧5 Options menu still turns the thumbnail back on.

## Site and media

### A drop in the trailer's camera (raised 2026-09-29)

The camera drops a few pixels when the first drawing's editor appears and the zoom in on it begins.
Not yet measured. Look at the camera move toward `editor` at `editor.landed` in `beats.toml`. It is
in the cut, so `trailer.py cut` from the same take shows a fix without a new recording.

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

## Tooling

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

## Discussed, not decided

- Drawing on the live screen, both directions: an agent pointing at a window, an element, or a
  phrase on the real screen (demoed 2026-09-18, source in docs/live-screen-demo/), and a person
  drawing on the live screen so the agent gets a crop plus what the mark is on.
  docs/live-screen-2026-09-18.md has the demos, the three anchors, the limits, and the tradeoffs.
- A drawing's marks as text for an agent: one line per mark with its kind and its position as a
  fraction of the image, from a command or on the clipboard beside the PNG. That is enough to crop
  the marked region from the original; a crop per mark would follow. Pete: keep using the app and
  see whether the need shows up.
- Agent pushes piling up in the screenshots folder. Two answers: a name rule for pushed files,
  such as `Agent <what> <state>.png`, so a card reads at a glance, or a second watched folder. Only
  if the push loop proves itself in use.
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
