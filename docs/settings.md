# Settings

`~/.config/vignette/settings.json` is the source of truth. The Settings window (menu bar → Settings…,
or `open -g vignette://settings`) edits it; so can you or your agent. The app reloads it within a
second of a save. `VIGNETTE_SETTINGS=<path>` in the environment points a launch at another file,
which is how tests and agents keep away from the real one.

```json
{
  "screenshotsFolder": "~/Dropbox/Screenshots",
  "syncAppleSaveLocation": true,
  "appleThumbnail": false,
  "windowShadow": false,
  "format": "png",
  "recentCount": 30,
  "recentHotkey": "cmd+shift+6",
  "hideMenuBarIcon": false,
  "launchAtLogin": false,
  "quickAnnotate": false,
  "annotateOnCapture": false,
  "copyOnCapture": true,
  "debug": false,
  "agentSkill": "unasked",
  "ui": { "cardMaxWidth": 208, "slideInDuration": 0.75, "backdropBlurRadius": 13, "...": "the design numbers" },
  "appleOriginal": { "location": "~/Desktop", "showThumbnail": true, "disableShadow": false, "type": "png" }
}
```

The folder is one setting for two things: where Cmd+Shift+3/4/5 saves and what Vignette watches.
`appleThumbnail`, `windowShadow`, and `format` are Apple's own screenshot defaults; Vignette writes
them for you. On first run the file mirrors what macOS is already doing, so nothing changes until
you edit it; `appleOriginal` records those first values, and `restore-apple-defaults` puts them
back. `launchAtLogin` adds Vignette to your login items. `quickAnnotate` is Quick draw: Done
copies the image you drew on and closes the annotator and the stack at once, instead of returning
to the stack. `copyOnCapture` puts every new screenshot on the clipboard as it lands (the image,
plus its file URL and path for apps that take those), and is on by default. `annotateOnCapture` is
Draw on New Captures: it opens every new screenshot in the annotator right away, instead of showing
a thumbnail. The menu bar toggles both.
An image that arrives through `add` skips both: a push from an agent is not a capture.
`agentSkill` is the skill for coding agents: `unasked`, `on`, or `off` (see [agents.md](agents.md)).
`debug` unlocks `eval`, `show-editor`,
`tweaks`, `send`, and `file=` outside the watch folder. A file that does not parse is moved aside as
`settings.json.invalid` and replaced with defaults, with a toast saying so.

The `ui` section holds the design numbers: card sizes, corners, shadows, hover buttons, animation
durations and curves, how far a card bows and swells on its way to the annotator, how narrow the
stack goes to make room for it and how far it stays from it, how deep the drag-select's edge band is
and how fast it scrolls there, how near an edge of the image a zoom holds that edge, backdrop blur
and tint, annotator window limits. The defaults are the
tuned UI, so a fresh install looks the same. A key the app does not know is ignored and the number
it names takes its default, so a renamed key leaves a dead line you can delete: `zoomEdgeBand`, a
fraction of the picture, is now `zoomEdgeBandPoints`, in points. With `debug` on, menu bar → Tweak UI… (or `open -g
vignette://tweaks`) opens a floating panel of sliders that edits them live, with buttons to summon
the thumbnail, stack, toast, and annotator while you tweak. `"ui": {"motion": 0}` turns every
animation off; the system's Reduce Motion does the same.
