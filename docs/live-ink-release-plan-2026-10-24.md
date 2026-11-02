# Live ink: the plan to release it (2026-10-24)

This plan takes live ink from branch `live-ink` into main and into a public release. It replaces
the "Before it ships" list that `docs/live-ink.md` held from 2026-10-18 to now, and every item from
that list is placed here.

It assumes Pete has decided to ship. On 2026-10-18 the proposal
(`docs/live-ink-proposal-2026-10-18.md`) decided to freeze the branch for two weeks and measure
use first. Its numbers still stand: the chord was used 0 times on 10-11 to 10-13, against 65
screenshots sent, and every number came from one person. A public release is the measurement that
proposal said was missing: "No one but you." Decision 1 below asks whether the freeze is dropped.

## Where it stands

- **The branch.** `live-ink` is 244 commits ahead of main and 14 behind. The merge base is
  2026-10-18. 46 commits are not pushed.
- **The size.** About 14,200 lines of new Swift are live ink, and 177 unit tests cover it.
  No e2e scenario does.
- **The conflicts.** A test merge of main conflicts in 9 files: `AGENTS.md`, `AnnotationController`,
  `AppDelegate`, `CardNotices`, `DebugPanel`, `ScreenshotRequests`, `ThumbnailController`,
  `media/trailer/trailer.py` and `scripts/e2e/scenarios.py`. Main's 14 commits include the
  screenshot key and the annotation run's openings. Both reach the files the note cards and result
  cards changed.
- **The gate.** Live ink runs only when both `liveInk` and `debug` are on (`Settings.usesLiveInk`).
  Its switch, the menu item and the speech rows are all inside the debug block. A fresh install
  never sees it.
