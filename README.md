<p align="center">
  <img src="docs/logotype.svg" width="150" alt="Vignette">
  <br>
  for macOS
</p>

What if macOS's built-in screenshot tool had continued to evolve after 2010? That's the idea
behind Vignette.

## See it

https://github.com/user-attachments/assets/cb06c65f-ba08-436f-8e7e-4df31729ad36

## What it does

### Capture

- **The same shortcuts**<br>
  Cmd+Shift+3, 4, and 5 still take the screenshot. A preview thumbnail appears in the bottom
  right corner, just like it used to, with Copy, Draw, and Delete on hover.
- **Copies on capture**<br>
  Every screenshot lands on the clipboard.

### Recent screenshots

- **Screenshot history, one key away**<br>
  Use the Vignette shortcut (double-tap `Shift`, by default) and your recent screenshots slide in
  from the right. A camera roll for screenshots. Arrows move, Space selects, Return opens.
- **One-click stitch**<br>
  Join several screenshots into one image. Each piece gets a number.

### Drawing

- **Simple by design**<br>
  Three tools: rectangle, text, arrow. No colour picker. Vignette picks the colour that stands out
  most against the image under your mark.
- **Non-destructive**<br>
  Your drawing is a separate file beside the original. Go back, change it, undo it. The original
  stays as it was.
- **Queue**<br>
  Annotate several in a row. Open them together and each Done opens the next.

### The app

- **Native, refined feel**<br>
  The stack answers your keys without taking focus from the app you're in. Hold the hotkey and
  the newest shot lifts into the editor. Close it and you're back where you were.
- **Customizable and hackable**<br>
  Every setting lives in a file, every action is a URL, and the source is MIT.
- **Agent-friendly**<br>
  Experimental. A coding agent can send you a screenshot with its own marks on it, and you can
  send yours back. The skill for Claude Code and Codex ships with the app.

## Get it

There is no download yet. The editor is tldraw, and shipping a build needs a license key.
Until then, build it yourself:

```
git clone https://github.com/petekp/vignette.git
cd vignette/web && pnpm install && cd ..
./scripts/run.sh
```

You need Xcode, `xcodegen`, `pnpm`, and macOS 14 or later. [docs/building.md](docs/building.md)
has the details, including why macOS asks you to re-trust your own build for Accessibility after
each rebuild.

## How it works

```
Cmd+Shift+4  ──►  ~/Dropbox/Screenshots/Screenshot ….png
                        │
                        ▼  ScreenshotWatcher (DispatchSource on the folder)
                  ThumbnailController  ── bottom-right panel: fresh shot, or recent stack
                        │ Copy / Draw / Delete
                        ▼
                  AnnotationController ── window hosting web/ (tldraw) via LocalServer
                        │ "done" message with PNG
                        ▼
                  Clipboard + "<name>-annotated.png" next to the original
```

`Sources/` is the Swift menu bar app. `web/` is the editor page, React and tldraw, bundled into
the app. [docs/building.md](docs/building.md) has the rest.

## Guides

- [Using Vignette](docs/using.md): the recent stack, the annotator, the hotkey.
- [Commands](docs/commands.md): every action as a `vignette://` URL, the marks format, the log.
- [Settings](docs/settings.md): `settings.json`, the `ui` numbers, the tweaks panel.
- [Building](docs/building.md): build, sign, the tldraw license, where things live, forking.
- [For agents](docs/agents.md): the skill that ships with the app and how it is installed.

`AGENTS.md` is the onboarding for anyone changing the app, person or agent. The dated notes in
`docs/` record the measurements and reasoning behind particular changes.

Vignette is MIT licensed. The editor is tldraw, under [its own license](LICENSE-tldraw.md).
