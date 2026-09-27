# Pre-release fixes (2026-09-26)

Pete asked for two problems and six opportunities to be addressed, from a list of what stood out
while working on Vignette before its public launch. This note says what each one was, what was
built, and how it was checked. Nothing here is committed yet.

## 1. Send stopped working after 50 sends

Requests were never cleared on their own, and at 50 open requests Send refused, with only
`vignette://requests?clear=all` to get past it.

- A send past `ScreenshotRequests.maxLiveRequests` now clears the oldest open request first, and
  logs `[requests] cleared <id> <name>: the oldest of 50 open`. Clearing is the same as a clear by
  hand: the request stops taking replies and its image goes.
- The limit is kept because it bounds what the app keeps: 50 PNGs and their tickets. An agent
  answers within the hour, not fifty sends later.
- The oldest is cleared only once the new request is stored, so a send that fails to store clears
  nothing.
- A cleared request's folder is deleted a week later (`ScreenshotRequests.clearedKept`, dated by its
  `request.json`), at launch and at each send. Before this, every request stayed on disk and was
  read at every launch. A request whose reply is still in the watch folder keeps its folder, because
  the reply's card is shown only while its record exists. `testPruningKeepsARequestWhoseReplyIsStillACard`
  checks that.

## 2. A changed default never reached an existing install

Every `ui` value was written into settings.json, so a file kept each default as it was when the key
first appeared. Pete's own file held the old `insertDuration`, which is how the pause before a new
card's slide came back after its default changed.

- settings.json now holds only the `ui` values that differ from the defaults. The encoder that
  writes the file sets `UITweaks.differencesOnly`; `UITweaks.encode(to:)` then skips a value equal
  to its default. Every other encoding is whole, since loading merges the file over it.
- The file's version is 2. Its first version dropped each `ui` value that had once been a default,
  on the reasoning that nobody chose it. That was wrong for Pete's file: it reset `slideInDuration`
  from 0.4, which he had run for 12 days, to 0.75, and `annotationScreenInset` from 60 to 65. It
  could not help anyone else, since every `ui` default in v0.1.0 and v0.1.1 equals today's. So the
  step to version 2 changes no value, and 0.4 and 60 are the defaults now: what Pete runs is the
  default.
- A build from before version 2 opens a version 2 file read-only, as it would any newer file.
- Checked by `testFileHoldsOnlyTheUIValuesThatDiffer`, and on the stage copy: a first launch
  writes `"ui": {}`.

## 3. Send reaches Claude Code only through herdr

Most people who download Vignette will not run herdr, and without it Claude Code never appears in
Send's menu, with nothing saying why.

- Under Claude Code, the Agents tab and setup's last page now say "Send reaches Claude Code through
  herdr, which Vignette can't find.", with herdr linked to herdr.dev, when no herdr is where Vignette
  looks for it (`AgentName`). A send that fails for the same reason says "Vignette can't find herdr,
  which Send uses to reach Claude Code." Vignette checks a fixed list of paths, so neither says herdr
  isn't installed.
- Reaching Claude Code without herdr is not built. It would need a way to put a message into a
  running Claude Code session that Claude Code itself offers.

## 4. A first send stalled on a permission prompt

Claude Code asks before it reads a file outside the session's folder, and each send's image is in a
request folder of its own. The session stopped on the question, herdr reported the pane `blocked`,
and the next Send to it failed.

- Tried first: `allowed-tools` in the skill's frontmatter. A headless Claude Code run with the
  trailer's own config showed it makes Claude Code ask to use the skill instead, so it was
  reverted.
- Built: `ClaudeReadRule`, one rule in `~/.claude/settings.json`'s `permissions.allow`:
  `Read(~/Library/Application Support/<bundle id>/requests/*/image.png)`. The same headless run with
  that rule read the image with no denial.
- The Agents tab has a switch for it, "Claude Code reads your drawings without asking". Setup's last
  page offers it too, on to start like the skill switches, and applies it when the window closes.
- The switch writes through a link to the file, since people keep it in a dotfiles repository, and
  keeps the file's permissions. A plain atomic write replaced the link with a copy.
