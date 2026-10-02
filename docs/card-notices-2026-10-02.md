# Card notices: one module for what a card says

Status: built 2026-10-02, in `Sources/CardNotices.swift` and `Tests/CardNoticesTests.swift`.

## Conclusion

`ThumbnailController` hands one of its jobs to a module, `CardNotices`. The job is the news a card
shows after something happened to it: Copied, Not copied, and where a send went. The rules for
that news were spread over six methods, three stores, three expiry timers and three overlays.
Because of that spread, two notices could be drawn on top of each other, and a mark could expire
early.

`CardNotices` is a pure value with four members. It keeps what each card shows apart from
the sends still waiting for an answer, so a failure is never lost behind a newer notice. The
controller keeps the parts that need
windows: bringing a card up as the lone thumbnail, and timing the corner.

Below, *module*, *interface*, *seam*, *depth* and *locality* are used in the sense of the
codebase-design skill. A module's interface is everything a caller must know to use it, including
its rules and its error cases. A module is deep when a small interface hides a lot of behaviour.

## Why `ThumbnailController`

At 1,643 lines, it is the largest coordinator in the app. Its jobs:

1. The panel's life: `present`, `insert`, `shiftUp`, `dismiss`, `leaveCorner`, and three generation
   counters that cancel stale timers.
2. Running the annotation run's effects, across nine closures to `AnnotationController` and six
   calls back from it.
3. The marks a flight carries (`flightMarks`, `outFlightMarks`, `homeFlightMarks`, `parkedMarks`).
4. Card notices: Copied, Not copied, and the send marks.
5. Selection, the drag-select, its auto-scroll, and the stack's keys.
6. Reading the Dock and laying out the panel.
7. Making cards, decoding them, reading their drawings, and reshaping them.
8. A stitch's pieces converging into one card.
9. The `[state]` report.

Several pure parts have already moved out into deep modules: `AnnotationRun`, `StackLayout`,
`FlightPress`, and `StackModel`'s selection. Each has its own tests. Job 4 is the clearest one
left: it is in-process logic with no window in it, and it has no tests.

## What was wrong

Two comments in the controller said a newer notice replaces an older one. Nothing enforced that
in one place. Each notice has
its own store, keyed differently:

| Notice | Store on `StackModel` | Key | Expiry check |
| --- | --- | --- | --- |
| Copied | `copied: Set<UUID>` plus one shared `copiedLabel` | card id | none |
| Not copied | `notCopied: [String: String]` | file path | the reason text is unchanged |
| Send | `sendMarks: [String: SendMark]` | file path | the request id is unchanged |

Each method clears some of the other notices, and some pairs are missing:

- `showCopied` clears Not copied but leaves a send mark in place.
- `markSending` clears Copied but leaves Not copied in place.
- `showNotCopied` clears Copied, through `takeBackCopied`, but leaves a send mark in place.

`CardView` drew three separate overlays. Each one covers the whole
card in black at 55% opacity with its words in the middle. So when a pair was missed, the card was
dimmed twice and two sets of words overlap. Example: send a card, and press ⌘C on it while its
"Sent" mark is up.

The expiry checks have holes too:

- **Copied.** The timer removes the card ids whatever was posted later. Press ⌘C twice, a second
  apart: the first timer takes the second mark down about a second early.
- **Not copied.** Two failures with the same reason are indistinguishable, so the first timer
  clears the second one early.
- **Send.** Correct, because it compares the request id.
- **The label.** `copiedLabel` is shared, so ⌘⇧C, which says "Copied Path", relabels a card still
  showing an earlier "Copied".

Knowledge that belongs to the notices also leaks into other code:

- `showsMark(_:)` and `leaveCorner`'s `delivering` check each read the three stores directly.
- `showsButtons` in `StackView` does the same.
- The hold rule is computed in three places: `markSeconds + expandDuration`, three times as long
  when the notice explains something.

None of these bugs is urgent. Together they show what the spread costs: whoever adds a kind of
notice has to change four or five places, and a reviewer cannot check the rule in one read.

## The rule

A card shows one notice at a time, and the newest wins. A send waiting for its answer is the
exception that makes this hard. The person can copy the card while the send is still out, and
the Copied notice then takes the card's one place. The send's answer must still be heard when it
arrives, above all a failure, which nothing else would report. So the module keeps two things
apart:

- **What the card shows:** one notice per file.
- **Which sends are waiting:** one request per file, kept until its answer comes, whatever the
  card shows meanwhile.

An answer to the waiting request is news, so it is posted as the newest notice. An answer to any
other request is dropped.

## The module

```swift
struct CardNotices {
    /// What a card shows.
    enum Notice: Equatable {
        case copied(label: String)
        case notCopied(reason: String)
        case send(SendMark)

        enum Kind: Hashable { case copied, notCopied, send }
        var kind: Kind
    }

    /// What happened to a file.
    enum Event: Equatable {
        case copied(label: String)
        case notCopied(reason: String)
        case sending(request: String, client: AgentClient, project: String)
        case answered(request: String, state: SendMark.State, reason: String?)
        case replyFailed(request: String, client: AgentClient, reason: String)
    }

    /// `hold`: when to call `expire(_:on:)`, nil while a send waits for its answer.
    struct Posted: Equatable { let id: Int; let hold: TimeInterval? }

    /// Nil when there is nothing to show: an answer to a request that is not the one waiting, a
    /// failed reply while a later send waits, or a send that worked on a card nobody will see.
    mutating func post(_ event: Event, on file: String, seen: Bool, markHold: TimeInterval) -> Posted?
    /// Takes a notice down if it is still the one `id` posted.
    mutating func expire(_ id: Int, on file: String)
    func notice(on file: String) -> Notice?
    /// A send on one of `files` is still waiting for its answer, so the corner stays.
    func awaitsAnswer(on files: some Sequence<String>) -> Bool
}
```

