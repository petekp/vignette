# Live ink: five questions, worked overnight (2026-10-07)

Pete asked five things before going to sleep. Everything here is on branch `live-ink-overnight`,
in the worktree `~/Code/worktrees/vignette/live-ink-overnight`, branched from `live-ink` at
8bc5a6f. Nothing is committed or pushed. Pete's running copy and the `live-ink` worktree are
untouched.

Status: done, waiting on Pete's review.

The agents' reports and scripts are in the worktree's `.scratch/overnight/`, which Git ignores.

## The answers

1. **Routing.** Use facts the Mac already has, in a fixed order: the dev server's parent process,
   then the project folder, then weaker hints. A prototype got all 15 made-up cases right, each in
   under a second. A model only breaks ties, and it's too slow to go first.
2. **Several asks in a row.** Give each ask its own state, so only the ask being worked on
   shimmers and queued ink rests. Gather asks to a busy session into one request.
3. **Screenshot history.** Keep each ask as a moment, on demand, with a Keep action. A setting can
   keep every one, off by default.
4. **Agents answering in prose.** Clean tests didn't reproduce it, and no wording change helped.
   Vignette now logs marks it throws out, and the next tests to run are listed.
5. **The feature.** When a session finishes, the ink shows whether anything changed where you
   drew: the before plays back and wipes away, or a note says nothing changed. Built, unit tested,
   and run end to end in the macOS 26 VM. Building it showed that Vignette gave up on a busy
   session after 3 minutes, so the feature would rarely have run. This branch fixes that too.

## What needs Pete

- Whether to merge `live-ink-overnight` into `live-ink` and rebuild his copy.
- Whether the "Nothing changed" note should go on its own after a while. Today it stays until
  tapped or cleared.
- Whether to add the walk-through sentence to the skill. That needs a plugin version bump and
  `/reload-plugins` in open sessions.

## The questions

1. **Routing.** How can Vignette tell which Claude Code or Codex session an annotation is about?
   Could a fast decision model help, or is there a simpler way?
2. **Rapid sequences.** How can someone make several annotations in a row without the screen
   filling with queued, shimmering ink?
3. **Screenshot history.** Should live ink also keep a screenshot to refer back to?
4. **Agents using live ink.** Agents often answer in prose even when asked to mark something.
   How do we make them use `--answer`, its marks and the focus techniques reliably?
5. **A killer feature.** Spec it, build it, test it.

## How the work is split

| Stream | Who | Output | Touches product code |
|---|---|---|---|
| 1. Routing | Sonnet agent: web research, a read-only prototype, a Haiku test on made-up window details | `.scratch/overnight/routing/` | No |
| 2 and 3. Rapid asks, history | Explore agent maps today's behaviour; Claude designs | This file | No |
| 4. Agents using ink | Sonnet agent: captures real packets in the VM, then replays them to `claude -p` with prompt variants | `.scratch/overnight/eval/` | One log line |
| 5. Feature | Claude | This worktree | Yes |

The VM (`vignette-tahoe`, macOS 26) is one resource: the eval uses it first to capture packets, then
the feature is tested there.

### Guardrails every stream follows

- No capture of Pete's real screen or windows. Only VM and lab windows go to a model.
- Nothing launches or rebuilds Pete's running copy or `build/`. The only `vignette://` commands
  it gets are the cards that show the results.
- `claude -p` runs for the eval use Pete's subscription, with MCP servers off and his Vignette
  plugin disabled for the run, so no eval session registers in his app. Each stream reports its
  run count.

## 1. Routing an annotation to its session

**Answer: use facts the Mac already has, in a fixed order, and learn from corrections. A model
isn't needed first.** The facts settle the common cases in 0.2 to 0.6 s, for free, and they can
say "not sure". A small model helps only with the ties left over, and it is too slow to pick the
chip before the note opens.

Today the note's target starts on the session picked last, else the built-in responder.

### The order

