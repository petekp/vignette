# A press on a card in flight (2026-09-23)

A press on the card flying into the editor now draws there. Before this change, the flight layer
ignored the mouse, and the editor's window passed every press through until about 21 ms after
`show`. A press during the flight reached the app behind it, and Pete asked on 2026-09-23 for that
to be fixed.

This note records what each press does now, the measurements the design rests on, and the two
limits still open. The code is `Sources/FlightPress.swift`, the press handling in
`TransitionLayer`, `AnnotationController.probeEvents`, and `ThumbnailController.flightPressed`.

## What a press does

| Where the press is | What happens |
|---|---|
| On the card flying into the editor | It is held until the editor's window takes presses. Then it goes to the editor with every drag since, in order, and the rest of the press follows it there. |
| On the card flying in, when the image turns back | The image turns back after Esc, a `cancel` or another image opening. What is held goes nowhere, and the rest of the press is swallowed. |
| On any other flight | It is swallowed up to its release. This covers a card flying home and a card leaving with the stack. |
| On a flight's shadow, or beside a flight | It reaches whatever is under it. Beside the card flying into the editor, that is a click outside the editor, which closes it. |
| Right-click, scroll or another button on a flying card | Nothing. The flight layer takes it, and nothing handles it. |

Keys still reach the editor during the flight, as they did before.

The reasons:

- **A flight going anywhere but the editor swallows the press.** The card is not in its slot yet,
  so a click on it has nothing to act on. A card flying home follows an Esc, a Done or a Send the
  person just gave, and a stray click should not reopen what they closed. The card takes clicks
  again the moment it lands.
- **The shadow passes presses.** The window server already does this, and the flight layer draws
  nothing else. The card's ring, 1 pt outside the picture, counts as the card, and a press on the
  ring lands on the picture's edge.
- **A held event lands where it was on the picture.** Each held event goes to the point of the
  picture that was under the pointer when it happened, mapped through the flying picture at that
  moment. So an early press draws a bigger rectangle for the same hand movement, because it maps
  through a smaller card.
- **After the handover, the pointer's place on screen decides.** The editor's window is where its
  picture is, and the flight still settling over it is a few points off at most. So ink lands under
  the pointer once the flight lifts.
- **Ink appears when the flight lifts.** The flight covers the editor until it lifts, at `arrived`.
  Ink drawn after the handover stays hidden under it until then, for about 0.1 to 0.2 s at motion 1,
  and appears all at once.

## Measurements

Scratch programs and driven runs on the test copy measured these on 2026-09-23. During every timed
press, a full-screen window at level 1 caught any press the app did not take.

**Which window a press reaches.** The window server gives a window only the presses on pixels it
draws. A drawn pixel with alpha as low as 0.004 takes the press. A clear pixel passes it, and so
does a shadow. The window server was asked which window was at 1, 4, 8, 16, 24, 32, 48 and 64 pt
outside a card. Every point was the window behind, both for a SwiftUI `.shadow` like the flight's
and for a layer shadow like the annotator's.

**`ignoresMouseEvents` must stay unset.** Set explicitly to `false`, a window takes presses on
clear pixels too. The flight layer covers the screen, so it would then catch every click on the
screen while a flight is up. The comment on `TransitionLayer` says so.

**Where the flying picture is.** A platform view inside SwiftUI's `GeometryEffect` gets the
effect's offset and scale, so `NSView.convert` returns the flown rect. In a test it gave exactly
the expected 80,95 300×150. So each flight carries a `FlightSpotView`, placed before the `Bow`
effect so that the bow and the swell are included. `FlightSpotView.fraction(of:in:picture:)` maps a
press onto the aspect-filled picture.

**When the editor's window takes presses.** The window is ordered in at alpha 0 in `prepare`. In 24
trials of a scratch harness, it took presses 5.7 to 25.4 ms after `show` set alpha 1. No occlusion
notification came with the change, and `CATransaction.flush()` right after setting the alpha did
not make it sooner. Nothing announces the moment, so the app asks for it. `probeEvents` asks the
window server every millisecond from `show` which window a press at the frame's centre would reach,
looking through this app's windows above it. It logs `[annotate] takes events after=<n>ms`. In the
app, 95 answers came back:

