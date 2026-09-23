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
- **`appleThumbnail`** is the value Vignette keeps Apple's floating thumbnail at. The first launch
  turns it off, because Apple's thumbnail holds the file back for about five seconds, and every
  launch puts it back if something else changed it. `restore-apple-defaults` sets it to what macOS
  had before.
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
- **`debug`** unlocks `tweaks`, `install-skill?root=`, and `file=` outside the watch folder.
- **`agentSkill`** records only whether the app has offered the skill for coding agents:
  `unasked` until the offer, then `off`. Whether the skill is installed is read from disk, and the
  Agents tab installs or removes it per agent. An older file holding `on` is read as `off`
  (see [agents.md](agents.md)).
- **`setup`** records whether the first-run setup window has had its turn: `unasked`, then `done`.
  It is written when the window closes, so a launch quit part way through asks again.
- **`ui`** holds the design numbers. See below.
- **`appleOriginal`** records what macOS was doing before Vignette's first launch changed anything.
  `restore-apple-defaults` puts those values back.

## The ui section

The `ui` section holds the design numbers: card sizes, corners, shadows, hover buttons, animation
durations and curves, backdrop blur and tint, the annotator window's limits, and the drawing
editor's sizes. It also holds the
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

### The drawing editor's numbers

These set how the editor feels and how a mark looks. The panel has them in its Editor and Marks
sections, and a change reaches an open editor at once. Sizes are in screen points unless the table
says otherwise, so they look the same at any zoom.

| Key | Default | What it sets |
|---|---|---|
| `dragDistance` | 4 | How far a press travels before it is a drag |
| `hitMargin` | 4 | Added to half a stroke's width to make the band that hits it |
| `cornerHitSize` | 13.5 | A corner handle's hit area, a square centred on the corner |
| `edgeHitSize` | 9 | An edge handle's hit area, a strip along the whole side |
| `smallSide` | 16 | A mark shorter than this on a side keeps its handles' hit areas outside it |
| `handleSize` | 8 | The corner square drawn |
| `dotRadius` | 4 | An arrow dot's drawn radius |
| `dotHitRadius` | 12 | An arrow dot's hit radius, and its halo's |
| `smallestRectangle` | 4 | A new rectangle's shortest side |
| `shortestArrow` | 8 | A new arrow's shortest length |
| `textDragDelay` | 0.15 | Seconds a Text tool press waits before a sideways drag sets a wrap width. `motion` does not change it. |
| `textDragDistance` | 24 | The sideways travel that drag needs |
| `newTextSize` | 24 | A new text's size, in points of the drawing |
| `selectionOutlineWidth` | 3.5 | The selection outline's whole width, light edge included |
| `textWeight` | 500 | From 100 to 900, rounded to the nearest of the system font's nine weights |
| `textLineHeight` | 1.35 | A multiple of the text's size |
| `arrowheadLength` | 4.5 | A multiple of the stroke width |
| `arrowheadWidth` | 4 | A multiple of the stroke width |

`textWeight`, `textLineHeight` and the arrowhead apply wherever marks are drawn: the editor, the
cards, a card in flight, a stitch, a dragged card, and what Done, Send and Copy Drawing render.

## Invalid files

A file that does not parse is moved aside as `settings.json.invalid` and replaced with defaults. A
toast says so.