1. **The dev server belongs to a session.** The window shows `localhost:<port>`. The process
   listening on that port has a `claude` process among its parents, and that pid names a live
   inbox. This decides alone. Common for web work, since a session usually starts its own dev
   server.
2. **The project folder.** The window's document path, or the dev server's working folder, is
   inside exactly one session's folder. Decides when no other session comes close.
3. **The same repo, another checkout.** For example, a worktree of the session's repo. This
   supports a guess but never decides alone.
4. **Words.** The window's title or URL shares words with a session's folder name or its title.
   This supports a guess but never decides alone.
5. **A small model,** only when two or more candidates are still plausible.
6. **Recency.** The session used last, or the one you came from, picks what the chip shows when
   nothing above decided. It is never evidence.

Vignette decides when the top candidate scores 60 or more and leads the next by 25. Otherwise it
says it isn't sure.

### What the prototype found

`.scratch/overnight/routing/resolve.py` is read-only. It reads the inbox folders and runs `ps`
and `lsof`. On this Mac's real sessions, with made-up window details pointing at real local state,
it gave the intended answer in 15 of 15 cases, taking 0.2 to 0.6 s each.

| Case | Result |
|---|---|
| A port served by a child of a session | Decided, score 101 |
| A document under one session's folder | Decided, score 72 |
| A document under a folder six sessions share | Not sure (correct) |
| A dev server whose parent had exited (`ppid 1`) | Not sure (a person would have guessed right) |
| Docker ports, Figma, docs sites, deployed sites, terminals | Not sure |

It found two traps, both fixed in the script:
- A session whose folder is `~/Code` matched every document. Folders that broad are now ignored.
- Every `claude` process listens on a localhost port of its own, which looked like its own dev
  server. Those listeners are now skipped.

### The models Pete named

The routing agent found secondary sources dated after this model's training. It called neither
service, so treat these facts as reported, not checked.

- **Jev**, from TypeSafe, is a "System One" model launched in mid September 2026. It picks from
  a fixed set of answers with probabilities and generates no text. It reports a median latency
  of 0.21 s on OpenRouter, at $0.042 per million input tokens.
- **OpenAI's Decisions API** was announced at DevDay on 29 September 2026. It is in limited
  preview, with no public schema or pricing.

Claude Haiku 5.5 (`claude-haiku-5-5`) was tested instead, on 18 made-up scenarios with known
answers:
- It got 17 right.
- The miss was the dangerous kind. It confidently sent a Stripe docs page to a "refund endpoint"
  session when the right answer was none.
- Its confidence wasn't calibrated well enough to gate on.
- Each call took 3.3 to 6.8 s through the CLI, and about 1 to 4 s of that was the API itself.
- Each call cost about $0.0008.

Jev's speed would suit the chip, but it adds a vendor and sends window titles off the Mac. Try it
only if the facts plus Haiku prove too slow or too vague in use.

### How it should look

- **The note's target chip says why.** For example, "circuit · your dev server on :41777". The
  chip has three states:
  - **Sure:** the order decided it.
  - **Guess:** a model, the same repo, or matching words picked it.
  - **Not sure:** today's choice stands.
- **A correction teaches it.** When the person changes the chip, Vignette remembers the window
  fact (app, host, or document folder) and the session's folder, not the session id, since
  `/clear` changes the id. Remembered facts are checked first.

