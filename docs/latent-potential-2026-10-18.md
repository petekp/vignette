# Latent Potential: Vignette (2026-10-18)

A review of value already present in Vignette: what it is, what it holds, and the few moves that would use it. Every usage number comes from Pete's own log, so it describes one user.

**Thesis:** The most valuable version of Vignette is the visual channel from a Mac developer to the agent session they are working with: capture or point, Send lands in the right Claude Code or Codex session, and the agent's pictures come back as cards. The screenshot stack is how people install it. Live ink is a second way into the same channel.

The runner-up is live ink as the product. It has the higher ceiling, but on the evidence so far it is used on the days it is being built, and Send is used on every working day.

All usage numbers below come from one person: Pete's own log, `~/Library/Logs/Vignette.log`, covering 2026-10-08 to 2026-10-18. Nobody else's use is visible. That limit runs through the whole report.

## 1. What this actually is

Vignette is a macOS 14+ menu bar app. It watches the folder macOS saves screenshots to and turns off Apple's floating thumbnail. Each new file becomes a card in a stack in the screen's corner. From a card you can copy, drag, trash, stitch several images into one, or open a native drawing editor with boxes, ellipses, arrows and text notes.

The second half is a file-based loop with coding agents. Send renders the drawing and delivers one line to a running Claude Code session, through a bundled plugin's inbox, or to a Codex thread, through `codex queue`. The agent can push images back with `vignette://add`, optionally with marks, or answer a request with an authenticated reply. Either one arrives as a new card. Every action is a `vignette://` URL, and a tagged `[state]` JSON line reports what the app is doing.

On the `live-ink` branch there is a third mechanism. You draw on the live screen over any app while holding a chord. Vignette sends a window capture, its OCR text lines and your ink to a persistent `claude` process. The answer is drawn back on that window as light.

**Stated north star.** The public surfaces disagree with each other:

| Surface | What it says |
|---|---|
| GitHub description | "MacOS's screenshot tool, just better in every way." |
| Site `<title>` | "Vignette: the agent-native screenshot tool" |
| Site, act one | "first and foremost a seamless replacement for the screenshot tool built into macOS" |
| `docs/agents.md`, line 3 | "The agent features are secondary and experimental." |
| `docs/recordings-north-star-2026-09-22.md` | "A recording becomes the few frames worth looking at" (nothing built) |

**Revealed north star.** Effort and use point in two different directions:
- **Effort.** About 85% of the lines changed in the last 14 days went to the unreleased `live-ink` branch: 194 commits. Its `Sources/` is 43,579 lines against main's 26,869. Nothing has shipped since 0.1.6 on 2026-10-04.
- **Use.** In the 10 days of log, the plain Send path dominates everything else, and almost all of it went to projects other than Vignette.

| Action, 2026-10-08 to 10-18 | Count |
|---|---|
| Send to an agent session | 178 |
| Copy | 71 |
| Done (copy a drawing) | 10 |
| Live-ink asks with words, on the real settings file | 47 |
| Agent pushes back (`[add] ok`) | 50 |
| Agent pushes that carried marks | 1 |
| Published agent replies | 14 |
| Stitch | 0 |

**Where the Sends went.** By the folder each session runs in, 170 of the 178 Sends went to sessions in at least five other repositories, and 8 to sessions in Vignette's own. One other project took 132. Only 6 of the 178 went to Codex.

**The difference between them.** The public story is a better screenshot tool with agents on the side. The effort story is live ink. The use story is Send. Send is the one that is finished and used every working day, across projects that have nothing to do with Vignette.

## 2. Asset inventory

