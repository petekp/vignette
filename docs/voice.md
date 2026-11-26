# How Vignette speaks

Every word a person reads in Vignette is clear, short and humble, and it points to what can happen
next. Pete set this on 2026-10-01. This file holds the rules and the messages written to them, so a
new message matches the ones already there. Change a message here and in the code together.

## Rules

- **Say what happened in plain words.** Name the thing: the thread, the session, the drawing.
  Leave out the mechanism, such as "rollout", "inbox" or "exit 1". The log keeps those.
- **Then say what can happen next, as a possibility.** "You can send it to another one", not "Send
  to another one". The person decides. A message never gives orders.
- **Be humble about what Vignette knows.** Say what Vignette saw, not more: "Codex can't find this
  thread", not "This thread is gone". When the fault is Vignette's, Vignette says so: "Vignette
  couldn't render the drawing".
- **Keep the way forward in view.** Nothing is lost when a send fails, since the drawing is still
  there, so a message points at the next try rather than at the failure. A queued send says when it
  will be read.
- **Fit the card.** A headline is two or three words, plus the session's title when it names one.
  The card cuts a title that is too long. A reason is one or two short sentences, about 60
  characters, since it sits under the headline on a card.
- **"The log has details."** is how a message points at the log. Use it only when the person can do
  nothing else.
- **Contractions, and no exclamation marks.** "couldn't", "can't", "isn't".
- **Draw, not annotate.** Every string a person reads says draw. The names scripts read say
  annotate (AGENTS.md, "Words and motion").
- **No toasts.** A message goes on something already on screen, usually the card it is about
  (`docs/no-toasts-2026-09-30.md`).

## Release notes

Release notes are for people who use Vignette. Give the gist of what they will notice, in a few
short bullets: a bold name and one sentence. Leave out wording changes, internal rework, and how
anything works inside.

## Messages

### A send, on its card (`SendOverlay`)

| State | Headline | Reason |
| --- | --- | --- |
| Waiting to send (the line has not gone yet) | Sending to *session* | Button: Don't send |
| Sending | Sending to *session* | |
| Starting the session, which was not running at Send | Starting in *session* | |
| Sent | Sent to *session* | |
| Queued: Codex holds the line while a turn runs, or while a command waits for approval | Queued for *session* | Codex reads it when its current turn ends. |
| Queued: Codex holds the line while its question waits for an answer | Queued for *session* | Codex is waiting for your answer, then reads this. |
| Queued: the thread's last turn was stopped | Queued for *session* | Codex stopped its last turn. You can resume it in Codex. |
| Queued: no Codex engine has the thread open | Queued for *session* | Codex reads it when you open this thread. |
| Queued: the thread is archived | Queued for *session* | This thread is archived. Codex reads it once you unarchive it. |
| Queued: Codex has the thread open and has not taken the line after 15 seconds | Queued for *session* | Codex hasn't picked it up yet. You can check the thread in Codex. |
| Queued, Don't send pressed, Codex had already started the line | Sent to *session* | Codex had already started on it. |
| Queued, Don't send pressed, Codex refused to remove the line | Queued for *session* | Vignette couldn't remove it. You can delete it in Codex. |
| Not confirmed in time | Check *session* | Codex didn't confirm it. It may still have arrived. |
| Not sent | Not sent | One of the reasons below |
| A reply that could not be shown | Reply not shown | You can ask *agent* to send it again. / Vignette couldn't save the reply. The log has details. |
| A live ink note whose session finished with nothing to show as a result card, or whose window changed while the person was using it | Done in *session* | |

*session* is the session's title as the toolbar or the live ink note showed it when Send was pressed: the herdr tab's label, else the session's name, with a suffix when two sessions share a title. `SessionMenu.cardTitle` decides it. A session that Send starts has no title yet, so the card names its project folder instead. On a card too narrow for the headline, the title stands alone. A title too long even for that is cut in the middle.

