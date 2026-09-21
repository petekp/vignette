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

Third pass, 2026-09-20 evening. Pete on the second: a switch is the wrong control for an install,
"Reveal" says nothing, "does not write through links" and "Vignette leaves it alone" mean nothing to
an end user. Disk is the truth and the button says the one thing the user can do next.

```
Vignette can teach your coding agents to show you an image and read back what you draw on it.

                                                              [ Install ]
Claude Code     Not installed
Codex           Installed by you. Vignette won't change it.
```

- One button. "Install" while any agent directory lacks Vignette's copy and could take one;
  "Remove" when every agent that could take one has it (and none is missing); no button when there
  is nothing it could do. Install writes `agentSkill` on, Remove writes off: the existing settings
  observer does the work, so `install-skill` and a hand-edited file behave as before.
- Links are followed. A `skills` directory that is a link is written through, so the skill lands
  where the agent reads it. The `linkedRoot` outcome, `linkedPath`, the state report's
  `linkedSkillRoots`, and the docs paragraph about links go. A skill folder that is itself a link
  is still foreign (the user's own).
- Rows, one per agent directory found, no paths:
  - none: "Not installed"
  - ours: "Installed"
  - foreign with a `SKILL.md`: "Installed by you. Vignette won't change it."
  - foreign without one: "A folder named vignette is already there and isn't a skill. Move it
    aside to install."
- An install that fails toasts "Couldn't install the skill for <agent>" (`thumbnail.showFeedback`
  from the AppDelegate's result handling); the row stays "Not installed".
- No agent found: "No coding agent found on this Mac. Vignette looks for Claude Code and Codex."
  and no button.
- The offer still opens this tab once, unasked; the Install button is the invitation.
- `docs/agents.md` "Installing" and "What the installer will not touch" say this in two short
  paragraphs.

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
