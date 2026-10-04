# Live ink: the ideal version

Live ink is drawing straight on the live screen, over any app, instead of on a screenshot. The
agent answers by drawing back on the same screen. This note describes the most capable version of
it, with technical limits set aside. What the first prototype does and measures is in
`docs/live-ink-spike-2026-10-04.md`.

In the ideal version, you point at anything on your screen the way you would point for someone
sitting beside you. The agent works out what you mean, not only what you circled. It answers on
the screen itself: by showing, by making the change, or by asking you back.

## What it can do

**Pointing**

- There is no mode to turn on. You draw with a finger, a pen, or a firm press on the trackpad, and
  the Mac tells ink from a click.
- Every gesture has a meaning. A loop picks something out. A strike-through means remove it. A
  bracket marks a range. Numbers set an order. A line between two things says they should match.
- Handwriting is read. "Bigger" written beside a button is an instruction.
- Voice and ink work together. Say "why is this one different from that one?" while tapping twice,
  and "this" and "that" become the two things you tapped.

**Understanding**

- The agent knows the thing behind the pixels. A circled number on a dashboard leads to the query
  and the data row behind it. A button in your own app leads to the component and the line of
  source that renders it. A sentence in an email belongs to its thread and the people in it.
- It knows what you were doing in the last few minutes: what changed, what you tried and what
  failed. So "this is broken again" makes sense to it.
- It connects things across apps. A line from a Figma frame to the running build means the build
  should match the design. A loop round an error followed by an arrow to a file says where the
  error comes from.

**Answering**

- The answer appears where the question was asked. Notes, loops and arrows, as in the prototype,
  or a quick sketch, a diagram drawn over the real layout, or a spoken sentence if you spoke. The
  agent picks whichever fits.
- It shows where it can. The corrected total appears over the wrong one. A proposed redesign is
  drawn over the real button, and you scrub between before and after. A second pointer shows where
  to click.
- It asks by pointing. When a request could mean two things, it loops both, and you tap one.

**Acting**

- With your approval, it makes the change. You tap its suggestion, the edit is made, the page
  reloads, and the ink finds its target again in the new layout and turns into a check. Every
  change it makes is shown where it happened and can be undone there.
- It checks its own work. After you follow a step, it looks at the target again and confirms the
  change is there, or points at what is still wrong.

**Over time**

- Ink belongs to the thing it marks, not to the screen. Open the page or document tomorrow and the
  exchange is still there, on the same element.
- Marks resolve. When the bug behind a mark is fixed, the mark turns green and fades, so nothing
  needs dismissing by hand.
- You can see where the agent is looking. During a long task, it marks what it is reading or
  editing in your own apps, and tapping its mark lets you interrupt or redirect it.
- It can point things out unprompted, such as a total that does not add up, as a quiet mark you
  are free to ignore.

**With other people**

- Ink can be shared. A teammate sees your marks on the same page in their own browser, and the
  agent's replies appear for both of you. A design review happens on the running product instead
  of on screenshots.
- Ink can be handed off. You loop a problem and write "for Sam", and Sam gets it on the real
  element, with the agent's diagnosis already beside it.

**Beyond the Mac's screen**

- The same ink works on an iPad with a Pencil, on a phone's camera pointed at a physical device,
  and across every display.

**How it behaves**

- There is no wait. The first mark of the answer appears while you are still lifting your hand.
- Ink behaves like ink on paper. It settles once sent, fades when its point is resolved, and never
  covers what you need to read.
- You can always see what the agent can see. Only what you pointed at, and the context around it,
  leaves the Mac.

## Where the prototype is

The prototype on branch `spike/live-ink` does a small part of this. It takes loops, arrows and taps
with a typed note. It understands them through Accessibility and on-screen text, and it draws the
agent's marks back so they stay on their targets as windows move and pages scroll.

The three largest steps from there:

1. Knowing the thing behind the pixels, starting with the source code of your own apps.
2. Showing a fix in place instead of describing it.
3. Ink that stays with the thing it marks and resolves itself.
