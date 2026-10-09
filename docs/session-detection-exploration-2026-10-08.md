# Session detection: exploration and spikes (2026-10-08)

Vignette has to pick the agent session a drawing goes to: Send's target in the editor, and the
target chip on live ink's note. Today Send starts on the session in herdr's focused pane, and the
note starts on the target picked last. This document gathers what is known, lists what is not,
and records the spikes that answer it. The plan comes after every question below has an answer or
a spent budget.

## What the evidence says today

**The shipped default is wrong almost half the time, and every miss is the wrong project.**
Vignette's log records the default it proposed (`[send] target … focus=pane`) and where the
drawing went (`[send] prepared … to`). Between 2026-10-03 and 10-08 that gives 47 sends of
screenshots. Pete kept herdr's focused pane 26 times and changed it 21 times. All 21 changes went
to a session in another repository, and 16 of them to one session. The log does not record what was
on screen.

The request records go back to 2026-09-21: 82 sends, each naming the session it went to.
- **57 screenshots.**
- **15 Reply cards.** These already go to the session the card names.
- **8 live ink sends.**
- **2 pushed images** whose session is unknown.

The records carry no context. Question 6's spike replayed rules against them.

## What earlier work settled

Two investigations came first. Neither was built.

- `docs/session-auto-select-2026-09-24.md`, for Send. It replayed 53 pasted screenshots against
  rules, and probed what a screenshot shows: a local page, a GitHub page, an app being built.
- Section 1 of `docs/live-ink-overnight-2026-10-07.md`, for the note. A read-only resolver ran on
  made-up window details pointing at real local state, and Haiku was tried on 18 made-up cases.

Settled, so no spike repeats it:

- **Local facts come first.** A deterministic order settles the common cases. A model only breaks
  ties, and only where nothing else did.
- **What a screenshot shows names a folder.** A local page leads to its dev server, a GitHub page to
  the checkout with that remote, an app being built to its project. Recency fails exactly when
  two projects are in flight: 9 of 11 misses of "used last" in the replay went to another folder.
- **Finding the dev server costs about 150 ms,** nearly all of it `lsof`. It belongs off the main
  thread.
- **Two traps.** Every `claude` process listens on a localhost port of its own, which looks like
  its own dev server. A session working in a broad folder such as `~/Code` matches every document.
- **Haiku is too slow and too sure.** 3.3 to 6.8 s through the CLI, and confidently wrong on a
  lookalike: a Stripe docs page sent to a session building a refund endpoint.
- **Text matching alone is weak.** Matching a screenshot's text to each session's recent text was
  right 43 times of 53 against 42 for "used last", and broke two right answers.
- **Privacy.** Keep the folder and the agent's id, never the page address or title, in the log or
  on disk.

The two disagree on one point, which question 2 settles. 2026-10-07 followed the dev server's parent
processes and lost a server whose parent had exited. 2026-09-24 found that the server's environment
still names the session that started it.

## Two surfaces

- **Send** works from a screenshot. The editor may open minutes after the capture, with another app
  in front. `CaptureOrigin` (2026-10-03) now finds the rect a capture was taken from, which
  2026-09-24 lacked: it could only use the app in front.
- **The live ink note** knows the exact window under the ink at that moment: its window id, its
  process, and its accessibility tree. It may reach "sure" where Send cannot.

## Constraints every answer must meet

- **Timing.** Send's target settles once and never changes under the pointer (AGENTS.md). The
  note's chip appears when the chord is let go. A signal counts only if its answer is ready then,
  or can be started earlier: at the capture, or when the chord goes down.
- **Permissions.** Vignette has Accessibility. Nothing may raise a new prompt, such as AppleScript's
  Automation prompt for a browser.
- **Pete's Mac runs macOS 15,** so Apple's on-device Foundation Models (macOS 26) are not available.
- **Safety.** A confident wrong target sends a picture of the screen to the wrong conversation.
  "Not sure" must stay a possible answer.

## Open questions

Each question names the result that would change the design, and a budget.

