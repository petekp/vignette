# Vignette glossary

The words Vignette uses for its screenshots, its drawings and the agents it talks to, and the
words it avoids. Labels a person reads say "draw"; identifiers, URL commands, log tags and
settings keys say "annotate". Both name the same act.

## Screenshots and the corner

**Screenshot**:
An image in the screenshots folder, whether macOS saved it from a capture or an agent added it.
_Avoid_: Capture when an agent added it, shot in anything a person reads

**Screenshot key**:
A screenshot's path as the screenshots folder spells it. Every store that keeps something about a screenshot is keyed by it, and a rename inside the folder moves the key. Code only.
_Avoid_: Path, file name

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
The column of the newest cards that the shortcut opens, and that stays until it is dismissed. Lone
thumbnails become a recent stack of their own cards when a person selects one, or presses Esc in
the editor while other cards are in the corner.
_Avoid_: Gallery, history, list

**Keyed**:
Holding the keys: the recent stack is keyed when keys pressed reach it rather than the app the
person was in. Only the recent stack is ever keyed, and never while a card is in the editor. Lone
thumbnails are never keyed, so a card that arrives on its own never takes a key from the app the
person is typing in.
_Avoid_: Focused, active

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
What a card says after something happened to it: Copied, Not copied, Not saved, or where a send
went and how it went. A card shows one notice at a time.
_Avoid_: Mark, toast, badge

**Tab**:
The white capsule in a card's top-right corner. It says which agent the card is from, which session
the screenshot was last sent to, or that an agent's card was replied to. It stays on the card, unlike
a notice.
_Avoid_: Coin, sticker

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
All the marks and pins on one screenshot. It is kept apart from the screenshot, which is never
changed.
_Avoid_: Annotation, layer, overlay

**Live ink**:
Drawing straight on the screen, over any app, while a pair of modifiers is held, Control and Option
unless another pair is picked: the chord. While
it is held the screen is inking, and each stroke becomes a mark or, as a tap, erases one. Its marks
belong to no screenshot and are no drawing. A mark drawn on a window moves with it and goes when it
closes. One on no window stays where it was drawn. Either goes when it is erased, or when a note sent
to an agent session takes it into its note card.
_Avoid_: Live annotation, screen drawing

**Note card**:
The card a live ink note sent to an agent session becomes: the window without the ink, in the
screenshots folder, with the ink and the words as its drawing.

**Result card**:
The card from an agent session once its turn on one or more note cards is over: the window as it was
then, with the session's answer drawn on it when it gave one. One turn that answers several note
cards on a window makes one result card.

**Responder**:
An agent Vignette keeps running to answer live ink on the screen: a `claude` process on the person's
own Claude Code, or a `codex app-server` on a Codex home of Vignette's own. Each has none of the
person's settings and no tools, and sees only what an ask sends. A responder is not an agent
session: nothing lists it, and it cannot be sent a drawing.
_Avoid_: Live agent, assistant

**Ask**:
One question about live ink, from the note beside it: a picture of the windows the ink is on, their
text, the ink, and the words typed. A follow-up is an ask with no new ink.

**Mark**:
One shape or note in a drawing, or on the screen with live ink, drawn by a person or an agent. Its
colour says which.
_Avoid_: Annotation, shape when a note is included

**Note**:
A mark that holds words, drawn as a tag. An agent's note carries a badge naming the agent.
_Avoid_: Text box, label, comment

**Pin**:
A numbered place on a screenshot, a point or an area, that holds one or more comments. On the
picture it shows as a teardrop holding its number, whose tip marks the place: red for a person's
pin, indigo for an agent's. A pin is part of the drawing and is not a mark.
_Avoid_: Badge, marker, comment

**Comment**:
The words one person or one agent wrote on a pin. A pin's comments are kept in the order they were
written. Words drawn on the picture are a note, never a comment.

**Pin number**:
The number a pin shows, from 1. A deleted pin's number is never given to another pin on that
screenshot while its drawing file exists.

**Cluster**:
Pins too close to tell apart at the current zoom, drawn as one teardrop widened to name them, such
as "3 · 4".

**Rendering**:
A screenshot with its drawing drawn into it, as one image. Copy, Send and a drag carry it.
_Avoid_: Export, annotated image, flattened image

**Annotation run**:
The time from a screenshot opening in the annotator until the annotator closes with nothing after
it. Drawing a list of screenshots is one run, which opens them in turn.
_Avoid_: Session

**Opening**:
One screenshot's time in the annotator, from its flight out until its card comes home. The same
screenshot closed and drawn again is a new opening. A run of a list is one opening per screenshot.
_Avoid_: Session, generation

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
The application or multiplexer holding terminal panes, such as the Herdr app. A pane can show different
agent sessions over time, so a pane is never a destination.

**Agent plugin**:
What Vignette installs into an agent client so the agent knows Vignette's commands and, for
Claude Code, receives what Send sends.
_Avoid_: Skill when the whole plugin is meant, extension

**Destination**:
The agent session a person means to send a screenshot to. Its display name helps the person
choose it but is not its identity.
_Avoid_: Target

**Destination choice**:
Vignette's pick of the session Send or a live ink note starts on, before the person picks one, and
the order Send's menu lists the sessions in. A note starts on the session the note before it was
sent to. When there is none, or it is not found again, the note starts on a responder, which is
not a destination.
_Avoid_: Default target

**Kept pick**:
A session the person picked in Send's menu and then sent to. Send starts on it before any other
rule for 10 minutes after each send to it. It is a destination choice, kept in memory only.
_Avoid_: Sticky target, last sent

**Delivery route**:
The way a screenshot request reaches a destination. Each agent client has exactly one, and the
routes differ in how firmly they pin the destination.

**Send**:
To hand a rendering, and an optional message, to a destination as a screenshot request.

**Grace period**:
The seconds between pressing Send and the line reaching the session (`ui.sendGraceSeconds`). A
send in it is in its grace period and can still be cancelled with Don't send. Once the grace
period ends the line is released to the session, and a cancel no longer takes it back.

**Don't send**:
The button on a card, and `vignette://unsend`, that cancel a send still in its grace period. The
request is cleared and nothing reaches the session. In code and logs the same act is `cancelled`
(`SendGrace.Event.cancelled`, `[send] cancelled`); `unsend` is only the URL and action id.
_Avoid_: Cancel or undo send in anything a person reads

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

**Agent title**:
What an agent says its screenshot shows: a title, and a description under it. The editor shows it
above the image. It is not part of the drawing.
_Avoid_: Caption, header, label
