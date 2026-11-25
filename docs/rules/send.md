# Send

- `Sources/AgentAddress.swift`, `Sources/AgentConnection.swift`, `Sources/ScreenshotRequests.swift`, `Sources/ReplyProtocol.swift`,
  `Sources/ReplyCommand.swift` and `skills/vignette/scripts/reply` are the closed loop: a drawing
  sent to an agent session and that agent's drawing sent back. `Sources/SessionListing.swift` lists
  the sessions Send can go to, `Sources/SendGrace.swift` decides what a send does while its line waits, and `Sources/HerdrFocus.swift` reads the Herdr app's focus. See the rules below, `docs/rules/replies.md` and
  `docs/closed-agent-loop-implementation-2026-09-20.md`. `agent-plugin/` is the plugin Claude Code
  and Codex install, which carries the skill and, for Claude Code, delivers what Send sends, and
  `Sources/AgentPlugin.swift` installs it (`docs/claude-code-without-herdr-2026-09-27.md`).
- A listing answers in parts: a kept list at once, then each client's fresh list
  (`SessionListing.list`). Every menu that lists sessions, the editor's target menu and live ink's
  note, passes each answer through one rule (`DestinationChoice.replacesList`): an answer that is
  not complete never replaces a complete list, since it lacks every session of a client still to
  answer. The complete list stays, even when it is older, and on a swap the image before's, until
  the next complete answer. A new menu of sessions uses the same rule.
- Send never brings the destination's app forward. The card says what happened, and the person
  decides where to look. When they sent from the destination's app, the hand-back returns them
  there (`FocusReturn`, `docs/rules/stack.md`). `scripts/check-app-activation.py` fails a call
  that activates, launches or opens an app outside its allowed list.
- A destination is an agent session, never the terminal displaying it. Codex is addressed by its
  thread UUID and nothing else: `codex queue --thread` resolves the UUID in the thread store or
  fails, which is `AddressGuard.runtimeEnforced`, and stores the message in Codex's queue. An engine
  that has the thread loaded, the Codex app's or a CLI session's, takes it within about 10 s. A
  thread no engine has loaded keeps it until someone opens the thread, and it then runs first.
  `codex queue` answers the same either way, so Vignette then looks for the lock file an engine
  holds while it has the thread (`CodexConnection.isLoaded`), and a send to a thread nobody has
  open is reported as queued. The codex Vignette runs is the one inside the Codex app when the app
  is installed (`AgentApp.codexCLI`), since the app keeps it in step with its own engine, and
  otherwise the first `AgentTools` finds. `AppServer.swift` is the only thing that
  speaks the app-server protocol, and it only reads: it carries a `thread/list` to a `codex
  app-server` of its own, asking for the threads used last (`sortKey: recency_at`), and a
  `thread/read` of each thread asked for by its id, the kept pick's and the one the Codex app
  shows, each under its own request id, and turns the answers into menu rows, each
  with the thread's own `cwd` and `recencyAt`. An ephemeral thread and a sub-agent's thread (one with
  a `parentThreadId`) are left out. A thread with no name is named by its first message. The thread store is on disk,
  so a server started for the length of that one listing answers for every session, whoever owns
  it; the listing's `status` is that server's own memory and says nothing about a session, so it is
  not kept. No `codex` on the machine means no Codex destinations, which is not an error.
  `docs/codex-discovery-2026-09-21.md` has the protocol, the timings behind `listLimit`, and what
  was verified against a live desktop session. Claude Code is addressed by
  its session id, through the plugin's inboxes (`ClaudeCodeConnection`): one folder per Claude Code
  process, `claude-sessions/<pid>/` under Application Support, holding the session it runs now, its
  folder and a file its monitor touches every 3 s. Only a session whose process and monitor are both
  alive is listed, since only those can receive, in any terminal. The inbox's folder is the
  session's project. Its row comes from its transcript, `~/.claude/projects/<folder>/<id>.jsonl`,
  read from the last 256 KB: the last `ai-title` names it, and the last user or assistant entry's
  `timestamp` is when it was last used. That entry's `cwd` follows the session's shell, so it is the
  project only when the inbox gives none. The file's modification time is
  not the last use: Claude Code writes entries with no message in them to transcripts it is not
  using (measured 2026-09-24). The Herdr app, when it runs, only says which session has the focus (`HerdrFocus`). `/clear`
  and `/resume` give the same process another session, so Vignette checks that the inbox still
  holds that exact session immediately before writing the line (`AddressGuard.preflight`). A
  session in no inbox is an error, "closed" or "cleared", and never another session. The line is
  accepted once it is in the inbox; the session reads it when its turn ends. The image travels as a
  path the session opens itself, so a Claude Code session that may not read it stops on a permission
  prompt, which Vignette cannot see. So turning Claude Code on, in setup or the Agents tab, also
  adds `ClaudeReadRule`, one `Read(…/requests/*/image.png)` rule in `~/.claude/settings.json`'s
  `permissions.allow`, which lets Claude Code open the sent images without asking, and turning it
  off there removes the rule. While the plugin is in, the Agents tab has a switch for the rule
  alone. A launch never adds it, so an install from before this keeps what it had. It writes through a link to that file, since people keep it in a dotfiles
  repository; a skill's `allowed-tools` was tried and made Claude Code ask to use the skill
  instead. The two tiers
  are recorded on every request and reported in `[state] requests`; `docs/closed-agent-loop-implementation-2026-09-20.md` says why the weaker one
  is still allowed to submit.
