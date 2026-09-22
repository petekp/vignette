# Settings

`~/.config/vignette/settings.json` is the source of truth. The Settings window edits it, and so can
you or your agent. Open it from the menu bar under Settings…, or with `open -g vignette://settings`.
It has three tabs, General, Screenshots and Agents, plus Developer when `debug` is on. The app
reloads the file within a second of a save. `VIGNETTE_SETTINGS=<path>` in the environment points a
launch at another file, which is how tests and agents keep away from the real one.

```json
{
  "screenshotsFolder": "~/Dropbox/Screenshots",
  "syncAppleSaveLocation": true,
  "appleThumbnail": false,
  "windowShadow": false,
  "format": "png",
  "recentCount": 30,
  "recentHotkey": "double-rshift",
  "hideMenuBarIcon": false,
  "launchAtLogin": false,
  "quickAnnotate": false,
  "annotateOnCapture": false,
  "copyOnCapture": true,
  "debug": false,
  "agentSkill": "unasked",
  "setup": "unasked",
  "ui": { "cardMaxWidth": 208, "slideInDuration": 0.75, "backdropBlurRadius": 13, "...": "the design numbers" },
  "appleOriginal": { "location": "~/Desktop", "showThumbnail": true, "disableShadow": false, "type": "png" }
}
```

- **`screenshotsFolder`** is one setting for two things: where Cmd+Shift+3/4/5 saves and what
  Vignette watches. Set it to the folder you want your screenshots to live in.
- **`syncAppleSaveLocation`** writes `screenshotsFolder` to Apple's screenshot save location. Turn
  it off to let Apple save somewhere other than the folder Vignette watches.
- **`appleThumbnail`** is Apple's own floating thumbnail after a capture. Vignette writes this
  setting for you, so turn it on if you want Apple's thumbnail back.
- **`windowShadow`** is Apple's drop shadow around a captured window, another Apple default that
  Vignette writes. Turn it off for window shots with no shadow margin.
- **`format`** is the file type Apple saves, such as `"png"`. Vignette writes this one too.
- **`recentCount`** is how many cards the recent stack holds. Raise it to reach further back.
- **`recentHotkey`** opens the recent stack. `"double-rshift"` by default, a double tap of right
  Shift, which needs Accessibility permission. A key combination such as `"cmd+shift+6"` needs none.
  The setup window on first launch is where this is normally chosen.
- **`hideMenuBarIcon`** removes Vignette's menu bar icon. `vignette://settings` still opens the
  Settings window.
- **`launchAtLogin`** adds Vignette to your login items.
- **`quickAnnotate`** changes what Done does. On, it copies the image you drew on and closes the
  annotator and the stack at once, instead of returning you to the stack.
- **`annotateOnCapture`** is Draw on New Screenshots: it opens every new screenshot in the annotator
  right away, instead of showing a thumbnail. The menu bar toggles it.
- **`copyOnCapture`** puts every new screenshot on the clipboard as it lands: the image, plus its
  file URL and path for apps that take those. It is on by default. An image that arrives through
  `add` skips this and Draw on New Screenshots, since a push from an agent is not a capture.
- **`debug`** unlocks `eval`, `show-editor`, `tweaks`, `send`, and `file=` outside the watch folder.
- **`agentSkill`** records only whether the app has offered the skill for coding agents:
  `unasked` until the offer, then `off`. Whether the skill is installed is read from disk, and the
  Agents tab installs or removes it per agent. An older file holding `on` is read as `off`
  (see [agents.md](agents.md)).
- **`setup`** records whether the first-run setup window has had its turn: `unasked`, then `done`.
  It is written when the window closes, so a launch quit part way through asks again.
- **`ui`** holds the design numbers. See below.
- **`appleOriginal`** records what macOS was already doing on first run, so nothing changes until
  you edit the file. `restore-apple-defaults` puts those values back.

## The ui section

The `ui` section holds the design numbers: card sizes, corners, shadows, hover buttons, animation
durations and curves, backdrop blur and tint, and the annotator window's limits. It also holds the
behaviour those numbers drive: how far a card bows and swells on its way to the annotator, how
narrow the stack goes to make room for it and how far it stays from it, how deep the drag-select's
edge band is and how fast it scrolls there, and how near an edge of the image a zoom holds that
edge.

The defaults are the tuned UI, so a fresh install looks the same. A key the app does not know is
ignored, and a key you leave out takes its default, so a line you no longer want is safe to delete.

`"ui": {"motion": 0}` turns every animation off. The system's Reduce Motion does the same.

With `debug` on, Tweak UI… in the Settings window's Developer tab, or `open -g vignette://tweaks`,
opens a floating panel of sliders that edits these live. It has buttons to summon the thumbnail,
stack, toast, and annotator while you tweak.

## Invalid files

A file that does not parse is moved aside as `settings.json.invalid` and replaced with defaults. A
toast says so.
