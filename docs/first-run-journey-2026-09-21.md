# The first-time journey, discovery to habit

A map of what a new user meets, stage by stage, and where the friction is. Stages are named for the
question the user is answering at that moment, because that is what decides whether they continue.

Stage 4 has its own plan: [first-run-setup-2026-09-21.md](first-run-setup-2026-09-21.md).

## The stages

| # | Stage | The user's question | Ends when |
|---|---|---|---|
| 1 | Discover | Is this for me? | They want it |
| 2 | Obtain | Can I get it? | They have a build on their Mac |
| 3 | Launch | Is it running? | They know it is there |
| 4 | Set up | How do I call it? | The shortcut works and they know it works |
| 5 | Prove | Does it do the thing? | One screenshot captured, drawn on, and used |
| 6 | Return | Do I reach for it again? | It is the reflex, not a thing they remember to try |

Depth (stitch, the queue, the selection strip, the agent loop) belongs inside stage 6. Nobody
explores a tool they have not yet trusted.

## Stage 1: Discover

**Today.** vignette.pete.design, the GitHub repo, and Pete's posts. The site leads with the 2010
question, a demo video of the agent loop, and a 3x3 feature grid.

**Friction.** The demo video shows the agent round trip, which is the experimental feature, not the
everyday one. A visitor deciding "is this for me" is most likely a person who takes screenshots, not
a person who wants an agent to draw on them. Worth checking whether the first thing they watch is
the thing most of them came for.

## Stage 2: Obtain

**Today.** There is no download. The site and README both say so and point at building from source:
clone, `pnpm install`, `./scripts/run.sh`, needing Xcode, `xcodegen`, `pnpm`, and macOS 14.

**Friction. This is the hard stop, and it ends the journey for nearly everyone.** Everything below
stage 2 is currently reachable only by people who own Xcode.

Three things stand between here and a download:

- **The tldraw key.** The stated blocker is that the Hobby key waits until the repo is public
  (`foundation-review-2026-09-15.md`, step 1). The repo is public now, so this condition may already
  be met. Worth confirming before designing anything else in this stage.
- **Packaging.** `scripts/build.sh` has no zip, dmg, notarize, or staple step. There is no artifact
  to hand anyone.
- **Gatekeeper.** The hardened runtime is on and the build is Developer ID signed, so notarizing is
  a build-pipeline job rather than a code change. Until it is done, a downloaded copy meets the
  "cannot be opened" dialog, which is its own stage-3 cliff.

## Stage 3: Launch

**Today.** The app has no main window. A menu bar icon appears, and one toast says the watch folder
and that launch at login is off. If `~/.claude` or `~/.codex` exists, the Settings window also opens
at the Agents tab, without activating.

**Friction.**

- A menu bar app that opens no window on first launch leaves the user unsure it started. The toast
  is the only evidence and it expires.
- The first window a new user may ever see is the agent-skill offer, which is the experimental
  feature, shown before they have taken a single screenshot.
- Self-builders on an ad-hoc signature lose the Accessibility grant on every rebuild
  (`building.md`), so their shortcut keeps dying. This only bites developers, but today developers
  are the only users.

## Stage 4: Set up

**Today.** Nothing asks. The shortcut default is `cmd+shift+6`. The user finds Settings on their
own, or never learns there is a shortcut.

**Friction and the plan.** See [first-run-setup-2026-09-21.md](first-run-setup-2026-09-21.md). The
core point: the Accessibility prompt must fire as the answer to a choice the user just made, never
during launch.

## Stage 5: Prove

This is where the product either earns the habit or does not, and it holds the two sharpest problems
in the whole journey.

**The empty stack is silent.** A new user who tries the shortcut before taking any screenshot gets
nothing at all: no window, no toast, no message. `ThumbnailController.swift:343` returns `.empty`
and `AppDelegate.swift:947` writes one line to a log file the user does not know exists. The natural
first act after setting up a shortcut is to press it, and the natural conclusion is that the app is
broken.

This also breaks the "try it" confirmation step proposed for stage 4, on a Mac whose screenshots
folder is empty.

**Apple's thumbnail is still on, so the first capture shows the old experience.** First run mirrors
whatever macOS was already doing (`Settings.fromSystem`, `Settings.swift:82`), and macOS ships with
the floating thumbnail on. So the first Cmd+Shift+4 shows Apple's thumbnail in the bottom-right
corner, and macOS holds the file back until that thumbnail expires, roughly five seconds. Only then
does the watcher see the file and Vignette's own card appear.

The first capture therefore reads as: the thing I already had, then a pause, then something new. The
promise is "the same shortcuts, better afterwards", and the first try delivers the old behaviour
first and the new behaviour late.

Turning `appleThumbnail` off is one toggle the app already owns and already writes. The reason it is
off-limits today is the deliberate rule that first run changes nothing about the user's machine
until they ask, which is a good rule. The opportunity is to find the moment where they do ask.

**Also in this stage, unevidenced and worth watching:** after Done, does the user know where the
annotated file went? The card takes a copied mark and `<name>-annotated.png` lands beside the
original, but nothing names the file on screen.

## Stage 6: Return

**Today.** Nothing teaches anything. The Draw hint over a card's corner buttons is the only in-product
teaching, and the selection strip's labels are the only place a shortcut is ever shown.

**Friction.** Stitch, the queue, drag-out, Copy Drawing, and the agent loop are discoverable only by
reading docs or by accident. Whether that matters depends on whether stage 5 produced a habit; a
user who reaches for the shortcut daily will find them, and a user who does not never will.

## What to decide next

1. Stage 2 is worth more than every other stage combined right now, because it gates them. Confirm
   the tldraw Hobby key situation first, since it decides whether stage 2 is a week or a quarter.
2. Stage 5's two problems are small, self-contained, and affect every user who ever gets that far.
   They can be fixed before stage 2 is solved.
3. Stage 4 has a plan and is ready to build.
