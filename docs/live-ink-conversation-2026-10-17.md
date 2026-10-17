# Live ink: the note becomes the conversation (2026-10-17)

On the screen, the note the person types in stays a popover from the moment they press Return to
the moment it leaves. It becomes the conversation: their question stays where they typed it, the
agent's row sits under it, and the answer streams in under the row. A thin light runs round the
popover's rim while the agent works. A card still draws the question as a red note tag, because a
card is a picture of the ink, not the live screen.

`docs/live-ink.md` has the rules as built. This note records what else was tried and why this one
was picked.

## What was wrong

The sent note used to turn into a drawn red note tag beside the ink, and the reply came up as a
second popover with the question quoted in its header. The person's words changed material, size
and place at the moment they pressed Return. Nothing on the screen said the words had become a
note, so the change read as the popover breaking. The note also had no waiting state of its own.

## Flows tried

Each was mocked in real `NSPopover`s, in light and dark mode, in the test VM
(`.scratch/flow-mock/flowmock.swift`, git-ignored).

| Flow | While asking | Answered | Verdict |
| --- | --- | --- | --- |
| Thread | The note as typed, its target settled into a plain row | The answer under the row; the question greys | Picked |
| Fold | As Thread | The question folds into a one-line header: Claude · "question" | The question jumps and shrinks at the moment the person reads the answer |
| Capsule | The question alone | The answer beside the logo, under the question | Loses who answers while asking, and the row the note had disappears |
| Status | "Asking Claude…" with a spinner, in place of the question | Header and answer | The person's words vanish while they wait, which is what the change was meant to stop |

Thread is the only flow in which nothing the person has already seen moves or changes size at the
handover or when the answer comes. The question keeps its frame from the note's field (`NoteLayout.fieldFrame`) and the row keeps the
target's frame, so the first frame of the conversation matches the last frame of the note.

## Waiting states tried

| Treatment | Verdict |
| --- | --- |
| Rim light, one light | Picked |
| Rim light, two lights | Busier, with nothing more to say |
| Rim light, wider | Lights a whole side at once, so it reads less as one light moving |
| Rim light in the ink's light colour in dark mode too | Shows less on a dark popover than white does |
| Rim light in the ink's deep colour | Shows less in both modes |
| Multicolour border sweep | Loud beside the ink, and it is the look macOS gives its own Apple Intelligence |
| Blue glow inside the body | Tints the whole popover, so the question reads as selected |
| Shimmer across the question | The question is harder to read while it moves |
| Spinner in the row | A second motion beside the ink's band, out of step with it |
| Skeleton lines for the answer | Grows the popover before there is anything to show |

The rim light ties the popover to the ink. It goes round once every two beats of the band on the ink
(`thinkingPeriod`), counted from the same start (`thinkingEpoch`), and leaves from under the arrow.
So the light leaves the arrow as the band on the ink starts a stroke, and two popovers lit at once
show it at the same point. That is what lets the note hand over to the conversation with no visible
change. It is white on a dark popover and the ink's light colour on a light one, where white does
not show.

## The handover, measured

A screen recording at 60 frames a second in the VM, each frame compared with the settled
conversation, shows:

- No shift. The note's host window is whole points and the popover hangs from the exact spot, so
  the conversation lands on the same pixels. A host at fractional points shifted by 1 pt.
- No darkening. Two glass popovers over each other darken for every frame they share: 3 frames at
  first, 1 frame with a fade. The note's alpha now drops to 0 in the same commit that shows the
  conversation, and its window goes three refreshes later.
- No gap and a steady shadow.

A session takes the note in about 40 ms, before the 0.18 s handover finishes. The note then leaves
with the ink, on the conversation's timing. Before that fix, the note vanished in one frame.

## Contrast

The conversation keeps the note's translucency and has no backing. Over a dark window in light mode
the glass turns mid-grey. Measured there, the answer is 7.4:1 and the greyed question 6.1:1; in dark
mode the answer is 12.8:1. The answer's words take the glass's vibrancy as the question's label does
(`Drawn.allowsVibrancy`). Without it the answer measured 4.8:1 and drew lighter than the greyed
question.

## Checked in the VM

- Light mode and dark mode, over a light window and a dark one
- A follow-up through an action button
- A failure, said in the row
- A five-line question
- Motion off: the rim holds at 35%
- A send to a session

Below and above edges were not checked against a recording.