Four members. What happened goes in as an `Event`, and what the card shows comes out as a
`Notice`. They differ because an answer names only its request: the module fills in the client
and project from the send that is waiting. `markHold` is `ui.markSeconds + ui.expandDuration`,
read at each call, so a tweak reaches the next notice. Behind the four members sit these rules:

- **The newest wins** what the card shows, so no two overlays can stack and no pair can be missed.
- **A waiting send keeps its claim** to its answer, whatever the card shows meanwhile.
- **Tokens guard expiry.** `expire(_:on:)` is checked against the posting that set the timer. That
  fixes both early-expiry holes in one place, the same way the send mark already works.
- **Each kind has its own hold.** A notice that explains something is held three times as long.
  Not copied explains something, and so does every send state but sending and sent. Sending has
  no hold.
- **A card nobody sees says nothing about a send that worked.** That answer is dropped, and the
  sending mark goes with it. `seen` comes from the caller, because only the controller knows what
  is on screen.

The controller keeps two helpers. `isSeen(_:)` is true when the card is on screen or in the
annotator, since a card in the annotator comes home wearing whatever was posted meanwhile.
`post(_:on:)` reads it, posts the notice, and calls `show(shot)` for a card nobody sees. It then
schedules `expire(_:on:)` after `hold`, and calls `leaveCorner(after: hold)`. Its public methods (`showCopied`, `showNotCopied`, `markSending`,
`delivered`, `replyFailed`) keep their signatures, so `AppDelegate` does not change.

Two controller rules stay outside the module:

- **A copy of several files** that are all off screen brings up only the first, labelled
  "Copied 3". That is a choice about the corner, so `showCopied` keeps it: it brings up the first,
  then posts a notice on each file whose card is seen.
- **A failed copy** still sends `.copyFailed` to the run, because a card on its way home must not
  take the mark. `showNotCopied` does it. `takeBackCopied`, whose only caller that was, is gone,
  and the Not copied notice replaces the Copied one.

`StackModel` holds `@Published var notices = CardNotices()` instead of the three stores and
`copiedLabel`. `CardView` reads `model.notices.notice(on: path)` and draws one overlay with a
`switch` whose branches are the notice's kinds, so one kind cross-fades into the next and a send
keeps its overlay while its state changes. The `[state]` report
keeps its `copied` and `notCopied` keys, derived from the notice, because the e2e scenarios read
`copied` (`scripts/e2e/scenarios.py:305` and `:671`).

### Seam and tests

All of the module's dependencies are in-process: no I/O and no clock. Time comes in as `expire`
calls, which the caller schedules. That means no adapter and no port, and the tests drive the
interface directly.

`CardNoticesTests` covers:

- A copy, a send, and a failed copy on one file: each replaces the one before, and only the last
  is shown.
- A copy while a send waits, then a failed answer: the failure is shown.
- Two copies in a row: expiring the first posting's id leaves the second in place.
- Two failures with the same reason: the same.
- An answer for an old request is dropped.
- A failed reply does not replace a send still waiting, and it does replace a finished one.
- Which answers a card nobody sees still shows, and the `hold` for every kind and every send
  state.

These are permanent tests, because the rule is a contract that a future notice could break, and
nothing covered it before. The e2e scenarios check only that a stitched or finished card is marked
copied.

### The alternative not taken

The bugs alone could have been fixed in place, in about fifteen lines: the missing clears, a token
for each of the two timers, and a label per card. That keeps three stores and pairwise clearing,
so the next kind of notice would again have to remember every pair, and the waiting-send rule
would stay untested. That rule is the easiest one to break: treating a send like any other notice
loses its failure.

### Decisions

Pete decided both on 2026-10-02:

- **A card shows one notice at a time.**
- **The Copied notice is keyed by file path**, like the other two. A stack reopened within the
  copied mark's hold, about 2 s, shows the mark again on that file's card, as a send mark does.

## Other candidates

- **The annotator handover** (job 2) is the next candidate. Whether the flight into the editor can
  lift depends on three moments: `arrived`, `editorLoaded` and `annotatorTakesEvents`. The state
  for them is split over `loadedKeys`, `takingEvents`, `run.key` and the flight layer. That gate
  could be a small pure value, the way `FlightPress` is. The nine closures to `AnnotationController`
  have one adapter, so wrapping them in a protocol would add a layer and gain nothing. The gate is
  worth extracting; the closures are not. That needs its own proposal.
- **Flight marks** (job 3) are a set of helpers that share state through `parkedMarks`. Moving
  them out alone would only relocate them.
- **The panel's life** (job 1) is mostly windows and SwiftUI transactions, and it is covered by
  the e2e suite rather than unit tests.

## Cleanup in passing

`ThumbnailController.swift:24-26` has a doc comment about the selection strip's labels. It is
stranded above `SendMark` and describes nothing there. It should go with this change.
