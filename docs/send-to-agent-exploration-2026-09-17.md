# Send to an agent: an exploration

A button that hands the screenshot you just marked up to the coding agent you are working with,
instead of copy, switch window, Ctrl+V, type. The hard part is not the sending. It is knowing
which agent, and delivering to *that* one rather than to whatever window happens to be in front.
Everything below was checked on this Mac on the night of 2026-09-16; the prototype at the end is
built and behind `debug`.

## What a send has to answer

1. **Which agent.** A running Claude Code or Codex is a process inside a terminal pane. Nothing
   about it is visible to another app: no port, no document, no window title that means anything.
2. **How the image gets in.** A pty carries bytes, not pictures. So the image travels either as a
   path the agent opens itself, or through the system pasteboard, or through an API of the agent's
   own.
3. **What happened.** A send that silently lands nowhere is worse than no send.

## herdr: the one that answers all three

herdr (0.8.2, running here as `HERDR_ENV=1`, socket `~/.config/herdr/herdr.sock`) is Pete's
terminal multiplexer for coding agents. It already knows which panes hold an agent.

**Detection is a list, not a guess.** `herdr agent list` answered with 17 live agents while this
was written. Per agent it gives the kind (`claude`, `codex`, … 22 kinds are recognized),
`agent_status` (`idle`, `working`, `blocked`, `unknown`), `cwd`, `pane_id`, `tab_id`,
`terminal_title`, the agent's own session id, and `focused` — the pane the herdr UI last had in
front, which is the natural default target.

**Delivery targets a pane, not a window.** `herdr agent prompt <target> <text>` writes the text and
Return to that pane atomically, wrapping in bracketed paste when the pane app asked for it
(`src/app/api_helpers.rs`). No focus changes, no synthetic keyboard, no Accessibility.

**The CLI works from an app.** Shotnote is launched by LaunchServices and inherits no shell PATH.
Verified: `env -i HOME=… PATH=/usr/bin:/bin ~/.local/bin/herdr agent list` exits 0 with the full
list, so shelling out to an absolute path is enough.

**Verified end to end.** A throwaway pane, a throwaway Claude Code, and the exact line Shotnote
would send:

```
$ herdr agent prompt sendprobe "Screenshot: /…/send-scratch/shots/probe-fixture.png - look at it
  and reply with one line: the code word plus the three square colours left to right." --wait
```

The pane showed `Read 1 file` and then `PELICAN-7391 teal magenta orange` — the code word and the
colours that exist only in that PNG's pixels. The image reached the model.

**A busy agent does not lose it.** Two prompts sent back to back while the first turn was still
running both landed, in order: the pane answered `FIRST DONE`, then read the image and answered
`PELICAN-7391`. So a send never has to wait for the agent to be free.

**What herdr cannot do:** there is no image in its socket API. `herdr api schema` has
`pane.send_text`, `pane.send_keys`, `agent.prompt`, and `pane.graphics.set` (kitty graphics, for
drawing an image *in* a pane). So the image still travels as a path or through the pasteboard.

### The path is free, until it is not

Both agents open a local image on their own: Claude Code's `Read` renders images, and Codex ships a
`view_image` tool. The cost is one tool call, and one rule: **the agent must already be allowed to
read that path.**

Verified both ways in one session. A path inside the session's working directory was read with no
prompt. The same file at `/private/tmp/…` produced:

```
 Read file
   Read(/private/tmp/shotnote-send-probe.png)
 Do you want to proceed?
 ❯ 1. Yes   2. Yes, allow reading from /private/tmp during this session   3. No
```

herdr reported that agent as `blocked`, so the stall is detectable. On this Mac the question is
mostly moot: `~/.claude/settings.json` lists `permissions.additionalDirectories` =
`~/Dropbox/Screenshots`, `~/.claude/skills`, `~/Code`, with `defaultMode: auto`. Every Claude Code
session here may already read the screenshots folder. A fresh machine would not, and that is worth
saying out loud in any UI.

### The pasteboard variant, also verified

