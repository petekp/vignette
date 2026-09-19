# The hover reveal

An icon button says its name while the cursor is on it. The label comes out beside the icon and the
button grows around it; the cursor leaves and it goes back. Two places use it: Copy among a card's
hover buttons, and every row of the selection strip.

## The mechanism

`RevealedLabel` in `StackView.swift` is the whole of it. The label is always in the view tree. What
changes is a frame width, from 0 to the width the label needs, and an opacity, both read from one
bool. The caller wraps it in `Anim.spring(ui.hoverRevealDuration)`, so it goes through the motion
scale like everything else and `"ui": {"motion": 0}` puts the label out at once.

It is not a SwiftUI insertion or removal transition. A removal starts again from nothing: a cursor
that passes over the button and leaves halfway through the reveal would snap the label to full width
and then shrink it. A width animated from a bool is one property, so an interrupted spring keeps its
velocity and blends into the new target. The label's edge never steps backwards.

The text keeps its own width (`fixedSize`) inside the animated frame and is clipped to it, so it is
uncovered from the icon outwards rather than being squeezed. `contentShape` follows the frame:
clipping hides a label, it does not stop it catching the mouse.

`ButtonLabel.width` in `StackLayout.swift` measures the label with AppKit in the font the view draws
it in. One measurement, so the room a button makes and the room the label needs are the same number,
and the strip's frame in `[state]` is the frame on screen.

## Which way it grows

The button under the cursor must stay under the cursor. So the icon never moves and the button grows
away from it, to the right: the leading edge is fixed, the trailing edge travels. The hover scale
grows the same way (`TactileButtonStyle`'s `anchor`), so the two motions pull together instead of
against each other.

A card puts Copy in the bottom-left corner and Delete in the bottom-right, so growing right also
leaves the other button where it is. At rest Copy is the same circle as Delete.

The strip is the other way round. It sits to the left of the cards, so labels growing to the right
would run over them. The strip keeps its right edge instead and grows to the left: the icons
translate left by the reveal and the labels take the room they leave. The button under the cursor
still stays under it, because a row is one button — icon and label in one `HStack` — and the grown
row always contains the resting row. The cursor's x ends up over the label of the row it started on,
so the hover does not end when the icon moves out from under it.

`StackLayout.stripReveal` is the widest label plus the room the icons keep on their own side. There
is no cap: `panelSize` adds the reveal to the strip's room whenever the strip shows, so the panel is
already that wide before the labels come out and the reveal never resizes the panel's window. The
panel's right edge does not move, so the extra width is on the left, away from the cards, and the
panel is transparent there.

The strip's box is always the grown width with the strip against its trailing edge, so the icon
column sits where the placement put it whether the labels are out or not.

One hover drives the whole strip: the cursor anywhere on it brings out every row's label, and every
label takes the same width, so the rows stay a column. A row's own hover keeps its fill and loses
its scale (`TactileButtonStyle`'s `hoverScale`): the label coming out is the hover, and a scale on
top of it would stretch the text and carry the icon out from under the cursor. A press still
scales, so the click stays physical.

## The numbers

`ui.hoverRevealDuration` (0.15 s) is the spring, shared with the card's own hover. There is no
second duration: the width, the opacity and the scale settle together.

The label's font size and the room it keeps on its right are in code, like the button sizes around
them: `ui.buttonIconSize - 1`, and `ui.buttonSpacing * 2` of room on the right, which is about what
the icon has on its left.

## Out from the keyboard too, with the shortcuts (2026-09-18)

The labels used to come out on hover only. Someone building a selection with Shift+arrows or Space
never moves the mouse, so they saw four icons and no hint of what a key would do; the shortcut was
in a tooltip, which needs the cursor.

`model.stripRevealed` replaces the old `stripHovered` bool. It is `nil`, `.hover` or `.keyboard`,
and the labels are out whenever it is not nil. `[state] stack.stripHovered` becomes
`stack.stripRevealed`, with those names or null.

**What sets it.** The keys that build a selection: `moveFocus(toward:extend:)` with Shift, Space on
the focused card, and Cmd+A. A plain arrow only moves the focus, so it sets nothing and clears
nothing — there may be no strip to reveal, and a reveal already up belongs to the selection that is
still there.

**What takes it away.** The pointer, as it does with the focus: moving onto a card clears a
`.keyboard` reveal, and the strip's own hover sets `.hover` on the way in and nil on the way out.
`releaseKeys` clears a `.keyboard` reveal, and a strip that goes clears it in `onDisappear`.

**The shortcut.** Each row draws its own after the label, dimmer (0.55), in the same font and size,
so one measurement covers both. `ShotAction.Key.glyphs` is the only renderer of ⌘C, ↩ and ⌘⌫; the
tooltip reads it too, so a row and its tooltip cannot disagree. The strip has four rows — Copy,
Draw, Stitch, Delete — and each shows its own key. Copy Paths and Copy Drawing are `.shortcut`
actions and stay out of the strip, so their keys are not shown; adding rows for them is Pete's call.

The shortcut is part of the label, not of the keyboard: it is out whenever the labels are, however
they came out. One reveal width then serves both, and the panel's room is right in either case.

**The room.** `stripReveal(rows:)` measures the widest label, the gap to the shortcut
(`stripShortcutGap`, 12 points) and the widest shortcut, plus the icons' own room. `panelSize` adds
that to the panel while the strip shows, so the labels still never resize the panel's window.
`stripLabelBox(reveal:)` is the box a row's label and shortcut share — the reveal less the icons'
room — and every row uses it, so the shortcuts line up in a column against its trailing edge.

## The card's hint, and where it steps aside (2026-09-18)

The Draw hint used to go out over the whole band along the card's bottom edge, `ui.buttonSize` plus
the padding tall and the card's full width. On a short card that is a third of the picture, and the
middle of it holds no button.

`CardView.overCornerButton` (was `inButtonRow`) is the two corner rects instead: each button's frame
plus its `CardView.buttonPad` of padding, bottom left for Copy and bottom right for Delete. The hint
now shows across the middle of that band, and a click there draws, as it always did.

The rects are the buttons at rest. Copy's label only comes out once the button itself is hovered,
and `model.overControl` hides the hint for as long as it is — so the grown Copy needs no rect of its
own. The band's job was only ever to cover the moment before that hover lands, and the label is not
out then.