- **Other work on the branch.** These ship with live ink unless they are taken out:
  - the wait before a send goes (`SendGrace`)
  - the session menus (`SessionMenu`, `SessionPlaces`, More Sessions, the herdr tab label and the
    inbox mod's goal)
  - the spinning check on a copied card (`CheckCoin`)
  - the automatic microphone choice
- **Plugin and protocol.** The plugin goes from 6.2.2 to 6.3.12, the skill from 10 to 21, and
  the reply protocol from 1 to 5. A Claude Code session that is already open needs
  `/reload-plugins`.
- **Already checked.** macOS 14.8 and 15.7 in VMs: light and dark mode, full screen, Spaces, a
  resolution change and display sleep. Pete tried two displays and sleep on 2026-10-22, and both
  worked. The 2026-10-18 list still named those two as untried.
- **The last release.** 0.1.6 was cut on 2026-10-03. Main has 45 commits since then, which ship in
  the same release.

## What cannot ship as it is

1. **The shadow log.** `SendContext`, `SendContextAuthors` and `SendContextShown` (1,105 lines)
   record every capture, send and note into `send-context.jsonl`. Nothing gates them: they run for
   anyone on the branch, and live ink being off does not stop them. The author search reads
   `~/.claude/file-history` and runs Vision on each capture. Removing them takes more than deleting
   the files, because `LivePacket`'s `LiveReads` and `InboxModStore` call into them. The log waits
   for the session selection rescore on 2026-11-01.
2. **The debug gate.** It comes out, along with the error lines and docs that name `debug` as a
   requirement.
3. **Silent failures.**
   - Without Screen Recording, the chord draws and the failure shows only after an ask.
   - Without the microphone or the speech model, speech fails with a log line and nothing on
     screen.
   - A missing or signed-out `claude` shows only as a failed ask.
4. **A billed process on every press.** `chordChanged(.began)` calls `responder.prepare()`. With no
   process running, that starts `claude -p` and sends a warm-up ask. So holding ⌃⌥ by accident, or
   inking for a note that goes to a session, costs a warm-up: $0.001 to $0.01 by
   `docs/live-ink-ask-cost-2026-10-06.md`, or plan usage on a subscription. That is fine for the
   builder but not for someone who never asked Claude anything.
5. **Wrong words.**
   - `docs/using.md` says "Turn it on in Settings → General". That is false while the gate exists.
   - It also says marks "don't follow the window under them". That contradicts ADR 0024.
   - The skill tells a Codex thread that a result card follows the turn. Codex turns are not
     watched.
   - The README and the site say nothing about live ink.

## Decisions for Pete

These come one at a time, each when its phase starts, with a recommendation. They are listed in
the order they block work.

1. **The freeze.** Decided 2026-10-24, Pete: "Drop the freeze". It would have measured one person
   again; the release measures others.
2. **The 2026-11-01 rescore.** Decided 2026-10-24, Pete: "Keep the rescore". The shadow log comes
   out on 11-02, and the merge into main waits for that.
3. **The other work on the branch.** Decided 2026-10-24, Pete: "Ship all four" (send grace, the
   session menus, the check coin, the microphone choice). The session menu reads herdr and the
   inbox mod. `InboxModStore` answers "no goal, no badge" when the mod's file is missing. Phase 3
   checks that a Mac with neither gets plain rows.
4. **How people turn it on.** Decided 2026-10-24, Pete: "Setup page and one-time offer". It needs
   Screen Recording and Accessibility, and it takes over ⌃⌥ for every app. Pete, the same day: "i
   want the setup step to be fun and whimsical and stand out". So the page is a designed moment
   with its own concept, chosen by Pete from prototypes, and the shortcut page's pattern below is
   only its floor.
   - Its own setup page, after the shortcut page. The chord is drawn as keys that go
     down while held, and a try on the page turns into a check, as the shortcut page does. The page
     has a Screen Recording row, and a microphone row once speech is on.
   - The page's switch starts on, as the skill page's does. Each permission is asked from a button
     the person pressed.
   - An install that already finished setup gets the same offer once, in Settings, as `agentSkill`
     does.
   - The alternative is on by default with no page. Then every install asks for Screen Recording
     on a question nobody asked, which the setup rules forbid for Accessibility.
5. **Saying what leaves the Mac.** Decided 2026-10-24, Pete: "Notice on page and in note".
   - A notice in two places. One is a sentence on the setup page and under the switch:
     Claude sees a picture of the window, its title and its URL, through your own Claude Code, at
     about one to four cents an ask. The other is a line in the note until the first send.
   - Asking first adds a step to the one gesture that must be cheaper than a screenshot.
6. **People without `claude`.** Decided 2026-10-24, Pete: "Check, then notes go to sessions".
   - Check for `claude` and its sign-in when live ink is turned on, and again on the
     setup page. When it is missing, the note opens on the sessions, and its target says why.
   - Live ink still draws, and notes still go to Claude Code and Codex sessions. A Codex responder
     waits: ADR 0021 measured `codex exec` at 16 to 23 s cold.
   - Keep the `sonnet` alias rather than pinning a model. The alias follows the newest Sonnet, and
     `--json-schema` holds the answer's shape whatever the model.
7. **The chord.** ⌃⌥ was fixed in code. It is also VoiceOver's modifier, and some window managers
   use it. Decided 2026-10-24, Pete: "⌃⌥ default, choosable". Where it is chosen was decided on
   2026-10-29: Pete kept the "Hold to draw" picker beside the Live ink switch.
   - Keep ⌃⌥ as the default, and let people choose another pair in "Hold to draw", under the Live
     ink switch. The pair sits with the switch it belongs to. The stack's shortcut control offers
     double taps and key combinations, which do not fit a held pair.
   - Pausing live ink while VoiceOver runs is the other way to handle VoiceOver. The choice of
     pair covers both.
8. **What to trim.** Decided 2026-10-24, Pete: "Trim as recommended". `liveInkSendWhenQuiet` stays
   on until Pete has tried it. These were listed as Pete's to decide on 10-18:
   - *Pointer styles:* ship Lamp, and delete the other styles and `PointerLab`.
   - *Tweaks:* delete the `liveInkField*` keys of the deleted styles, and keep the rest in
     `UITweaks`, where tuned numbers live.
   - *Speech experiments:* one behaviour each. For `liveInkListenUntil`, keep listening until
     release, which Pete runs. For `liveInkSendWhenQuiet`, Pete's call after a try.
   - *`live-ink-clear`:* no `debug`. It only erases ink, as the menu item does.
   - *Labs:* Check Lab and Intro Lab stay behind `debug`, as Intro Lab is on main.
9. **The version.** Decided 2026-10-24, Pete: "0.2.0". `docs/releasing.md` steps the patch number, but this
   release adds a second way into Vignette. The release notes rule there gets one line saying
   when the minor number moves.
10. **The site and the trailer.** Creative direction is Pete's, so this comes as options when phase
    5 starts. The proposal's position is that live ink is how you point for the agent channel, not
    a separate product. That suggests a section beside Send, with the headline unchanged. Whether
    the trailer gets a live ink beat is the second question.

11. **Codex.** Pete, 2026-10-24: "can we have live ink support other agents like codex?" Live ink
    reaches Codex in one way today. A note goes to a Codex thread as a card, but no result card
    follows the turn, because Vignette sees no Codex turns. Decided 2026-10-24, Pete: "Spike both
    for this release". Codex becomes a peer of Claude Code in the release, if the spike's numbers
    hold:
    - **A Codex responder.** It is a long-lived `codex app-server` with one thread, kept warm the
      way the `claude` process is. ADR 0021 rejected `codex exec` at 16 to 23 s cold, but it never
      measured a warm app-server. `AppServer.swift` already speaks that protocol. The spike
      measures the first token, image input and a structured answer. The responder is whichever
      agent is installed, or the person's choice when both are.
    - **Codex result cards.** A note's turn end is seen on Codex too, so a change under the ink
      makes a result card, as it does for Claude Code. How to see a Codex turn end is part of the
      same spike.
    - **Other agents,** such as Cursor, come through the proposal's bet 3b, a local `look` tool that
      any agent can call. That one follows the release.

The proposal's bets (the bare chord, the checked result card, the agent asking you to point) are
not in this release. Each can follow on main.

## The phases

Each phase is delegated as before: a worktree under `~/Code/worktrees/vignette/`, a brief, a
report, tests run to a log, and live checks in the `vignette-e2e` VM. Nothing merges into main
before phase 7.

### Phase 1: bring main into live-ink (now, no decision needed)

- Merge main into `live-ink` and resolve the 9 conflicts. The branch's note cards and result cards
  take the screenshot key and the openings, rather than keeping their own paths.
- Run the unit tests. Run the e2e suite in the VM, because main changed `scenarios.py` and the
  merge touches the send path.
- Repeat whenever main moves, so the final merge into main is a fast-forward.

### Phase 2: remove the shadow log (2026-11-02, after the rescore)

Done on 2026-11-02, on branch `shadow-log`. `LiveReads` went too: the author search was its only
reader.

- Delete the three `SendContext` files, their tests and every call site. `LiveReads` either goes
  or becomes a counter of its own, if the author search was its only reader.
- A launch deletes `send-context.jsonl` from Application Support, as it removes the web editor's
  leftovers, with one log line.

### Phase 3: make it a product (after decisions 3 to 7)

- Remove the gate. Move live ink out of the debug block into General, with the chord and the
  permissions.
- Build the setup page and the one-time offer for existing installs.
- Check for `claude` when live ink is turned on. Start the responder only when the note's target
  is Claude, at the first stroke rather than the press.
- Say each missing permission when it matters:
  - Screen Recording on the press, before any drawing.
  - The microphone and speech model in the note.
- Make the chord choosable. Handle VoiceOver.
- Give the note and reply popovers accessibility labels.
- Check that a Mac without herdr or the inbox mod gets plain session rows.
- Add every new string to `docs/voice.md`.

### Phase 4: trim (after decision 8)

Delete what decision 8 drops, with its tests, docs and tweak bounds. Keep the defaults Pete tuned.

### Phase 5: words (after decision 10, partly in parallel with phase 3)

- Fix `docs/using.md`. Add live ink to the README and to the site's draft.
- Make the skill tell Codex the truth about result cards. Raise the skill and plugin versions.
- Bring `docs/live-ink.md` and `AGENTS.md` up to date. Mark the dated notes that ADR 0024
  superseded (the step 3, anchoring and integration notes) with one line at the top each.
- Draft the release notes per `docs/releasing.md`. They cover live ink, the riders, and the need
  for `/reload-plugins` in an open Claude Code session.

### Phase 6: verify

- **Unit tests** on the merged branch.
- **New e2e scenarios** with `scripts/e2e/fake_claude.py`, which is ready:
  - an ask answered on the window
  - a note sent to a session
  - an ask without Screen Recording
  - an ask with no `claude`
- **The full suite** with `e2e.py run --input`, in the VM. `docs/releasing.md` requires every
  scenario to pass.
- **A fresh Mac** in the VM: setup with the live ink page, then the first ask.
- **An update from 0.1.6** in the VM, through a scratch feed (`VIGNETTE_FEED`): the one-time offer,
  and a session's reply after `/reload-plugins`. Check also that a real session runs the reply
  helper without a permission prompt. That was never checked.
- **A review of the whole branch** against main. 34,000 lines have been reviewed piece by piece but
  never as one change. Findings are fixed on `live-ink` before the merge.
- **Pete's try** on his own Mac, of what synthetic input cannot prove: the chord, speech with
  AirPods, and the setup page.

### Phase 7: release

- Ask Pete before each outward step.
- Push `live-ink`, then merge it into main with history kept, since the docs cite its commits.
- Pushing main deploys the site, so the site's changes land in the same push.
- Cut the release per `docs/releasing.md`.
- Then remove the worktrees kept until the push (more-sessions, session-menu, mic-choice,
  project-menus, ink-queue, findings, multi-window, ink-on-window, ask-cleanup) and the branch
  `backup/ink-on-window-pre-rebase`.

## Order and timing

- **Now.** Phase 1 can start. Decision 1 is the only question before it.
- **Through 11-01.** Phases 3, 4 and 5 run in parallel as their decisions come in.
- **11-02.** Phase 2.
- **After that.** Phase 6, then phase 7.

The earliest release is the first week of November. That date is a guess from the size of phases 3
and 6. It is not measured.

## What would change the plan

- **The rescore moves the start of Send.** Phase 3's note target follows it. It did not: on
  2026-11-02 Pete chose to keep Send as it is.
- **Phase 1 takes more than a day.** Then the two branches have drifted further than the 9 files
  show, and the review in phase 6 starts earlier.
- **The fresh-Mac run finds the setup page too long.** Then the live ink page becomes an offer
  after setup, as the skill offer was before it had a page.