Both agents read the system pasteboard themselves when they see Ctrl+V:

- Claude Code shells out to `osascript -e 'set png_data to (the clipboard as «class PNGf»)'` and
  writes `claude_cli_latest_screenshot.png` (strings in the 2.1.274 binary).
- Codex says so in its own UI: "Ctrl+V to attach it to your next message."; its `paste.rs` has
  `get_image` / `encode_image` and the error "no image on clipboard".

So the only thing that must arrive at the pane is byte 0x16. herdr delivers it: a pane running
`cat` in raw mode captured `look at /Users/x/Screenshot test.png` followed by `0x16` after
`herdr pane send-text` and `herdr pane send-keys ctrl+v`. (herdr passes raw Ctrl+V through to local
panes on purpose; `keys.remote_image_paste` only applies to `herdr --remote`.) In the live Claude
Code session, the image on the pasteboard plus a sent Ctrl+V produced `[Image #1]` in the composer,
and the answer `PELICAN-7391` with no `Read` call at all.

This variant costs no tool call and no permission, and works for a file the agent may not read. It
pays for that with the pasteboard: it is global, Pete may copy something else a second later, and
two sends in flight race each other. The send also becomes three steps (text, Ctrl+V, Return) with
a wait in the middle for the agent's own clipboard read to finish.

## Claude Code's cross-session inbox

Every Claude Code process listens on a unix socket. This session's environment has
`CLAUDE_CODE_MESSAGING_SOCKET=/tmp/cc-socks/<pid>.sock` and `CLAUDE_CODE_MESSAGING_TOKEN=…`; 27
sockets were live in `/tmp/cc-socks`. The binary documents its own protocol in a log line:

```
[uds-messaging] Inject messages (auth line REQUIRED here):
{ echo '{"type":"auth","token":"'"$CLAUDE_CODE_MESSAGING_TOKEN"'"}';
  echo '{"type":"user","message":{"role":"user","content":"hello"}}'; } | socat - UNIX-CONNECT:<socket>
```

A registry at `~/.claude/sessions/` holds one `<pid>.json` per session next to a `0600`
`<pid>.<hash>.key`, so a peer can find the socket and its key without reading another process's
environment. (I listed those files; I did not read them.) `crossSessionInbound` is `"accept"` in
Pete's settings, and the code has states for a message being `held` for the recipient's approval,
`denied`, or `expired`.

This is the most direct route that exists — a message straight into the conversation, no keystrokes
— and it is the one I would not build on. It is undocumented plumbing for Claude-to-Claude
messaging, it can change in any release, it is Claude Code only, and whether `content` accepts an
image block is unverified. A wrong guess here fails silently.

`claude --help` has nothing else local that reaches a *running* session: `--bg`, `attach`, `logs`,
`stop`, `rm`, `agents --json` manage background sessions, and `-p` or `--resume <id> "prompt"`
starts a new process with its own turn. `--remote-control` does reach one, but through claude.ai
(Pete has `remoteControlAtStartup: true`), which is a phone talking to a session, not an app on the
same Mac.

## Codex's app-server

Codex (codex-cli 0.154.0) has the API the others lack:

- `codex queue --thread <uuid|name> --message <text> -i <FILE>…` — "Queue a message for an existing
  session". It takes `-i`, though the flag's help text is the shared one about an initial prompt, so
  whether `queue` honors it is part of what is unverified below.
- The protocol behind it (dumped with `codex app-server generate-json-schema`) has a `UserInput`
  union with `{"type":"localImage","path":"…"}` and `{"type":"image","url":"…"}`, a
  `turn/start` that takes `input: UserInput[]`, a `turn/steer` that pushes input into the turn
  already running, and `thread/injectItems` for raw history.
- `codex -i/--image` does the same for a new session.

