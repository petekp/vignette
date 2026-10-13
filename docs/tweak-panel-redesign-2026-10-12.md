# Tweak panel redesign (2026-10-12)

Status: built (`TweakCatalog.swift`, `DebugPanel.swift`).

The tweak panel (Tweak UI… in the menu, `vignette://tweaks`) has grown to about 120 controls in 17
sections on one scrolling page. It is slow to drag a slider in and hard to find anything. This plan
rebuilds it around one list of tweak definitions, a sidebar with search, and rows that redraw only
themselves.

## Why it is slow and hard to use

- **Every row redraws on every change.** Each row observes all of `Settings.shared`, so one slider
  step redraws every row in the panel, and every other view that observes the settings.
- **Each step re-applies everything.** A change to any `ui` value runs `applyTweaks` on the stack,
  the annotator and live ink, and warms the thumbnails again (`AppDelegate.settingsChanged`). A drag
  does this for every step the slider reports.
- **Tick marks.** Every slider is given a `step`, so AppKit draws one tick per step: 200 on a
  0 to 2 slider in steps of 0.01. The striped bars are those ticks.
- **One long page.** There is no search and no way to jump to a section. The preview buttons are cut
  off at the panel's width.
- **Each tweak is written down twice or more.** Its label, slider range and step are in
  `DebugPanel.swift`, its safety range is in `UITweaks.bounds`, and the Intro, Check and Pointer labs
  write their own rows for the tweaks they share.

## The design

- **One list of tweaks.** Each tweak is defined once: its key path, label, section, slider range,
  step, unit, a help line, and its safety range. `UITweaks.bounds` is derived from that list, so a new
  tweak is added in one place and cannot be on the panel without a safety range. The labs show a
  filtered part of the same list.
- **A sidebar of sections, and search.** The panel is a split view. The sidebar lists the sections,
  each with a count of the values that differ from the default. Search filters by label, section and
  setting name across every section. Only the chosen section's rows exist, so a slider step redraws
  about ten rows, not 120.
- **Rows drawn again only when their own value changes.** A row is equal to its last drawing while
  its value is (`TweakRow` is `Equatable`), so a slider step draws one row.
- **Changed.** The top of the sidebar lists every value that differs from its default, across all
  sections.
- **A compact row.** The label, a plain slider with no ticks, and the value as a field that takes a
  typed number. A value that differs from its default shows a dot, and the row's reset puts that one
  value back.
- **Previews in the toolbar.** The preview buttons move to a toolbar menu, so they are never cut off.
  Revealing the file and resetting every tweak sit at the foot of the sidebar.

## Measured

In the `vignette-e2e` VM, with a slider dragged back and forth for 4 s by pointer events posted at
120 a second:

| | Before | After |
|---|---|---|
| Opening the panel | 4.1 s | 0.14 s |
| Slider steps a second | about 17 | about 95 |
| Longest gap between steps | 220 ms | 44 ms |

A settings change itself took 0.1 to 0.4 ms both times, so the cost was the panel drawing itself,
and slider changes are not coalesced.

## Rules the panel keeps

- **Its structure holds still while a value changes.** A form that gains or loses a section while a
  slider is dragged ends the drag. So a section's reset button is always there and only disabled, and
  Changed keeps listing a setting brought back to its default until another section is picked.
- **A row hidden for the current style stays hidden in search.** A row's `applies` says whether the
  setting does anything with the others as they are, as the pointer lab's rows did.
- **The labs show the same rows.** The Menu bar intro, Pointer and Check labs show their section of
  the catalog with `TweakGroups`, so a tweak changed in a lab is the same row in the panel.
