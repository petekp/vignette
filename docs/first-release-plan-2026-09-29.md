# The first public release (2026-09-29)

Pete wants to focus on releasing the first public version. This is where things stand and the
order proposed to get there.

## Where things stand

- **Released quietly:** 0.1.0 (2026-09-24) and 0.1.1 (2026-09-25) on GitHub. The landing page's
  Download button gives the latest release, 0.1.1. Its disk image is notarized and stapled (checked
  2026-09-29 with `stapler validate` and `spctl`).
- **On `main`, pushed, not released:** the Sparkle updater, the Vignette plugin (Send to Claude Code
  in any terminal), notes on tags, author colours with the white edge, the mark look in
  settings.json, the pre-release fixes, and the test-copy guard.
- **The landing page is ahead of the download.** Pushing `main` deployed the trailer, which shows
  the plugin and the new notes. 0.1.1 has neither.
- **0.1.1 has no updater.** Nothing tells its installs about a new version. Every install made
  before the first release with Sparkle has to be updated by hand.

## Must do before announcing

1. **Find out why a fresh install skipped setup** (`docs/TODOS.md`, "A fresh install of 0.1.3
   skipped setup"). No 0.1.3 exists; the landing page gave 0.1.1, so that was most likely the build
   installed. What to check is listed there. The "are you sure" prompt is macOS's usual question
   for any downloaded app, since the image is notarized.
2. **Run a fresh install of today's `main` on the second MacBook**, before tagging: setup, the
   folder permission, Accessibility, the plugin install, and one Send.
3. **Check today's mark work by hand:** the white edge on a note while typing, an agent's note
   becoming the person's when retyped, and selecting an agent's marks, which Pete could not do.
4. **Pass the end-to-end smoke gate** (`docs/e2e-suite-plan-2026-09-29.md`), and fix the git stamp's
   ordering, which can leave a release at `CFBundleVersion` 0.
5. **Cut 0.1.2 with `scripts/release.sh`.** It is the first build with the updater. It needs the
   update signing key in the Keychain (account `vignette`) and the notarization profile.
6. **Cut 0.1.3 and let 0.1.2 update to it** through the GitHub feed. That is the only full test of
   the updater, and it covers the cases the local test could not (`docs/updater-2026-09-27.md`).

## Done on 2026-09-29

- **Finding the `claude` and `codex` commands:** Vignette now also looks in the folders nvm, fnm,
  Volta, Bun, pnpm, asdf and mise put a global command in, then asks the login shell once at launch
  (`AgentTools`).
- **Setup's last page** says Claude Code sessions already open need `/reload-plugins`.
- **The README** says Claude Code's auto mode asks once before the first drawing.
- **Agent-free mode:** after the release. It is a new setting that reaches the editor's bar, setup
  and the stack, and nothing in the release depends on it.
- **Stitch with a recording:** Stitch takes the recording's first frame, the picture its card shows.
  Saying why Stitch was off without a hover would have needed room in the strip for the reason.

## Can wait

The stitch layout, the disk image window, the glint, sounds, the 3D logo, the annotator redesign,
and Xcode's JSON project format.
