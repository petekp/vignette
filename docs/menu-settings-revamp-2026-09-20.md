# Menu bar menu and Settings revamp (2026-09-20)

Pete asked for the menu bar menu and the Settings window to look and feel more polished, for the
terminology to be reconsidered, and for anything an end user has no use for to be hidden.

This file is the spec the work is built from. `docs/using.md` and `docs/settings.md` are updated
with it so the words match.

## Terminology

One word per concept, used the same way in the menu, the window, the toasts, and the docs:

| Concept | Word | Not |
| --- | --- | --- |
| A file the watcher reports | screenshot | capture, shot, image |
| The thing the user does in the editor | draw (Draw, drawing) | annotate (code and URLs keep `annotate`) |
| The editor window | the drawing window in copy; `annotator` in code | |
| The column of recent screenshots | Recent Screenshots (menu), recent stack (docs) | thumbnails |
| The key that opens it | shortcut | hotkey (the settings key stays `recentHotkey`) |
| A key combination shortcut | ⇧⌘6 rendered as glyphs | "cmd+shift+6" |
| The double-tap shortcut | double-tap Right Shift | "double-rshift" |
| Apple's screenshot machinery | macOS | Apple |
| `quickAnnotate` | "When you finish drawing: Copy and close" | Quick draw, Quick annotate |

Settings keys, URL ids, log tags, and identifiers do not change (AGENTS.md, "Two vocabularies").

## The menu

```
Show Recent Screenshots            ⇧⌘6         ← native key equivalent when the shortcut is a combination;
Draw on Last Screenshot            hold ⇧⌘6       a trailing badge (NSMenuItemBadge) when it is a double tap
                                                  ("double-tap Right Shift", "hold double-tap Right Shift")
─────────────────────
✓ Copy New Screenshots
  Draw on New Screenshots
─────────────────────
Open Screenshots Folder
Settings…                          ⌘,
─────────────────────
Quit Vignette                      ⌘Q
```

- "Open Last Screenshot" leaves the menu. It summoned the thumbnail, which the shortcut already does
  better. `vignette://last` and `openLast` stay for scripts.
- The disabled "Watching: <path>" line becomes "Open Screenshots Folder", which opens the folder in
  Finder; its tooltip is the full path.
- "Restore Apple Screenshot Defaults" leaves the menu and lives in Settings › Screenshots as a button.
- "Tweak UI…" and "Open Log" leave the menu. With `debug` on, a "Developer" group appears above Quit:
  "Tweak UI…", "Open Log", "Reveal settings.json". With `debug` off there is no trace of them.
- The shortcut is shown once, in the shortcut column, not repeated in the title.

## The Settings window

A toolbar-tabbed window (`NSWindow.toolbarStyle = .preference`, an `NSToolbar` whose items switch the
hosted SwiftUI view; the window title is the tab's name, the window resizes to each tab's fitting size
with the standard animation). Each tab is a grouped `Form`, 480 pt wide. Tabs, with SF Symbols:

### General (`gearshape`)

- **Shortcut** — a segmented choice: "Key combination" | "Double-tap Right Shift".
  Key combination shows a recorder: a bordered field reading "⇧⌘6"; click it and it reads "Type a
  shortcut…" and takes the next key press with at least one of ⌘⌥⌃ (⇧ alone is not enough) and a key
  `HotKeySpec` names; Esc cancels. A press it cannot use is refused with a short shake or a beep and
  the field returns to the old value. Writes `recentHotkey` as `HotKeySpec.text(keyCode:modifiers:)`.
  Double-tap Right Shift writes `"double-rshift"`.
  One caption under it: "Shows your recent screenshots. Hold it to draw on the newest one."
  When double-tap is chosen and the app is not trusted for Accessibility, a second caption line:
  "Needs Accessibility permission." with a button "Open System Settings" that opens the Accessibility
  pane (`x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`).
- **Keep the last N screenshots** — stepper, 1…100 (`recentCount`).
- **Show a new screenshot for N seconds** — slider 2…15 with the value beside it (`ui.thumbnailSeconds`).
- **Launch at login** — toggle (`launchAtLogin`).
- **Show in menu bar** — toggle, the inverse of `hideMenuBarIcon`. While off, one caption:
  "Reopen Settings with `open vignette://settings` in Terminal."