Pressing Don't send says nothing. The press is the confirmation, the ring and the button go with
it, and "Not sent" is the headline for a failure, not for a choice. On a queued line the overlay
goes the same way, and the tab's clock turns to a spinner until Codex has removed the line. A line
the person deletes in Codex also says nothing, since they did it there.

### The tab on a card (`CardTab`)

| Card | Tab | Folded on a narrow card |
| --- | --- | --- |
| An agent pushed it | From *Agent* ("From an agent" with no name) | The logo |
| A person's screenshot that was sent | Sent to *session* | The logo and a paper plane |
| A person's screenshot whose line Codex still holds in its queue | Queued for *session*; on hover the clock is a Don't send button whose help is the queued reason | The logo and a clock |
| An agent's card sent back to the session it came from | From *Agent* · Replied | The logo and a check |

*session* is the title the send's notice showed, as above. A newer send replaces it. The tab
names the last send that reached its client: a send that failed, went unconfirmed or was
cancelled with Don't send leaves the tab as it was.

### Why a send did not go (`SubmissionOutcome.reason`)

| When | Reason |
| --- | --- |
| The Claude Code session ended | This session has ended. You can send it to another one. |
| The Claude Code session was cleared | This session was cleared. You can send it to another one. |
| Codex has no such thread | Codex can't find this thread. You can send it to another one. |
| The Codex thread is archived | This thread is archived. You can unarchive it in Codex or send to another one. |
| Codex's engine can't be reached | Codex isn't running. You can send again once it's open. |
| No Codex on this Mac | Sending to Codex needs the Codex app or its CLI. |
| Herdr did not open a tab for a session that was not running | Vignette couldn't open a Herdr tab for Claude Code. The log has details. |
| The started session, or one whose `hc run` gave no answer, had no inbox 45 s later | Claude Code didn't open in time. You can send again once it's running. |
| Codex did not start | Codex couldn't start. The log has details. |
| Codex refused it for a reason Vignette has no words for | Codex: *its own words* |
| Anything else | Something went wrong in Vignette. The log has details. |

### Before the request is stored, beside Send's "Not sent"

| When | Reason |
| --- | --- |
| The drawing did not render | Vignette couldn't render the drawing. The log has details. |
| The request could not be written, when it was made or as its line was about to go (`SubmissionOutcome.notSaved`) | Vignette couldn't save the request. *the system's words* |
| Anything else | Vignette couldn't send the drawing. The log has details. |
| The screenshot is gone | Vignette can't read *name*. It may have been moved or deleted. |

### The annotator's bar

| When | Tooltip |
| --- | --- |
| Reply is unavailable: no message, and the agent's drawing as it sent it (`AnnotatorToolbar.Model.nothingToReplyTip`) | Add a message or draw to reply |

### Undo and Redo in the Edit menu, and VoiceOver after each (`StepName.title`)

Each follows "Undo" or "Redo", as in Apple's editors: "Undo Arrow", "Redo Typing". Plain "Undo"
and "Redo" when there is nothing to take.

| Step | Name |
| --- | --- |
| A rectangle, an ellipse or an arrow drawn | Rectangle, Ellipse, Arrow |
| A typing session, on the image or in the message field | Typing |
| A drag or a nudge | Move |
| A resize | Resize |
| An arrow bent | Bend Arrow |
| An arrow's end dragged | Move Arrow End |
| Cmd+D or an Option-drag | Duplicate |
| Delete | Delete |
| A paste or a drop, on the image or in the field | Paste |
| A cut, on the image or in the field | Cut |
| Agents' marks joining the open drawing | *Agent*'s Marks, as in "Claude's Marks"; "Agent's Marks" without one name |
| A comment posted on a pin; an edited one is Typing, an emptied one Delete | Comment |

### Undo and Redo in the stack and the annotator (`UndoTimeline.Name`)

The same form as the editor's, in Finder's words where Finder has the action. Plain "Undo"
and "Redo" when there is nothing to take; Cmd+Z then beeps. While a screenshot is in the editor,
the editor's own step names come first (the table above).

