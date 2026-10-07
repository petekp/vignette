<p align="center">
  <a href="https://vignette.pete.design"><img src="docs/app-icon.png" width="128" alt=""></a>
  <br>
  <a href="https://vignette.pete.design"><img src="docs/logotype.svg" width="150" alt="Vignette"></a>
</p>

<h1 align="center">Show, don’t prompt.</h1>

Vignette works like the Mac’s screenshot tool, with quicker drawing and a Send button for Claude
Code and Codex. Your agent can draw on a screenshot and send it back, too.

**[Download Vignette](https://github.com/petekp/vignette/releases/latest)**. It’s free and open
source, for macOS 14 or later. You can try it in your browser at
[vignette.pete.design](https://vignette.pete.design).

https://github.com/user-attachments/assets/eb7e5cee-5110-4d25-9c72-121783a37048

## What it does

### Recent screenshots

Keep taking screenshots with Cmd+Shift+3, 4 or 5. Vignette takes over what happens after. Each new
screenshot goes on your clipboard as soon as it’s saved, and a thumbnail shows up in the corner, as
it does with macOS. Hover it to copy or delete it, or click it to draw on it.

When you need one from a few minutes ago, double-tap right Shift. Your recent screenshots slide in
from the right edge of the screen as a stack of cards, newest at the bottom, so you don’t have to
dig through a folder for them. Arrow keys move between cards and Return opens one. The app you were
using stays in front, and when you close the stack you’re right back where you were.

Select a few cards to copy, stitch, drag or delete them together. Hold the second tap of the
shortcut and the newest screenshot opens in the editor.

### Drawing

Click a card to draw on it. There’s a box, an arrow and a text note, and that’s it. Draw a box or an
arrow and start typing, and the note goes right next to it. Arrows follow your hand, so they can
curve around what’s in the way. A stroke that’s nearly straight comes out straight.

There’s no colour picker. Your marks are red and your agent’s are indigo, so you can tell who drew
what. A thin white edge keeps every mark readable on dark and light screenshots.

Your drawing is saved apart from the screenshot. The original file never changes, and you can come
back later to move, change or delete any mark.

To draw on several screenshots in a row, select their cards and press Return. Copy or send one and
the next one opens.

### Sending to Claude Code and Codex

Draw on a screenshot, type a message if you want, and press Send. It goes to the Claude Code or
Codex session you were just in. Click the session’s name in the toolbar to pick another.

Your agent can send you screenshots too, with its own marks on them. You can change its marks like
your own, and Reply sends your drawing straight back to that session.

This works through the Vignette plugin, which comes with the app. Setup offers to install it, and
the Agents tab in Settings adds or removes it.

- Claude Code gets your drawings through the plugin, in any terminal. A session that was already
  open when you installed the plugin needs `/reload-plugins` first.
- Codex needs the Codex app or its command-line tool.

### A few more things

- **Stitch** joins the cards you selected into one image and numbers each piece. Claude shrinks
  large images before reading them, so Stitch picks the layout that keeps the most detail.
- **Drag a card** into Claude Code, a chat or Finder. If you drew on it, the image you drop has your
  drawing on it.
- **Screen recordings** from Cmd+Shift+5 show up as cards with their length. Click one to play it.
- **Instant Draw**, in the menu bar menu, opens each new screenshot in the editor right away. It
  flies in from the part of the screen you captured.
- **Cards fly** into the editor and back. Change your mind halfway and a card turns around in
  mid-air.
- **Scripts and settings.** Every action is a `vignette://` URL, which is how your agent shows you
  screenshots. Settings live in a JSON file you can edit. The source is MIT licensed.

## Get it

Download Vignette from the [latest release](https://github.com/petekp/vignette/releases/latest).
Open the disk image and drag Vignette to Applications. Apple has notarized the app.

The first launch opens a short setup:

- If macOS saves your screenshots to the Desktop, Documents or Downloads, allow Vignette to read
  that folder. macOS asks once.
- Pick the shortcut. The double tap needs Accessibility permission. A key combination needs none.
- If Claude Code or Codex is installed, choose whether to add the Vignette plugin.

While Vignette runs, it turns off macOS’s floating thumbnail and shows its own. Quitting Vignette
turns macOS’s thumbnail back on.

Vignette checks for updates once a day. It installs one only when you choose Install.

To report a problem, choose Report a Problem… in the menu bar menu. It opens a GitHub issue with
your version and Mac filled in, and shows Vignette’s log in Finder so you can attach it.

### Build it yourself

```
git clone https://github.com/petekp/vignette.git
cd vignette
./scripts/run.sh
```

You need Xcode 26 or later and `xcodegen`. [docs/building.md](docs/building.md) has the details,
including why macOS asks you to re-trust your own build for Accessibility after each rebuild, and
how a signing certificate avoids it.

## Guides

- [Using Vignette](docs/using.md): after a screenshot, the recent stack, the annotator, Send and
  Reply, the shortcut.
- [The drawing editor](docs/editor.md): the tools, the keys, the clipboard, the drawing file.
- [Commands](docs/commands.md): every action as a `vignette://` URL, the marks format, the log.
- [Settings](docs/settings.md): `settings.json`, the `ui` numbers, the tweaks panel.
- [Building](docs/building.md): build, sign, where things live, forking.
- [For agents](docs/agents.md): the plugin that ships with the app, the skill it carries, and how
  it is installed.

`AGENTS.md` is the onboarding for anyone changing the app, person or agent. The dated notes in
`docs/` record the measurements and reasoning behind particular changes.

Vignette is MIT licensed.