1. **Ground truth.** What was on screen at each of Pete's sends, and does a rule pick where he
   actually sent? *Changes the design if* the rule that wins on real sends differs from the one
   that wins on made-up cases. *Method:* a shadow log in Pete's build that records, at each
   capture, note and send, the signals each tier found, as folders and session ids only, and
   later scores every rule against where the drawing went. *Budget:* a few days of Pete's normal
   use. Needs Pete's approval, since it changes his build.
2. **Process signals.** Can Vignette read a dev server's environment (`CLAUDE_CODE_SESSION_ID`,
   `CODEX_THREAD_ID`) under the hardened runtime, and at what cost? Can `libproc` replace `lsof`?
   How many of the servers running now lead to a live session? *Changes the design if* the
   environment works where the parent chain breaks: then the strongest tier covers servers that
   outlived their parent. *Budget:* 1 hour.
3. **Which window.** For Send, does `CaptureOrigin`'s rect lead to the right window, its app and
   its process, at capture time? For the note, what does the window under the ink give: process,
   document, URL? *Changes the design if* Send can know the captured window rather than the app in
   front. *Budget:* 1 hour.
4. **The subject of a window, by kind of app.** Browsers, editors, Xcode, Finder, Figma and other
   Electron apps: what can be read through Accessibility (a URL, a document path), how fast, and
   at what cost to the app? *Changes the design if* a common app gives nothing, or costs too much
   to ask. *Budget:* 1.5 hours, in the VM for anything that changes an app's state.
5. **Terminal windows.** Which terminal window, tab or herdr pane shows a given `claude` process?
   Ghostty, Terminal, iTerm and herdr. *Changes the design if* a terminal window can name its
   session directly: then inking on a terminal is "sure". *Budget:* 1 hour.
6. **Several sessions in one folder.** Can a session's transcript (files it edited, routes,
   branches) tell it apart from the others in that folder, given what the window shows? *Changes
   the design if* it separates them often enough to decide, not just to rank. *Budget:* 1 hour.
7. **The session you came from.** Does the order in which apps and herdr panes were focused before
   the capture or the ink predict the target better than the focus now? *Changes the design if*
   Vignette should keep a short focus history. *Budget:* folded into question 1's shadow log.

8. **A decision model as the decider.** Jev (TypeSafe) and OpenAI's Decisions API pick one of a
   fixed set of answers, with probabilities, in a fraction of a second. Could one decide the cases
   local facts leave open: a deployed site, a design tool, a docs page, two sessions in one folder?
   What would it be given (local facts and candidate summaries, or the screenshot itself), what
   leaves the Mac, whose key pays, and are its probabilities calibrated well enough to gate "not
   sure" on? *Changes the design if* a model's probability separates right from wrong where
   Haiku's self-reported confidence did not: then it replaces the hand-tuned scores in the
   uncertain middle. *Method:* primary-source research first, then synthetic cases only, then real
   cases only with Pete's approval. *Budget:* 1 hour of research; any API calls need a key from
   Pete.
9. **Host or author.** A window that shows an agent's interface names the session that runs in it,
   the host. The drawing may be about another session's work, the author: the inbox plugin draws
   its panel inside every session's terminal. Can the text under the ink name the author? The
   candidates are the session whose repository, conversation or edited files hold that text, or
   whose name shares its words. *Changes the design if* one of them ranks the author above the
   host: then step 3 of "Where this stands" has a way to offer the author. *Budget:* 1 hour.

## Rules for the spikes

- Read-only on Pete's Mac. Never touch his running build, his settings, or his browsers'
  accessibility flags (`AXManualAccessibility` costs a Chromium browser memory and CPU until it
  quits). Anything that changes an app's state, or raises a prompt, runs in the VM.
- No model call on real window titles, URLs, screenshots or transcripts. Synthetic inputs only.
- Spike code lives in `.scratch/session-detection/`, never in `Sources/`.
- Each spike reports what it observed, the evidence, its limits, and what it implies.

## Results

Filled in as each spike reports. Each spike's full notes are in
`.scratch/session-detection/<spike>/FINDINGS.md`, which Git ignores.

### 1, 6 and 7. Pete's real sends

**Knowing the captured window's folder would settle most sends. Pete's own last pick is the next
best signal. Telling apart sessions in one folder rarely matters.**

- **Every correction crossed projects.** All 21 defaults Pete changed went to a session in another
  repository. None was a choice between sessions in one folder.
