# Release prep, 2026-09-27

Pete asked for four things before the first public release, in this order:

1. Fix six bugs he found.
2. Test the plugin as a first-time user would meet it: setup, the plugin install, and use.
3. Record a new promo video that shows what Vignette can do.
4. Put the video on GitHub and the landing page, and review both for accuracy and consistency.

## 1. Bugs

| Bug | Cause | Fix |
|---|---|---|
| The toolbar's target jumps and overlaps when the session changes | A pick from the target menu ran inside the menu's own event loop, so the name's new width landed without the bar's spring while the controls beside it moved on it. Long project names had no limit. | The name's width is set, so it springs with the bar. The pick is applied a turn later on the bar's spring. Names are cut in the middle past 132 pt. |
| Esc does not close the editor | A quick click on the message field lost its release to a SwiftUI gesture on the field, and the text field waited for it with every event queued behind, Esc included, until the next click. | The gesture is off the field's text. The padding's gesture stays behind it. An Esc that reaches the window unhandled also closes, and logs what held the keys. |
| The focus goes back to the newest card after the editor | `takeKeys` focused the hovered or newest card. | The card coming back from the editor takes the focus. |
| The focus ring and circle switch on at once | No animation on either. | The ring grows out of the resting border and the circle fades, on 0.2 s springs. |
| Stitch is disabled with several cards selected | A recording in the selection disables Stitch, and its reason shows only on hover. Recordings are mixed in with screenshots in Pete's folder. | Open question for Pete, below. |
| Draw lags behind the strip's other rows | Draw and Open share a row and were two identities, so the row faded out where it had been while its twin faded in. The button style's springs also covered the whole label. | One identity per row. The springs reach only the fill and the scale. |

Open question: should Stitch take a recording's first frame, or should the strip say why Stitch is off without a hover?

## 2. First-time install test

A Release test copy with its own bundle id and URL scheme, on a scratch home with no settings file,
so setup runs from the start. Claude Code is the trailer's signed-in config, with its plugins and
settings backed up first. The steps:

- Setup from the first page to the agent page, both agents switched on, Done.
- The plugin installs into the scratch roots, and each agent lists it enabled.
- A new Claude Code session starts its monitor and inbox, and shows up in Send's menu.
- A drawing sent from the editor arrives as one event, and Claude acts on it.
- Claude's reply comes back as a card, and Reply from that card reaches the session.
- The Agents tab shows the plugin on, and turning it off removes it.
- Closing the session removes it from the menu.

The test copy's skill is patched to its own scheme and log, since the shipped skill always names
`vignette://`. A fork has the same problem: see Findings.

### Results (2026-09-27, Claude Code 2.1.283)

Every step passed.

| Step | What happened |
|---|---|
| Setup | Welcome, shortcut and agents pages in order. Both agents' switches start on, with the read rule. |
| Install | Done installed `vignette@vignette-plugintest` into both agents in about a second. Each agent's own `plugin list` shows it enabled. |
| New session | The monitor and inbox were up within seconds of `claude` starting. The footer says "1 monitor". Send picked the session by itself. |
| Send | A box, a note and a message arrived as one "Drawing from Vignette" event. Claude read the drawing and made the change. |
| Reply with a drawing | Asked for a sketch, Claude sent three marks back in about 20 s. The card's bar offered Reply. |
| Reply | Reply with a message reached the same session, and Claude acted on it. |
| Show an image | Asked through Send, Claude rendered the page and pushed it with `add` in about 8 s. |
| Agents tab | Both on. Codex off removed it, and on installed it again, each in about a second. |
| Closing the session | Its monitor stopped and its inbox was removed. The editor then offered Copy alone. |

What a first-time user will run into:

- **Claude Code's auto mode asks once before the first drawing.** "Read outside the working
  directories" comes up on the first read outside the project, and the drawing waits for the
  answer. Vignette's read rule does not prevent it: it came up with a rule matching the exact path.
  Users not in auto mode are not asked this. It needs a line in the docs.
