# The line Send puts in a session (2026-09-25)

Send now puts this line in the session, with the image's path in place of `<folder>`:

```text
From Vignette: "<folder>/image.png". If a drawing would answer better than words, you can send one back.
```

The skill carries the rest. That is Pete's wording, from 2026-09-25: "I feel like the skill should
take care of the rest; it seems safe to assume that even if we provide the python3 command, the
agent is going to look up Vignette and its skill anyway to understand it."

## Who reads it

- **The agent.** It opens the image and acts on the marks. Now and then a drawing answers better
  than words, and then it needs the reply helper and the ticket.
- **The person.** The line arrives as their own message. Claude Code shows it in the transcript,
  and the Codex app shows it as the person's bubble.

## What was wrong with the old line

Pete's send at 09:08, to a Codex thread, was 734 characters:

```text
Vignette request 3f0de335-c8a7-4295-a966-1ed61c9252b8: open the drawing at "/Users/petepetrash/Library/Application Support/com.petepetrash.vignette/requests/3f0de335-…/image.png" and do what it asks. To answer with a drawing of your own, run: python3 "/Users/petepetrash/Code/vignette/build/…/scripts/reply" --ticket "…/ticket.json" --marks <marks.json>; python3 "/Users/petepetrash/Code/vignette/build/…/scripts/reply" --help explains the mark format and what it answers.
```

- **It opened with a request id,** which neither reader needs.
- **Most of it was paths.** 492 of the 734 characters were the image, the ticket and the helper,
  and the helper's path appeared twice.
- **Replying with a drawing took up half the line,** though it is the rare case.

## What moved to the skill

- **When to load it.** The skill's description now says to use it when a message contains
  "From Vignette:". Before, it covered only showing the user an image.
- **Where the ticket is.** `ticket.json` is in the image's folder. A test holds that.
- **Where the helper is.** The skill's own `scripts/reply`. A launch rewrites an installed copy
  whose version is older than the bundle's, so the helper stays current.
- **Which app to answer.** A fork answers to its own URL scheme, which the old line passed as
  `--scheme`. The helper now reads it from the Info.plist of the app the ticket names.

The cost: an agent without the skill can read the drawing, but cannot answer with one.

## A message with the drawing (2026-09-26)

The bar has a message field beside Send and Reply. What the person types there leads the line, and
the Vignette part follows in brackets:

```text
Make this button bigger [From Vignette: "<folder>/image.png". If a drawing would answer better than words, you can send one back.]
```

- **The message first.** The first build put it at the end, after "send one back.", so the line
  still started "From Vignette:". Pete found that haphazard: the ask read as an afterthought
  tacked onto an instruction. First, it is the request, as a message typed in the session would
  be, and the person sees their own words first in the transcript.
- **The rest in brackets,** so it reads as a note on what came with the message rather than a
  second request. The skill's description looks for "From Vignette:" anywhere in a message, so
  it still loads.
- **Without a message, the line is as before.**
- **One line.** Line breaks and tabs from a paste or Option+Return become single spaces
  (`AnnotatorToolbar.Model.sentMessage`), because herdr submits the line with Return.
- **Not stored.** The message travels in the line only. The request's record and the log leave it
  out, as they leave out a text mark's words.

## The sentence is the person's to change (2026-09-26)

`sendInstructions` in settings.json holds the sentence after the image, with today's as its default:

```json
"sendInstructions": "If a drawing would answer better than words, you can send one back."
```

- **Only the sentence.** `From Vignette: "<path>".` stays fixed: the skill loads on
  "From Vignette:", and the path is the drawing. An edit that broke either would leave an agent
  unable to find the image, with nothing saying why. The skill tells agents to know the line by
  those two, not the sentence.
- **One line.** A line break or a tab becomes a space, and the sentence is capped at a text mark's
  length, 2,000 characters. Settings logs the correction.
- **Empty is allowed.** The line is then `From Vignette: "<path>".`, with the message before it as
  usual.
- **No control in the window.** It is for someone tuning what their agent reads, which the file
  serves, and the Agents tab stays about the agents.

## Unchanged

- One line, because herdr submits it with Return.
- The ticket's secret never travels in the line, because `[url]` logs every URL.
- The reply protocol. Nothing in the ticket or the envelope changed, so `ReplyProtocol.version`
  stays 1.
