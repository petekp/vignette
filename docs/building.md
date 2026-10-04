# Building Vignette

## Build and run

```
./scripts/run.sh          # regenerates the Xcode project, builds, relaunches
./scripts/build.sh --test # the same build plus the unit tests
```

Requires Xcode and `xcodegen`. `Info.plist` is generated from `project.yml`, so edit that.

## Where things live

`Sources/` is the whole app, in Swift: the menu bar item, the folder watcher, the panels, the
clipboard, the shortcut, and the drawing editor. [editor.md](editor.md) says how the editor behaves.

Drawings are files the app keeps on disk, one per screenshot, in
`~/Library/Application Support/com.petepetrash.vignette/drawings/`. The editor hands its drawing
over 0.3 seconds after each change and again when it closes or the app quits, so a drawing
survives a relaunch.

Three places hold what you are most likely to change:

- `~/.config/vignette/settings.json`: folder, counts, timing, shortcut, backdrop, the editor's
  sizes, and how marks look: their colours, stroke, edge, fonts and text sizes. No rebuild.
- `Sources/Config.swift`: the actions list.
- `Sources/EditorCore.swift`: the editor's tools (`EditorCore.Tool`).

See [AGENTS.md](../AGENTS.md) for the working loop.

## Signing

Without `scripts/signing.env` the build is ad-hoc signed and runs.

The catch is Accessibility. The double-tap shortcut needs the app trusted for Accessibility, and
macOS ties that grant to the app's code signature. An ad-hoc signature is a hash of the build, so
every rebuild is a new app to macOS and the grant is lost.

A certificate fixes that. The signature's designated requirement names the certificate, not the
build, so trust survives rebuilds. This was verified with a Developer ID certificate.

Put yours in the gitignored `scripts/signing.env`:

```
CODE_SIGN_IDENTITY="Developer ID Application"
DEVELOPMENT_TEAM=ABCDE12345
```

A self-signed code-signing certificate works the same way. Make one in Keychain Access, under
Certificate Assistant → Create a Certificate, type Code Signing. This was verified too: its
designated requirement names the certificate, and a build rebuilt from changed source kept its
Accessibility grant. Leave `DEVELOPMENT_TEAM` empty for it.

Two things matter on that route.

`project.yml` turns off Xcode's debug dylib with `ENABLE_DEBUG_DYLIB`. The hardened runtime
refuses to load that dylib when the signer has no team ID, and the app dies at launch.

macOS keys the Accessibility list by bundle id. A second build of the same bundle id with a
different signer shows the existing row as enabled while staying untrusted. Give a fork its own
bundle id. See Forking below.

The hardened runtime is on, because notarization requires it.

The app is not sandboxed. It writes Apple's screencapture defaults, watches a folder you name, and
installs global event monitors.

## Releasing

`docs/releasing.md` has the checks before a release, the steps to publish it, and how to write
its release notes. This section covers the script.

`scripts/release.sh <version>` builds a Release archive, exports it Developer ID signed, packages a
disk image with an Applications alias, notarizes it, and staples the ticket. Finder lays out the
disk image: a small window with the app on the left, Applications on the right, and a looping red
arrow between them, which `scripts/dmg-background.swift` draws at build time. So the first
run asks for your terminal to control Finder, and the script stops if a volume named Vignette is
already mounted, because the new image would then mount under another name.

```
./scripts/release.sh 0.1.0 --dry-run   # everything but notarization
./scripts/release.sh 0.1.0             # the real thing
```

It refuses to run without three things:

- **A Developer ID certificate** in `scripts/signing.env`, with `DEVELOPMENT_TEAM` set. An ad-hoc or
  self-signed build cannot be notarized.
- **Notarization credentials**, unless `--dry-run`. Store them once:

  ```
  xcrun notarytool store-credentials vignette \
    --apple-id <your Apple ID> --team-id <your team id> --password <app-specific password>
  ```

  The app-specific password comes from appleid.apple.com under Sign-In and Security. The profile
  name is `vignette`; `NOTARY_PROFILE` in the environment picks another.
- **The update signing key** in your login Keychain, under the account `vignette`.
  `SPARKLE_ACCOUNT` in the environment picks another. Before building the disk image, the script
  checks that the key's public half is the app's `SUPublicEDKey`. After stapling, Sparkle's
  `generate_appcast` signs the image and writes `build/dist/appcast.xml`. The Keychain may ask for
  your password the first time a Sparkle tool reads the key; choose Always Allow. Keep a backup of
  the key in a password manager: `generate_keys --account vignette -x <file>` exports it. Installs
  trust only this key, so without it no later version can reach them.

It also refuses a dirty working tree, so the artifact matches the tag it goes out under.

The script archives and exports rather than running `xcodebuild build`. A plain build is signed for
development and carries the `get-task-allow` entitlement whatever the configuration says, and the
notary service rejects a binary that has it. The script checks for that entitlement, for the
hardened runtime, and for a strict signature before it packages anything.

A `.dmg` rather than a `.zip` on purpose. An app launched out of a downloaded zip is still
quarantined, and macOS runs it from a randomized read-only location. Vignette registers a URL
scheme, writes `~/.config/vignette/settings.json`, and needs an Accessibility grant, none of which
survive that. Dragging out of a disk image into Applications clears the quarantine. An app opened
straight from the disk image offers to move itself to Applications (`AppLocation.swift`).

Publishing is two commands, which the script prints when it finishes:

```
git tag v0.1.0 && git push origin v0.1.0
gh release create v0.1.0 build/dist/Vignette-0.1.0.dmg build/dist/appcast.xml --title "Vignette 0.1.0"
```

Upload `appcast.xml` with every release. The app reads
`https://github.com/petekp/vignette/releases/latest/download/appcast.xml`, which GitHub redirects to
the newest release's copy, so a release without it leaves every install on the version before.
Installs of 0.1.0 and 0.1.1 have no updater and never read it.

The README and the site link to `/releases/latest`, so both always point at the newest release.

## Forking

1. In `project.yml`, change `name`, the target and scheme keys that repeat it, both
   `PRODUCT_BUNDLE_IDENTIFIER` values, and the URL scheme. The log name, status item, drawings
   folder, and hotkey registration follow the bundle id at runtime.
2. Add `scripts/signing.env` with your certificate. Or accept ad-hoc and re-grant Accessibility
   after each rebuild if you use the double-tap shortcut.
3. Run `./scripts/build.sh --test`. A clone builds with no manual step.
4. Point `SUFeedURL` in `project.yml` at your own releases and make your own update key.
   `generate_keys --account <name>` prints the public key for `SUPublicEDKey`, and
   `SPARKLE_ACCOUNT=<name>` tells `scripts/release.sh` to sign with it.
5. Point `VignetteIssuesURL` in `project.yml` at your own repository's new-issue page, or remove it
   to leave Report a Problem… out of the menu. The form it opens is `.github/ISSUE_TEMPLATE/bug_report.yml`.
