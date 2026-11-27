# How Vignette speaks: pins

These are the words for pins in the editor, written to the rules in [voice.md](voice.md). The words
for a comment that goes to an agent session as it is posted are in
[voice-live-comments.md](voice-live-comments.md).

| Where | Words |
| --- | --- |
| The popover's field, empty | Reply, on a pin with comments; Comment, on a new pin |
| The post button inside it, its tooltip and to VoiceOver | Post comment |
| The field, to VoiceOver | Comment on pin *n*; Comment on new pin |
| A comment's trash button, its tooltip and to VoiceOver, and the comment's VoiceOver action | Delete comment |
| A comment's contextual menu | Delete Comment |
| A comment, to VoiceOver, as a hint | Edit this comment |
| Who wrote a comment, beside their avatar and above their words (`PinHoverCard.Words.writer`) | You; Claude, the agent's name capitalized; An agent |
| A comment's row, to VoiceOver | You: *words*, then Edit this comment |
| A pin's first comment posted, to VoiceOver | Pin *n* added |
| A pin, to VoiceOver | Pin 3, area, 2 comments; Pin 1, point, 1 comment; New pin |
| A selection with pins, to VoiceOver | 2 pins; 1 mark and 2 pins |
| The rotor and the action | Pins; Add Pin |
| A pin's row in a cluster's or the toolbar's menu, to VoiceOver (`EditorView.pinListItem`) | Pin 3, area, 2 comments: *first comment* |
| The toolbar's button, its tooltip, and to VoiceOver (`ToolbarView.pinsButton`) | Pins, beside a badge with the count; Pins; Pins, *n* |
| The card a pin grows into under the pointer, its writer (`PinHoverCard.Words`) | You; Claude, the agent's name capitalized; An agent |
| Beside the writer | Pin 3 · 1 min. ago, in `RelativeDateTimeFormatter`'s abbreviated style; Pin 3 for a comment that kept no time |
| Under the first comment's first line, on a pin with replies | 1 reply from Claude; 2 replies from you; 3 replies, from more than one writer |
| After the replies, on a resolved pin | Resolved by Claude; Resolved by you |
| The ✓ on an open pin's first comment, its tooltip (`ResolveAction`) | Resolve pin. It turns grey and is left out of copies and Send.; Post your reply and resolve the pin, while the field holds words |
| The ✓ on a resolved pin's first comment, its tooltip | Reopen |
| The ✓, to VoiceOver, and the comment's VoiceOver action | Resolve pin; Reply and resolve pin; Reopen pin |
| Over a resolved pin's comments (`PinResolveControls`) | Resolved by Claude, 1 min. ago |
| A resolved pin's field, empty | Reply to reopen |
| A pin resolved or reopened, to VoiceOver, and its actions | Pin *n* resolved; Pin *n* reopened; Resolve; Reopen |
| A resolved pin, to VoiceOver | Pin 3, area, 2 comments, resolved |
| The Pins menu's heading over resolved pins | Resolved |
| The toolbar's button with every pin resolved, to VoiceOver | A checkmark for the badge; Pins, 0 open, 3 resolved |
