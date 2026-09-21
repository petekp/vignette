# Closed agent loop implementation — 2026-09-20

What was built, the two gates the plan left open, and how each
route was proved. Update this file rather than adding another.

## The two gates, and what was chosen

**Native Codex connection setup.** The plan required either a supported way to reach an existing
session's endpoint or an explicit choice of Vignette-created sessions. Neither was taken silently.
`codex app-server daemon start` refuses on this Mac (`managed standalone Codex install not found at
~/.codex/packages/standalone/current/codex`), so there is no shared local endpoint to discover, and
installing one is a machine change that needs Pete. Vignette therefore takes the endpoint and the
thread UUID as **explicit configuration** and never starts, owns, resumes, or stops a Codex server
or session. A Codex destination is a line in `settings.json`.

That gate is now half open. Vignette reads a running app-server's own thread list when one is
there, so a daemon supplies the sessions automatically and the configured lines are the fallback
rather than the only way (`docs/codex-discovery-2026-09-21.md`). It still starts nothing: no
socket, no discovery.

**Reply trust model.** Implemented as the plan's own proposal: a per-request bearer ticket in a
private request directory. Possession of the ticket authorizes one request's replies; it does not
prove which process produced them, and there is no verified-author badge. Mutually untrusted
same-user processes remain outside the guarantee.

## The two routes

| Client | Submission | Address | Guard |
| --- | --- | --- | --- |
| Codex | `codex queue --thread <UUID> [--remote <endpoint>] --message <line>` | the thread UUID | runtime-enforced: the app server resolves the UUID or fails |
| Claude Code | `herdr agent prompt <pane> <line>` | the Claude Code session UUID | preflight: `herdr agent list` must still report that session UUID in a pane |

Codex matches the plan's first eligibility row. Claude Code does not: herdr's prompt API takes a
pane and has no expected-session parameter (`AgentPromptParams` is `target`, `text`, `wait`), so
Vignette checks the pane still holds the bound session immediately before submitting instead of the
receiver rejecting a stale generation. The residual race is the milliseconds between that check and
the submission, and it needs the person to be clearing or resuming that exact pane inside them.

This is a deliberate departure from the plan's table, recorded here rather than hidden: the plan's
row 3 describes routing that has *no* conversation identity, and Vignette's Claude route has one —
it binds to the session UUID, resolves it to a pane at send time, and reports an error rather than
a replacement target when the UUID is not in any pane. `AgentAddress.guard` names the two tiers,
`[state] agents` reports which tier a destination is on, and the request record keeps it, so the
decision to make the weaker tier manual-only is one setting away.

## What a send and a reply touch

Files under `~/Library/Application Support/<bundle id>/requests/<requestID>/`:

```
request.json           destination, address, guard, status, the sent image's name
image.png              the fixed sent PNG; never offered to the editor or the stack
ticket.json            the reply ticket: secret, protocol version, where replies go
submissions/<replyID>/ helper-owned: bundle.json, image.png, attempts/<attemptID>.json
receipts/<attemptID>.json   Vignette's only acknowledgement; atomic, derived path
payloads/<replyID>/    Vignette's own copy of an accepted reply's bytes
replies/<replyID>.json the authoritative reply record and its import stage
```

Every accepted reply becomes one new watch-folder file named `Agent reply <replyID>.png`. That name
is reserved: a file in that shape with no `published` reply record is excluded from every listing,
card, and file action until publication commits, and a corrupt or unreadable store fails closed.

## What is refused, and how a helper finds out

`vignette://reply` answers one `[reply]` line and writes one receipt per attempt, at a path derived
from the attempt's own ids. The helper waits for that receipt and for nothing else: `open` exiting
zero is a dispatch result, not an application answer. Refusal codes are `bad-envelope`,
`unknown-request`, `protocol-mismatch`, `bad-authorization`, `request-closed`, `digest-mismatch`,
`conflicting-reply`, `bad-payload`, `too-large`, `store-failed`.

## Live runs, 2026-09-20

Driven through the real interface against a scratch settings file, a scratch watch folder, a
purpose-made Claude Code session in a herdr pane, and a purpose-made Codex thread on a disposable
loopback App Server. Both were created for the test and stopped afterwards; nothing was sent to any
session already running.