| Answers | Time after `show` | Conditions |
|---|---|---|
| 80 | 6 to 39 ms | ordinary use |
| 9 | 46 to 97 ms | during traces, with a load average of 15 to 28 |
| 6 | the 0.5 s deadline | the Mac going to sleep, or asleep |

**The deadline is 0.5 s.** After it, the press is handed over anyway, and the log line ends in
` deadline`. Relayed events reach the editor whatever the window server says. A flight kept over
the frame for want of an answer would hide what the editor draws.

**The flight into the editor lifts no earlier than the answer.** It also still waits for `arrived`
and the loaded image. At motion 1 the answer comes long before `arrived`, so nothing on screen
changes. The wait keeps the flight over the window until the window takes presses itself.

**Releases that never arrive.** Before the release watch, 4 of 29 driven presses on flights home got
no release at any window. Neither the app nor the catcher behind it saw one. That left the flight
layer up, and the cause was not found. The flight layer has to stay up until the release, because
the window server sends the drag and the release to the window that took the press. So
`TransitionLayer.watchRelease` reads `NSEvent.pressedMouseButtons` every 50 ms while a press is
down. After two readings of up in a row, it ends the press and logs `[flight] release missed`. Two
readings are needed so that a release still queued behind the first reading is not overtaken. With
the watch, 14 more presses missed none, and it fired once when the Mac went to sleep in the middle
of a drag.

**The drives.**

- A press and drag during a 3 s flight was held, handed over 24 ms after `show`, and drew a
  rectangle.
- During a 40 s flight, a capture right after the press put it at 0.3054, 0.6012 of the picture,
  which is image px 462, 590. The rectangle's origin came out at 461, 591.
- On a normal 0.25 s flight, presses came 0.13 to 0.43 s after `annotate`. The one at 0.13 s
  reached the catcher, which is correct, because the card was not under the point yet. Three came
  during `flyingOut` and were held and handed over. Two came during `annotating` and reached the
  editor too. All five drew.
- During `flyingOut`, the A key switched the tool from Rectangle to Arrow. The editor stayed key
  after every press.
- A press was held on a 3 s flight, and then `cancel` turned the card back. The release came in
  `idle`. No drawing was stored, and nothing reached the catcher.
- 14 presses on flights home and 3 on dismissals were all swallowed, with no strays. Each was at a
  point where the window server showed the flight layer at that moment.
- A stitch's pieces converge inside the stack's column. The stack panel, also at `.statusBar`,
  already takes every press there, and a press on a converging piece did nothing. The flight layer
  taking such a press was not shown separately.
- A press at 60,900, beside a card flying into the editor, reached the catcher. It closed the
  session the way any click outside does.

`FlightPressTests` checks where `FlightPress` sends each event: held, handed over, swallowed, or
dropped when the image turns back. It also checks the aspect-fill mapping.

## What is still open

**The window server's lag.** The window server applies a window's new pixels, or its alpha, 6 to
about 30 ms late. A press in that interval goes to whatever was drawn there before. At motion 1 the
start of a flight is over the stack's column, which takes presses itself. The leading edge of a fast
card could let a press through for a frame. That was not measured.

**One press passed through at motion 0.** The cause was not found. The press came 27 ms after
`show`, 13 ms before the probe answered, and reached the catcher. The flight should have covered
that point: at motion 0 a flight is still made, and it lifts only after the probe answers. So the
flight layer's own pixels were not taking presses either. The press came 72 ms after `prepare`, and
the editor's load held the main thread for 43 ms of that. The likely cause is the window server's
lag on the flight layer's new pixels, added to that wait. It is not confirmed. That drive ran on the
working tree before `dd1df6a` was committed, with the lift and the probe already in it.
