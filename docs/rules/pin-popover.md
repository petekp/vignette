# The pin popover and the hover card

How a pin's popover shows its comments, and the card a pin grows into under the pointer. The rest of
the pins' rules are in `pins.md`.

- The popover's comments are in the system's face, an agent's as a person's. Each starts with a line
  holding its writer's avatar, the one the hover card shows (`PinHoverCard.paint`, `Pin.Comment.writer`),
  their name in the label colour, "You" or the agent's capitalized, and how long ago they wrote in the
  secondary label colour. The time is said as of when the popover opened and holds still while it is
  open; a comment with no time (`Pin.Comment.at`) shows none. The words, separators, working row,
  field and a resolved pin's "Resolved by …" line start at the name's left edge. The person's avatar is their macOS
  account picture (`CBIdentity`), or their initial on `ui.personColor` when the account has none.
  An agent's is what its pin wears (`PinFace`) on its pin's colour: its logo, the first letter of its
  name, or `Agent.fallbackSymbol` when it gave no name, in the words' colour and at the pin's
  `ui.pinLogoSize`, as Claude's white logo on orange. Codex's is its black logo on a white
  circle (`Agent.oneColourAvatar`), `ui.pinOneColourLogoSize` of the circle across, larger than the
  pin's share since nothing but the logo shows on the white. The popover is
  macOS's own, with nothing behind its content: a view of our own under the content is not clipped
  to the popover's shape, so its arrow and body part ways. The field is a capsule with a hairline
  edge in the tertiary label colour (`ComposerCapsule`), so it reads as a place to type, with the
  post button inside its trailing end, `ui.pinFieldPadding` from its edge. Its placeholder is in the
  field's font and the secondary label colour: "Reply" on a pin with comments, "Comment" on a new
  pin, and "Reply to reopen" on a resolved one. It names no session: the toolbar's Send target and
  the working row name the agent. The post button is centred on the field's last line
  (`PinPopover.composerRow`), so one line of words, the placeholder and the caret sit on the
  capsule's centre line with the button. The field grows a line at a time as its words wrap, measured
  from the field editor's layout while it is edited, up to `ui.pinComposerLines` lines, past which
  it scrolls (`PinPopover.wrappedHeight`).
- Every change inside the popover moves, on springs that settle in `ui.pinPopoverDuration`, which
  the motion setting scales (`PinPopoverColumn`). Each row sits in a slot whose height springs, and
  the rows are laid out from those heights, so they never overlap. A row that comes, a comment, the
  working row or the "Resolved by …" line, opens its slot and fades in as it is uncovered. A row that
  goes folds its slot away as it fades out. The rows after them follow, and the popover's height is
  its slots', so it grows and shrinks round its arrow. The field growing a line moves the same way. Words that change in place, a delivery's
  status or note, a comment's colour on Resolve and Reopen, the "Resolved by …" words and the
  placeholder, fade out over what replaces them (`PopoverFade`), and so do the ✓'s symbol and the
  rim's colour. A row stays the same view while it shows the same thing, a comment's row while its
  comment is there (`PinPopover.showComments`), so a change moves only what changed. A row fading out
  takes no presses and is gone from VoiceOver.
- The pin's first comment shown ends its top line with a ✓ before its trash (`ResolveAction`).
  On an open pin it shows with the trash, while the pointer or the keyboard focus is on that
  comment or on them. It resolves the
  pin, posting the field's words first while it holds some, and its tooltip says so. On a resolved
  pin it is filled and always shown, and it reopens the pin. A new pin has none. The ✓ and the
  trash fade in and out, stay in the accessibility tree while clear, and are the comment's
  VoiceOver actions too. With Full Keyboard Access, Tab reaches them after their comment. A popover
  that opens under the pointer shows the buttons of the comment it is on, and a comment that came
  or moved under a pointer that stood still shows them once the rows come to rest.
- Each comment in the popover has its own Delete, for the person's and an agent's alike: a trash
  button ending its top line, shown while the pointer or the keyboard focus is on the comment, Delete Comment in its
  contextual menu, the Delete key on the comment when Full Keyboard Access focuses it, and a
  VoiceOver action (`CommentRow`). It sends `ComposerInput.delete`, which empties the comment as an
  edit would, so it is one "Delete" undo step and the pin goes with its only comment.
- When the editor lands on a screenshot with numbered pins, the lowest-numbered open pin's popover
  opens (`ComposerInput.openFirst`, from `AnnotationController.landed`), unless a popover, a drag or
  typing is under way, or every pin is resolved. It does not select the pin, and it opens without the keys
  (`Composer.takesKeys` false; `PinPopover.show` gives the key back to the editor's window). So
  the tool letters, Delete and the arrows act on the drawing as they would with no popover. None of
  its views takes the focus (`PinPopover.holdNoFocus`), so with Full Keyboard Access on no comment
  shows a focus ring until the person moves into the popover. The
  field takes the keys when the person clicks into it. Esc closes an open popover before it closes
  the editor.
- In the editor, the pointer resting on a pin with a number grows it into a card (`PinHoverCard`),
  while no popover, menu or drag is under way. The card is the teardrop widened, its rim included,
  in the popover's glass: the tip stays its square corner and the other corners keep the teardrop's
  radius. It is laid out as a popover comment: the first writer's
  avatar, name and how long ago, muted, then under the name the first comment's first line and
  replies. A selected pin's ring is left off while its card shows, since the card covers the teardrop
  the ring goes round. A press on the card is a press on its pin's teardrop, which the card
  covers: a click opens the popover with any tool and a drag moves the pin. The card's panel takes
  the presses on the pixels it draws and hands them to the editor through `EditorView.take`
  (`PinCardRoom`, `EditorView.relay`), and a press on the card's shadow lands where it is. The second
  press of a double-click on the card is dropped, so it does not land on what was under the card.
  A press, an open popover or a parked editor takes the card away at once; during a press the panel
  stays, clear, until the release. The card stays while the pointer is on the pin or on the card,
  and goes back into its teardrop when it leaves both. A pin that was clicked grows no card again
  until the pointer has left it (`EditorPinUI.pressedPin`), so closing its popover does not bring the
  card straight back. VoiceOver reads the pin instead of the card. The card's width is `ui.pinHoverWidth`
  and it grows over `ui.pinHoverDuration`, which the motion setting scales. The card draws in a
  borderless panel of its own, a child of the editor's window at the
  toolbar's level, above the stack's column. So it reaches past the picture's frame over whatever is
  beside the editor, as the popover does. It grows the way the teardrop faces and turns back on an axis
  only where the screen's visible frame has no room that way. The glass blurs what is behind the panel.