| Step | Name |
| --- | --- |
| Delete, which moves the files to the Trash | Move to Trash |
| Stitch | Stitch |
| A screenshot opened in the annotator, or another opened in its place | Open Drawing |
| The annotator closed | Close Drawing |
| Keep on an agent's marks, on a card or in the editor | Keep Marks |
| Clear on an agent's marks, on a card or in the editor | Clear Marks |

### The line an agent receives (`ScreenshotRequests.requestLine`)

The person's message leads, and the Vignette part follows in brackets. "From Vignette:" is fixed,
because the skill loads on it. The sentence after it is `sendInstructions` from settings.json.

| When | Vignette part |
| --- | --- |
| A drawing | From Vignette: "*folder*/image.png". If a drawing would answer better than words, you can send one back. |
| Words alone on the agent's own image | From Vignette: about your image "*card*" ("*its title*"), unchanged since you sent it. The reply ticket is "*folder*/ticket.json". If a drawing would answer better than words, you can send one back. |

A drawing with pins puts each pin's words after the message and before the bracket, in number
order: `Pin 1: remove extra margin. Pin 3: too narrow. / can we pulse it?` A comment's words are
joined into one line, and one pin's comments are joined with " / ". A full stop follows the message
and each pin's words when they end in a letter or a digit (`Pin.lineWords`, `Pin.ended`).

### Settings switches

Their words are in [voice-settings.md](voice-settings.md).

### Setup's shortcut page, after the hold (`SetupBanter`)

These lines break the rules above on purpose. Pete wrote them on 2026-11-01, and they stay word for
word. The first hold of the shortcut says line 1, and each later hold says the next line. A hold
moves the script on only while its line shows on the shortcut page.

| Hold | Words |
| --- | --- |
| 1 | You're a quick learner! Think you got it down? |
| 2 | Amazing, you did it again! |
| 3 | Sheesh. You're an expert now. |
| 4 | You're THE expert, now. |
| 5 | You've done this before, haven't you? |
| 6 | The ease with which you do it... marvelous. |
| 7 | Must feel nice to be so good at something. |
| 8 | Very good. Let's move on shall we? |
| 9 | Great. |
| 10 | Nice. |
| 11 | Hmm. |
| 12 | I see what you're doing. |
| 13 | Okay, ha ha. Let's continue on, yeah? |
| 14 | Yes, you did it again. |
| 15 | You're trying to get a rise out of me aren't you. |
| 16 | Let's get a rise out of the ol' setup menu, very funny. |
| 17 | Picking on a setup menu is an interesting choice. |
| 18 | ... |
| 19 | ..... |
| 20 | What do you want from me? |
| 21 | Bro. |
| 22 | C'mon bro. |
| 23 | BRUH. |
| 24 | Okay whatever. I'll just wait here. |
| 25 | ... |
| 26 | ... |
| 27 | ... |
| 28 | Ugh. |
| 29 | Fine, that's it. |
| 30 | One more time and I'm pushing the button myself. |
| 31 | Bye. Then setup goes on to the next page, as Continue would. |
| Back on the shortcut page | Hi! Welcome to the setup... oh, it's you. |
| 32 | Dude. No. |
| 33 | F%@#! |
| 34 | I'm out. ✌️ |
| 35 and after | *The setup assistant has peaced out.* In muted italics, and it stays. |

### Warnings at the top of the Settings window's General tab

| When | Title | Line under it |
| --- | --- | --- |
| The last settings write failed and no later one has succeeded (`Settings.notSavedNotice`) | Settings not saved | Vignette couldn't write to *file*. It tries again with your next change. |
| The file could not be created at launch | Settings can't be saved | Vignette can't write to *folder*. Changes last until it quits. |
| The file did not parse at launch and was set aside | settings.json could not be read | Vignette is using the default settings. Your file was kept as settings.json.invalid. |
| The file did not parse and could not be set aside | settings.json could not be read | Vignette is using the default settings and will not save changes until the file is fixed. |