### Screenshots (`camera.viewfinder`)

- **Save to** — the folder, middle-truncated, with "Choose…" (`screenshotsFolder`).
- **Save macOS screenshots here** — toggle (`syncAppleSaveLocation`). No caption.
- **Format** — PNG | JPEG picker (`format`, values stay "png"/"jpg").
- **Show the macOS thumbnail** — toggle (`appleThumbnail`). Caption: "Off saves the file right away
  and Vignette's thumbnail is the only one."
- **Shadow on window screenshots** — toggle (`windowShadow`).
- Section **After a screenshot**:
  - **Copy to the clipboard** — toggle (`copyOnCapture`). No caption.
  - **Open it to draw** — toggle (`annotateOnCapture`). Caption: "Instead of showing a thumbnail."
    (The menu calls the same setting "Draw on New Screenshots"; the toggle's short name sits under
    the section heading, which carries "screenshot".)
- Section **When you finish drawing** — a radio picker (`quickAnnotate`):
  "Return to the stack" (false) | "Copy and close" (true). No caption.
- Section **macOS** — a button "Restore macOS Screenshot Settings…", enabled only when
  `appleOriginal` is recorded. It runs `Settings.restoreAppleDefaults()` and shows the existing toast.
  Caption: "Puts back where macOS saved screenshots, the thumbnail, the shadow, and the format from
  before Vignette changed them."

### Agents (`sparkles`)

Decided with Pete on 2026-09-20, after the first build: the switch could lie (a linked
`~/.claude/skills` installs nothing and only the log says so), nothing showed whether the skill was
there, and the caption listed paths and mechanism instead of the reason.

```
Vignette can teach your coding agents to show you an image and read back what you draw on it.

  Install the skill                                              [switch]

  Claude Code     Installed, 1.4 (4787973)
                  ~/.claude/skills/vignette
  Codex           Not installed: ~/.codex/skills is a link, and Vignette
                  does not write through links.                  [Reveal]
```

- The sentence at the top is the whole pitch, and the offer text when the window opens itself.
- One switch, "Install the skill", bound as before (`agentSkill` on/off; off is an answer, never
  `unasked`). Disabled, and off, when no agent directory exists.
- One row per agent directory found (`SkillInstaller.roots`), named "Claude Code" for `.claude`
  and "Codex" for `.codex`, computed from disk (`SkillInstaller.state(of:)`, `linkedPath(in:)`)
  on show and after every settings change. The states, in words:
  - ours: "Installed, <version> (<build>)" from the stamp, then the path.
  - none: "Not installed", then the path it would take.
  - foreign: "Something else is at <path>. Vignette leaves it alone."
  - linked root: "Not installed: <link path> is a link, and Vignette does not write through
    links." with a "Reveal" button that selects the link in Finder.
- No agent found: "No coding agent found on this Mac. Vignette looks for Claude Code and Codex."
- The offer (`offerAgentSkill`) still opens this tab once, unasked, `activating: false`.
- No installer change and no settings change. `docs/agents.md` "Installing" describes the tab.

### Developer (`wrench.and.screwdriver`) — only when `debug` is on

- Buttons: "Tweak UI…", "Open Log", "Reveal settings.json".
- Caption: "Shown because `debug` is on in settings.json."

## Captions

Every caption that restated its toggle is gone. What stays is one line that says a consequence the
label cannot: the macOS thumbnail delaying the file, the way back when the menu bar icon is hidden,
the Accessibility permission, what the restore button restores.

## Docs

- `docs/using.md`: "hotkey" → "shortcut" where it names the user's key; "Draw on New Captures" →
  "Draw on New Screenshots"; the last paragraph of "The hotkey" says the menu shows the same command.
- `docs/settings.md`: the window's description (tabs), "Quick draw" → the finish-drawing choice,
  "Draw on New Captures" → "Draw on New Screenshots", "Tweak UI…" moves to the Developer tab.
- `README.md`: only if a user-facing line names a renamed item.

## Out of scope

Settings keys, `vignette://` ids, the tweak panel itself, the stack, the annotator, and any
behaviour behind a setting. The `debug` flag stays file-only.