| Check | Result |
| --- | --- |
| Claude Code, whole loop | Circled a swatch, Send, the session read the image and replied with 3 marks; the card carried the agent's marks over the sent picture; edited it, Reply, and the same session answered again with 2 marks. |
| Codex, whole loop | The same, by thread UUID at `ws://127.0.0.1:54971`: 2 marks back, then a second round trip of 1 mark. The helper's `{"status": "accepted"}` reached the Codex transcript. |
| Stopped mid-import | The app was replaced while a reply sat at `reserved`. The next launch loaded it (`pending=1`) and published it: one file, one card, no duplicate. |
| Forged ticket | `bad-authorization`, no reply record, helper exit 2. |
| The same bundle sent twice | Second attempt answered `accepted / ready` from the record; four reply files before, four after. |
| Cleared request | New replies refused with `request-closed`; the fixed PNG and submissions removed; published cards untouched. |
| Deleted reply file | Recorded as removed and never recreated from the recovery copy. |
| Codex endpoint stopped | `destination-changed`; the request kept with the reason; nothing sent anywhere else. |
| Claude session exited | Reply from its own card refused: "session … is in no herdr pane now". Never redirected to another pane. |
| An older build answered the URL | Before `ticket.app` existed, `open` handed the reply to another Vignette build on this Mac, which answered `unknown-command`, and the helper reported it as unconfirmed rather than as delivered. That routing is what `ticket.app` fixes. |