*file* and *folder* are the settings file and its folder, written with `~`. A failed write can follow
a launch that set a bad file aside, and then both warnings show, Settings not saved first.

### The menu bar menu's shortcuts (`HotKeySpec.glyphs`, `HotKeySpec.holdLabel`)

| Item | With a double tap | With a key combination |
| --- | --- | --- |
| Show Recent Screenshots | Right Shift ×2 | ⇧⌘6, in the menu's shortcut column |
| Draw on Newest Screenshot | Right Shift ×2 and Hold | Hold ⇧⌘6 |

### Live ink

Live ink's messages are in [voice-live-ink.md](voice-live-ink.md).

### A copy, on its card ("Not copied")

| When | Reason |
| --- | --- |
| The screenshot did not read | Vignette couldn't read the screenshot. |
| The rendering could not be written | Vignette couldn't save the drawing. |
| A stitch's pieces hold pins and one could not be read, on that piece's card (`Stitch.refusal`) | Vignette couldn't read this screenshot, so it made no stitch. |
| A stitch's pieces hold more than 99 pins between them, on the first piece's card | A stitch holds up to 99 pins. These hold *n*. |

### The end of a copy's comment list (`CommentList`)

| When | Line |
| --- | --- |
| One pin did not fit under the cap | 1 more pin didn't fit. You can read it in Vignette. |
| More than one | *n* more pins didn't fit. You can read them in Vignette. |

### Pins in the editor (`PinPopover`, `Pin.spokenName`, `EditorView+Pins.swift`)

| Where | Words |
| --- | --- |
| The popover's field, empty | Add a comment |
| The field, to VoiceOver | Comment on pin *n*; Comment on new pin |
| Who wrote a comment, above its words | You; the agent's name, or Agent |
| A comment's row, to VoiceOver | You: *words*, then Edit this comment |
| A pin's first comment posted, to VoiceOver | Pin *n* added |
| A pin, to VoiceOver | Pin 3, area, 2 comments; Pin 1, point, 1 comment; New pin |
| A selection with pins, to VoiceOver | 2 pins; 1 mark and 2 pins |
| The rotor and the action | Pins; Add Pin |
| A pin's row in a cluster's or the toolbar's menu, to VoiceOver (`EditorView.pinListItem`) | Pin 3, area, 2 comments: *first comment* |
| The toolbar's button, its tooltip, and to VoiceOver (`ToolbarView.pinsButton`) | Pins, beside a badge with the count; Pins; Pins, *n* |

### An agent showing a screenshot (`ShownOverlay`, `AgentMarksBar`, `Shown`)

A card an agent showed with `vignette://show` says who showed it, in the tab's own words, and the
agent's line under them. While the notice says the tab's words, the tab gives way, so a card never
says the same words twice.

| Where | Words |
| --- | --- |
| The notice's headline | From *Agent* ("From an agent" with no name) |
| The notice's second line | The agent's `message=`, at most 60 characters, cut at a word with an ellipsis |
| The notice, to VoiceOver | From *Agent*: *message* |
| VoiceOver, once per call | *Agent* showed you a screenshot; *Agent* showed you 3 screenshots ("An agent" with no name) |
| The buttons, wherever the agent's marks are on top | Clear, Keep |
| Clear's help | Take the agent's marks off |
| Keep's help | Add the agent's marks to your drawing |
| The editor's bar, and the band on a card whose shown state ended while the marks are still on top | Marks from *Agent* ("Marks from an agent" with no name) |
| "Not saved", when Keep could not write the marks | Vignette couldn't add the marks. You can keep them again. |

### A drawing, on its card ("Not saved")

| When | Reason |
| --- | --- |
| The editor's drawing could not be written after the editor let go of it (`Drawings.notSaved`) | Vignette couldn't save the drawing. The log has details. |

After Done, "Not saved" takes the place of Copied.
