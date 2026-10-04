# Vignette glossary

The words Vignette uses for its screenshots, its drawings and the agents it talks to, and the
words it avoids. Labels a person reads say "draw"; identifiers, URL commands, log tags and
settings keys say "annotate". Both name the same act.

## Screenshots and the corner

**Screenshot**:
An image in the screenshots folder, whether macOS saved it from a capture or an agent added it.
_Avoid_: Capture when an agent added it, shot in anything a person reads

**Screen recording**:
A movie macOS saved to the screenshots folder. It appears as a card but is never drawn on.
_Avoid_: Video

**Screenshots folder**:
The folder macOS saves screenshots in. Vignette watches it and follows macOS when it changes.
_Avoid_: Watch folder in anything a person reads, save location

**Card**:
One screenshot or screen recording as it appears in the corner or the recent stack.
_Avoid_: Thumbnail when the recent stack is meant, tile

**Lone thumbnail**:
A card that comes up in the corner after a screenshot arrives, and leaves after a few seconds.
_Avoid_: Toast, preview, popup

**Recent stack**:
The column of the newest cards that the shortcut opens, and that stays until it is dismissed.
_Avoid_: Gallery, history, list

**Selection**:
The cards a person has picked in the recent stack, in the order they picked them. Every action
receives the cards in that order.

**Focused card**:
The one card a key acts on when nothing is selected.
_Avoid_: Active card, current card

**Action**:
Something a person can do to the selected or focused cards, such as Copy, Draw, Stitch or Delete.
_Avoid_: Command when a person reads it

**Stitch**:
One new screenshot made from several, laid out for a model to read, with each piece's number on it.
_Avoid_: Merge, collage, combine

**Notice**:
What a card says after something happened to it: Copied, Not copied, or where a send went and how
it went. A card shows one notice at a time.
_Avoid_: Mark, toast, badge

## Drawing

**Draw**:
To open a screenshot in the annotator and mark it up.
_Avoid_: Annotate, edit, mark up in anything a person reads

**Annotator**:
The window a screenshot is drawn on in, with its frame, its toolbar and its zoom.
_Avoid_: Editor window, canvas

**Editor**:
The drawing surface inside the annotator: its tools, its marks and its undo history.
_Avoid_: Canvas

**Drawing**:
All the marks on one screenshot. It is kept apart from the screenshot, which is never changed.
_Avoid_: Annotation, layer, overlay

**Live ink**:
Drawing straight on the screen, over any app, while Control and Option are held: the chord. While
it is held the screen is inking, and each stroke becomes a mark or, as a tap, erases one. Its marks
belong to no screenshot and are no drawing; they stay where they were drawn until they are erased.
_Avoid_: Live annotation, screen drawing

**Mark**:
One shape or note in a drawing, or on the screen with live ink, drawn by a person or an agent. Its
colour says which.
_Avoid_: Annotation, shape when a note is included

**Note**:
A mark that holds words, drawn as a tag. An agent's note carries a badge naming the agent.
_Avoid_: Text box, label, comment

**Rendering**:
A screenshot with its drawing drawn into it, as one image. Copy, Send and a drag carry it.
_Avoid_: Export, annotated image, flattened image

**Annotation run**:
The time from a screenshot opening in the annotator until the annotator closes with nothing after
it. Drawing a list of screenshots is one run, which opens them in turn.
_Avoid_: Session

**Queue**:
The screenshots waiting in an annotation run, in the order they will open.

**Flight**:
A card's image travelling between its place in the corner and the annotator, standing in for both
until it lands.
_Avoid_: Transition, animation

## Agents

**Agent client**:
The software running an agent conversation, such as Claude Code or Codex. It is distinct from the
model vendor and from the terminal displaying it.
_Avoid_: Provider when it could mean both an agent client and a terminal host

**Agent session**:
One conversation with an agent, including the context it has built up. Showing it in another
window does not make it a different conversation.
_Avoid_: Session without qualification, pane, tab, thread when Claude Code is included

**Terminal host**:
The application or multiplexer holding terminal panes, such as herdr. A pane can show different
agent sessions over time, so a pane is never a destination.

**Agent plugin**:
What Vignette installs into an agent client so the agent knows Vignette's commands and, for
Claude Code, receives what Send sends.
_Avoid_: Skill when the whole plugin is meant, extension

**Destination**:
The agent session a person means to send a screenshot to. Its display name helps the person
choose it but is not its identity.
_Avoid_: Target

**Delivery route**:
The way a screenshot request reaches a destination. Each agent client has exactly one, and the
routes differ in how firmly they pin the destination.

**Send**:
To hand a rendering, and an optional message, to a destination as a screenshot request.

**Reply**:
To send to the agent session a card came from, which the card names.
_Avoid_: Respond, answer

**Screenshot request**:
One sent rendering and its message, addressed to one destination.

**Screenshot reply**:
An image, with optional agent marks, that answers one screenshot request. One request may have
several replies.

**Reply ticket**:
Permission to submit replies to one screenshot request. Holding it does not show which agent
process produced a reply.

**Accepted reply**:
A screenshot reply whose every byte Vignette holds. It is not yet a card.

**Published reply**:
An accepted reply that has become a card.

**Agent push**:
A screenshot an agent adds to the screenshots folder through Vignette, with optional marks. Its
card says which agent sent it.
_Avoid_: Upload, import