| Asset | Where it lives | What it could be 90% of |
|---|---|---|
| Send to a specific session, with a guard that the session is still the one addressed | `Sources/AgentConnection.swift`, `SessionListing.swift`, `DestinationChoice.swift`, `agent-plugin/` | The channel this report argues is the product |
| A measured, better rule for picking the session | live-ink: `docs/session-detection-exploration-2026-10-08.md`, `Sources/SendContext.swift` (marked "Temporary: it is removed before live ink reaches main") | Send landing in the right place without a correction |
| The `[send] target` and `[send] prepared` log pairs | `Sources/ScreenshotRequests.swift` logging | A standing miss-rate metric for routing |
| Request store with an authenticated reply (per-request ticket, digest identity, receipts) | `ScreenshotRequests.swift`, `ReplyProtocol.swift`, `ReplyCommand.swift`, ADR 0006 and 0013 | A general app-to-agent-and-back protocol |
| OCR lines with ids, ink as boxes, lines picked near the ink, measured token cost | live-ink: `Sources/LivePacket.swift`, `docs/live-ink-ask-cost-2026-10-06.md` | Text and marks as data on every Send |
| Live ink's ask path: chord, window anchors, persistent responder, streamed light | live-ink: `Sources/Live*.swift`, ADR 0019 to 0022 on the branch | Point-and-ask on any window |
| Agent marks JSON with one validator | `Sources/AgentMarks.swift`, `Drawing.swift`, `docs/commands.md` | An interchange format for agents pointing at pixels |
| Stitch laid out for the vision model's resize | `Sources/Stitch.swift` (`readerLongSide` 1568) | Recordings turned into a frame sheet; a packing utility |
| Native editor as a pure reducer, one renderer | `EditorCore.swift`, `MarkRendering.swift`, ADR 0003 and 0010 | An embeddable Swift annotation component |
| Agent-drivable control surface | `Commands.swift`, `StateReport.swift`, `Log.swift` | A pattern for making any Mac app safe for agents to drive |
| E2E harness with a separate test copy, scratch home and state-gated input | `scripts/e2e/` | A test kit for menu bar and agent-integrated Mac apps |
| Frame and commit measurement tools | `scripts/measure/`, `scripts/input.swift` | A jank-measurement toolkit for Mac apps |
| Dated macOS measurements | `docs/icloud-files-2026-09-25.md`, `flight-press-2026-09-23.md`, `test-isolation-2026-09-29.md` | Technical writing other Mac developers would otherwise spend days on |
| Trailer pipeline that re-records from source | `media/trailer/` | A demo recorded again on every release |
| Signed, notarized releases with a Sparkle feed | `scripts/release.sh`, `Updater.swift`, `project.yml` | The path for any of this to reach existing installs |
| Site with an in-browser demo | `site/index.html`, `site/demo/` | A no-install trial for whatever the product becomes |
| Fork support from the bundle id | `Sources/Identity.swift` | A white-label "send the screen to our agent" tool for a team |

## 3. Top opportunities (ranked)

### 1. Send lands in the right session

- **The move:**
  - Port the "sent to last within 2 hours" rule from the branch to `DestinationChoice` on main.
  - Guard it at a project switch: when herdr's focused pane is in a different repository than the last session, keep the focused pane.
  - Log the proposed and the final target together, so the miss rate is a standing number.
  - Leave content matching out.
- **Channels:**
  - `Sources/DestinationChoice.swift` (`choose`, line 47) on main.
  - The rule and its data in `docs/session-detection-exploration-2026-10-08.md` on the branch.
  - The existing `[send] target` and `[send] prepared` log lines.
- **Mechanism of value:**
  - Pete changed the proposed target on 57 of 178 Sends (32%).
  - A miss someone catches costs a correction. A miss nobody catches puts a picture of the screen in the wrong conversation.
  - Replayed over the log, the rule is right on 134 of 160 Sends, against 113 for the shipped default. That is 45% fewer misses.
  - The gain is flat between 1 and 6 hours, so 2 hours is not a fragile number.
  - This serves anyone who runs more than one session, which is the person Send exists for.
- **Why now:** The finding was measured on 10-08 and sits in code labelled temporary on a branch. If the branch stays a lab, the best Send result of the fortnight stays with it.
- **Cheapest probe:**
  - Already run once: the replay above, a script over the log's `[send]` lines that was not kept.
  - Next, count the first Send after each project switch in the replay. If the rule is wrong on most of those, the guard is mandatory.
  - Then run it in Pete's own build for a week and recount. Success is fewer than 15% of targets changed.
- **Cost and displacement:**
  - About a day.
  - Main has no stored "last sent" target today. Its "used last" means transcript recency, so the rule needs a small piece of new state.
  - It displaces branch time.
- **Skeptic's objection:** The rule overrides the default on 154 of 178 Sends, which turns herdr's focus into a rare fallback. A replay counted 13 Sends where the shipped default was right and the rule would have picked a stale session. Those are the silent misses the session doc calls the safety risk. The replay is also in-sample: the log starts the day the rule was proposed. **Partly answered.** The project-switch guard targets exactly those 13. The week in Pete's build is the out-of-sample test. The objection stands until that week runs.

### 2. Say what it is, in one sentence, everywhere

- **The move:**
  - Pick one sentence and use it in the GitHub description, the site `<title>` and hero, the README opener and `docs/agents.md`.
  - Suggested: "Vignette is how you show your coding agent what's on your screen."
  - Delete "The agent features are secondary and experimental."
  - Keep act one, the screenshot replacement, as proof of craft rather than as the category.
  - Don't lead with "your agent draws back" yet.
- **Channels:** `README.md`, `site/index.html`, the repo description (`gh repo edit`), `docs/agents.md`, `docs/TODOS.md` ("Vignette without the agent features"), and the next release note.
- **Mechanism of value:**
  - "A better screenshot tool" puts Vignette in a crowded category, where it has 28 downloads.
  - "The screenshot tool that sends to the right agent session" has no direct competitor that I found. It is also what Pete actually uses it for: 178 Sends against 81 copies.
  - The agent-draws-back claim rests on 1 push in 50 carrying marks, and 14 published replies.
