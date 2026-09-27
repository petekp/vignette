# TODOs

Things decided or raised but not built. Each entry says what, why, and what it waits on.

## Before the public release

### Updates that reach every install (raised 2026-09-27)

Vignette has no updater yet. "Check for Updates…" opens the latest release on GitHub
(`Identity.releasesURL`), and nothing tells a user that a new version exists. Someone who installs a
build without an updater has to find each later version themselves. So the first public build has
to carry the updater, and it has to be tested before the release.

Recommended: Sparkle 2, which most Mac apps outside the App Store use. It reads a feed of versions
(an appcast), checks each download's EdDSA signature, and replaces the app in place. The feed and the
downloads can live on GitHub Releases. Adding it changes `project.yml` and `scripts/release.sh`, which
are release tooling, so each change needs Pete's approval.

Test it on installs of the stage copy, which has its own bundle id, from a feed served out of a
scratch folder, so no test touches Pete's install. Cases to cover:

- **The update itself.** From the current release to the next, through the updater. An update that
  arrives while the stack or the editor is open, or while a send waits for its answer. A declined
  update, a skipped version, a failed download, and no network.
- **Settings.** A newer build migrates an older settings file (`Settings.migrate`). A default changed
  in the new build reaches the install, since the file keeps only the `ui` values that differ. An
  older build installed by hand over a newer one opens the newer file read-only.
- **Permissions.** Accessibility trust survives the update. It is tied to the signature's designated
  requirement, so every release must be signed with the same Developer ID. The folder permission for
  a watch folder on the Desktop, in Documents or in Downloads survives too, and the login item opens
  the new version.
- **Stored data.** The new build opens drawings the old one wrote. Open screenshot requests and
  replies still waiting to be imported come through the relaunch. An agent holding the old skill
  can still reply (`ReplyProtocol.version`).
- **The agent skill.** The first launch after an update rewrites the older copies of the skill it
  finds (`SkillInstaller.version(of:)`), and leaves a newer or edited copy alone.
- **Apple's screenshot settings.** The launch reconcile runs again, and `appleOriginal` is kept, so
  Restore still puts back what was there before Vignette.
- **Where the app lives.** /Applications, ~/Applications, a folder the user cannot write to, where
  Sparkle asks for an administrator's password, and a copy still running from the disk image.

## Not placed yet

### The stitch layout (raised 2026-09-27)

`docs/stitch-layout-2026-09-27.md` proposes three changes: size a stitch for Claude Code on current
models, lay the pieces out in rows that wrap in reading order, and warn when a stitch would make text
too small for the model to read. It waits on Pete's decision. The warning's wording needs his
approval, and the 10 px threshold should first be checked by pasting a few stitches into Claude Code.

### A nicer disk image window (raised 2026-09-25)

The window the disk image opens, where you drag Vignette to Applications, should look better. Today
`scripts/release.sh` lays it out with Vignette on the left and Applications on the right, and
nothing else. The look is Pete's to choose. The change is to the release script, so it needs his
approval for that change before it is made.

### A new demo video (raised 2026-09-24)

The tldraw-era video left the site and the README with the native editor, and a still of the stack
and the editor leads in its place (`site/stack-and-editor.png`). A new recording replaces the still
when Pete makes one.

### The annotator's redesign: agent controls and comments (raised 2026-09-24)

Pete wants Send to be first-class and Done to stop being ambiguous, and proposed comments pinned to
the image, as in Figma, that agents leave and answer too. The design so far: the tools in a rail on
the left, the comments listed on the right, and along the bottom Copy (in place of Done, on Return)
beside session tabs, a message field and Send (Cmd+Return). Paused on 2026-09-24 for the promo
videos. The bar's Send and Reply came forward the same day, with a target beside Send in place of
tabs: `docs/send-and-reply-2026-09-24.md`. `docs/annotator-redesign-2026-09-24.md` has what's decided, what's open and a mockup. When
it resumes, settle the Return rule first. It would change the site's pitch and the recordings.

### Agents' marks in their own typeface (raised 2026-09-24)

Tell an agent's marks from a person's by typeface, not colour. Colour stays with the colour pass,
which picks whatever stands out against the image, and a colour reserved for agents would work
against that. Since 2026-09-26 an agent's texts are set in SF Mono (`TextStyle.forAgent`). Open:
what marks the difference on a box or an arrow, which have no typeface.

### Xcode's JSON project format (raised 2026-09-21)

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

### Vignette without the agent features (raised 2026-09-26)

Pete wants an option to leave out the agent features altogether and use Vignette only as a
replacement for macOS's screenshot thumbnail. With it on, nothing about agents would show: Send,
Reply, the target menu and the message box in the editor's bar, the Agents tab, setup's skill page,
and the "From <Name>" tab on a pushed card. Vignette would also stop asking herdr and Codex for
sessions, which today happens at launch, on a capture and when the stack opens. Open: where the
switch lives (setup, Settings, or both), and whether `vignette://add` and the skill still work
while it is on.

### Send to Claude Code without herdr (raised 2026-09-26)

Send reaches a Claude Code session only through the herdr pane it runs in, and most people who
download Vignette will not run herdr. The Agents tab and setup now say so. Reaching Claude Code
without herdr needs a way into a running session that Claude Code itself offers; none is known yet.

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
- Vendor logos on the agent badge. Claude's is in (`Resources/agents/claude.svg`, Pete's call on
  2026-09-20). ChatGPT's and others wait on the same review. One `<name>.svg` in that folder per
  `agent=` value is all `Agent.logo(for:)` needs.
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
  though only about six are in view. Measured again on 2026-09-26, after the click hint went: a
  Release build drops at most one frame per narrowing, and a Debug build up to four. Holding the
  hover still made no difference and was not kept. Laying out only the cards in view is what is left
  (`docs/stack-narrowing-2026-09-23.md`, option B; `docs/prerelease-fixes-2026-09-26.md`).