- A send refused because the session is waiting on a question says, while the rule is off, that
  Settings > Agents can stop it asking about drawings.
- The switch changes nothing else in the file. A file that does not parse, or whose permissions are
  not in the expected shape, is left alone and the switch says why. Off leaves the file as it was.
- Checked by four tests in `SkillInstallerTests`, and on the stage copy with a scratch home folder
  (`CFFIXED_USER_HOME`): the switch wrote and removed the rule, and setup's Done added it with the
  skill.

## 5. The last two toasts in the agent loop

- The "<session> replied" toast is gone: the reply is a card of its own.
- A reply that was accepted and could not be made a card now shows on the card it answers, as
  "Reply not shown" (`SendMark.State.replyFailed`). When the agent's image or marks did not read,
  the reason is "Ask Claude Code to send it again."; when Vignette could not write it, "Vignette
  couldn't save the reply. See the log." The mark does not replace a later send of the same card
  that is still waiting for its answer. The
  card is found from the request's `source` in the watch folder, so this works after a relaunch
  too, when the import is retried. A card off screen comes back as a lone thumbnail, as a failed
  send does.
- Checked on the stage copy: a pending reply whose image was removed failed its import at launch,
  and the sent card came up with the mark.

## 6. The stack stuttering while it narrows

Measured again, and nothing was changed. The September 23 note measured a build whose click hint
followed the pointer on every frame. That hint is gone since this morning, and with it most of the
hover work.

Two opens and two closes of wide images, pointer over the column, 21 cards, per narrowing or
widening:

| Build | Commits in 1.1 s | Main thread in commits | Median commit | Commits over 8.3 ms |
| --- | --- | --- | --- | --- |
| Release (stage copy) | 158 to 185 | 320 to 475 ms | 1.9 to 2.4 ms | 0 to 1 |
| Release, hover held still while the column moves | 148 to 191 | 320 to 385 ms | 1.8 to 2.3 ms | 0 to 1 |
| Debug (what `scripts/run.sh` builds) | 101 to 143 | 200 to 405 ms | 2.0 to 2.5 ms | 0 to 4, longest 31 ms |

The Debug build also drew about a quarter fewer frames in the same windows, which the count of long
commits does not show.

- Holding the hover still (option A in `docs/stack-narrowing-2026-09-23.md`) made no measurable
  difference, so it was taken out again.
- In the Release build people download, a narrowing drops at most one frame. The drops Pete sees in
  his own build are partly the Debug build's.
- Laying out only the cards in view (option B) is what is left if it still shows. It is 1 to 2 days
  and touches the stack's transitions.
- An earlier pair of traces opened 1600 by 1000 images, which never narrow the stack, so it measured
  no narrowing; `stack.widthScale` in `[state]` is the check.

## 7. Test tools kept in the repo

- `scripts/measure/frames.sh`: `extract`, `sheet` and `track` on a `screencapture -v` recording.
  Swift, compiled on first use, so it needs nothing a Mac with Xcode lacks.
- `scripts/measure/commits.py`: the commits in an Instruments trace, by quarter second or after
  given times.
- `scripts/fake-herdr`: one fake Claude Code session that answers Send as a mode file says. The
  stage copy's herdr wrapper (`drive.write_herdr`) runs it when the app is launched with
  `FAKE_HERDR` set, and runs the real herdr otherwise.
- AGENTS.md says how to use each, under Measuring and Testing Send.

## 8. AGENTS.md

Reorganised as the 2026-09-23 review proposed: a "Before you drive the app" list opens The loop,
the rules sit under subheadings, the buried driving rules moved to where a reader looks for them,
and the build bullets are one.

## An incident during the checks

A Release stage copy started without `VIGNETTE_SETTINGS` at 21:57:23 (pid 1281). It ran on Pete's
real settings file and watch folder, and it wrote the settings file at that moment: with this
change, that is the version 2 migration his own build would make at its next launch. It started
when the driver sent `open -a <Release stage copy> vignette-demo://state` right after a Debug stage
copy of the same bundle id had run; the Release instance Instruments had launched was up, and
LaunchServices launched another. Stopping it was refused to the agent, so it is Pete's to stop.
