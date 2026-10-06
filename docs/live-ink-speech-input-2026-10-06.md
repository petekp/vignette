# Live ink: speech input (2026-10-06)

Status: steps 1 and 2 are built on `live-ink` and pass the unit tests. Nothing has been heard yet:
the microphone needs the entitlement below, and the recognizer needs its permission.

## What it does

You talk while you draw. Your words appear in the note beside your ink as you say them, and
"this" and "that" are tied to what you were drawing when you said them. Speech is turned into words
on the Mac and never leaves it. This is the first step on speech in `docs/vision.md`.

## Decided

- **On device only.** Audio never leaves the Mac, which keeps the principle that only what the
  person pointed at leaves it.
- **Apple's `SFSpeechRecognizer` first**, behind an interface that another engine can replace. It
  is the on-device recognizer that runs on macOS 15. `docs/live-ink-apis-2026-10-04.md` has its
  limits, and the options compared are in the conversation of 2026-10-06: Apple's `SpeechAnalyzer`
  (macOS 26), Parakeet through FluidAudio, WhisperKit, and cloud services.
- **Two experiments**, each with a switch, so both ways can be tried:
  1. **When listening ends:** when you let go of ⌃⌥, or when you pause after letting go.
  2. **When the ask is sent:** when you stop talking, or when you press Return.

## The parts

### 1. The transcriber, which can be replaced

`Transcriber` is a protocol: it takes audio buffers and answers timed words, partial while you speak
and final at the end. Each engine is one file that conforms to it.

The microphone is kept out of it. Every engine considered takes PCM audio, but each has its own way
of being fed. With the microphone outside, a recorded file can be fed through any engine in place of
a voice, which is how the engines are tested and compared.

```swift
struct SpokenWord { let text: String; let start: TimeInterval; let duration: TimeInterval }

protocol Transcriber: AnyObject {
    /// The format `append` takes; the microphone converts to it.
    var format: AVAudioFormat { get }
    /// Words partial so far, each time they change.
    var onWords: (([SpokenWord]) -> Void)? { get set }
    /// `hints` are words likely to be said, such as the text on the window under the ink.
    func begin(hints: [String]) throws
    func append(_ buffer: AVAudioPCMBuffer)
    /// The final words, once the audio so far is transcribed.
    func finish() async -> [SpokenWord]
    func cancel()
}
```

`AppleTranscriber` is the first engine. It sets `requiresOnDeviceRecognition`, and fails when the
Mac has no on-device model rather than sending audio to Apple. It passes the hints as
`contextualStrings`, so a word on the page, such as "Arno", can be primed before it is said. Times
come from each segment's `timestamp` and `duration`. `SpeechEngine.make` is the one place that
picks the engine.

Live ink passes no hints yet. Listening starts as the glow shows, before the first stroke, and the
window's text is read after it. Priming would mean holding the audio until the text is read, then
starting the request with it.

### 2. The microphone

`Microphone` taps `AVAudioEngine`'s input, converts each buffer to the transcriber's format, and
reports the level, which the pause check reads. It runs only while listening. macOS shows its orange
microphone dot in the menu bar for exactly that time, which is the honest sign that Vignette is
listening.

### 3. Listening in live ink

- **Listening starts** when you press ⌃⌥, if speech is on, so a word said as the first stroke begins
  is heard.
- **Words appear in the note.** The note opens when you let go, as it does now, already holding what
  you said while drawing. After that it fills as you speak. Typing in the note stops listening: the
  keyboard wins.
- **Listening ends** by the first experiment:
  - *On release:* 0.3 s after you let go of ⌃⌥, which catches the end of the last word.
  - *On a pause:* after you let go, once the level stays under the speech threshold for
    `ui.liveInkSpeechPause`, 1.2 s to start.
- **Sending** follows the second experiment:
  - *When you stop talking:* the ask goes as Return would send it, to the note's target.
  - *On Return:* the words wait in the note, where you can fix a misheard word first.
- **Nothing said** leaves the note as it is now, waiting for typing.

### 4. Tying words to ink

Each mark the person draws records when it was drawn. When the ask goes, Vignette numbers the ink
and puts each number into the words where it was drawn: "make this [2] the same size as that [3]".
The agent reads that as language and resolves "this" itself. The ink in the ask's `ink` list
carries the same numbers.

The responder's ask has the ink as a list, so the numbers work there. An ask sent to a session
carries only the picture and one line, and its picture has no numbers on the ink. Step 3 decides
whether to draw numbers into that picture or send the words without them.

### 5. Permissions and the build

- **The microphone entitlement.** Vignette runs with the hardened runtime, which blocks the
  microphone unless the app has `com.apple.security.device.audio-input`. project.yml gains an
  entitlements file with that one key. This changes what every signed build may do, so it needs
  Pete's approval.
- **Usage strings.** `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` in
  project.yml, written to `docs/voice.md`.
- **Prompts come from a press.** A "Speak while you draw" switch under Live ink in Settings raises
  macOS's microphone and speech recognition prompts when turned on, as the Live ink switch raises
  Screen Recording's. A refused permission shows a row like the Screen Recording one. Nothing asks at
  launch.

### 6. The switches

| Key | Values | Default |
|---|---|---|
| `liveInkSpeech` | on or off | off |
| `liveInkListenUntil` | `release` or `pause` | `pause` |
| `liveInkSendWhenQuiet` | on or off | on |
| `ui.liveInkSpeechPause` | seconds | 1.2 |

Settings shows the last three under the speech switch while the experiments run. Once each is
decided, its switch and key go, and the chosen behaviour stays.

## Checking it

- **Without a microphone.** `.scratch/speech-check/check <audio> [hint …]` feeds a recorded file
  through an engine and prints each word with its time; `say -o` makes the recordings, so engines
  can be compared on the same audio. Apple's recognizer needs the Speech Recognition permission even
  for a file, so its first run raises that prompt once. A debug command that feeds a file through
  live ink as if spoken is not built.
- **Unit tests.** Putting ink numbers into the words, and the pause check.
- **By voice.** Pete tries it with the microphone.
- **What to measure.** Words misheard, especially words on the page; the time from the last word to
  the words showing; and how far "this" falls from its stroke in time.

## Steps

1. The transcriber, the Apple engine, the microphone, and the file check.
2. Listening in live ink: words in the note, and both experiments.
3. Tying words to ink, and the session route.
