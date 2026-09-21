<p align="center">
  <img src="docs/logotype.svg" width="220" alt="Vignette">
  <br>
  for macOS
</p>

What if macOS's built-in screenshot tool had continued to evolve after 2010? That's the idea
behind Vignette.

## See it

https://github.com/user-attachments/assets/cb06c65f-ba08-436f-8e7e-4df31729ad36

## What it does

- **The same shortcuts.** Cmd+Shift+3, 4, and 5 still take the screenshot. A preview thumbnail
  appears in the bottom right corner, just like it used to, with Copy, Draw, and Delete on hover.
- **Screenshot history, one key away.** Use the Vignette shortcut (double-tap `Shift`, by default)
  and your recent screenshots slide in from the right. A camera roll for your screenshots. Arrows
  move, Space selects, Return opens.
- **Non-destructive.** A drawing is saved beside the original and stays editable. Go back,
  change it, undo it. The original is never touched.
- **Queue.** Annotate several at once. Open them and they come one after another. Each Done
  opens the next.
- **One-click stitch.** Several screenshots into one image, auto-numbered.
- **No colour picker.** The colour is chosen from the image for the highest contrast.
- **Three tools.** Rectangle, text, arrow.
- **Copies on capture.** Every screenshot lands on the clipboard.
- **Native, refined feel.** Draw without leaving what you were doing. The stack takes keys
  without stealing focus from your app. Hold the hotkey and the newest shot lifts into the editor.
- **Agent-friendly.** Experimental. Two-way: a coding agent can send you annotations, and you can
  send it yours. A skill for Claude Code and Codex ships with the app.
- **Customizable and hackable.** A settings file, every action as a URL, MIT licensed.

## Get it

There is no download yet. The editor is tldraw, and shipping a build needs a license key.
Until then, build it yourself:

```
git clone https://github.com/petekp/vignette.git
cd vignette/web && pnpm install && cd ..
./scripts/run.sh
```

That needs Xcode, `xcodegen`, and `pnpm`. [docs/building.md](docs/building.md) has the details,
and its Signing section says why a build of your own has to be re-trusted for Accessibility
after each rebuild. macOS 14 or later.

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

`AGENTS.md` is the working loop for a person or agent changing the app. The dated notes in
`docs/` are measurements and reasoning behind particular changes, not guides.

Vignette is MIT licensed. The editor is tldraw, under [its own license](LICENSE-tldraw.md).
