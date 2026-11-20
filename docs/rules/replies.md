# Replies

- Sending a drawing to an agent session and taking its drawing back is one object,
  `ScreenshotRequests`, and one small boundary, `AgentConnection`. Listing the sessions is
  `SessionListing`, which uses the same connections (`AppDelegate.connections`). Two things are durable and
  different: **acceptance** means Vignette owns every byte of a reply, and is what the receipt a
  helper waits for acknowledges; **publication** means the reply is a card. Between them the reply's
  watch-folder name is reserved and excluded from every listing, so an interrupted import leaves
  nothing half-shown. `isVisible` is derived from the reply record, not a second ledger, and it
  fails closed: a file named `Agent reply <uuid>.png` with no `published` record is hidden, whoever
  wrote it. Only that exact name shape is managed; a screenshot merely starting with "Agent" is an
  ordinary capture. Naming one is refused the same way listing it is: a `file=` on a reserved reply
  answers `missing-file`, and `add` refuses a source with that name outright, since the copy would
  have no record and so could never be shown. Reservation persists the actual destination URL
  before copying. Visibility and origin use that location; a later screenshots-folder change does
  not move an existing reply. A published reply the person renames inside the folder keeps its
  record, which records the new location as `renamedTo`, so its card keeps Reply. Cleanup never
  reads `renamedTo`: it removes only unpublished outputs, at their reserved name. Startup loads the records before the watcher starts, then waits for
  successful current-folder inventory before recovery. Deletion needs confirmed absence in the
  reply's own folder. Locationless published records are retained conservatively.
  `Drawings.installReply` writes one complete drawing before publication. Recovery reuses a valid
  checkpoint's geometry and point scale. Strict reads refuse missing marks, invalid fields, wrong
  image size, or shapes outside the image. Text anchors are checked without reflowing their stored
  geometry under current typography. Additive pushes still use `Drawings.add`.
  Clearing commits the terminal request record before removing payloads and unpublished outputs.
  A failed commit retains the state and files. Late transport outcomes report delivery without
  reopening the request. Cleanup uses recorded locations and replays after restart; unresolved
  output cleanup prevents retention pruning. Completed cancellation records remain untouched on
  later scans; failed record writes remain pending until persistence succeeds. Published files
  remain the person's.
  A managed reply is never a capture after publication, so late watcher events cannot copy or
  open it. Its own import inserts the card once. At `maxLiveRequests` a send stores its new
  candidate before clearing the oldest of 50 open requests. Failed retirement discards the
  unsubmitted candidate. A pre-existing over-limit store requires explicit clearing before Send.
  Cleared request folders are removed after a week only when no published reply or unfinished
  output cleanup still needs their records. Every stack open reconciles the cleared requests on
  the main thread, so `ClearedRequestFolders` remembers each one's cleared date and its folder's
  stamp from the last pass that found its sent image and submissions gone. A remembered fact
  only skips a check: pruning reads the date from disk again before it removes a folder, and a
  folder whose stamp changed is looked at again. `docs/request-safety-plan-2026-10-02.md` is the plan
  these rules came from, with how it was verified.
- A `vignette://` URL has no authenticated sender, so a reply is authorized by a per-request bearer
  secret in the request's own directory. The request line names only the image
  (`ScreenshotRequests.requestLine`, "From Vignette: …", then `sendInstructions` from settings.json),
  and the skill tells the agent that the
  ticket is `ticket.json` beside it and the helper is the skill's own `scripts/reply`, so an agent
  without the skill can read the drawing but not answer with one. Words alone on the agent's own
  image (`Record.unchanged`) name the card's file and its title instead, say it is unchanged, and
  name the ticket, since no image is beside that file. The request still stores `image.png`, the
  card's picture without the agent's marks, as the picture a reply without its own image draws on.
  The line never names it. The secret never travels in the
  line, because `[url]` logs every URL. Holding the ticket permits replies to that one request
  and proves nothing about which process wrote them. The helper writes its envelope where its own
  ids say it should be and Vignette derives that path itself, so a caller cannot name a file
  outside the request directory. Only the request root is resolved, because Vignette created it;
  every component below it must be real, so a link put in place of `submissions/<replyId>` is
  refused rather than read through. A refusal writes a receipt where the attempt's ids say, except
  when the authorization itself failed and a receipt is already there: the attempt id is the
  caller's to choose, and an unauthenticated one may not replace the answer a genuine attempt is
  waiting for. A reply's
  identity is a digest over the bundle file's own bytes and then the image's, which is why the
  helper and the app cannot disagree about how a number is spelled. The same reply id with the same
  digest is acknowledged from its record and makes no second card; with a different digest it is
  refused and the first is untouched. Raise `ReplyProtocol.version` with any change to what either
  side writes: a skill copy from before 2026-09-26 carries a Python helper that still answers.
- The reply helper is the app's own binary. `AppDelegate.main` hands `<binary> reply …` to
  `ReplyCommand` before an `NSApplication` exists, and it exits, so the app never starts. The
  skill's `scripts/reply` is a shell script, so the skill needs nothing a Mac does not ship:
  `/usr/bin/python3` is a stub that asks to install Apple's developer tools. It reads the ticket's
  `app` with `plutil` and runs that bundle's `CFBundleExecutable` only when its Info.plist has
  `VignetteReplyCommand` (project.yml): a binary without the command would start the app and
  replace the running instance. The ticket decides what runs, so the script takes only a ticket in
  `<requests>/<request id>/`, where `<requests>` ends in `<that app's bundle id>/requests` and is
  either the folder in the script's own `requests_root=` line or
  `$HOME/Library/Application Support/<bundle id>/requests`. `AgentPlugin.stage` writes the copy's
  own requests folder (`ScreenshotRequests.defaultRoot`) into that line of the staged script, so the
  helper in a copy's plugin takes that copy's tickets wherever `Launch.dataHome` put them, whatever
  the agent's `HOME`. The folder is in the script itself because a file read from beside the
  script follows `$0`, which the caller chooses: a link to the helper, or `sh reply` found on
  `PATH`, would read a file the caller wrote. The script refuses a folder that is not an absolute
  path. The repo's copy leaves the line empty, so a skill linked from the repo takes only the `HOME`
  folder. It finds
  `--ticket` the way `ReplyCommand.Options` does, and the command refuses a ticket another app
  issued (`checkIssuer`); change the two parsers together. The file is also Python that hands
  itself to sh, for agents that still hold the version 3 instructions. The command checks the marks
  with `AgentMark.parse` and converts the image to PNG before anything is sent, and the app refuses
  a reply image that is not a PNG, since it is published as `Agent reply <id>.png` and Copy puts a
  file's bytes on the pasteboard as PNG. `docs/reply-command-2026-09-26.md` has the reasons.
- The reply helper returns to the app that issued the request: `ticket.app` names the bundle and the
  helper passes it to `open -a`. Plain `open` hands a `vignette://` URL to whichever copy of the
  bundle id LaunchServices registered last, which on a Mac with a second build is a different app
  that answers `unknown-command` (observed). The helper reads the URL scheme from that bundle's
  Info.plist too (`ReplyCommand.dispatch`), so a fork's reply goes to the fork's scheme.
