# Build and run

```
./scripts/run.sh          # builds web, regenerates the Xcode project, builds, relaunches
./scripts/build.sh --test # the same build plus the unit tests
```

Requires Xcode, `xcodegen`, and `pnpm` (run `pnpm install` in `web/` once). `web/dist` must
exist before `xcodegen` runs, which is why `build.sh` builds the page first; `Info.plist` is
generated from `project.yml`, so edit that.

## Signing

Without `scripts/signing.env` the build is ad-hoc signed and runs. The catch is Accessibility:
the double-tap hotkey needs the app trusted for Accessibility, and macOS ties that grant to the
app's code signature. An ad-hoc signature is a hash of the build, so every rebuild is a new app
to macOS and the grant is lost. A certificate fixes that: the signature's designated requirement
names the certificate, not the build, so trust survives rebuilds (verified with a Developer ID
certificate). Put yours in the gitignored `scripts/signing.env`:

```
CODE_SIGN_IDENTITY="Developer ID Application"
DEVELOPMENT_TEAM=ABCDE12345
```

A self-signed code-signing certificate made in Keychain Access (Certificate Assistant → Create a
Certificate, type Code Signing) works the same way, verified: its designated requirement names the
certificate, and a build rebuilt from changed source kept its Accessibility grant. Leave
`DEVELOPMENT_TEAM` empty for it. Two things to know for that route: `project.yml` turns off
Xcode's debug dylib (`ENABLE_DEBUG_DYLIB`), because the hardened runtime refuses to load it when
the signer has no team ID and the app dies at launch; and macOS keys the Accessibility list by
bundle id, so a second build of the same bundle id with a different signer shows the existing row
as enabled while staying untrusted. Give a fork its own bundle id (see Forking).
The hardened runtime is on so notarizing later needs no code change. The app is not sandboxed: it
writes Apple's screencapture defaults, watches a folder you name, and installs global event monitors.

## tldraw license

tldraw is licensed, not open source. Without a key the editor shows a "Get a license for
production" watermark, which stays. A key goes in as `VITE_TLDRAW_LICENSE_KEY` in the build
environment (`App.tsx` passes it as the `licenseKey` prop). `LICENSE-tldraw.md` ships in the
bundle verbatim, as the license requires.

# Make it yours

- `~/.config/vignette/settings.json`: folder, counts, timing, hotkey, backdrop. No rebuild.
- `Sources/Config.swift`: the actions list.
- `web/src/config.ts`: editor tools, the tool each image opens on, the colours a mark may be drawn
  in, stroke size.
- `web/src/bridge.ts` and `Sources/Bridge.swift`: the only contract between the two sides.

See `AGENTS.md` for the working loop.

# Forking

1. In `project.yml`, change `name`, the target and scheme keys that repeat it, both
   `PRODUCT_BUNDLE_IDENTIFIER` values, and the URL scheme. The log name, status item, drafts
   folder, and hotkey registration follow the bundle id at runtime.
2. Signing: add `scripts/signing.env` with your certificate, or accept ad-hoc and re-grant
   Accessibility after each rebuild if you use the double-tap hotkey.
3. `./scripts/build.sh --test`. It builds `web/dist` before `xcodegen`, so a clone builds
   without any manual step besides `pnpm install`.
4. Drafts live on disk, so relaunching while annotating loses nothing that was parked.
5. Ship only with a tldraw license key of your own (see the tldraw license section above).

# How it works

- `Sources/` is the Swift shell: menu bar item, folder watcher, panels, clipboard, hotkey, drafts.
- `web/` is the editor page: React + tldraw, built with Vite into `web/dist`, bundled into the app.
- `Sources/LocalServer.swift` serves `web/dist` and the screenshot being annotated on 127.0.0.1,
  behind a per-launch token. tldraw only runs unlicensed on http origins; `file://` and custom
  schemes make it hide the editor after five seconds, and the image has to share the page's
  origin for the export canvas to stay untainted.
- `web/src/bridge.ts` and `Sources/Bridge.swift` are the whole contract between the two sides.
  The page reports a protocol version in `ready`; a stale page is refused with a log line and a
  toast instead of failing quietly.
- Annotations in progress are drafts the app keeps on disk (`~/Library/Application Support/
  com.petepetrash.vignette/drafts/`), so they survive relaunches and a crashed web process.
