# Settings

`~/.config/vignette/settings.json` is the source of truth. The Settings window edits it, and so can
you or your agent. Open it from the menu bar under Settings…, or with `open -g vignette://settings`.
It has three tabs, General, Screenshots and Agents, plus Developer when `debug` is on. The app
reloads the file within a second of a save. `VIGNETTE_SETTINGS=<path>` in the environment points a
launch at another file, which is how tests and agents keep away from the real one. That launch also
keeps Apple's screenshot settings in `<bundle id>.screencapture` instead of
`com.apple.screencapture`, so it never moves where your screenshots are saved.

```json
{
  "version": 2,
  "screenshotsFolder": "~/Dropbox/Screenshots",
  "appleThumbnail": false,
  "windowShadow": false,
  "format": "png",
  "recentCount": 30,
  "recentHotkey": "double-rshift",
  "hideMenuBarIcon": false,
  "launchAtLogin": true,
  "quickAnnotate": false,
  "sendInstructions": "If a drawing would answer better than words, you can send one back.",
  "annotateOnCapture": false,
  "copyOnCapture": true,
  "debug": false,
  "agentSkill": "unasked",
  "setup": "unasked",
  "ui": { "cardMaxWidth": 208 },
  "appleOriginal": { "location": "~/Desktop", "showThumbnail": true, "disableShadow": false, "type": "png" }
}
```

- **`version`** is the file's format version, which Vignette writes. A Vignette older than the file
  reads it and never writes to it, so it cannot drop keys it does not know.
- **`screenshotsFolder`** is one setting for two things: where Cmd+Shift+3/4/5 saves and what
  Vignette watches. Vignette follows macOS here: pick a folder in the Options menu of Cmd+Shift+5
  and Vignette watches it at once. Set it here, or with Save to in Settings → Screenshots, and macOS
  saves there.
- **`appleThumbnail`** is the value Vignette keeps Apple's floating thumbnail at while it runs. The
  first launch turns it off, because Apple's thumbnail holds the file back for about five seconds.
  Every launch puts it back if something else changed it. Quitting Vignette turns Apple's thumbnail
  back on when macOS showed it before, and the next launch turns it off again. The
  `restore-apple-defaults` command sets it to what macOS had before. While it is `true`,
  Settings → Screenshots shows a Turn Off button that sets it back to `false`.
- **`windowShadow`** is Apple's drop shadow around a captured window, another Apple default that
  Vignette writes. Turn it off for window shots with no shadow margin.
- **`format`** is the file type Apple saves, such as `"png"`. Vignette writes this one too.
- **`recentCount`** is how many cards the recent stack holds. Raise it to reach further back.
  Settings → General sets it from 1 to 100, under How many to show. The file takes up to 1000.
- **`recentHotkey`** opens the recent stack. `"double-rshift"` by default, a double tap of right
  Shift, which needs Accessibility permission. A key combination needs none. The other double taps
  are `double-lshift`, `double-rcmd` and `double-ropt`. A key combination is written like
  `cmd+shift+2`. Picking Key Combination… writes `"cmd+shift+2"` and waits for the keys you want.
  The setup window on first launch is where this is normally chosen.
- **`hideMenuBarIcon`** removes Vignette's menu bar icon. In Settings → General it is Show in menu
  bar, which is the reverse. Opening Vignette again, from Finder or Spotlight, still opens the
  Settings window, and so does `vignette://settings`.
- **`launchAtLogin`** is Open at login, which adds Vignette to your login items. A new settings file
  has it on. The setup window shows the switch and applies it when you close the window. If you
  remove Vignette under Open at Login in System Settings, the next launch turns this off instead of
  adding it back.
- **`quickAnnotate`** is Close after copying a drawing. On, Copy in the annotator, or Return, copies
  the image you drew on and closes the annotator and the stack at once, instead of returning you to
  the stack. It also drops any screenshots still waiting to be drawn on.
- **`sendInstructions`** is the sentence after the image in the line Send and Reply put in a
  session, with no control in the window. `From Vignette: "<path>".` before it is fixed: the skill
  loads on "From Vignette:", and the path is the drawing. It is kept to one line, since the plugin
  delivers each line as its own message, so line breaks and tabs become spaces. An empty one leaves
  the line at the path.
- **`annotateOnCapture`** is Instant Draw in Settings and the menu bar: it opens every new
  screenshot in the annotator right away, instead of showing a thumbnail. A screen recording still
  shows a thumbnail.
- **`copyOnCapture`** is Copy to Clipboard in Settings and the menu bar. It puts every new
  screenshot on the clipboard as it lands: the image, plus its file URL and path for apps that take
  those. It is on by default. An image that arrives through `add` skips this and Instant Draw, since
  a push from an agent is not a capture.
- **`debug`** shows the Developer tab and the menu's Developer section. It also unlocks the `tweaks`
  and `intro-lab` commands, `install-skill?root=`, and `file=` outside the screenshots folder.
- **`agentSkill`** records only whether the app has offered the skill for coding agents:
  `unasked` until the offer, then `off`. The setup window's last page makes the offer. Whether the
  skill is installed is read from disk, and the Agents tab's switches install or remove it per
  agent. An older file holding `on` is read as `off`
  (see [agents.md](agents.md)).
