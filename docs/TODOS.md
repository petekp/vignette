# TODOs

Things decided or raised but not built. Each entry says what, why, and what it waits on.

## Public release (raised 2026-09-19)

A downloadable build waits on two things, in order:

- Notarization. `scripts/signing.env` names the Developer ID certificate, so a Release build is
  signed, but a download is refused by Gatekeeper until it is notarized: `xcrun notarytool submit`
  with a keychain profile for the App Store Connect API key, then `xcrun stapler staple`. No profile
  exists on this Mac yet.
- The release itself: a Release configuration build, zipped with `ditto -c -k --keepParent`, and a
  GitHub Release carrying the zip, with the README's Get it section and the site's download line
  pointing at it. Whether that is a script or a workflow is a separate decision; nothing is
  committed for it yet.

After the release, publish `skills/vignette/SKILL.md` on skills.sh from the public repo, as herdr
does, so Cursor and other agents can install it without the app.

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
- AGENTS.md is long enough that a rule in it is easy to miss. It was reviewed as a whole when the
  native editor replaced tldraw, and it is still about 750 lines, so shortening it is still open.

## Known costs, left alone

- Opening the stack reads one extended attribute per card on the main thread (`Agent.of`), about
  4 µs each on APFS. The card already reads each file's pixel size on the same path. If
  online-only Dropbox placeholders at a large `recentCount` ever make it show, read the attribute
  where the thumbnail decodes, off the main thread, and let the badge appear with the image.
  Measure on the real folder first.
