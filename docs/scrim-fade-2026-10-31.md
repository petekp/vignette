# The scrim's fade (2026-10-31)

The scrim is `DimPanel`: a panel the size of the screen behind the annotator, holding a blur and a
black tint. It fades in when the annotator opens and out when the annotator closes. The blur and the
tint fade together, because the fade is on the opacity of the panel's content view.

Core Animation runs the fade, in the render server. Each fade is a `CASpringAnimation` on the
opacity of the content view's layer. It follows `Tween`'s curve: a critically damped spring that
settles over `ui.dimFade`. The window's own alpha stays at 0.995.

## Why the main thread doesn't run it

Driven from the main thread, the fade stepped. `Tween` set the window's alpha on each tick of a
display link on the main thread. When a tick came late, it landed where the spring was by then, so
the scrim jumped.

- **The app's own log** recorded each alpha it set, in 20 exits recorded in the `vignette-e2e` VM.
  In 14 of them the alpha moved by more than 0.101 across a gap between ticks over 25 ms. 0.101 is
  the most the spring moves in one frame at 60 Hz. The largest move was 0.27, across a 46 ms gap.
- **Stack exits stepped more often than lone ones.** A stack exit moved by more than 0.15 between
  ticks in 9 of 10 takes, a lone exit in 4 of 10. A stack exit also widens the stack back, and
  that layout runs on the main thread. The log can't tell a busy main thread from a display link
  that fired late in the VM.

A recording of the VM's screen also shows steps that the app didn't make. The VM's display path
holds frames for every animation. In openings, a marker square that Core Animation alone animated
held in 25% of frames, and one the ticks moved in 26%. In exits, the ticks' marker held more often,
17% against 11%, but the 95% interval on the difference, −0.007 to +0.126, includes zero. So
the late ticks are shown by the app's log, and the recordings show what reached the screen.

## Why the layer's opacity is held until the spring ends

`fade(to:)` leaves the layer's own opacity, its model value, where the fade started. The spring has
`fillMode = .forwards`. Its completion sets the model value to the target and removes the spring,
but only when no newer fade has begun since (`fadeCount`). A fade that interrupts another starts
from the running spring's value and velocity, from `Tween.spring`.

When the model value was set to the target in the same transaction as the spring, the target
showed first in exits. In 10 of 12 exits in the VM, the whole scrim went clear for one or two
frames. Then it came back at 0.77 to 0.91 of full strength and faded from there. With the model
value held, none of 12 exits went clear (one-sided Fisher p = 3.4e-05). Openings written the same
way showed no full-scrim frame before the spring, so the early model value was seen in exits only.

- **The blur doesn't cause it.** With the blur view hidden, 10 of 12 exits still went clear.
- **Group opacity doesn't cause it.** With the content resting at 0.999, so it is always drawn with
  an opacity, 12 of 12 exits went clear.
- **Why the model value shows isn't known.** A plain `CALayer` written the same way, in its own
  window, never showed its model value early. What was measured is the write that avoids it.
- **The completion's write doesn't show.** After the fade began, no band of the scrim moved more
  than 0.106 away from a marker animated beside it.

## Against the fade with ticks

Both fades were recorded in the VM in one boot: 5 rounds of each, the order alternating by round.
Each fade recorded:

- 20 exits, by Done and by Esc, from a lone thumbnail and from the stack;
- 10 openings;
- 5 takes where Esc interrupts the opening;
- 5 where an opening interrupts the exit.

Each take is measured in bands of the scrim, from 1 at the full scrim to 0 at the clear screen. A
take is flagged when, in one frame, a band moves the wrong way by more than 0.25 or either way by
more than 0.7. It is also flagged when a band moves by more than 0.25 and comes back within three
frames, or when the fade's last leg takes under 0.1 s.

| | Render server | Ticks |
|---|---|---|
| Exits flagged | 0 of 20 | 2 of 20 |
| Openings flagged | 0 of 10 | 0 of 10 |
| Interrupted takes flagged | 0 of 10 | 0 of 10 |
| Exit, 5% to 95% of the way, median | 284 ms | 283 ms |
| Opening, 5% to 95%, median | 292 ms | 283 ms |
| Esc during the opening, last leg, median | 317 ms | 316 ms |
| Opening during the exit, last leg, median | 300 ms | 308 ms |
| Blur over tint in lone exits, median | 1.02 | 1.05 |
| Largest move after 0.5 s | 0.006 | 0.005 |

The full scrim looks the same with both. Each band's median luminance differs by at most 0.003 of a
level. For the render-server fade, the 95% Wilson bounds on the rate of flagged takes are 0.16 in
exits and 0.28 in openings.

**The two flagged exits are stalls of more than the scrim.** In both, the annotator's image left its
frame in one or three frames, where every other exit took five frames or more. These recordings
can't tell a stall of the main thread from one of the VM's display path. No exit of the
render-server fade met a stall like them. The render-server fade's takes with a recording gap near
the fade's start were recorded again, and those of the fade with ticks were kept. So these counts
don't show the render-server fade stepping less often.

**The run is a deviation from its plan.** The plan expected no flagged take from the fade with ticks
and called any a stop. These two were stalls the plan didn't foresee. Pete accepted the run as a
labelled deviation from the plan. A run with a control like this one needs a rule for stalls,
written before it runs and applied to both fades.

**The fade now starts before the image moves.** In exits, the render-server fade starts a median
34 ms before the annotator's image starts to leave, and 0 to 84 ms in single takes. The fade with
ticks starts with the image, a median of 0 ms. 34 ms is about two frames at 60 Hz. The measure is
against the image, so it can't tell whether the render-server fade starts early or the fade with
ticks started late. The earlier start is kept: a delay to match the image would be sized to a lag
measured in a VM.

## Limits

- **All of it is in a VM.** Nothing was recorded on a real display. Whether a real Mac shows a
  layer's model value early, as the VM did, isn't measured. Neither is whether the step a person saw
  on a real display is gone.
- **The counts are small.** 0 of 20 exits bounds the rate at 0.16, not at zero.
- **The host was loaded.** The app's log of late ticks was recorded at a 1-minute load of 5.2 to
  7.9. Load makes late ticks more frequent than on a quiet Mac, so the log overstates how often the
  fade with ticks stepped.
- **Counting large steps in a recording doesn't separate the two fades in the VM.** Its display
  path shows the render-server spring with steps of the same size. So the evidence on the ticks is
  the app's log and the marker beside it.
