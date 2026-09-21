# Vignette

A macOS screenshot companion you can reshape. Apple's Cmd+Shift+3/4/5 still take the
screenshot. Vignette watches the save folder and handles everything after: a floating
thumbnail, a recent-screenshots stack, and a tldraw annotator that copies the result to
your clipboard.

## See it

https://github.com/user-attachments/assets/cb06c65f-ba08-436f-8e7e-4df31729ad36

One minute, real footage, one take: grab a corner of a page, box the gap and name what goes
there, paste the drawing into Claude Code, and the page changes in place. Then the recent stack,
three shots stitched into one, and a screenshot from Claude landing in the stack with a
question drawn on it, answered with one arrow. The file is in the repo at
[docs/demo/vignette-demo.mp4](docs/demo/vignette-demo.mp4) (59 s, no sound).

## Get it

The source is at [github.com/petekp/vignette](https://github.com/petekp/vignette), MIT licensed.
There is no download yet: the editor is tldraw, whose license requires a key to ship, and the
key waits on the repository being public, which it now is. Until then, build it yourself:

```
git clone https://github.com/petekp/vignette.git
cd vignette/web && pnpm install && cd ..
./scripts/run.sh
```

That needs Xcode, `xcodegen`, and `pnpm`; [docs/building.md](docs/building.md) has the details,
and its Signing section says why a build of your own has to be re-trusted for Accessibility after
each rebuild. macOS 14 or later.

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

- `Sources/` is the Swift shell: menu bar item, folder watcher, panels, clipboard, hotkey, drafts.
- `web/` is the editor page: React + tldraw, built with Vite into `web/dist`, bundled into the app.
- `Sources/LocalServer.swift` serves `web/dist` and the screenshot being annotated on 127.0.0.1,
  behind a per-launch token. tldraw only runs unlicensed on http origins; `file://` and custom
  schemes make it hide the editor after five seconds, and the image has to share the page's
  origin for the export canvas to stay untainted.
- `web/src/bridge.ts` and `Sources/Bridge.swift` are the whole contract between the two sides.
  The page reports a protocol version in `ready`; a stale page is refused with a log line and a
  toast instead of failing quietly.
- Annotations in progress are drafts the app keeps on disk (`~/Library/Application Support/
  com.petepetrash.vignette/drafts/`), so they survive relaunches and a crashed web process.

## Guides

- [Using Vignette](docs/using.md): the recent stack, the annotator, the hotkey.
- [Commands](docs/commands.md): every action as a `vignette://` URL, the marks format, the log.
- [Settings](docs/settings.md): `settings.json`, the `ui` numbers, the tweaks panel.
- [Building](docs/building.md): build, sign, the tldraw license, where things live, forking.
- [For agents](docs/agents.md): the skill that ships with the app and how it is installed.

`AGENTS.md` is the working loop for a person or agent changing the app. The dated notes in
`docs/` are measurements and reasoning behind particular changes, not guides.