Not covered yet: terminal windows (match the `claude` process's tty to the terminal), searching
transcripts to tell same-folder sessions apart, Codex threads (the same folder rules apply to
their `cwd`), and Docker port mappings.

## 2. Several annotations in a row

**Answer: give each ask its own state. Then queued ink rests quietly and only the ask being worked
on shimmers. Asks sent to a busy session gather into one request.**

### What happens today

- A new ask is allowed while a session works on the last one.
- The earlier ask's ink stops shimmering, but nothing ever finishes it. It stays until erased or
  cleared.
- A late answer to the earlier ask takes over the one "current ask". After that, the newer ask's
  ink is never finished either.
- A Claude Code session that is busy keeps each ask as a `.line` file. All waiting lines are
  delivered together when its turn ends, each as its own message.
- Codex never reports a turn ending, so its ink shimmers for the full 3-minute limit.
- `[state]` shows only the latest ask.

So the clutter is real, and it doesn't clear itself.

### What to do

1. **One state per ask, keyed by its request.** Today one `asking` value and one `working` watch
   cover every ask. Each ask should carry its own ink, its own phase, and its own end. This fixes
   the stuck ink by itself.
2. **Three looks for three phases.**
   - **Queued:** the line is still waiting in the inbox. The ink is calm: 60% opacity, no light,
     and a small number on the note.
   - **Working:** the line was delivered, which the inbox shows once the file is gone. The ink
     shimmers.
   - **Done:** it resolves, as section 5 describes.

   Only asks the agent is actually on carry light.
3. **Gather asks for a busy session.** While the session's line for this window is still waiting,
   a new ask to the same session replaces that waiting line with one combined request. That is one
   picture with every waiting ink numbered, and one line listing each note: "1: bigger. 2: move
   under the title." The agent gets one turn with everything, and the screen shows one waiting
   ask.
4. **Draw several, then send once.** In the note, ⌥Return could keep the note and open the next
   ink for another, and Return sends them all as one numbered request. This suits a review pass,
   where the person marks five things and wants one answer.

**Order:** 1 and 2 first, since they fix a bug and cost little. Then 3. Leave 4 until Pete tries
3. Codex can't be helped this way: its queue is Codex's own, and nothing says when a thread's
turn ends.

## 3. Keeping a screenshot of each ask

**Answer: yes, keep one, but not in the screenshot folder by default. Keep it on demand.**

### What exists today

- An ask sent to a session already saves the window, with the ink drawn in, as the request's
  `image.png` in Application Support. Nothing shows it.
- An ask to the built-in responder saves nothing.
- An answer drawn on the window is never saved.

### What to build

- **Each ask is a moment.** Store the window with the ink, the person's words, the answer's words
  and marks, and, from section 5, how the window looked after the turn. The marks are real
  `Mark`s, so a moment opens in the editor as an ordinary drawing.
- **Keep on demand.** Add a Keep action beside Reply under an answer, and a menu item for the
  last ask. It adds the moment to the stack as a card, with the ink and the answer as editable
  marks, the way `add` does. From there, Copy, Send to another agent, and drag all work.
- **A setting to keep every ask, off by default.** It writes to the person's real screenshot
  folder, which here syncs through Dropbox.

### Other uses

- **Before and after for a PR.** A stitch of the before and the after, with the ink.
- **Handing an ask to a second agent,** with its picture and words.
- **Checking for a regression.** Capture the same window later and compare it with the kept
  after, using the comparison from section 5.
- **A log of what was asked and changed,** for the end of a session.

## 4. Getting agents to answer on the window

**Answer: in clean tests the wording isn't the problem. Both paths already mark an explicit ask
almost every time, and no wording change moved that.** The prose-only answers in Pete's log
probably come from conditions the eval didn't reproduce. Vignette now logs one of them, so his next
real use can say which.

The eval agent's full report is `.scratch/overnight/eval/eval.md`.

### What was measured

The pictures came from lab pages in the VM. Each ask was the exact line Vignette sends.

| Path | Runs | Result |
|---|---|---|
| The built-in responder, today's prompt | 36 prompts | A valid mark on 23 of 24 asks that asked for one |
| The responder, three prompt rewrites | 108 | The same. The one miss moved between prompts, so it is noise. |
| A Claude Code session, today's skill | 27 | Answered with `--answer` on every ask that called for a mark, and loaded the skill every time |
| A session, four wording levers | 48 | No change: the request line naming `--answer`, a sharper skill description, the SessionStart text, and all three together |

Pete's own log is different: 17 of his 39 responder answers had no marks. Two things
are more common among those, though the samples are small and overlap:
- **Later asks in a conversation.** 10 of 18 had no marks, against 7 of 21 first asks. The eval
  started a fresh responder for every ask.
- **Asks where no window was found.** 8 of 14 had no marks, against 9 of 25. The eval always had a
  named Safari window.

### What moved

One sentence in the skill: "When they ask to be walked through something, give a `focus` mark for
each stop, in the order `say` talks about them." Without it, "Walk me through this chart" got
circles and no focus marks in 6 of 6 runs. With it, the session gave 3 focus marks. That is one
prompt, so it needs more runs before it ships.

### Failures nobody sees

- **A mark can be thrown out as the answer is read.** In 3 of 144 answers the responder gave a box
  in pixels instead of thousandths. The mark fell outside the picture and was dropped, and nothing
  logged it. Vignette now logs it for the responder: `[live-ink] answered … thrownOut=<n>`. A
  session's marks are checked by the reply helper, which still drops them silently. This is the one
  change from this section, and it needs only a rebuild.
- **A session's words are found by reading the window, and reading can fail.** In the VM, Vision
  read `$72k` as `1ZL$`, so all 14 session marks that named it were dropped. A session could give
  a box as well as words for a number or a table cell, and Vignette would use the box when the
  words aren't found. Untested.
- **Marks on questions that need none.** 22 of 25 responder answers to "explain" or "why"
  questions carried marks. No rewrite fixed it.
- **A session learns nothing from `--answer`.** It can't tell that a mark was dropped.

### What to try next

1. Use live ink for a day with this build and read `thrownOut=` and `marks=` in the log.
2. Replay a whole responder conversation, with its warm-up ask, to test whether earlier answers
   with no marks lead to later ones.
3. Check that a real session may run the reply helper without a permission prompt. A prompt would
   stop it and look like a prose answer. The eval allowed Bash, so it couldn't see this.

### How the eval ran

- 150 responder runs, 80 session runs, and 4 probes that stopped before any model call.
- Each run showed only the staged Vignette plugin and Claude Code's built-ins, with no MCP servers.
  Session runs ran under `sandbox-exec`, writing only to the eval folder and Claude Code's own.
- Departures from the guardrails, all on the eval's own processes:
  - The first probe ran with the shell's environment and loaded the `inbox` plugin. It made no
    model call.
  - Once, five `claude` processes ran at the same time, one over the limit of four.
  - The agent stopped its own harness script once with `pkill -f`.
- Nothing appeared in Pete's `claude-sessions` folder. That is from modification times, not a
  listing before and after.

## 5. The feature: ink that tells you whether the change landed

**Built and tested in the VM.** When a session finishes an ask, the ink now shows whether
anything changed where the person drew. A change plays back: how it looked before comes in over
the window, then wipes away to how it looks now. If nothing changed there, the ink stays and says
so. The code is in this worktree, uncommitted. All 54 live ink unit tests pass, 7 of them new,
and so does the full suite.

### The problem

Today, live ink sent to a session ends the same way whatever happened. When the session's turn
ends with no answer drawn, the ink and its note play the done animation and go.
- The person has to look for the change themselves.
- If nothing changed where they pointed, nothing says so.
- If something did change, the picture of how it looked before is gone with the ink.

### What it does now

Vignette keeps the window round the ink as the ask goes. When the session's turn ends, it looks
again:

| Case | What the person sees |
|---|---|
| Changed under the ink | The old pixels come in over the window with a "Before" tag, hold for 0.8 s, and wipe away from left to right. The done animation follows: green, a check, gone. About 3.5 s in all. |
| Nothing changed under the ink | The ink stays, and Vignette's note beside it says "Nothing changed under your ink. Check *project*." The session may have answered in words, as it does for a question. |
| Can't tell | The window closed or changed size, or Vignette stopped waiting on a turn it couldn't see end, as with Codex. The done animation plays, as it did before. |
| The session answered on the window | Nothing new. The answer and the ink stay, as before. |

The rule for "changed":
- The window is read on a grid of 3 pt cells of grey.
- Only the cells under the ink decide: its shapes plus 12 pt.
- A cell counts when its grey moved by more than 24 of 255.
- A cell that also moves between two captures half a second apart is ignored, so a caret or a
  spinner never counts.
- Changed means at least 2% of the deciding cells, and at least 4.

The playback covers every changed cell within 64 pt of the ink. So a button that grew past the
loop plays back whole. The first take showed a sliver of the new button beside the old one, and
this fixed it.

### How it was tested

In the macOS 26 VM, with a fake Claude Code session and a page in Safari:
1. Draw a loop round its Subscribe button.
2. Ask "Make this green", sent to the session.
3. Remove the request's line from the session's inbox, as its monitor does, write `busy` to the
   session's `turn` file, change the page, then write `idle`.

| Case | Log | Seen |
|---|---|---|
| The page changed | `landed changed=0.095`, then `done` 2.0 s later | The four steps above, recorded at about 6 frames a second over VNC |
| The page didn't change | `nothing changed under the ink changed=0.000` | The note, clear of the person's own note |
| The window was resized during the turn | `can't tell whether it landed: the window changed size`, then `done` | Today's done animation |
| The session answered with `--answer` | `drew answer marks=2`, and no `landed` | The answer stays |
| The request waited 200 s behind another turn, then its own turn changed the page | No `stopped waiting`. `session's turn ended` once its own turn went idle, then `landed changed=0.095` | The playback, as in the first row |

In the last case the fake session sat idle for 1.3 s between the other turn and its own, as a
real one does while the monitor hands the request over. The watch didn't take that gap for the end.

### Changes outside the feature

- **Vignette now waits for a busy session.** Before, it stopped waiting 3 minutes after the ask,
  even when the request was still queued behind another turn. None of Pete's three real session
  asks logged a turn ending. He cleared the first after 26 seconds, and a relaunch cut the last
  short. The second was queued for 7 minutes, and Vignette stopped waiting after 3, before the
  session had read it. This feature would not have run for it.

  Now a request waiting in the inbox counts as queued, and the 3-minute limit starts only once the
  session has it. A request may stay queued for 30 minutes after the ask, and a turn Vignette sees
  start may run 30 minutes. A turn the person interrupted counts as over, as the plugin's monitor
  already reads it.
- `say()` now places Vignette's note clear of the person's own note, not only their ink. Before,
  the "Nothing changed" note covered the person's words. The same overlap could already happen
  with "Queued for…" and "Check…".
- `LiveWindows.Anchor` gained `.window`, a mark pinned to the window alone. The playback uses it.

### Known gaps

- **The compared part stays put in the window.** Content the session moved away counts as a
  change, which is right. Content the person scrolled during the turn also counts, which is
  wrong.
- **Turn ends are seen only for Claude Code.** Codex never reports one, so its asks keep today's
  ending after 3 minutes.
- **A queued request holds the light on every ask to that session.** Vignette sees that a request
  is waiting, not whose it is. Section 2's one state per ask would fix this too.
- **Only the latest ask is resolved.** An earlier ask that a newer one replaced still sits there,
  as section 2 describes. Giving each ask its own state fixes both.
- **The before and after pictures aren't saved.** Section 3's moments would keep them.
- **Seen only on macOS 26.** Pete runs macOS 15. The window capture and the marks pinned to a
  window already run there every day; the playback itself hasn't been seen there.
- **About 2.6 s between a turn's end and the playback.** 2 s of that is the existing wait that
  makes sure the turn really ended.

### Why this one

- It answers the question the person has at the moment the ink goes: did it work?
- It needs only a rebuild: no plugin or skill change, so no `/reload-plugins`.
- It is built on parts that exist: the turn watch (`LiveInk.watchWorking`), the window capture
  (`LivePacket.capture(window:)`), marks pinned to windows (`LiveWindows`), and the done animation.
- It helps question 2: ink that landed clears itself, and ink that didn't stays and says so.
- It is the first step to the vision's "ink that resolves itself" (`docs/LIVE_INK_VISION.md`).
- The VM can test it end to end, with a fake session and a hand-written `turn` file.