- **The command line tools are looked for in fixed places.** Claude Code is found only in
  `~/.local/bin`, `~/.claude/local`, `/opt/homebrew/bin` and `/usr/local/bin`. An install through npm
  under nvm, Volta or Bun is elsewhere, and the switch says only "Needs the claude command, which
  Vignette can't find." Codex's list is similar.
- **Sessions already open when setup finishes get nothing until `/reload-plugins`.** The Agents tab
  says so after an install. Setup's last page does not.
- **M after drawing a box types an "m" into the box's note.** A character right after a box starts
  its note, so the message field's M shortcut, which its tooltip names, does not reach the field
  then.
- **Copy on capture is on for a new install,** so the first capture replaces the clipboard. That is
  the setting's purpose. It's listed here because a tester will notice it.

## 3. Promo video

Done 2026-09-28. The trailer now runs on the plugin, with no herdr: the stage copy installs its own
plugin into the trailer's Claude Code config, Ghostty runs `claude` directly, and the take waits on
the inbox's `turn` file. A dry run and three takes passed every beat, and that 38 s cut went on the pages.
Pete's review then found the camera too tight and quick, and Claude's sketch unconnected to his
request. `docs/trailer-v2-2026-09-28.md` is the second version, with a new story: Claude finds that
the water tower you asked for blocks the cat's jump. Its cut, 47.7 s, replaces the first on the
pages.

Changes from the first cut, each from a problem seen in a take:

| Problem | Change |
|---|---|
| "You've used 83% of your weekly limit" in yellow over the terminal's input at the start | The take starts 20 s after Claude Code does. The notice was gone within 15 s. |
| "Image in clipboard · ctrl+v to paste" in Claude Code's footer, and the take replaced your clipboard | Copy on capture is off in the stage copy's settings. |
| Claude Code's tips under its spinner | `spinnerTipsEnabled: false` in the trailer's config. |
| The first Send landed off camera: a new session writes from the top of the terminal, and the camera framed the bottom | The Send beat frames the terminal's top half and holds until Claude reads the drawing. |
| The poster caught a caption mid-change, an empty pill | The poster is the three marks done, with "Mark it up". |

Claude Code's "Share Claude Code and earn $10 in usage credits" line shows in its header in the
first seconds. It is small and not settable.

## 4. GitHub and the landing page

Done locally 2026-09-28, not pushed.

- **`site/index.html`:** the trailer replaces the still, autoplaying and looping, muted. With
  Reduce Motion on it waits for play. The caption says Claude's working time is cut.
- **Send without herdr:** the site, the README, `docs/using.md`, `docs/settings.md` and
  `docs/agents.md` said Claude Code needs herdr. They now say the plugin reaches it in any terminal.
- **Plugin, not skill:** the agent card, the README's agent section and setup step, and
  `docs/agents.md`, which is rewritten around the plugin, its install commands, the inbox, and
  auto mode's one-time read prompt.
- **The updater:** a line on the site and in the README. It checks once a day and installs only
  when you choose Install.
- **The README** leads its Tour with the trailer's poster, linked to the site, since GitHub plays
  only videos uploaded through its web editor.

Checked in Chrome at 1440 and 390 px: the video plays and nothing scrolls sideways.

**Push with the release that has the plugin, not before.** The Download button gets 0.1.1, which
has no plugin and sends to Claude Code only through herdr. Pushing `main` deploys the site.

## Findings

- The staged skill names `vignette://`, `Vignette.log` and `~/.config/vignette` whatever the app's
  identity, so a fork's agents drive the wrong app. `AgentPlugin.stage` could rewrite the three.
- The tool lookup could fall back to the login shell's `PATH`: run `$SHELL -lc 'command -v claude'`
  once, off the main thread, with a timeout, when no fixed path has the tool. And the switch could
  name the paths it tried, as Codex's error line already does.
- Setup's last page could say that sessions already open need `/reload-plugins`, as the Agents
  tab does.
