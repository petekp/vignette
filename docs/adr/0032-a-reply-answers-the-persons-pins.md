# A reply answers the person's pins, on a picture without their numbers

Status: accepted, 2026-11-25. Pete chose this as Choice 5 of
`docs/screenshot-comments-2026-11-24.md` ("Yes, as step 4"), and
`docs/screenshot-comments-2026-11-24/outputs.md` has the plan it came from.

When the person sends a screenshot with pins, the line cites each one ("Pin 3: …") and the request
keeps them as `pins.json`. Before this change an agent could answer only with marks, drawn on the
picture it was sent. That picture has the pins' numbers in its pixels, so the reply card showed
numbers that no longer belonged to any pin. The agent's words about each pin went to its session,
away from the place they were about.

## What a reply may carry

A reply bundle may now carry `comments`, a list of `{"pin": "<id>", "text": "<words>"}`. Each
item is the agent's answer to one of the person's pins:

- The reply helper takes `--comments`: a JSON object, or the path of a file holding one. Each key
  is a pin's number as the line cites it ("3") or its `id` from `pins.json`, and each value is
  the answer's words.
- The helper reads the request's `pins.json`, turns numbers into ids, and refuses a pin the
  request did not send. The bundle always names pins by id.
- One answer per pin per reply, at most 99, each within a comment's 2,000 characters.
- Comments answer pins on the picture that was sent, so they never come with `--image` or
  `--answer`. A reply may carry comments and no marks.
- Vignette checks the comments again when it accepts the reply, against its own copy of the
  request's pins. A pin it did not send is refused as `bad-payload`, naming the pin.

## The picture a reply goes on

A request whose drawing has pins also stores `base.png`: the picture with the person's marks and
no pins. `image.png`, with the numbers, is still the picture the agent reads.

A reply without its own image is drawn on `base.png`. Its card holds the request's pins as live
pins, with the same ids, numbers, places and comments. Each answer is added to its pin as the
agent's comment, timed when Vignette accepted the reply. Recovery rebuilds the same drawing from
that time. The card's next new pin takes the number after the highest one.

A request without `base.png` works as before. That is a request without pins, or one stored by a
build from before this change. Its replies are drawn on `image.png`, and their cards hold no pins.
A reply with comments to such a request is refused, since it has no live pins to answer.

## The protocol

`ReplyProtocol.version` goes from 6 to 7, since the bundle gains a field. A helper from an older
skill is refused with `protocol-mismatch`. A request stored before the update carries a version 6
ticket, which the new helper refuses, so the person sends it again.

The logs name the counts: `[reply] <id> accepted for <request> marks=<n> comments=<n>` and
`[reply] published <file> marks=<n> pins=<n>`.

## What was weighed

- Answers as text marks beside each pin. These need no new format, but the words lose their pin:
  a move or a copy does not carry them together, and the list in Copy and Send leaves them out.
- Drawing the reply on `image.png` with live pins on top. Each number would show twice, once in
  the pixels and once on the live teardrop.
- Naming pins by id only, as `outputs.md` first said. The line cites numbers, so the agent would
  have to open `pins.json` to answer. The helper reads it instead.
- New pins in a reply, as `add`'s `pins=` makes them. Nobody asked for that. An agent places
  new pins on the person's screenshot with `show`, or on its own with `add`.