The catch is the transport. All of it goes through the shared local app-server daemon, and on this
Mac that daemon was not running: `codex app-server daemon version` failed with
`failed to connect to ~/.codex/app-server-control/app-server-control.sock (No such file or
directory)`, and no Codex session was live to start one. So the Codex API is real and typed, but
whether a plain `codex` TUI in a pane is reachable by `codex queue` is **unverified here**. Until
it is, the herdr route covers Codex the same way it covers Claude Code, through `view_image` —
inferred from the tool and its error strings in the binary, not run live here, because no Codex
session was up and starting one in a scratch directory needs a trust entry in Pete's
`~/.codex/config.toml`.

## The desktop apps

Neither desktop app takes an attachment through its URL scheme.

- Claude.app 2.110.0 registers `claude://`. Its routes are `claude://claude.ai/new?surface=chat`,
  `claude://code/new`, `claude://code/continue?session=last`, `claude://code/needs-input`,
  `claude://resume`, `claude://cowork/shared-artifact?uuid=…`. Its document types are `.dxt`,
  `.mcpb`, `.skill`, and folders — no image.
- The Codex desktop app ships inside ChatGPT.app, which registers `codex://`:
  `codex://threads/new`, `codex://threads/<id>`, `codex://review?pr=…&path=…&line=…`,
  `codex://launch`, `codex://space`. No attachment parameter either.

They open a window. They cannot hand it a picture, and they are not where the work is happening.

## The last resort: Accessibility

Put the PNG on the pasteboard, then post Ctrl+V with CGEvent, the way `scripts/input.swift`
already posts clicks and hotkeys. It needs no herdr. It is also the least trustworthy thing in this
document:

- It goes to whatever is frontmost. At the moment of a send, that is Shotnote's own annotator, so
  the app would have to activate the terminal first and wait for it to come up.
- "The terminal" is not enough. The keystroke lands in the focused split, which may be a different
  pane than the one Pete means.
- Over SSH the remote agent cannot see the local pasteboard, so the paste produces nothing.
- Trust is granted per app and can be revoked; a revoked grant drops events silently.
- Nothing reports what happened.

Every one of those failures is invisible to the user until they look. Use it only if herdr is
absent and Pete asks for it anyway.

## What the image costs

Anthropic bills an image at roughly `width × height / 750` tokens, after a downscale to 1568 px on
the long edge. Claude Code carries the same number: each model entry in the binary has
`image_limits: {max_width: 1568, max_height: 1568}`, and it resizes before upload
(`tengu_pasted_image_resize_attempt`).

This display is 3024 × 1964. A full-screen capture therefore lands at 1568 × 1018 ≈ **2,100
tokens**. A crop around the marked region, say 900 × 600, is **720**. Roughly a third, and the
agent's attention goes to the part that was marked instead of the whole desktop.

Shotnote already has what a crop needs. The draft on disk is the tldraw snapshot, one per
screenshot, and it carries every shape's geometry; the page knows the bounding box exactly. The
change is small and mechanical: `park` and `export` return `bounds` in image pixels next to the
PNG, `ParkResult`/`ExportResult` gain the field, and `bridgeProtocolVersion` / `PROTOCOL` go up
together. Then a send can offer "the marks" or "the whole shot".

Not yet worth building. Measure first: a 2,100-token screenshot is a rounding error next to the
context an agent already carries, and cropping away the surroundings can remove the thing that made
the screenshot legible.

## Recommendation

**Send through herdr, with the image as a path.** It is the only route where Shotnote knows which
agent it is talking to, the delivery is aimed at that pane, the failure is reported, and the same
code covers Claude Code, Codex, and the twenty other kinds herdr recognizes. It needs no private
protocol and no Accessibility grant.

Keep the pasteboard variant (Ctrl+V into the same pane) as the option for a file the agent has no
permission to read. Both are verified above; the path is the better default because nothing else
on the machine can change it between the send and the read.

The honest limit: this works when the agent lives in a herdr pane. An agent in a plain terminal tab
has no target, and there is no reliable way to find one — that is exactly the gap herdr fills. When
there is no herdr, Shotnote already does the right thing: Copy puts the image on the pasteboard and
Pete pastes it himself.

## What is built