- **Why now:** No release since 2026-10-04. The next release note is the cheapest moment to change the story, and it should ship with opportunity 1 so the claim is true for a stranger.
- **Cheapest probe:** Show the current and proposed hero sentences to 5 Claude Code users and ask which one they would install. Half a day of copy, no code.
- **Cost and displacement:** Copy only. The cost is giving up the safer "better screenshot tool" story for a claim Send has to earn for strangers.
- **Skeptic's objection:** All the evidence is one user, who is also the builder. **Answered in part.** I first suspected the Sends were plugin testing, but 170 of 178 went to sessions in other projects. So this is real use by a developer for unrelated work, not testing. It is still one developer. The objection about strangers stands, which is why the probe asks five of them.

### 3. Live ink: let use decide, and harvest it first

- **The move:**
  - Move the two general pieces live ink holds onto main first: the routing rule (opportunity 1), and, if a probe earns it, the OCR packet as data on Send.
  - Log the frontmost app at each ask, one line on the branch, so an ask about someone else's app is distinguishable from testing.
  - Promote the ask path out of `debug` only when asks keep coming on screens Pete is not building.
  - Pause the visual layer until then: `InkGel.metal`, `PointerField.metal`, `CheckCoin.metal`, the labs, `TweakCatalog`.
  - Renumber the branch's ADR 0019 to 0022, since main already has an ADR 0019.
- **Channels:** the branch's `Live*.swift` ask path, the `[live-ink] asking` log line, and Sparkle for the later path to installs.
- **Mechanism of value:**
  - It answers the question the effort has been avoiding, and frees attention.
  - On the real settings file there were 47 asks with words. All fell on days with commits to the branch.
  - On 10-11 to 10-13 there were 0 asks, while 65 screenshots went to agents.
- **Why now:** Every day the branch grows, the merge costs more. Its `Sources/` is already 16,710 lines larger than main's.
- **Cheapest probe:** The frontmost-app log line, then two weeks of ordinary work. Count asks about apps that are not Vignette, against Sends on the same days.
- **Cost and displacement:** The probe is nearly free. The real cost is pausing the work with the most momentum and the most craft.
- **Skeptic's objection:**
  - The branch has commits on almost every day, so "days without commits" is not a usable control. A ten-day pause might fail by construction.
  - **Answered:** the frontmost-app field replaces the commit-day control. It measures what the ask was about, not whether the branch also changed that day.
  - **Left standing:** the 8 wordless asks on 10-17 look like tests, so the 47 overstates real use by an unknown amount.

### 4. Ship from main, with a working download path

- **The move:**
  - Cut 0.1.7 from main with opportunities 1 and 2 in it.
  - Point both site Download buttons (`site/index.html`, lines 46 and 128) at a stable direct link to the DMG instead of the release page.
  - Rewrite `docs/first-run-journey-2026-09-21.md`, which still says "There is no download" (line 34) and gives `cmd+shift+6` as the default shortcut (line 68).
  - Do one timed clean install in the VM, from download to first Send.
- **Channels:** `scripts/release.sh`, Sparkle (`project.yml` line 57), `site/index.html`, the `vignette-e2e` VM.
- **Mechanism of value:**
  - The few machines that check the appcast get the routing fix without doing anything. 38 fetches on 0.1.6 point to roughly 3 or more machines, likely mostly Pete's.
  - The timed VM run finds the step where a stranger stalls. The default shortcut needs Accessibility, which is the hardest permission, and it comes first.
- **Why now:** Fourteen days without a release.
  - Local `main` is 9 commits ahead of `origin/main` and 4 behind it. The 4 include `1079db4` ("CI: run the unit tests on every push").
  - Reconcile the two before cutting anything.
- **Cheapest probe:** One VM run, timed, written into the first-run doc. That checks for an obstacle and doesn't need a sample size.
- **Cost and displacement:**
  - About a day.
  - The asset is named `Vignette-0.1.6.dmg` today, so a stable link means either a stable asset name or a site edit every release. Changing the asset name is a change to `release.sh`, which needs Pete's approval.
- **Skeptic's objection:** At 10 repo page views and about 7 DMG downloads per release, a before-and-after read of downloads is noise. **Answered by dropping that claim.** The value here is the stale doc, the deep link and the timed install, not measurement.

## 4. The reframe

**Current frame:** "MacOS's screenshot tool, just better in every way", with agent features "secondary and experimental".

**Proposed frame:** Vignette is how you show your coding agent what's on your screen, and how it shows you back. You capture or point, Send goes to the session you are working with, and the agent's pictures come back as cards. Replacing Apple's thumbnail is how it gets onto your Mac.

