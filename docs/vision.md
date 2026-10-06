# Vision and design principles

Status: draft for discussion, 2026-10-06.

## The vision

Vignette is becoming a visual way to work with an agent, the way you work with a person at the same
screen.

Today most work with an agent runs through text. You describe what you see, the agent describes
what it did, and you go and check. Much of each turn goes to translating between the screen and
words. Two people at one screen do less of that. They point while they talk, they show rather than
describe, and they look at the result together.

Vignette's aim is for a person and an agent to work that way. The screen they both see is the
medium. Each side speaks and points: the person talks while drawing, and the agent talks while it
points back. Typing is there for when speaking is not.

The exchange takes two forms:

- **A still.** A screenshot you draw on and send, which the agent draws back on. It suits a moment
  that has to travel or wait: a bug report, a design note, a question for later.
- **Live ink.** Drawing on the live screen, over any app, while the agent points back on the same
  screen. It suits working on something together, now.

The same principles apply to both.

## Where the principles come from

They come from watching two people work at one screen. A good collaborator:

- sees what you see, and you know what they see;
- points while talking, then lowers their hand;
- shows you rather than describing;
- asks when unsure, and points at the options;
- checks the result with you;
- notices when you look away, and shows you again when you ask;
- leaves your mouse alone, and keeps out from in front of what you are reading.

## Principles

1. **One shared view.** The person and the agent work from the same screen, and each can tell what
   the other sees. The agent says what it was shown, and what it could not see. Only what the person
   pointed at, and the context around it, leaves the Mac.

2. **Point at things, not pixels.** A mark belongs to the thing it marks: a button, a line of text,
   a cell. It follows that thing as it scrolls, moves or reflows, and it goes when the thing goes.

3. **Everything happens at the thing.** The answer, the question, the progress and the result appear
   on the thing being discussed, where the person is already looking. The person never has to watch
   a separate panel or bar to know what the agent is doing.

4. **Pointing passes; what needs you stays.** A gesture fades once the person has had a chance to
   see it. A mark stays only while it still needs the person: a choice to make, an action to take, a
   problem not yet fixed. It goes when that is done, so the person seldom clears anything by hand.

5. **Paced to the person.** The agent points while it talks, one thing at a time, at a speed a
   person can follow. It waits while the person is looking elsewhere. When the person missed
   something, they ask, and the agent shows it again on the screen as it is now.

6. **Show, act when asked, then check.** The agent shows before it describes: the fix drawn in
   place, the value it means, the options it is choosing between. It changes things when the person
   asked it to, or pressed one of its buttons. Then it looks at the result, and points at it or at
   what is still wrong. Like a collaborator, it also points out what it notices along the way, such
   as a total that looks wrong, while it works on what the person asked.

7. **Stay out of the way.** Marks keep clear of what the person needs to read. The keyboard, the
   focus and the pointer stay with the person. Everything arrives and leaves with motion, and
   Vignette's words are short and humble (`docs/voice.md`).

## The hard cases

These are the cases that need the most care. Each answer follows from the principles.

| Case | What happens |
|---|---|
| Did the agent get my ink, and is it working? | The ink answers. It settles when sent, shows that it is being worked on, and the reply grows out of it. |
| The answer came while I was in another app | It waits on the thing. When the thing is off screen, a small mark at the screen's edge points toward it. |
| I missed what it pointed at | Gestures wait while you are away. Tap your own ink, or ask again, and it points again at the screen as it is now. |
| The page changed since | Marks follow their things. When a thing is gone, its mark goes, and the agent says so. |
| Too many marks | It points at one thing at a time, and each gesture fades as the next begins. Only what needs you stays. |
| I want a mark gone now | Scribble over it, as on a whiteboard. A quick tap of the drawing keys clears them all. |
| It is not sure what I meant | It points at each thing you might have meant, and you tap one. |

## Where this goes

1. **Now.** Stills both ways. Live ink with a typed note, answered with marks that follow their
   windows.
2. **Next.** Speech input: the person talks while drawing, and what they say about "this" and
   "that" is tied to what they pointed at. Then speech output: the agent talks while it points.
3. **After that.** The agent knows the thing behind the pixels, such as the line of source or the
   data row. It shows fixes in place and checks its own result.
4. **Later.** Marks stay with their things across days, and other people can see them.

`docs/LIVE_INK_VISION.md` lists these capabilities in detail.

## To decide

1. **Presence while working.** Should the agent show where it is looking as it works, faintly, on
   things you can see? To explore: it may be how you can tell what the agent is doing without a
   progress bar.
2. **Memory.** Do marks stay with their things after the session ends? Undecided.