- **`setup`** records whether the first-run setup window has had its turn: `unasked`, then `done`.
  It is written when the window closes, so a launch quit part way through asks again. This Mac
  keeps its own record too, so a file synced from another Mac does not skip setup here.
- **`ui`** holds the design numbers. See below.
- **`appleOriginal`** records what macOS was doing before Vignette's first launch changed anything.
  `restore-apple-defaults` puts those values back.

## The ui section

The `ui` section holds the design numbers: card sizes, corners, shadows, hover buttons, animation
durations and curves, how long a thumbnail and a card's notice stay, backdrop blur and tint, the
annotator window's limits, the drawing editor's sizes, and a stitch's largest size. It also holds
the behaviour those numbers drive: how far a card bows and swells on its way to the annotator, how
narrow the stack goes to make room for it and how far it stays from it, how deep the drag-select's
edge band is and how fast it scrolls there, and how near an edge of the image a zoom holds that
edge.

The defaults are the tuned UI, so a fresh install looks the same. A key the app does not know is
ignored, and a key you leave out takes its default, so a line you no longer want is safe to delete.
The file holds only the `ui` values that differ from the defaults. Vignette leaves the rest out
when it writes, so a default tuned in a later version reaches you.

Settings → Screenshots sets one `ui` number: `thumbnailSeconds`, as Show the thumbnail for, from 2
to 15 seconds.

`"ui": {"motion": 0}` turns every animation off. The system's Reduce Motion does the same.

With `debug` on, a floating panel of sliders edits these live. Open it with Tweak UI… in the
Settings window's Developer tab or the menu, or with `open -g vignette://tweaks`. Its sections are
Cards, Hover buttons, Timings, Flights, Backdrop, Annotator, Editor, Marks, Notes and Stitch. Its
Preview buttons bring up the thumbnail, the stack and the annotator while you tweak. Intro opens
the Intro Lab, which tunes the setup window's flight into the menu bar. Reset UI to defaults clears
every `ui` value.

### The drawing editor's numbers

These set how the editor feels. The panel has them in its Editor section, except New text size,
which is under Notes. A change reaches an open editor at once. Sizes are in screen points unless
the table says otherwise, so they look the same at any zoom.

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
| `newTextSize` | 17 | A new text's size, in points of the drawing |
| `selectionOutlineWidth` | 3.5 | The selection outline's whole width, light edge included |
| `noteSettleDuration` | 0.25 | Seconds a note takes to move to its balanced lines when typing ends. `motion` scales it. |

### How marks look

These set how every mark is drawn. The panel has them in its Marks and Notes sections. A change
reaches every place marks are drawn at once: the editor, the cards, a card in flight, a stitch, a
dragged card, and what Copy, Send and Copy Drawing render. Widths are in points of the drawing.

| Key | Default | What it sets |
|---|---|---|
| `personColor` | `#e03131` | A person's marks |
| `agentColor` | `#364fc7` | Every agent's marks |
| `edgeColor` | `#ffffff` | The edge around every mark |
| `noteTextColor` | `#ffffff` | The words on a note's tag |
| `strokeWidth` | 3.5 | A shape's stroke |
| `edgeWidth` | 1.5 | The edge outside a stroke and around a tag. 0 turns it off. |
| `shadowOpacity` | 1 | A multiplier on the marks' shadows' darkness. 0 turns them off. |
| `arrowheadLength` | 4.5 | A multiple of the stroke width |
| `arrowheadWidth` | 4 | A multiple of the stroke width |
| `textFont` | `rounded` | A person's notes |
| `textWeight` | 600 | From 100 to 900, the nearest weight the font has |
| `agentTextFont` | `monospaced` | An agent's notes |
| `agentTextWeight` | 600 | From 100 to 900 |
| `agentTextSize` | 1.33 | An agent's note, as a percentage of the image's width. A person's is `newTextSize`. |
| `textLineHeight` | 1.32 | A multiple of the text's size |
| `notePaddingTop` | 0.42 | The tag above the words, a multiple of the text's size |
| `notePaddingBottom` | 0.47 | Below the words |
| `notePaddingSide` | 0.8 | Each side of the words |
| `noteMaxWidth` | 18 | A note without a wrap width wraps at this many times its size, or at the image's edge |
| `badgeInset` | 0.35 | An agent's badge from its tag's left edge, a multiple of the text's size |
| `badgeOverlap` | 0.2 | How far the badge overlaps the tag's top edge, from 0 to 1.36, its height |

- A colour is `#rrggbb`.
- A font is `rounded`, `monospaced`, `serif` or `default`, which pick one of the system font's
  designs, or the name of an installed font family, such as `Avenir Next`.
- A colour or a font that is not valid is replaced by the default and logged as
  `[settings] warning clamped`, like a number out of range.

## Invalid files

A file that does not parse is moved aside as `settings.json.invalid` and replaced with defaults. A
warning at the top of Settings → General says so. If the file cannot be moved aside, Vignette runs
on the defaults and saves nothing until the file is fixed.

If the file stops parsing while Vignette runs, Vignette keeps the settings it has and logs
`[settings] error settings-invalid`. Vignette reads the file again at the next save that parses.

If Vignette cannot create the file, for example because another tool owns `~/.config`, it runs on
the defaults without saving. The same place says so, and changes last until Vignette quits.