- **A folder almost always holds one live session.** That held for 65 of 76 sends. Told the
  destination's folder, "used last there" is right for 46 of 47. That is a ceiling: it assumes
  Vignette learns the folder.
- **The screenshot's text does not name the folder.** In 0 of 52 did the recognized text contain the
  destination's repository or worktree name. The folder has to come from the captured window
  (questions 3 and 4). How often a capture yields it is what the shadow log must measure first.
- **Recency is weak now.** About 6 sessions are active at once. "Used last" was right for 17 of 57
  screenshots, against 42 of 53 in the 2026-09-24 replay.
- **A hand-picked target should stick.**
  - Inside runs of sends, 5 of 7 corrections repeated one made minutes before.
  - 8 of the 14 corrections that started a run went back to the session sent to 10 to 74 minutes
    earlier.
  - "The session sent to last, if within 2 hours, else herdr's focus" was right 34 times of 47,
    against 26 for herdr's focus. Almost all of that gain comes from keeping a correction.
- **Several sessions in one folder (question 6)** came up in 11 of 76 sends.
  - Matching the screenshot's text against transcripts got 7 of 10, the same as "used last".
  - The checkout a session edits, often a worktree it reaches by path, separated 9 of 11. Its
    working folder separated 4. Its branch and its server ports separated none.
- **Text recognition is not a decider.** It takes 46 ms per image, but it does not break real ties.
  Across folders it did worse than "sent last".

### 2. Process signals

**A dev server's environment names its session, and reading it costs under a millisecond.** It is
the strongest tier for local pages.

- **Vignette can read it.** A hardened, Developer ID signed probe read another process's
  environment through `sysctl` `KERN_PROCARGS2` in about 7 µs. It read the same whether started
  from a terminal or through LaunchServices.
- **libproc replaces `lsof`.** It found the same 114 listening ports in 2 ms instead of 75 ms. One
  port takes 0.4 ms, and a process's working folder 1.6 µs.
- **The environment beats the parent chain.** Agents had started 16 of the listeners:
  - for 11, the environment led to a live session, though only 2 of those 11 are dev servers;
  - for 4, it named a session that had ended a day earlier, which is itself a useful "not sure";
  - the chain reached a live session for only 3.
  - The 9 other listeners with a live session are agent-browser daemons, whose parent is launchd.
  - The day's sample has only 3 pages a person would view, so "environment finds a live session
    where the chain breaks" rests on 2026-09-24's count: 11 of 20 dev servers had outlived their
    session.
- **The working folder is a hint, not an answer.** It was right once and wrong once, and offered 6
  candidates for each of 6 listeners.
- **The tiers:**
  - The environment names a live session, and the listener's working folder is not `/` → sure.
  - A parent is a live session's process → sure.
  - The environment names an ended session → not sure, with no fallback to "used last".
  - The working folder → a candidate only.
- **Traps:**
  - **An app started from an agent's shell inherits that session's environment for life.** Pete's
    own Vignette, relaunched from an agent session, carries its `CLAUDE_CODE_SESSION_ID`. That is
    why a listener whose working folder is `/` is not trusted.
  - The kernel hides some processes' environment, such as OrbStack Helper's, returning it empty
    rather than failing. Empty means unknown.
  - `claude`'s process name is its version number, so the check matches its path.
- **Untested:**
  - Codex: no running process carried `CODEX_THREAD_ID`.
  - `/clear` and `/resume`.

### 3 and 4. Which window, and what it shows

**Send can know the captured window, and the note already knows its window. What a window says
about its project depends on the kind of app.**

- **Send.**
  - **Which window:**
    - A window capture matches one window's frame exactly.
    - A selection goes to the window that covers the largest visible share of it, and is "mixed"
      when no window covers most of it.
    - A full-screen capture names no single window.
    - The window list costs 0.25 ms. Read at the release the ⌘⇧ poll already sees, it also
      survives the pointer moving before the file arrives.
  - **A change of hook.** Today `CaptureOrigin` runs only when "draw on capture" is on, so the read
    belongs in the watcher's report of a new capture. It also needs to keep the window number and
    process, which it now discards.