- A project with past Claude Code sessions and none running offers Continue last session and New
  session in both session menus (`StartableSessions`, `SessionStart`). Search finds them, after the
  running sessions; the top rows, the project submenus and their counts hold running sessions only,
  unless none is running, when these rows fill the top rows (`SessionMenu.menu`). Sending to one opens a tab in
  the space the Herdr window shows (`HerdrLauncher`, through `hc run`), starts `claude --resume <id>` or `claude --session-id <id>` there, waits up to
  45 s for its inbox, then writes the line as any send does. An `hc run` that gives no answer in
  time may still have opened the tab, so its inbox is waited for the same way. Only a person's pick starts a process:
  the rows travel apart from the running sessions (`Candidates.startable`), so `DestinationChoice`
  never sees them, and only the menus join the two (`DestinationChoice.Answer.sessions`). Without the Herdr app and `hc` no row is offered.
  `docs/session-starts-2026-10-25.md` has the design.
- Send never reuses Done. It renders the drawing on `RenderingQueue` and closes nothing while it
  waits. The request is stored before the image leaves the editor, so a failure anywhere before then
  leaves the drawing where the hand left it. A rendering belongs to the opening Send was
  pressed in (`annotator.opening`). One that answers after that opening ended is dropped, even when
  the same image is open again, and nothing is sent or closed
  (`[send] dropped <name>; the editor moved on`). `sending` stays on from the press until the bar
  has left, so the button keeps its paper plane through the exit, and `prepare` resets it, so the
  next image's toolbar never shows a send that is not its own. A list of agent sessions that
  arrives after its opening ended is dropped as well, including a close and reopen of the same
  image. Both discovery continuations compare `annotator.opening`. A rendering that fails is a
  refusal, never a send of the bare screenshot: only a drawing with no marks sends the picture
  itself, and it goes through PNG whatever the capture's own format is. Reply to the card's own
  agent session, with the drawing exactly as the agent sent it (`Agent.hasSentDrawing`), sends the
  person's words and no picture (`ScreenshotRequests.Picture.unchanged`). A PNG card needs no
  rendering, and its file is cloned as the request's `image.png`. With no words either there is
  nothing new to send: the bar's Reply is unavailable, and Return and Cmd+Return copy and close as
  Done does, with no error (`docs/rules/annotator-toolbar.md`). An undo back to the agent's drawing
  counts as unchanged. An edit to the picture in another app, a new text style or mark scale, and a
  card path with a line break in it count as changed, so the picture goes
  (`ScreenshotRequests.Carried`). A file with no
  recorded drawing always sends the picture. Send closes the editor
  without a Copied notice, and the queue carries on to the next card: a list of files to annotate is
  something the person asked for, and handing one of them to an agent does not withdraw the rest.
  Esc is the one that empties the queue, because that is a person stopping.
  Once the request is stored, its line waits `ui.sendGraceSeconds` (3 by default, 0 for no wait)
  before the client gets it (`SendGrace`, run by `ScreenshotRequests`). The wait is time, not
  motion: the scale and Reduce Motion never shorten it. When it ends the line goes through the
  same `submit` as before, so nothing written changes. Quitting hands every waiting line over at
  once and waits up to 2 s for the clients (`releaseHeld`). Every hand-over records its request
  uncertain before the line leaves, so `prepared` means the line never went. When that record
  can't be written, the line does not go and the card says "Not sent". And a clear of the request, by
  `requests?clear=` or by the 50-request limit, stops its waiting send. So does a file leaving
  the watch folder, which is how deleting a card during the wait cancels its send
  (`ScreenshotRequests.fileRemoved`). A rename inside the folder carries its waiting sends to the
  new name, so Don't send on the renamed card still stops them. A crash during the wait loses the send, and the next launch
  clears the request it left prepared, unless that launch replaced a running copy, which may
  still be handing its lines over (`load(clearingUnsent:)`); a later launch clears it then.
