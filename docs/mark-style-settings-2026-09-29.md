# How marks look, in settings.json (2026-09-29)

Status: built on 2026-09-29 in the working tree, not committed. `docs/settings.md` lists the keys
for readers of the file; this note keeps the reasons.

Pete asked for every value that sets how a mark looks to be a setting: the colours, the stroke, the
fonts, the text sizes, and the rest. They join the `ui` section of settings.json (`UITweaks`), in
the tweak panel's Marks and Notes sections. The defaults are today's look, so nothing changes until someone
edits a value.

## The settings

| Key | Default | What it sets |
|---|---|---|
| `personColor` | `#e03131` | A person's marks |
| `agentColor` | `#364fc7` | Every agent's marks |
| `edgeColor` | `#ffffff` | The edge around every mark |
| `noteTextColor` | `#ffffff` | The words on a note's tag |
| `strokeWidth` | 3.5 | A shape's stroke, in pt of the drawing |
| `edgeWidth` | 1.5 | The edge outside a stroke and around a tag, in pt |
| `shadowOpacity` | 1 | A multiplier on the marks' shadows; 0 turns them off |
| `textFont` | `rounded` | A person's notes |
| `agentTextFont` | `monospaced` | An agent's notes |
| `textWeight` | 600 | A person's notes, 100 to 900 (existing) |
| `agentTextWeight` | 600 | An agent's notes |
| `newTextSize` | 17 | A person's new note, in pt (existing) |
| `agentTextSize` | 1.33 | An agent's note, as a percentage of the image's width |
| `textLineHeight` | 1.32 | Both, a multiple of the size (existing) |
| `notePaddingTop`, `notePaddingBottom`, `notePaddingSide` | 0.42, 0.47, 0.8 | The tag around the words, in multiples of the text size |
| `noteMaxWidth` | 18 | The widest a note wraps without a wrap width, in multiples of the text size |
| `badgeInset`, `badgeOverlap` | 0.35, 0.2 | Where an agent's badge sits on its tag, in multiples of the text size |
| `arrowheadLength`, `arrowheadWidth` | 4.5, 4 | Multiples of the stroke width (existing) |

- A colour is `#rrggbb`. Anything else is replaced by the default and logged as
  `[settings] warning clamped`, like an out-of-range number.
- A font is `rounded`, `monospaced`, `serif` or `default`, which pick the system font's design, or
  the name of an installed font family. A family that is not installed falls back to the default
  and is logged the same way.

## How the values reach the drawing

Every place that draws or measures a mark already receives two values made from settings:
`TextStyle` and `ArrowheadStyle`. The new values go into those rather than into a global, so a
rendering off the main thread keeps using the values it started with, and a test sets them directly.

- `ArrowheadStyle` becomes `MarkStyle`: the stroke and edge widths, the colours, the shadow
  opacity, and the arrowhead. `Mark.strokeWidth`, `Mark.edgeWidth`, `MarkColor.hex` and
  `NoteTag.ink` go.
- `TextStyle` gains the two fonts and weights, the agent's text size, the padding, the width cap
  and the badge's place. `TextLayout`'s and `NoteBadge`'s constants for these go.

A change reaches the open editor, the cards and flights, and the next rendering, as the existing
Marks settings do. A note's bitmap records both styles it was drawn in (`MarkLayers.Styles`), so a
colour change redraws it.

## What was verified

- **Unit tests:** all 404 pass. The settings test now also repairs a colour that is not `#rrggbb`
  and a font that is not installed.
- **In a test copy** on scratch settings, with an agent's marks pushed and open in the editor:
  - Non-default values at launch all showed: a green agent colour, a 7 pt stroke, a 3 pt edge,
    Avenir Next at weight 800, a 2.2% agent text size, and the badge inset 1 em.
  - `personColor: "not-a-colour"` logged
    `[settings] warning clamped ui.personColor "not-a-colour" -> "#e03131": a colour is #rrggbb`.
  - An edit of the file with the editor open reached it within a second: orange, no edge, a serif
    face, no shadows and wider side padding.