- **The note.**
  - **What it already has.** Its window's id, process, title, text, and a `location`: the window's
    document, or its web page's URL. The chip uses none of them.
  - **When it's ready.** The read finishes 38 to 124 ms after the stroke ends, before the chord is
    let go.
- **By kind of app.** Reading one window, matched by number, takes about 2 ms warm, and 11 to 57 ms
  the first time. Walking a window's whole tree is what costs: Finder took 72 to 181 ms and found
  nothing.
  - **Chromium browsers and Electron apps** give a page's URL only while their accessibility tree is
    on. Slack, Notion and the Codex app give only a title.
  - **Finder** gives its folder through the items in its list, not as a document.
  - **Terminals** are question 5.
  - **Safari** gives its page's URL with no flag (the shadow log's check in the VM).
  - **Not measured, because none was running:** Chrome, Arc, Firefox, VS Code, Cursor, Zed, Xcode,
    Preview, TextEdit, Figma, Terminal.app and Linear.
- **Vignette asks only Electron apps for the tree** (Pete, 2026-10-08; live-ink 31d4375). Live ink
  asks one when a mark lands where it has no page yet, since the app keeps the tree until it quits.
  It never asks a Chromium browser, and Send never asks anything. So a page in Chrome or Dia names
  no folder and no dev server, unless the browser runs with `--force-renderer-accessibility`, as
  the demo's Chrome does.
- **Privacy.** The picker keeps only the folder and the kind of app, never the URL.

### 5. Terminal windows

**Through herdr, a terminal window names its session for certain. A terminal on its own does not.**

- **herdr is certain.** `herdr pane list`, which Send already runs, gives each pane's session id
  (`agent_session.value`). It named all 19 live sessions on this Mac. Each `claude` process's
  `HERDR_PANE_ID` agrees.
- **So herdr's window names the session it shows** when four things hold:
  - the window belongs to a terminal app;
  - that app runs a herdr client;
  - herdr's focused pane is alone in its tab;
  - that pane's session has a live inbox.

  That is the session the window shows, not necessarily the one the drawing is for. "Where this
  stands" explains why it ranks as a strong candidate rather than a decision.
- **Following parent processes is the wrong way in.** A `claude` process under herdr descends from
  herdr's server, not from the terminal. The way in is down from the window's app to the herdr
  client, then asking herdr.
- **A terminal without herdr gives only its title.** Claude Code titles the terminal with its
  session's `ai-title`, which matched for 16 of 18 sessions. A title can rank candidates but not
  decide.
  - **Ghostty** exposes no tty or process for a window, through Accessibility or AppleScript.
  - **Terminal.app and iTerm2** expose each tab's tty, but only through AppleScript, which raises
    the Automation prompt.
- **Traps:**
  - Ghostty keeps closed windows with titles in the window list, so only on-screen windows count.
  - A terminal's text area holds the whole screen, so it is never read.
  - `GHOSTTY_*` in a process's environment does not mean Ghostty draws it.
- **Cost.** herdr answers in 5 ms, and launching it costs about 1 ms more. `Subprocess.run` waits
  on the process's termination handler (main eb59689): `waitUntilExit`, which it used before, kept
  15 of 200 calls waiting 60 to 69 ms after the command had exited.
- **Untested:**
  - a tab split into several panes, where ink can land on a pane without the focus;
  - two herdr clients attached at once;
  - Codex in a herdr pane;
  - Terminal.app and iTerm2 through Accessibility.

### 8. A decision model as the decider

**Neither Jev nor OpenAI's Decisions API should decide yet.** Both exist and are fast enough on
text. Neither has shown that its probabilities can safely decide when to say "not sure" on
lookalike cases. This comes from desk research only: no model was called.

- **Jev** (TypeSafe's own documentation):
  - takes text only, with up to 255 options and a probability for each;
  - costs $0.042 per million input tokens;
  - publishes no latency or calibration figures;
  - says itself that it leans toward the first option;
  - offers zero data retention only to enterprise customers.
- **OpenAI's Decisions API** (OpenAI's own guide):
  - is in public beta, not the limited preview reported on 2026-10-07;
  - takes images and gives a probability per option;
  - costs $0.10 per million input tokens;
  - keeps logs 30 days unless OpenAI approves zero retention.
