# The reply helper moves into the app (2026-09-26)

The skill's reply helper stops being Python. The Vignette app answers `reply` from the command
line, and the skill's `scripts/reply` becomes a short shell script that runs it. After this, the
skill needs nothing a Mac does not ship.

## Why not Python

- `/usr/bin/python3` is a stub on a Mac without Apple's developer tools. Running it opens a dialog
  asking to install them, so an agent answering with a drawing could stop on that dialog.
- It was a second copy of the reply protocol, in another language. `ReplyProtocol.version` and
  the helper's `PROTOCOL` had to go up together by hand.

## Why not bash alone

- The helper reads and writes JSON: the ticket, the marks, the bundle, the envelope and the
  receipt. macOS 15 ships `jq`, but Vignette supports macOS 14, which does not.
- JSON built by hand in bash breaks on a text mark that holds a quote.
- It would still be a second copy of the protocol.

## What changes

- **`Vignette reply` in the app.** `AppDelegate.main` checks its arguments before
  `NSApplication` exists. With `reply` first, `ReplyCommand` runs the helper's steps and exits:
  the same arguments, the same JSON line, the same exit codes. It never starts a second instance
  of the app.
- **One implementation of the protocol.** The command writes the bundle and the envelope with
  `ReplyProtocol`'s paths, digest and types, and reads the receipt with `ReplyProtocol.Receipt`.
- **Marks are checked before anything is sent.** The command reads them with `AgentMark.parse`,
  the validator the app uses on arrival, so a bad mark fails at once with the mark and the field,
  instead of coming back as a `bad-payload` refusal. With `--image`, an empty list is accepted, as
  the app accepts it.
- **The script finds the binary through the app.** `scripts/reply` reads the ticket's `app` with
  `plutil`, which reads JSON on every macOS. It runs `<app>/Contents/MacOS/<CFBundleExecutable>
  reply "$@"` only when the app's Info.plist has `VignetteReplyCommand` (project.yml).
  - Only the bundle can say whether its binary has the command. A binary without it starts the
    app and replaces the running instance.
  - A field in the ticket, the first version of this change, answered that question wrongly both
    ways. A request sent before an update could not be answered after it. An older binary put at
    the same path, by a downgrade or a rebuild from an older commit, would have been run.
- **The script runs only a ticket where Vignette writes them.** That is
  `~/Library/Application Support/<the app's bundle id>/requests/<request id>/ticket.json`, the
  bundle id being the one in the app's own Info.plist.
  - The ticket decides what runs, and a prompt can name any file as the ticket. Without the check,
    a planted ticket could make the script run any binary, which matters where an agent's
    permission rules allow `scripts/reply` without asking.
  - Anything that can write into that folder can already run code as the user.
- **The script and the command find the same ticket.** The script reads `--ticket` the way
  `ReplyCommand.Options` does: a flag written without `=` takes the next argument as its value.
  The command also refuses a ticket another app issued (`checkIssuer`), so a later drift between
  the two parsers cannot send a reply through the wrong binary.
- **The skill runs the script with `sh`.** It then works without its executable bit.
  `SkillInstaller.matches` compares bytes only, so it would never repair a copy that lost the bit.
- **The script is also Python.** Agents that loaded version 3 of the skill still run
  `python3 scripts/reply`. Python reads the shell part as a string and runs the file with sh. This
  matters most for the retry line the Python helper printed after an unconfirmed reply: that is
  the case where the agent must not send a new reply instead.
- **A reply image is a PNG.** It is published as `Agent reply <id>.png`, and Copy puts a file's
  bytes on the pasteboard as PNG.
  - The command converts any image ImageIO reads (`Thumbnailer.png(from:)`), and checks the
    64 MB limit before and after.
  - The app refuses a reply image that is not a PNG (`bad-payload`), which only a helper from
    before this change could send.
- **Exit 1 means this run sent nothing.** After `--retry`, the first attempt may still have
  arrived, and the skill says not to send a new reply then either. A retry of a request the user
  cleared says so. The shell's own 126 and 127 become a JSON error with exit 1. The retry line the
  command prints names the ticket by its absolute path.
- **The skill's `add` example encodes the path with `osascript`.** JavaScript's
  `encodeURIComponent` ships with every macOS. The example also stops assigning `path`, which zsh
  ties to `PATH`: the old example left `open` unfindable in zsh.
- **The skill goes to version 5.** A launch replaces an older installed copy, so the Python
  helper leaves every agent directory the app manages. Version 4 was the first version of this
  change and never shipped, but builds of it installed it on this Mac.

## What stays

- `ReplyProtocol.version` stays 1. Nothing in the envelope, the bundle, the digest or the receipt
  changes, so an older Python helper still answers a new app's requests. Tickets written with the
  first version's `executable` field still read; the field is ignored.
- The app's side is unchanged except for the PNG rule: acceptance, publication and every other
  refusal.

## Choices

- **A mode of the app's own binary, not a separate helper target.** A second executable in the
  bundle needs its own target, signing and notarization. The app binary is already signed and
  already knows the protocol.
- **The path encoding for `add` stays in the skill.** An agent pushing an image has no ticket, so
  it has no path to the app's binary. `osascript` needs none.

## Checks

- Unit tests, in `ScreenshotRequestsTests`:
  - A reply the command prepares is accepted, and a retry of the same bundle makes no second card.
  - A JPEG the command sends with an empty marks list arrives as a PNG and is accepted.
  - A reply image that is not a PNG is refused.
- The script, against a scratch HOME and fake app bundles: every placement and naming check, the
  capability key, a missing or unrunnable binary, exit codes passed through, and runs under sh,
  bash, zsh and python3.
- The command, run from the built binary with `open` blocked: each new refusal and the retry line.
- Live, on the demo copy: a request stored by Send, answered through `scripts/reply`.

## Results (2026-09-26)

- All 410 unit tests pass.
- The script took the ticket the command takes in every argument order tried, refused tickets
  outside the requests folder, under another bundle id, in a folder not named by the request, with
  a `..` request id, linked, or not named `ticket.json`. It refused an app without the key, and a
  binary that was missing, not executable, or could not run, each with one JSON line and exit 1.
- Live, on the demo copy, with a ticket that has no `executable` field:
  - A reply with two marks, one a text holding quotation marks: accepted, and the card arrived
    with both.
  - `--retry` of the same bundle: accepted, `already published`, no second card.
  - A JPEG with `[]` as marks: accepted, published as a PNG.
  - `python3 scripts/reply`, as version 3 of the skill runs it: accepted.
  - After the request was cleared, `--retry` said the user cleared it (exit 1), and a new reply was
    refused `request-closed` (exit 2).
- Under Codex's `:workspace` and `:read-only` sandboxes, `osascript` and the app binary both run.
  Writes to `~/Library` are refused, so a sandboxed Codex cannot reply, as with the Python helper.
- The skill's `add` example, run in bash and zsh on names holding spaces, `é`, `&`, `%`, `+`, `#`,
  `?`, `;`, `=`, a tab, an emoji, quotes and parentheses, round-trips through the app's decoding.