`shotnote://send` — behind `debug`, one URL command, no UI.

```
open -g "shotnote://send?file=<path>&to=<agent or pane>&text=<words>"
```

- `file=` is the image; without it, the newest screenshot.
- `to=` is a herdr agent name or a pane id; without it, the agent in the focused pane.
- `text=` is the line that goes with the path; without it, `Screenshot:`.
- The line is always one line with the path quoted, because herdr submits it with Return and
  screenshot names have spaces in them.
- It refuses a `blocked` agent, so a send never types into a permission prompt that is waiting for
  a number.
- It answers `[send] ok <target> kind=… pane=… file=…`, or `[send] error no-agent …` /
  `[send] error send-failed …` with herdr's own message.

`Sources/Send.swift` holds the parsing, the target choice, the message, and the subprocess;
`Tests/SendTests.swift` covers the first three against a recorded `herdr agent list`.

Driven against a throwaway agent, the four lines it wrote were:

```
[send] ok sendprobe2 kind=claude pane=w9:pE file=probe-fixture.png
[send] error no-agent no agent "nobody"; herdr has: herdr-config-names(claude) … designer-guide(claude)
[send] error missing-file /…/send-scratch/shots/not-here.png
[send] ok sendprobe2 kind=claude pane=w9:pE file=probe-fixture.png
```

and that pane answered `PELICAN-7391` and then `Magenta` — the code word and the middle square of
the fixture. The last send named no target, so it went to the focused pane.

## How the CTA would sit

The annotator's toolbar (`AnnotatorToolbar.swift`) is a native panel under the window, built from
the tool list the page sends plus Done. A send button belongs next to Done, on the right, because
it is the other way to finish: Done copies, Send hands it over. The same SF Symbol vocabulary
applies (`paperplane`).

Two details decide whether it feels good:

- **The target must be visible before the click.** The button's label should name the agent it will
  hit — "Send to breadcrumbs" — from one `herdr agent list` call when the annotator opens. A
  right-click (or a long press) opens the full list: name, kind, and cwd, which is what tells Pete
  which of seventeen he means.
- **Words are optional.** The screenshot usually says it. Send with no words is one click; a
  modifier-click can open a one-line field first.

After Done there is a second home for it: the toast that confirms the copy could carry "Send to
<agent>" for its few seconds, which costs no toolbar space and catches the moment Pete realizes he
wants it. In the recent stack, the same thing is a `ShotAction` with `placement: .bar`, so a card
can go to an agent without opening the editor.

## Open questions

- Does a send carry the annotated export or the original file? Done writes `<name>-annotated.png`
  next to the original, and the watcher ignores `*-annotated.png`, so the "newest screenshot" is
  never the annotated one. The prototype takes `file=` explicitly.
- Should the send wait? `herdr agent prompt --wait` returns when the agent settles, which would let
  a toast say "answered" or "asked for permission". It also blocks for as long as the agent thinks.
- Should an unnamed agent be sent to at all, or should Shotnote only offer agents Pete has named in
  herdr? Names are what make the target list readable.
- Is the focused pane the right default, or the most recently idle agent?

## The cheapest probes for what is left

- **Codex, both halves** (30 minutes): start a codex TUI in a scratch directory. Send it a path
  with `herdr agent prompt` and check that `view_image` fires — that is the recommended route's
  Codex half. Then read the thread id from `codex agents` and run
  `codex queue --thread <id> --message "what is the code word" -i <fixture.png>`, which settles
  whether Shotnote can hand Codex an image with no keystrokes at all. Both need a directory Codex
  already trusts, or a trust entry in `~/.codex/config.toml`, which is why neither is answered here.
- **The Claude Code inbox with an image block** (15 minutes): against a throwaway session's own
  socket, send `{"type":"user","message":{"role":"user","content":[{"type":"text",…},
  {"type":"image","source":{"type":"base64","media_type":"image/png","data":…}}]}}` and see whether
  the image appears in the transcript. A yes would be the cheapest possible send for Claude Code —
  and still an undocumented one.