**What changes downstream:**
- **Name:** keep "Vignette" and "Show, don't prompt.", which already fit.
- **README and site:** the hero becomes the channel, and act two moves up, with Send to the right session as its first beat. Act one stays as proof of craft.
- **`docs/agents.md`:** loses "secondary and experimental".
- **`docs/TODOS.md`:** "Vignette without the agent features" becomes an install option. The stack already works with no agent installed.
- **Roadmap order:** Send quality first (routing, then text as data if it measures well). Live ink is judged as a second input into the same channel. Recordings are a third.

**Adoption cost:** half a day of copy. The real cost is a promise that Send has to keep for people other than Pete.

## 5. Worth exploring

- **Text near the marks as data on Send** (`LivePacket.lines(near:)`, on the branch). Unproven: accurate OCR is slower than "tens of milliseconds", and 129 lines cost about 3,650 tokens. Run it on 10 real requests from the request store before building.
- **Agents that actually draw.** 1 of 50 pushes carried marks, though `skills/vignette/SKILL.md` documents them. Add one rule about when to circle, then recount after a week.
- **An agent asks you to point.** A skill step that pushes an image and waits for your drawing. The push and reply paths exist (`ReplyCommand.swift`).
- **Recordings to a frame sheet** (`Stitch.compose`, `Thumbnailer.posterFrame`). Recordings run at 1% to 14% of Pete's captures by month (7 against 528 in October), so it's real but small.
- **A shortcut that needs no permission** as the default for new installs (`Sources/HotKey.swift`, Carbon), keeping the double tap as an upgrade in setup.
- **Three short posts** from measurements already written: the iCloud placeholder freeze, the 6 to 97 ms press handover, and TCC attribution for apps started from a terminal.
- **The E2E kit** (`scripts/e2e/`) lifted out for Pete's other overlay work. The first adopter would be Pete.
- **Agent neutrality** through `AgentConnection`. Wait for evidence first: 6 of 178 Sends went to Codex.
- **The plugin without the app.** Less ready than it looks: `agent-plugin/` is a template that `AgentPlugin.stage` completes, and its inbox is fed only by the app.

## 6. Stop or shrink

- **Live ink's visual layer.** The shaders, labs and tweak catalog shared most of the branch's 194 commits. Pause them until opportunity 3's probe says the ask is used.
- **New contracts in the request store.** `ScreenshotRequests.swift` is 795 lines with acceptance, publication, cleanup replay and a 50-request cap. The store holds 117 requests and 16 replies from two clients. Freeze new guarantees until there is load or an outside client.
- **A dated doc after every step.**
  - Main changed 43,373 doc lines, about 0.8 per source line through W40.
  - AGENTS.md is 121 KB.
  - The branch wrote about 28 notes in 14 days.
  - Write a doc when a decision needs one.
- **Presentation craft for the install moment.**
  - `MenuBarIntro`, `IntroLab` and `IntroFunnel.metal` total 1,038 lines for an animation each install sees once.
  - The trailer was recorded three times in about two weeks.
  - With 10 repo views in 14 days, presentation is not what limits adoption.
- **Stitch as the landing page's one number.** It was used 0 times in the 10 days of log.

## 7. The skeptic's page

**The case against.** There is no sign that anyone but Pete has sent a drawing:
- 28 DMG downloads, some of them his.
- 2 stars, one of them his.
- 0 outside issues.
- 10 repo page views in 14 days.

926 clones in the same 14 days are almost certainly automated. The thesis rests on one developer's habits, and a developer who builds the tool is also its most forgiving user. The honest read today is modest potential with one strong signal. Pete reaches for Send dozens of times a day in projects that have nothing to do with Vignette, and nothing else in the data comes close.

**The hard part.** Pete's own use already chose the product, and it's the plain one. Most of the last two weeks went to the part that is most fun to build. Meanwhile the part Pete uses every day sent to the wrong session about a third of the time. Its fix was measured on 10-08 and left in a file marked temporary. That doesn't make live ink a mistake. It means the effort numbers measure interest, not use, and this review almost repeated the error: five of seven lenses voted to ship live ink before the log was read.

**What would have to be true:**
- Other Mac developers who run Claude Code or Codex have the same habit of showing their agent the screen.
- They would find Send reliable on their setup: plugin monitors, their Claude Code version, Codex.
- Routing in their setup stays within reach of the 15% target.

**First disconfirming signals:**
- **Routing.** In Pete's own build, after the routing rule ships, the changed-target rate stays above 25%.
- **The pitch.** Of five Claude Code users shown the hero sentence, none says they would install it.
- **Live ink.** Two weeks of the frontmost-app log show live-ink asks about apps other than Vignette. That would reverse the ranking of opportunity 3, and would be good news.
