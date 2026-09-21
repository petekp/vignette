# Building Vignette

## Build and run

```
./scripts/run.sh          # builds web, regenerates the Xcode project, builds, relaunches
./scripts/build.sh --test # the same build plus the unit tests
```

Requires Xcode, `xcodegen`, and `pnpm`. Run `pnpm install` in `web/` once. `web/dist` must exist
before `xcodegen` runs, which is why `build.sh` builds the page first. `Info.plist` is generated
from `project.yml`, so edit that.

## Where things live

`Sources/` is the Swift shell: menu bar item, folder watcher, panels, clipboard, hotkey, drafts.

`web/` is the editor page: React + tldraw, built with Vite into `web/dist`, bundled into the app.

`Sources/LocalServer.swift` serves `web/dist` and the screenshot being annotated on 127.0.0.1,
behind a per-launch token. It serves on http because tldraw only runs unlicensed on http origins.
On `file://` and custom schemes the editor hides itself after five seconds. The image also has to
share the page's origin, or the export canvas is tainted.

`web/src/bridge.ts` and `Sources/Bridge.swift` are the whole contract between the two sides. The
page reports a protocol version in `ready`. A stale page is refused with a log line and a toast
instead of failing quietly.

Annotations in progress are drafts the app keeps on disk, in
`~/Library/Application Support/com.petepetrash.vignette/drafts/`. They survive relaunches and a
crashed web process. Relaunching while annotating loses nothing that was parked.

Three places hold what you are most likely to change:

- `~/.config/vignette/settings.json`: folder, counts, timing, hotkey, backdrop. No rebuild.
- `Sources/Config.swift`: the actions list.
- `web/src/config.ts`: editor tools, the tool each image opens on, the colours a mark may be drawn
  in, stroke size.

See [AGENTS.md](../AGENTS.md) for the working loop.

## Signing

Without `scripts/signing.env` the build is ad-hoc signed and runs.

The catch is Accessibility. The double-tap hotkey needs the app trusted for Accessibility, and
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

The hardened runtime is on so notarizing later needs no code change.

The app is not sandboxed. It writes Apple's screencapture defaults, watches a folder you name, and
installs global event monitors.

## The tldraw license

tldraw is licensed, not open source. Without a key the editor shows a "Get a license for
production" watermark, and the watermark stays. A key goes in as `VITE_TLDRAW_LICENSE_KEY` in the
build environment, and `App.tsx` passes it as the `licenseKey` prop. `LICENSE-tldraw.md` ships in
the bundle verbatim, as the license requires.

## Forking

1. In `project.yml`, change `name`, the target and scheme keys that repeat it, both
   `PRODUCT_BUNDLE_IDENTIFIER` values, and the URL scheme. The log name, status item, drafts
   folder, and hotkey registration follow the bundle id at runtime.
2. Add `scripts/signing.env` with your certificate. Or accept ad-hoc and re-grant Accessibility
   after each rebuild if you use the double-tap hotkey.
3. Run `./scripts/build.sh --test`. It builds `web/dist` before `xcodegen`, so a clone builds
   without any manual step besides `pnpm install`.
4. Ship only with a tldraw license key of your own. See The tldraw license above.
