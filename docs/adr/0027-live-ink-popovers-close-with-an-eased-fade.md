# Live ink's popovers close with an eased fade

AGENTS.md says every AppKit animation uses `Tween`'s spring curve, so that an interrupted motion
keeps its velocity. Live ink's popovers are the exception when they close. `LiveNotePopover.fadeAway`
and `LiveReplyPopover.close` fade the window's alpha to 0 with `NSAnimationContext` on an ease-in
curve, then close the popover. The fade's length is scaled by the motion setting, and at
motion 0 the popover closes at once.

A spring is for a motion that can be sent a new target. A closing popover never is: both methods
return early once `closing` is set, so nothing turns the fade around, and a spring would have no
velocity to carry over.

## Considered options

- A `Tween` spring on the alpha. It would behave the same here, since nothing interrupts the fade,
  and it would add a display link to drive what AppKit already animates.