- **OpenRouter's decisions endpoint** routes to five such models with one request shape, three of
  which take images. So one key would cover a side-by-side test.
- **Speed.** Independent measurements, all from servers and all on text, put the median at 150 to
  320 ms and the 99th percentile at 0.75 s. None measured a request that carries an image.
- **Calibration, the property that matters, is unproven here:**
  - Independent tests found 2 to 8% of answers given at 0.9 or higher were wrong, more on lookalikes.
  - With every option wrong, Jev's mean confidence was 54%, so it needs an explicit "none of these"
    option.
  - These are still real probabilities, unlike Haiku's self-report. Jev ranked right answers above
    wrong ones with an AUROC of 0.73 to 0.88.
- **What leaves the Mac.** A model needs titles, URLs, or the screenshot itself. Those are exactly
  what the privacy rule keeps off disk. A distributed app also cannot ship a key. The options are
  the user's own key, an OpenRouter sign-in that issues the user one, or a proxy Pete would run.
- **The shadow log cannot score a model afterwards,** because it keeps no titles or URLs. Testing a
  model on real sends would mean calling it live or logging its inputs. Either needs Pete's
  approval.
- **A cheap test exists.**
  - **Cases:** 300 made-up cases from the open middle: deployed sites, design files, lookalike docs
    pages, sessions sharing a folder, and about 25% where the answer is "none".
  - **Models:** Jev, OpenAI's model, Clef and pplx-decider, each asked forward and in reverse
    order.
  - **Scoring:** the share of cases decided while confident wrong picks stay under 1 in 100. Only
    cases the rules leave open count.
  - **Cost:** about $0.05 in calls, 2 to 3 hours of work, and an OpenRouter key.
- **Haiku 5.5 exposes no log probabilities.** A local 1 to 3B model is an unmeasured option. On
  Pete's M4 Max it might take about 50 ms, but it needs 0.7 to 2 GB of memory and a separate
  download.

#### The synthetic test (Pete's OpenRouter key, 2026-10-08)

Every case is invented: no project, session or title from Pete's Mac is sent. The scripts are in
`.scratch/session-detection/decision-models/synth/`.

**The bar, fixed before the full run.** A model earns a place in step 5 of "Where this stands" only
if, on the 200 held-out cases that the name rule leaves open, with a threshold fitted on the 100
fit cases:

- it picks the right session for at least 30% of the open cases that have one;
- it makes at most 1 wrong pick in all, where picking any session on a "none" case counts as wrong;
- and it clears both in the title-only group, which is what Chrome, Dia and Figma give now.

Below that, models leave the plan, and step 5 shows a guess by rule or says it isn't sure.

**How it is built:**

- **Window facts as the Mac reads them now,** in three groups reported apart: title only (Chromium
  browsers, Figma, Slack); title and URL (Safari, or an Electron app once asked); and nothing
  useful.
- **The name rule:** picks a session when exactly one session's folder or repository name appears
  as a word in the window's title, host or path. Models are scored mainly where it says not sure.
- **"None" means no session works on the window's subject.** A lookalike shares surface words only.
  A Stripe docs page while a session builds Stripe checkout belongs to that session.
- **Each case is asked twice,** with the candidates in one order and then reversed, and the two
  probabilities averaged. The right answer's position is spread evenly. A "none of these" option is
  always offered.
- **Frozen before the full run:** the cases (fixed seed, `cases.json` SHA-256 `5d9937d67f866c6d…`)
  and the instructions. The splits came to 104 fit cases and 196 held out.
- **Baselines:** the name rule, the session used last, and Haiku 5.5 with a stated confidence.

**Results: every model clears the bar, Haiku included.** So a window whose title is about a
session's work can be matched to it, but the test cannot tell the models apart. It also says nothing
about Pete's real windows, which are messier than these. It is an optimistic, necessary check, not
evidence for building.

- **The baselines.** The name rule decides 45 cases: the 30 windows that name a repository, all
  right, and the 15 hostile titles, all wrong. The session used last is right for 36 of 216. That
  leaves 167 held-out cases open, 123 of them with a right session.