Two defects were found by running it and fixed: the reply going to whichever build LaunchServices
registered last, and a free canvas reading as "the app is gone" (optional chaining flattened
`canvasRefusal`'s own nil), which left every import waiting forever.

Unit coverage is in `Tests/ReplyProtocolTests.swift`, `Tests/ScreenshotRequestsTests.swift`, and
`Tests/AgentConnectionTests.swift`: envelope location and link refusal, digest recomputation, the
reserved-name shape, acceptance and the duplicate/conflict matrix, publication stages and
fail-closed visibility, resume from disk, clearing, and each connection's guard and failure
classification. `./scripts/build.sh --test`: 253 pass.

## Review, 2026-09-20

An adversarial read of the whole feature found sixteen things. Nine were changed; the rest are
recorded under Known limits or were already what they should be. Each change has a test that fails
without it.

| Found | Change |
| --- | --- |
| A reply carrying its own image was refused `store-failed` unless a marks-only reply had already created `payloads/`. Every first `--image` reply to a request failed. | The directory is created before the image is written. Verified live: a `--image` reply is now accepted, reserved, and published, and the card carries the agent's own picture. |
| Clearing a request while its marks were still building published the reply anyway, from a record copy captured before the clear. | Publication re-reads the stored stage and takes the reserved file back instead. |
| A reply waiting for the canvas resumed only when an annotator session happened to end: an export finishing or a prepared image being abandoned signalled nothing. | `AnnotationController.canvasMaybeFreed` fires `onCanvasFree` from each of the four release points. Verified live: two replies queued behind an open editor both published the moment it closed. |
| An unauthenticated caller could overwrite the receipt a genuine attempt was waiting for, because the attempt id names the receipt file. | A `bad-authorization` refusal never replaces a receipt that is already there. |
| Done stopped cancelling when `render` answered null with marks on the canvas; it posted `done` with no png, and the host copied the plain screenshot. | A null rendering with marks present is an error again, so Done cancels and Send refuses. |
| The session list is read by subprocess and two images' answers could arrive out of order, labelling an ordinary screenshot as a reply to the wrong session. | The answer is dropped unless the editor still holds the image that asked. |
| An explicit `file=` reached past the visibility rule: a reserved reply could be opened or trashed mid-import, and `add` could write a name that would never be shown. | Both refuse. Verified live. |
| herdr's `agent_blocked` was reported as the session being gone. | It is a non-submission with the reason; only `agent_not_found` is a changed destination. Codex's bare `not found` match went the same way, since `command not found` says nothing about a thread. |
| A jpg or heic sent with nothing drawn on it put the capture's own bytes under a `.png` name. | It goes through PNG. |
| `SubmissionOutcome.word`, `AgentDestination.stateJSON`, and an unreachable pane fallback that contradicted its own comment. | Deleted. `ScreenshotRequests.destinations` is a plain main-actor method rather than `nonisolated` plus an `assumeIsolated` that could trap. |

Two of the sixteen were comment drift (`pendingImports` is in arrival order only within a launch;
the watch-folder check is about the folder being gone) and are corrected in place. The symlink
comment overclaimed: resolving both sides of the path check matched through a link put in place of
`submissions/<replyId>`. Only the request root is resolved now.

## Adding another agent

Implement its connection and whatever instructions it needs to read an image and return a reply.
Reuse the request records, the reply validation, the receipts, the import queue, and the UI. An
agent shown in several terminals is still one connection: a second integration that needs Vignette's
delivery code changed has not reused the workflow.

Prove the missing capability before adding anything. If a runtime cannot receive an external
message or return what a reply needs, that integration is unsupported and the answer is manual
copy and paste — not a terminal adapter, a wrapper, or a new service to fill the gap. The
agent-driver and terminal-transport designs were considered and withdrawn for that reason; raw
terminal injection is outside this feature.

Whether a connection may submit at all is the eligibility rule, which is what `AddressGuard`
records on every request:

| What the connection proves | May Vignette submit | Why |
| --- | --- | --- |
| The receiving runtime enforces an immutable conversation address | Yes | It submits to that exact conversation. A missing or archived one is an error, never a substitute target. |
| A receiver-side check of the expected conversation, made atomically as it accepts | Yes | An old generation is rejected before anything is written or queued. |
| A preflight check with no receiver-side guard, but a real conversation identity | Yes, and recorded as the weaker tier | The window between the check and the submission is real; the address is still a conversation, not a pane. This is the Claude Code route, and the note above says why it is allowed. |
| No conversation identity at all | No | Addressing a pane is addressing whatever is in it. |

Automatic means Vignette submits without the person pasting into the agent's own UI. It never
means delivery without their Send or Reply. A binding does not survive the conversation being
replaced, `/clear`, a resume into another conversation, or a reused pane; a new one needs the
person to pick again, and queued requests are never silently redirected. A submission that timed
out stays unknown: it is neither retried on another route nor reported as failed.

## Known limits

- Codex sessions are discovered only while an app-server is running with a control socket. On a
  Mac with none, they still have to be named in `settings.json`, and the ChatGPT desktop app's own
  server does not count: it listens on nothing. Sending to a *discovered* thread is also the one
  part of the loop never exercised end to end, since no daemon owns a thread here.
- The Send menu groups the sessions by the project each is working in, which is what a person
  picking among a dozen navigates by. Up to six projects they are sections, so every session is one
  press away; above that each project is a submenu, because a heading and separator per project is
  what pushes the list off the bottom of the screen. The conversation a reply belongs to leads the
  menu on its own, named with its project. Two sessions in the same project with the same pane
  title still read alike; they are addressed by their own session ids, so a send is correct, but
  the person cannot tell them apart in the menu.
- A reply refused for a closed or unauthorized request leaves the helper's bundle in the request
  directory. Vignette never reads it. Clearing the request removes the whole `submissions` tree.
- There is no expiry or retention sweep. `maxLiveRequests` (50) refuses a new Send instead, and
  `vignette://requests?clear=all` is how room is made.
- A reply carries a drawing and nothing else. An agent answers in words in its own session, where
  the person is already looking.
- Accepting a reply reads, hashes, and writes its image on the main thread, and `maxImageBytes` is
  64 MB. A screenshot is a few megabytes and costs nothing; the cap is what a capture can be rather
  than what is comfortable there, so a reply at the cap would hitch the UI for about a second.
- `[state] app.bundle` is how a driving script tells whose instance answered. `build` cannot:
  parallel worktrees branched from one commit produce the same `git describe`, which is exactly the
  case the multi-build hazard arises in, and it is how a restore check passed against the wrong app
  on 2026-09-20.
- `ticket.app` names the issuing bundle and the helper passes it to `open -a`, which is what stops a
  reply reaching another build of the same bundle id. With a second copy of that bundle id already
  running, `open -a <path>` can still reach the running copy instead of the path named. The failure
  is bounded — the wrong app answers `unknown-command`, no receipt is written, and the helper says
  unconfirmed — but a retry from the same machine state repeats it.
- Send returns the card without a copied mark and lets a queued run carry on to the next card. It
  reused Esc's path at first, which emptied the queue: nothing in the toolbar says Send abandons
  the rest of a list, and a run ended that way cannot be resumed, while a person who wants to stop
  can still press Esc.
