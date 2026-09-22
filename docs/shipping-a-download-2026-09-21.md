# Shipping a download

Stage 2 of [the first-time journey](first-run-journey-2026-09-21.md), and the one that gates every
other stage. Proposed, not built. Release tooling needs Pete's approval before any of it is written.

## The target

What a new user should do, end to end:

1. Click Download on vignette.pete.design.
2. `Vignette.dmg` downloads and opens.
3. Drag Vignette to Applications.
4. Double-click. It opens. No warning dialog.
5. The setup window asks for the shortcut ([stage 4](first-run-setup-2026-09-21.md)).

Five steps, no terminal, no Xcode, no "cannot be opened because the developer cannot be verified".

## What actually stands in the way

Four things, in the order they block.

### 1. The tldraw license key (Pete's action, and it is a form)

The blocker recorded in `foundation-review-2026-09-15.md` was that the Hobby key waits until the
repo is public. It is public now, so this is unblocked and smaller than it looked.

tldraw's Hobby license is free and discretionary, for "personal projects and early experiments;
student work, research, side projects, prototypes, and ideas that aren't a business yet". The form
asks for name, email, project website, project domain, and a project description. Vignette has all
of those. Projects on a Hobby key must show the "made with tldraw" watermark on the canvas, which
Vignette already does and already treats as non-negotiable (`AGENTS.md`).

Review time is not published; the page says a team member looks at each application.

- **Bridge if review is slow:** tldraw also issues a free 100-day trial key immediately on form
  submission. It would unblock a first release today. The risk is that business units get one trial
  period, so spending it before knowing the Hobby answer removes the fallback. Worth applying for
  Hobby first and holding the trial in reserve.
- **Worth knowing now:** Hobby is for projects that are not a business. If Vignette ever charges,
  that path needs a commercial license, which tldraw prices privately (public
  reports put it around $6k/year). That is a constraint on the product's future, not on this release.

Nothing below can ship publicly until one of these keys is in hand. The key goes in as
`VITE_TLDRAW_LICENSE_KEY` in the build environment (`web/src/App.tsx:166`).

### 2. There is no artifact (my work, needs approval)

`scripts/build.sh` builds Debug into `build/` and stops. There is no Release build, no packaging, no
notarization, no tag, no release. No git tags and no GitHub releases exist yet.

Two details that will bite if missed:

- **Release, not Debug.** Debug builds carry the `get-task-allow` entitlement, and notarization
  rejects a binary that has it. The generated project already has a Release configuration; the
  release path has to select it.
- **The version.** `MARKETING_VERSION` is `0.1.0` in `project.yml`. `CFBundleVersion` is overwritten
  by a build phase with the git commit count, which is already monotonic and therefore already
  correct for an updater later.

### 3. Gatekeeper (one-time setup by Pete, then automatic)

The hard part is already done. The build is signed with a Developer ID Application certificate (team
U8GTZZSBDM) and `ENABLE_HARDENED_RUNTIME` has been on from the start, which is exactly what
notarization needs.

What is missing is credentials for `notarytool`: either an App Store Connect API key, or an Apple ID
with an app-specific password. Stored once with `xcrun notarytool store-credentials`, after which a
script can submit, wait, and staple without any secret in the repo.

### 4. .dmg, not .zip

This is the difference between "it works" and "it half works", and it is worth being firm about.

A quarantined app launched straight out of a downloaded zip is subject to Gatekeeper path
randomization, which runs the app from a read-only temporary location. For most apps that is
cosmetic. For Vignette it is not: the app registers a `vignette://` URL scheme, writes
`~/.config/vignette/settings.json`, and needs an Accessibility grant that macOS ties to the app's
identity and location expectations. An app running translocated is the wrong app in all the ways
that matter here.

Dragging out of a disk image into Applications clears the quarantine properly. So: a `.dmg` with a
window containing the app and an Applications alias, which is also the install gesture every Mac
user already knows.

## Recommended shape

**A local `scripts/release.sh`, run from Pete's Mac. Not a GitHub Actions workflow, not yet.**

A CI release needs the Developer ID certificate and the notarization credentials as repository
secrets, which is more setup, more to get wrong, and a private key in more places. The certificate
is already in his keychain. For a project with zero releases so far, a script he runs is the simpler
path that meets the requirement. If releases become frequent enough that running a script is the
annoying part, that is the moment to move it to CI.

The script would: build web with the license key in the environment, build Release, sign, package
the dmg, notarize, staple, verify, and print the artifact path. Tagging and uploading to GitHub
Releases can be part of it or stay a separate `gh release create`.

## Updates

Not required for a first release, and worth a decision now because early users are the ones stranded
if it is forgotten.

- **v1: a "Check for Updates" menu item that opens the releases page.** No dependency, an hour of
  work, and it means the first users have a route to the second version.
- **Later: Sparkle**, when there is a release cadence worth automating. It needs an appcast, an
  EdDSA signing key, and a hosted feed. Retrofitting it is ordinary work, not a redesign.

## Order

1. Apply for the tldraw Hobby key. Everything else is blocked on it, and it costs 15 minutes.
2. Set up `notarytool` credentials. Independent of the key, can happen the same day.
3. Build the release script and cut `v0.1.0` as a private dry run: notarize, staple, install from
   the dmg on a second Mac or a fresh user account, confirm it opens with no dialog.
4. Put the download on the site and the README, replacing "There is no download yet."
5. Add Check for Updates.

Steps 3 to 5 are the ones that need approval to write.
