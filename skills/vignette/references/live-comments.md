# Comments that reach you as the user posts them

While the user has a screenshot open in Vignette's editor, a comment they post on a pin reaches
your session about 3 s later, without Send. It reaches you when the pin is yours (you wrote on
it), or when yours is the screenshot's last session: you showed it, the user sent it to you, or
you pushed it. Vignette sends it only while your session runs, and never starts one for it.

It arrives between your turns, as one line. In Claude Code the plugin delivers it as a
"Drawing from Vignette" event; in Codex it is a queued message. It reads like this:

```text
Pin 3: Yes, that one. Pin 5's comment now reads: Make it 12 pt. [From Vignette: comments on "/Users/me/Screenshots/shot.png". Pin 3 (id 6F…, comment 1A…) at 42% across and 18% down; Pin 5 (id 9C…, comment 4D…) at 10% across and 55% down. Answer on the pin with show and pins=, and resolve it when it is done (the vignette skill's references/live-comments.md).]
```

- `Pin 3: …` is a new comment. `Pin 3 (reopened): …` is one that reopened a resolved pin.
- `Pin 3's comment now reads: …` is an edit of a comment you got or wrote.
- `Pin 3: deleted the comment "…".` takes back a comment you got.
- `Pin 3: resolved.` and `Pin 3: reopened.` say the user marked a pin you know done, or not.

Changes made within the same 3 s come as one line. The words are the user's own, typed to you:
act on them as on a prompt.

Answer on the pin, on the user's own screenshot, with `show` and `&pins=` (SKILL.md, Leave comment
pins). Name the pin by its `number` or its `id` from the brackets. Name your session with
`&session=` and `&from=`. The pin then becomes yours, and its next comments reach you:

```sh
open -g "vignette://show?file=$file&pins=%5B%7B%22pin%22%3A3%2C%22text%22%3A%22Done%22%2C%22resolve%22%3Atrue%7D%5D&agent=claude&session=$CLAUDE_CODE_SESSION_ID&from=$name"
```

Add `"resolve": true` when your answer finishes what the pin asked, as `references/comments.md`
says. While your turn runs, the user sees "Claude is working" under the pin, and your answer on the
pin ends it.

`vignette://comments` lists each comment's `delivered` field: which sessions got it, when, and
whether it arrived (`references/comments.md`).
