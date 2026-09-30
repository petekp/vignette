# Who drew a mark, and what colour it is (2026-09-29)

Status: built on 2026-09-29 in the working tree, not committed. "What was built" lists the numbers
Pete chose, and "What was verified" what was checked.

## Decision

- **The mark's edge provides the contrast, not its hue.** Every mark, notes included, has a 1.5 pt
  white edge (a casing) and the note tag's soft shadow, so it shows on any screenshot in any colour.
- **The hue says who drew it.** A person's marks are always red, `#e03131`. An agent's marks are
  always indigo 9, `#364fc7`, shapes and notes alike.
- **The colour pass is retired**, because the edge does its job.

## What a mark's colour has to do

1. Show on any screenshot: light, dark, busy, or the same colour as the mark.
2. Say who drew it. The person needs to tell at a glance. So does the model reading the PNG, which
   is how an agent tells its own marks from the person's when a drawing comes back.
3. Look like one set of marks, not a mix of colours that seem to mean something.

## What happens today, and where it falls short

- **The colour pass picks a mark's hue from what is under it** (`ColorPass.swift`). It tries red,
  yellow, light blue, white and violet in that order and keeps the first that is far enough from
  the pixels. So hue carries contrast and nothing else. One drawing can be red, yellow and light
  blue, and a reader cannot tell that the difference means nothing.
- **Hue now also carries identity, for notes only.** An agent's note is always violet. An agent's
  arrow or box still goes through the colour pass, so the test push had red arrows next to violet
  notes. A person's mark can come out violet when violet is what the pass picks.
- **The two jobs conflict.** A fixed agent colour can fail contrast, which is what the pass
  exists for. A hue picked for contrast can look like the agent's.
- **Nothing tells a model the rule.** The skill cannot say "the red marks are the person's",
  because that is not true.
- **Only notes carry identity by form**: an agent's note is set in SF Mono and has a badge. Shapes
  carry none.

## The proposal

### Contrast from the edge

Every shape gets a white casing under its stroke, 1.5 pt on each side, and every mark gets the
note tag's soft shadow. Maps draw roads the same way, with a pale casing under the colour, so a road
shows on any terrain.

- On a dark or busy screenshot, the white edge separates the mark from the picture.
- On a light screenshot, the edge disappears into the background and the colour does the work.
- On a background the same colour as the mark, such as red on red, the white edge still draws the
  shape.

Notes get the same edge around the tag, so every mark is drawn the same way.

### Hue from the author

- A person's marks are red, `#e03131`. It is the colour annotations are expected in, and it
  passes on white at 4.5 to 1.
- An agent's marks are the agent colour. One colour covers every agent, and the note's badge says
  which agent it was.
- A note's words are white on both colours. The dark ink for yellow and white tags goes, because
  neither colour is drawn any more.

### What goes

- The colour pass: `ColorSample`, the decode it needs, and the core's `colorOwed` and
  `colorSampleArrived`.
- `colorChosen`. With no pass, nothing needs to be protected from it.
- An agent naming a colour. If colour says who drew a mark, an agent that draws in red would be
  speaking as the person. `marks=` would still accept `color`, so an older skill's push does not
  fail. It would ignore the value and log `[marks] color ignored`. That is a change to a documented
  contract, so `docs/commands.md` and the skill change with it.

The skill then says: the red marks are the person's, and the agent-coloured ones are the agent's own.

## The agent colour

The candidates are Open Color values, the palette today's red comes from. For each candidate: white words on
it, the colour itself on a white screenshot, the colour on near-black, and its CIE76 distance (ΔE,
the straight-line colour difference in CIELAB) from the person's red and from the selection outline
`#3182ed`.

| Candidate | White words on it | On white | On `#1a1a1a` | ΔE from red | ΔE from selection |
|---|---|---|---|---|---|
| Today's violet, grape 7 `#ae3ec9` | 4.8 | 4.8 | 3.6 | 94 | 52 |
| Violet 7 `#7950f2` | 4.9 | 4.9 | 3.5 | 119 | 45 |
| **Violet 8 `#7048e8`** | **5.6** | **5.6** | **3.1** | **119** | **46** |
| Violet 9 `#6741d9` | 6.3 | 6.3 | 2.8 | 116 | 44 |
| Indigo 7 `#4c6ef5` | 4.3 | 4.3 | 4.0 | 119 | 22 |
| **Indigo 9 `#364fc7`, chosen** | **6.8** | **6.8** | **2.6** | **114** | **25** |
| Blue 7 `#1c7ed6` | 4.2 | 4.2 | 4.1 | 113 | 12 |
| Cyan 8 `#0c8599` | 4.3 | 4.3 | 4.0 | 108 | 55 |

- **Blue is the selection outline's colour.** Blue 7 is 12 from it and indigo 22. An agent's
  selected arrow would be a blue line inside a blue outline. Blue is also every link and button
  in the screenshots being annotated.
- **Violet 8 moves toward blue and gains contrast.** White words on it go from 4.8 to 5.6, and it
  moves further from the person's red (94 to 119). It stays 46 from the selection outline.
- **Red and blue-violet stay distinct with red-green colour blindness,** which is the common kind.
  Red against teal or green does not.
- **None of these is readable on near-black by hue alone** (2.8 to 4.1 to 1). The white edge is what
  carries them on dark screenshots, for the person's red as well.

Pete chose indigo 9 from a mockup of the candidates on light, dark and busy screenshots. It is
darker than the others, so white words on it read best (6.8 to 1). It sits 25 from the selection
outline, and the white edge keeps an agent's selected mark apart from the outline around it.

## What was built

- **Colour:** `MarkColor` has two cases, `person` and `agent`. `Mark.color` is derived from
  `agent`, so neither a mark nor the file stores a colour. The two colours are settings
  (`docs/mark-style-settings-2026-09-29.md`). Nothing reads drawings from an earlier
  build.
- **Edge:** `MarkStyle.edgeWidth`, 1.5 pt on each side of a stroke and around a tag. The renderer draws
  the white edge once per shadow inside a transparency layer, then the colour over it. On screen,
  `MarkLayers` draws the same with shadowed shape layers. `inkExtent` and the selection outline
  include the edge.
- **Words:** always white.
- **An agent's note:** the tag keeps a person's note's padding, 0.42 em above, 0.47 em below and
  0.8 em at the sides. The badge sits on the tag's top edge, 0.35 em from its left, overlapping it
  by 0.2 em.
- **An agent naming a colour:** `marks=` accepts `color`, ignores it, and logs
  `[marks] color ignored for <name>`.
- **Retyping:** an agent's note whose words the person changes becomes theirs when typing ends
  (`EditorCore.endTyping`), as one undo step. Its tag settles to red and the badge fades out. A move
  or a resize keeps it the agent's.
- **Removed:** `ColorPass.swift`, `colorChosen`, `colorOwed`, the colour sample, and `noteInk`.

## What was verified

- **Unit tests:** all 404 pass. The renderer tests check the white edge on a note and a shape, red
  for a person's mark and white words. The core test checks that retyping an agent's note makes it
  the person's.
- **In the app:** a test copy on scratch settings showed a person's and an agent's marks in the
  editor and in the PNG that Copy Drawing writes. Edges, shadows and badge matched between the two.
  An agent mark that named `red` was drawn indigo.
- **A bug found and fixed:** the selection outline overlapped the edge on ellipses and arrows,
  because `outline(of:)` did not include the edge.

Not checked yet: the typing field with the edge, and the cross-fade when a retyped agent note
becomes the person's. Both need a keyboard round in a test copy.