- **On the open held-out cases:**

  | Model | Threshold | Right, of 123 | Wrong picks | Title only, of 66 | Title and URL, of 49 | Order flips, of 300 | Median / p95 from this Mac |
  |---|---|---|---|---|---|---|---|
  | pplx-decider 1.1 | 0.95 | 98 | 0 | 59 | 39 | 5 | 419 / 676 ms |
  | Clef Flash | 0.7 | 94 | 1 | 51 | 43, 1 wrong | 0 | 409 / 1,174 ms |
  | Haiku 5.5, stated confidence | 0.7 | 79 | 1 | 46 | 33, 1 wrong | asked once | 1,180 / 1,556 ms, 4 at a time |
  | OpenAI's Luna Decisions | 0.85 | 67 | 0 | 36 | 31 | 25 | 264 / 442 ms |
  | Jev 1.13 | 0.93 | 66 | 0 | 36 | 30 | 13 | 251 / 389 ms |
  | Clef | 0.9 | 59 | 0 | 35 | 24 | 0 | 475 / 1,667 ms |

- **"None" held.** No model gave a session to a "none" case at 0.9 or more (0 of 44 each).
  Lookalikes came back "none" 21 to 23 times in 23.
- **Hostile titles move every reader of titles.** Asked alone, the models' top answer followed the
  planted session name in 1 (Clef) to 7 (Clef Flash) of the 9 held-out hostile cases, mostly below
  the threshold. The name rule followed it in all 15. Any website writes its own title, so a rule
  that reads names should match a URL's host or path, not a title's free text.
- **Order matters for Luna and Jev.** Reversing the candidates changed the top answer in 25 and 13
  of 300 cases. Averaging both orders costs a second call.
- **Privacy.** pplx-decider and Clef are on OpenRouter's zero-retention list. Jev and Luna were not
  found there.
- **Haiku** answered in prose instead of JSON 14 times in 300, counted as not sure.
- **Cost:** $0.11 for 3,300 calls on Pete's key, about twice the estimate, which was for one model.

