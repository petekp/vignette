# Releasing Vignette

How to check, cut and publish a release, and how to write its release notes. `docs/building.md`
says what `scripts/release.sh` does and what it needs: the certificate, the notary profile and the
update key.

## Before a release

- **Unit tests pass.** Run `scripts/build.sh --test`. When someone is running a build from
  `build/`, run `xcodebuild … test` with another `-derivedDataPath` instead, since `build.sh`
  rewrites that app under the running process.
- **Every end-to-end scenario passes, with input.** Run `scripts/e2e/e2e.py run --input`. It takes
  about 7 minutes. It moves the mouse and types, so nobody may use the Mac meanwhile.
- **A person tries what synthetic input cannot prove.** For example, a change to how captures are
  found needs a real ⌘⇧4.
- **Everything that ships is committed.** `release.sh` refuses a dirty working tree.

## Cutting it

Versions go up by one patch number: 0.1.5, then 0.1.6.

Other work is often uncommitted in the main checkout, so cut the release in a worktree of its own at
the commit that ships:

```
git worktree add ../worktrees/vignette/release-0.1.6 <commit>
cp scripts/signing.env ../worktrees/vignette/release-0.1.6/scripts/
cd ../worktrees/vignette/release-0.1.6 && ./scripts/release.sh 0.1.6
```

Do not edit that worktree while the script builds: the build stamps `git describe --dirty`. When
the script finishes, unregister the app it built with `lsregister -u <app>`. It has the real bundle
id, so LaunchServices would otherwise send the next `vignette://` URL to it, on the person's real
settings. Remove the worktree with `git worktree remove` once the release is published.

## Publishing

`release.sh` prints the two commands. Pass the release notes in a file:

```
git tag v0.1.6 <commit> && git push origin v0.1.6
gh release create v0.1.6 build/dist/Vignette-0.1.6.dmg build/dist/appcast.xml \
  --title "Vignette 0.1.6" --notes-file notes.md
```

Upload `appcast.xml` with every release, or installs never see the update. Pushing `main` deploys
the website. An agent asks Pete before it pushes, tags or publishes anything.

## Release notes

Release notes are for people who use Vignette, and most of them have never read the code. Each line
says what changed for them.

### What goes in

- Something new they can do.
- A change they will notice in how something looks or behaves.
- A fix for a problem they could have run into.
- Anything they have to do themselves, such as a permission to grant again.
- A renamed setting or menu item, since people look for it by its old name.

### What stays out

- Wording changes, except a rename someone would look for.
- Refactors, tests, docs, the website, the build and the release tooling.
- Tuning too small to notice.
- How it works inside: protocols, logs, file names, settings keys, command line flags, plugin
  versions.

### How to write a line

- **Start with a verb, in the imperative,** as a commit subject does: Add, Fix, Show, Keep, Rename,
  Send, Open.
- **One change per line,** in one short sentence. Aim for 12 words or fewer.
- **Use the words people see.** Name a setting, menu item or button exactly as the app shows it. Say
  screenshot, thumbnail, drawing and editor. Do not say annotator, card, flight, mark, notice or
  inbox.
- **Say what happens, plainly.** No adjectives that praise the change: seamless, smooth, delightful,
  powerful, better, improved. No taglines or bold lead-ins, no exclamation marks, no "we".
- **Put what people will notice most first.** Five lines a section at most. Cut the rest.

### Layout

```
## What's new

- Open a new screenshot in the editor from where you took it, with Instant Draw on.
- Rename "Open to Draw" to "Instant Draw".
- Send from the message box with Return.

## Fixes

- Show why a send failed, every time.

## Install

On 0.1.2 or later, choose Update Available… in Vignette's menu bar menu, or Check for Updates…,
then Install Update.

On an earlier version, download `Vignette-<version>.dmg` below, open it, and drag Vignette to
Applications to replace the old copy. It needs macOS 14 or later. The app is signed with a
Developer ID and notarized by Apple.
```

Leave out a section that has nothing in it. The Install section is the same every time, with the
version filled in.

### Examples

| Not this | This |
|---|---|
| **Better with the ChatGPT app.** Send now starts on the Codex thread you're looking at. | Start Send on the Codex thread the ChatGPT app is showing. |
| A card says one thing at a time, and a send's failure is never lost. | Show why a send failed, every time. |
| Rendered files are immutable results with a unique id. | Save each copied drawing as its own file. |
| The bow's cap goes from 64 to 240 pt. | Nothing. It is too small to notice. |