- A send reports on the card it was sent from. Once the request is stored the card
  carries a `SendNotice` (`ThumbnailController.showSending`), keyed by the file's path because a lone
  thumbnail's card leaves the panel while it is in the editor. It shows the destination's logo and
  the session's title from the moment the card lands: the title the toolbar or the live ink note
  showed at Send, or the project folder's name for a session Send starts (`SessionMenu.cardTitle`).
  `delivered` turns it to sent, queued, uncertain or failed when the client answers. Anything but
  sent carries a `reason`: every `SubmissionOutcome` but `accepted` has one, written where the client knows what happened, and `detail` stays for the
  log. A card gone from the screen by then says nothing more about a success and comes back as a
  lone thumbnail for anything else. A failure before the request is stored leaves the drawing in
  the editor, so it shows there: the button reads "Not sent" and a popover on it gives the reason,
  both until a click elsewhere or Send again. A reply that was accepted and could not be made a card
  has no card to report on, so the card it answers takes a `replyFailed` notice, "Reply not shown"
  (`ScreenshotRequests.Callbacks.replyFailed`). The card is found by the request record's
  `sourceKey`, the source's full path as the folder spelled it when the send was stored; a record
  from before that holds only the name, and its key is built in the current folder
  (`ScreenshotRequests.sourceKey(of:)`). A rename after the send moves `sourceKey` with it.
  A published reply is its own card and nothing else
  says it arrived. `docs/send-confirmation-2026-09-26.md` has the frames.
- A send that reaches its client, accepted or queued by Codex, is recorded on the screenshot it was
  sent from as the `com.petepetrash.vignette.sent` attribute (`Agent.Sent`), which the card's tab
  shows (`docs/rules/agent-push.md`). `ScreenshotRequests.recordOutcome` writes it, so a send handed
  over at quit and a request cleared after its line went are recorded too. A failed or uncertain
  send writes nothing, and a send cancelled with Don't send never gets an outcome. The title is the
  request's `cardTitle`, which `send` takes from the caller at Send. A newer send replaces the record.
  While the line waits, the card shows `.inGrace`: a ring round the logo that empties to the
  deadline, and a Don't send button, the only part of the overlay that takes presses. The ring is
  drawn from the clock and is the one animation not scaled by the motion setting. The button
  and `vignette://unsend` both run the `unsend` action, which cancels every send of that file
  still waiting and clears the request: the card shows only the newest, and an older one would go
  out unseen. An editor card keeps its screenshot and goes back to no
  notice. A live ink note card is Vignette's own file, so it is discarded with its drawing
  (`FolderWrites.discard`). `docs/send-grace-2026-10-10.md` has the reasons and the checks.
- A Codex send's line is watched in the thread's queue until Codex takes it (`QueueWatch` in
  `CodexQueue.swift`). `codex queue` prints the line's id, and `ScreenshotRequests` asks a `codex
  app-server` of its own for `thread/queue/list` (experimental, so the client says
  `experimentalApi`): every 3 s in the first minute, then every 10 s, 30 s and 60 s, since a line
  behind a stopped turn can wait for hours. The reason comes from the thread's rollout and its writer
  lock: a turn running, a question open, the last turn stopped, no engine with the thread open, or
  the thread archived. A command approval leaves no mark in the rollout, so it reads as a running
  turn. An open thread whose last turn ended is said to hold the line only after 15 s, since its
  engine looks at the queue every 10 s. A line gone from the queue is taken when the thread's rollout
  holds the request's id, which the line names in its folder, and removed in Codex when it does not.
  A compressed rollout reads as unread, and the watch looks again.
- The send's answer is its notice: Queued for the session, with the reason and Don't send. Every
  later change only redraws the card's tab (`Callbacks.queueChanged`), so a card off screen does not
  come back for it. While the watch says the line is held, the tab reads "Queued for *session*" with
  an orange clock (`Card.Sent.queued`, from `ScreenshotRequests.queuedSend(of:)`). Hovering the tab
  turns the clock into Don't send, whose help is the reason. The Queued state comes from the live
  watch, never the `Agent.Sent` attribute, so after a relaunch the tab says Sent as before. Don't
  send on a queued line runs the same `unsend` action: it takes the overlay down at once and asks for
  `thread/queue/delete`. Removed clears the request, and the card says nothing, as for a send in
  its grace. The attribute goes back to the newest other send of the file that reached its client,
  so the tab still names an earlier queued line, or it goes. Already taken says "Codex had already started on it." under Sent, and
  a refusal says "Vignette couldn't remove it. You can delete it in Codex." under Queued
  (`Callbacks.laterAnswer`), with the watch going on. Don't send takes out only the line of the newest send
  to the session the tab names, since answers can come back out of order, and only when no send of the file in its grace is newer, so an earlier send's line,
  to this session or another, stays (`ScreenshotRequests.unsend(file:)`). A live ink note takes back
  its own request. Deleting the file takes back every send of it: those in their grace, and every
  line of it a queue holds. A line the person deletes in Codex clears the
  request and puts the attribute back the same way, without a word. A thread Codex can no longer find ends the watch with a
  failure on the card. A clear stops the watch and leaves the line in the queue.
  `docs/codex-queued-sends-2026-11-16.md` has the live runs behind each reading.