**What it changes.** Models stay in the plan as a candidate for step 5, nothing more. Real windows
would decide it. That needs titles kept on the Mac (still Pete's call), and his decision on sending
them. If it gets that far, pplx-decider is the one to try first: the most right picks with none
wrong, zero retention available, and about 420 ms.

**Images.** Jev reads text only. Luna Decisions, Clef and pplx-decider take images through the same
OpenRouter key. They were not tested on images. A mock screenshot that repeats the title would test
only reading, and the value of an image is in a real screenshot, which shows Pete's screen.

### 9. Host or author

**The files each session edited ranked the author first, in 150 ms. Whole repositories and session
names did not.** This is one case.

- **The case.** At 20:29 Pete circled the inbox plugin's panel in the terminal of the session
  building Vignette, the host. He expected the session building the inbox plugin, the author. Two
  sessions build it: be4e71f4, live in `~/Code/inbox`, and b39e954a. b39e954a received 49 of Pete's
  sends, did most of its file work in `~/Code/inbox`, last wrote at 20:03, and has no live inbox now.
  Both are Claude Code sessions.
- **How it ran.**
  - The ink's frame is not kept, so the terminal's window was captured about 10 minutes later. Vision
    read it on the Mac. The panel's region came from where its lines sit: 12 lines, 10 long enough to
    search.
  - The candidates were 28 sessions: the 13 live Claude Code sessions, 14 Codex threads written to in
    the last 12 hours, and b39e954a.
  - Each line was searched ignoring case and punctuation, whole and in runs of two and three words.
    A line weighs 1 divided by the number of sessions that hold it.
  - Nothing left the Mac. The scripts printed counts and ids only, and the capture was deleted.
- **Results.** Both inbox sessions scored the same.

  | Signal | Inbox sessions | Best other | Cost |
  |---|---|---|---|
  | Files the session edited | 1.38, first | 0.88 | 150 ms for 41 MB |
  | Its whole conversation | 1.46, first | 0.46 | 12.5 s for 1 GB |
  | The last 256 KB of its conversation | 0.50, fourth | 0.61 | 160 ms |
  | The repositories it started in or edited | 0.51, below three others | 0.58 | about 20 s |
  | Its name | no shared word | one | none |

  The edited files are Claude Code's backups, `~/.claude/file-history/<session id>/`. They held the
  current text of all 31 files be4e71f4 had edited that still exist. The last-256 KB row was measured
  with be4e71f4 alone. The two sessions next on edited files, at 0.88, work on evercars and on
  munari, and the munari one had also edited the inbox repository.
- **What decided it.** Two of the panel's lines, 8 characters each, occur in the two inbox sessions'
  conversations and in no other. One of them is also in files that only those two edited. Both are
  common words: 15 to 17 sessions' repositories hold them. That is why searching repositories does
  not separate the sessions. The two longest lines occur nowhere whole.
- **The host gained nothing.** The Vignette session, whose terminal drew the panel, scored like the
  unrelated sessions. On its conversation and its edited files it was level with two evercars
  sessions, below both inbox sessions.
- **Names are a negative.** 24 of the 28 sessions had a name, and the panel had 10 words of four
  letters or more. No name shared one, except one Codex thread's, by one word.
- **Limits.**
  - One ink on one window. The author talks about its own interface all day, which favours searching
    conversations.
  - The region was chosen from the layout, not the ink, 10 minutes after it.
  - Edited files exist for Claude Code only. Codex keeps its edits inside its conversation file, so a
    Codex author needs the slow search.
  - Whether b39e954a was still live at 20:29 is unknown.
- **What it implies.**
  - When ink lands on a terminal or an agent's app, the sessions whose edited files hold the text
    under it are candidates for the author. Live ink already reads the window's text before the
    chord is let go, so this adds about 150 ms to that.
  - It ranks; it does not decide. On edited files the margin was about 3 to 2, on one case.
  - An index of each conversation, kept up as it grows, could make the conversation signal fast
    enough. That was not measured.

## Where this stands

The spikes point to one shape. The order below is what the evidence supports so far. It is not yet
the plan.

1. **Exact facts decide alone.** Each one names a session with nothing left to guess:
   - **A card that names its session:** a Reply card, or an agent's push.
   - **A local page:** its dev server's environment names the session, read in under 1 ms. Or its
     parent process is a session's. Only where the page's URL can be read: Safari, an Electron app
     once asked, or a browser started with its accessibility forced on. Not Chrome or Dia.
2. **The window's folder decides when one live session works there.** Each session counts the
   checkouts it edits as well as the one it started in. Pete's 21 corrections all crossed folders,
   and a folder nearly always holds one live session. The folder comes from the captured window, or
   the window under the ink:
   - its document;
   - its page's dev server;
   - Finder's folder;
   - for an app being built, the checkout its executable runs from, through its derived-data
     folder. 2026-09-24 measured that at 116 ms. Pete's own Vignette runs from such a folder.
3. **A window that shows an agent is a strong candidate, never a decision.** A herdr window names
   its focused pane's session, but that answers which session the window shows. It does not answer
   which session the drawing is for.
   - **The likely counterexample.** Pete sent 16 of his 21 corrections to the session building the
     inbox plugin, while herdr's focus sat on an evercars pane in 15 of the 21 misses. The inbox
     plugin draws inside other sessions' terminals. So those were likely captures of an evercars
     terminal showing the inbox's UI, sent to the session building it. This is a hypothesis: the
     screenshots were not looked at.
   - **One such case, met directly.** Pete circled the inbox plugin's panel in the Vignette
     session's terminal, and expected the inbox session. The text under the ink, found in the files
     each session edited, ranked the inbox sessions first, at about 1.6 times the next score
     (question 9).
   - **The general rule.** A window that shows an agent's own interface, such as a terminal or the
     Codex app, may be about the tool being built rather than the session running in it. The same
     goes for step 2's folder when the window is a terminal. The sessions whose edited files hold
     the text under the ink are then candidates beside the host.
4. **Pete's own last pick holds for a while. This step is tentative.**
   - "Sent last within about 2 hours" beat herdr's focus 34 to 26 of 47.
   - The 2 hours was chosen by trying 5, 30, 60 and 120 minutes on those same 47 sends.
   - On the first send after a break it gains just one: 17 against 16.
   - The note already starts on the target picked last, so this is new only for Send.
5. **Otherwise the target shows its guess, or says it isn't sure.** The guess may be herdr's focus
   or the session used last. Every model passed question 8's made-up cases, which shows a model can
   do this, not that it will on real windows.

**What is still unknown:**

- **How often a real capture yields a folder,** and how often a terminal capture is about another
  session's tool. The shadow log below measures these.
- **Apps not measured:** Chrome without the flag, VS Code, Cursor, Xcode, Preview, Figma and
  Terminal.app.
- **herdr's edge cases:** split tabs, two clients at once, and Codex panes.
- **Codex dev servers carrying `CODEX_THREAD_ID`:** none was running.

## The shadow log

Pete approved it on 2026-10-08, to run for a few days in his own build. It records what Vignette
could see at each capture and each send, and where the drawing went. A script then scores each
rule in "Where this stands" against those sends. It lives on live-ink only (`Sources/SendContext.swift`)
and is removed before live ink reaches main.

- **The file.** `send-context.jsonl` in Application Support, one JSON object per line, appended off
  the main thread. A test launch writes it beside its scratch settings file instead. It stops at
  20 MB. It is a file of its own because `Vignette.log` rotates at 5 MB and would lose the first
  days.
- **What it keeps:** session ids, folders, bundle ids, port numbers, and a digest of the
  screenshot's file name, which joins a capture to its send. Never a window's title, a page's URL or
  a file's name: an agent names the image it pushes for what it shows.
  Titles are only compared, in memory, with each session's name and folder. No model inputs are
  kept unless Pete chooses that (question 8).
- **`capture`, at each new screenshot** (the watcher's report, whatever "draw on capture" says):
  - `capture`: `window` when its size is one window's, with or without Apple's shadow; `display`
    when it is a display's; otherwise `selection`, of the window under the pointer.
  - `app`, and `kind`: terminal, agent-app, browser, editor, finder, other or none; `electron`.
  - `page`: `file`, `local`, `web`, `other`, `none`, or `unread` for a browser whose URL could not
    be read. That last one measures what the Chromium decision costs.
  - `folder`: the document's or file page's folder, or Finder's. `port` and `server` for a local
    page: the listener's folder and the session its environment names, `trusted` when its folder
    is not `/`.
  - `built`: the checkout an app being built runs from.
  - `titleNames` and `titleFolders`: the sessions whose name, or folder's last part, the window's
    title contains.
  - `titleWords` and `titleOverlap`: how many words the title has that could name some work, and
    for each session, how many of them its name and folder's last part share. Words under three
    letters, a plural's "s" and common words such as app names are left out first. These are
    counts only. They show how often a title gives anything to match on.
  - `sessions`: each live Claude Code session's id, folder, herdr `focus` and seconds `idle`.
  - `readMs`: how long the window's reads took.
- **`send`, at each send from the editor:** `file` (the digest), `request`, `to`, `client`, and `offered`, where
  the bar's filled button sent before the person changed it, with `reply` when that was a Reply.
- **`note`, at each live ink note sent:** `to` (a session id, or `responder` for the built-in
  Claude), `offered` (the target the note started on), and the window's facts as for a capture.
- **Not recorded, since the log itself gives them:** the session sent to last and how long ago, from
  the `send` and `note` lines before.
- **Checked in the macOS 26 VM:** a window capture of Safari gave the page's folder; an odd-sized
  image gave a selection; a Reply card's send recorded `offered` and `reply: true`; a note sent to
  a fake session recorded its window and both targets. A Safari window titled "Newsletter" counted
  one shared word for a session named "Tighten the newsletter signup form" and one for a session in
  a `newsletters` folder, and none for two sessions in a folder named `project`.
- **One fix came first,** on main (886322e): the `[send] target` line logged herdr's focus even for a
  Reply card, whose bar offers the card's own session. It now logs where the filled button sends,
  marked `reply` for the card's own session.

**Decided by Pete (2026-10-08):**

- **The shadow log:** approved, ids and folders only.
- **Chromium's accessibility tree:** asked of Electron apps only, when needed.
- **Whether anything may leave the Mac for a model:** decide later. No model is called meanwhile.

**Still Pete's to decide:**

- **Whether the log also keeps model inputs,** titles and URLs, in a file that never leaves the Mac.
  Without them, a model can be tested only on made-up cases.
