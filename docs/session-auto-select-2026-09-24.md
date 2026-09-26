# Picking the agent session without asking (2026-09-24)

Pete asked for Send to start on the right agent session, so choosing one by hand becomes rare. This
note compares the ways to do that, measures the ones that can be measured, and recommends one. It was
investigated with a standalone probe. Nothing in the app has changed.

## The recommendation

Pick the session from what the screenshot shows, read when the file arrives. A screenshot of a local
page, of an app being built, or of a project's GitHub page points at a project folder. For a local
page it often names the exact session: Claude Code and Codex put their session's id in the
environment of every command they run, and a dev server they start keeps it.

The default becomes the first of these that exists:

1. The session the image names. Shipped as Reply.
2. The session that started the server behind the page.
3. A session working in the folder the screenshot shows. The rule looks for one working there now,
   from its transcript's folder, then one started there, from herdr's pane folder, then one in
   another worktree of the same repository. Ties go to herdr's focus, then to the session used last.
4. The thread the Codex app shows, when it was the app in front, which is built and not yet
   released. Then the session in herdr's focused pane, then the one agent in the focused tab, which
   are shipped.
5. The session used last. Shipped.

The safeguards stay as shipped. The chip shows the target before anything is sent, and Return never
sends to a session Vignette picked.

This is the strongest option because recency fails exactly when you work on two projects at once. In
the replay below, 9 of the 11 misses of "used last" went to a session in another folder. What the
screenshot shows is the one signal that names the folder, and Vignette reads it from the system
instead of guessing it.

## What the evidence says

**Replay of past pastes.** I matched 53 screenshots pasted into Claude Code sessions in the last 35
days to their captures, by time and pixel size. Each rule picked from the sessions active in the 4
hours before the capture.

| Rule | Right |
|---|---|
| Used last: the latest entry from you or the agent | 42 of 53 |
| Prompted last | 39 |
| Pasted into last | 31 |
| The screenshot's text matched against each session's recent text | 43 |
| That text match when it leads by 1.5 times, else used last | 44 |

- **Most misses were in another project.** 9 of the 11 misses of "used last" went to a session in
  another folder. They include two old sessions resumed after 11 hours and one new session with no
  history.
- **The text match fixed 4 of the 11 and broke 2 right answers.** It fixed both misses in the same
  folder and two in other folders.
- **The subject would likely have fixed 6 of those 9.** Judging from their text, those 6 show a
  local page in a worktree, the app being built, or the project's README. This comes from reading
  the screenshots, not from a replay. A replay needs the frontmost app at each capture. That is in
  macOS's usage history, which I was not allowed to read.
- **herdr's focus, the shipped default, is unmeasured.** I found no history of it I could read.

**The probe, run live on this Mac.** `subject` takes an app, a page address or a path, and prints the
session it leads to.

| What was captured | Where it led | Time |
|---|---|---|
| Vignette's own Debug build | `~/Code/vignette`, this session | 116 ms |
| The GitHub page of a pull request on `petekp/vignette` | the checkout with that remote, this session | 82 ms |
| A local page served from `~/Code/munari/apps/lab` | the `munari` repository, 2 sessions there | about 320 ms |
| Dia on chatgpt.com, Finder, Notes, Linear | nothing, so herdr's focus decides | about 20 ms each |

- **Local pages.** 103 ports were listening between 3000 and 8999. 38 were dev servers an agent had
  started: 20 by Claude Code, 18 by Codex. The other 65 were services such as databases.
- **The 20 Claude Code servers:**
  - 7 led to the session that started them, still in a herdr pane.
  - 11 had outlived their session. Their folder led to the same project: 4 to one session, 7 to
    several.
  - 2 ran in `/tmp` and led nowhere.
- **The 18 Codex servers** carry `CODEX_THREAD_ID`. The probe does not list Codex threads. The app
  would match that id against its Codex list.
- **Finding the server** takes about 150 ms, all of it `lsof`. The app would do this off the main
  thread, once per capture, and only for a local page.
- **Reading a page's address.** Dia gives it through Accessibility once it has been asked to build
  its accessibility tree (`AXManualAccessibility`). The first read after that found nothing. The
  next, 300 ms later, found it. After that a read takes about 20 ms.
- **Finder and Notes.** Walking the whole window tree took 4.9 s in Finder and 9.8 s in Notes. The
  probe reads only the focused window's document and the page, with a 250 ms deadline, and both
  answered in about 20 ms.

**What it cannot see:**

- **Which window a region capture covered.** The frontmost app stands in for it. A capture of a
  browser behind the terminal reads as the terminal, and herdr's focus decides.
- **Deployed pages,** such as a Vercel preview. They name no folder. Only GitHub pages map to a
  checkout.
- **A dev server run by hand in a plain terminal.** It carries no agent's id, so only its folder
  counts.

**Other approaches, not recommended now:**

- **Matching the screenshot's text to each session's text.** It was right 2 more times out of 53 than
  "used last" and broke two right answers. Text recognition takes 61 ms per image. It might later
  break ties inside one project.
- **Asking a model to rank the sessions.** It is slow, and it sends the screenshot's text away.
- **Hooks in each agent.** Every client needs its own, and each sees only its own session.
- **Process ancestry.** A dev server started in the background is reparented to launchd, so its
  parent chain no longer leads to the session. Its environment still names the session, so the
  environment is the signal to use.
- **An agent declaring it expects a screenshot,** for example with a `vignette://expect` command.
  It's precise, but it covers only the case where the agent asks.

## Building it

- **Read the subject when the watcher reports a capture,** off the main thread, within 250 ms.
  Store it on the file as an extended attribute, as a push's agent and session are stored. The
  editor may open minutes later, with another app in front.
- **Keep only the folder and the agent's id.** The page address is read and dropped, so no browsing
  history reaches the log or the disk.
- **Record herdr's focused session at capture too.** The shipped rule reads the focus when the
  editor opens. The capture is the moment the screenshot is about.
- **Accessibility is needed for page addresses and documents.** Without it, the app-build and
  process-folder cases still work, and the rest falls through to herdr's focus.
- **Cost:** once Vignette asks, a Chromium browser such as Dia, Chrome or Arc keeps its accessibility
  tree on until it quits. That costs the browser memory and CPU on heavy pages. The probe turned it
  on in Dia on 2026-09-24, and it stays on until Dia quits.
- **The code:**
  - a new `CaptureSubject.swift` for the reading;
  - `AgentDestination.defaultTarget` gains the subject's tiers;
  - each destination carries its folders: herdr's, the transcript's and the Codex thread's.
- **The tests** cover the order of the tiers, and the mapping from an address or a path to a folder
  as pure functions.
- **How to measure it once built.** Each capture logs the session the rule picked, and each send logs
  where the drawing went. A few days of use gives the hit rate, including herdr's focus.
- **A side finding:** Codex's commands carry `CODEX_THREAD_ID`. The skill could pass it on a push, as
  it passes `CLAUDE_CODE_SESSION_ID`, so a Codex card could offer Reply too.
