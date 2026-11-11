# Live ink's voice in the note

With `liveInkSpeech` on, the note shows what the person says while they say it, after a waveform
that stands where the caret will be. `docs/live-ink.md` has the rest of listening: when it starts
and ends, typing over it, and what the agent gets.

| Part | Where |
| --- | --- |
| Opening the note while the chord is held | `LiveInk+Listening.swift` (`heard`, `showNoteWhileListening`, `listen(into:)`) |
| The note by the pointer, before any ink | `LiveInk+Note.swift` (`showNoteOnTheVoice`, `noteMayMove`), `LiveNotePopover+Place.swift` (`pointerPlace`) |
| The pointer field's light following the voice | `PointerFieldMotion.swift` (`hear`, `voice`), `PointerField.swift` (`ringVoice`) |
| The note's side: starting, words, levels, the end | `LiveNotePopover+Voice.swift` |
| The waveform, the letters and the levels, as pure values | `VoiceCaret.swift` (`VoiceCaret`, `HeardLetters`, `VoiceLevels`) |
| Drawing them in the note | `LiveNoteVoice.swift` (`NoteVoice`, `VoiceCaretView`, `NoteWordsLayout`) |
| The input's level | `Microphone.swift` (`levels(of:)`) |
| Tests | `Tests/VoiceCaretTests.swift`, `Tests/LiveInkTests+Voice.swift` |

## Opening while the chord is held

From the moment live ink listens, the pointer field's light follows the voice: the lamp grows
brighter and wider with the input's level, by `ui.liveInkLampVoice` (0.8), and settles over about
0.45 s once the sound stops. It is the same field, and it covers nothing new.

The first word heard opens the note without the keys, `ui.liveInkNoteClearance` (40 pt) from the
pointer, to its right where it fits, then its left, below or above. The chord alone opens nothing,
since the person may be about to draw in silence. When the pointer or the pen comes within half that
distance of the note, the note slides out of its way on a spring and keeps its side while it fits.

A stroke that ends while live ink listens moves the note to that ink, or opens it there when nothing
has been heard yet. A later stroke moves it to the newest ink, as the release does. The chord's
release gives the note the keys. A menu still open waits for the release, which closes it first.
While it listens the words show at full strength, keys or not, and the empty note shows no prompt.

Let go with words and no ink, and the note stays by the pointer with the keys and the words. It
sends nothing on its own, and `liveInkSendWhenQuiet` waits for ink. An ask is about ink, so Return
there beeps and keeps the note; a stroke drawn on a later hold moves the note to it. Esc closes it.
With nothing heard and no ink, nothing opens. When inking is cut short, by sleep or a screen
change, a note by the pointer closes.

## The waveform

The waveform is ten bars on a fixed grid, 4 pt apart. Each bar is centred on the middle of the
lowercase letters and is never taller than 11 pt, so it stays inside the line. The bars follow the
input's level, which `Microphone` measures in 10 ms slices and `VoiceLevels` plays back at that rate.
Each grid slot has its own shape, so neighbouring bars differ. The middle bars are the strongest, and the bars fade toward
both ends of the waveform.

The words come a letter at a time. Each letter fades in, and the letters are never more than 0.4 s
behind what was heard (`HeardLetters`). The newest word shows lighter until the next one comes,
since the recognizer may still change it. A word it corrects changes in place.

Each letter takes the place of the bars at the waveform's left end, and new bars come in at its
right end, so the waveform rolls along the line. It stays on the line of the last letter shown and
moves down only once a letter is on the next line. At the line's end the bars stop at the edge and
the letters take them. Only the letters shown set the note's height, so the bars never grow or
shrink it.

Once listening ends and the last letter shows, the bars fold into the field's caret over 0.35 s.
Without the keys the note has no caret, and the bars fold away. A key typed in the note shows every
letter and folds the waveform away. With no motion, the letters show at once, the waveform is still,
and it goes at once.

## Limits

Words past the note's five lines are cut off, and the waveform with them.
