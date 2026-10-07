# What a live-ink ask costs (2026-10-06)

An ask about a new screen costs 1 to 4 cents at API prices. Most of that is the new screen being
written into Claude's prompt cache, and in a terminal the window's text cost more than the
pictures. Sending that text as plain lines instead of JSON halved its tokens, and sending only the
lines nearest the ink halves a terminal's again. On a Claude subscription the cost is plan usage,
not money.

## How the responder is billed

- **The log gives each ask's own numbers.** `claude -p` reports `total_cost_usd` on each `result`
  line as the conversation's total so far, so the responder logs the difference from the line
  before. The `usage` on the same line is the ask's own. One line per answer:

  `[live-ink] answered ms=… firstToken=… firstWord=… cost=… input=… written=… read=… output=… thinking=… marks=…`

  | Key | What it is |
  |---|---|
  | `ms` | The turn, as `claude` measured it |
  | `firstToken` | From sending the ask to its first output of any kind, in ms: the reading of the prompt and the screen |
  | `firstWord` | From sending the ask to the reply's first word, in ms |
  | `cost` | This ask's own cost in dollars at API prices |
  | `input`, `written`, `read` | Input tokens: plain, written to the cache, and read from it |
  | `output`, `thinking` | Output tokens, and how many of them were thinking |

  A late `firstToken` means the screen took long to read. A gap from `firstToken` to `firstWord`,
  with `thinking` above 0, is thinking.
- **Claude Code caches the conversation.** On a Claude subscription it uses the 1-hour cache, and
  with an API key the 5-minute cache. `CLAUDE_CODE_PROMPT_CACHE_TTL=5m` or `1h` overrides it.
- **The responder runs on the 5-minute cache** (`LiveResponder.promptCacheTTL`). Asks come less
  than a minute apart, so the 1-hour cache's longer life bought nothing, and its writes cost 60%
  more. Each request renews the cache for another 5 minutes, so the responder stops 4.5 minutes
  after its last request (`LiveResponder.idleLimit`). Kept longer, its next ask would write the whole
  conversation into the cache again. The cost is that an ask more than 4.5 minutes after the one
  before starts a new conversation, without Claude's earlier answers.
  - Checked with `claude` 2.1.292 and the responder's flags: with the variable set, the warm-up
    wrote 2,597 tokens to the 5-minute cache and none to the 1-hour one, and the next ask read
    them back.
- **A cache write costs more than plain input, and a read much less.** For Sonnet 5.5, per million
  tokens:

  | Input | Output | 1-hour write | 5-minute write | Read |
  |---|---|---|---|---|
  | $2 | $10 | $4 | $2.50 | $0.20 |

- **The warm-up shows the cache working.** It costs $0.001 when the prompt is already cached, and
  $0.006 to $0.01 when the prompt is written.

## What an ask sends, in tokens

Measured with `claude -p` and the responder's flags, a synthetic picture, and 129 lines of Swift
source standing in for a terminal's text. Each figure is the turn's `cache_creation_input_tokens`
less an empty turn's 108.

| Part | Tokens |
|---|---|
| The picture, at `Stitch.readerScale`'s cap | 1,570 |
| The close-up, for a window too large to read whole | up to 1,570 |
| 129 text lines as JSON objects, as sent until this change | 6,500 |
| The same lines as plain lines: id, box in thousandths, words | 3,650 |
| The same lines with only x and y | 3,140 |
| The words alone | 2,320 |

JSON repeated each key on every line, wrote each coordinate as `0.034`, and escaped every quote in
the text. That overhead was larger than the words themselves.

Asks from the log of 2026-10-05, before the change, each its own cost:

| Ask | Cost |
|---|---|
| A terminal, 129 to 135 lines, new screen | 3.7¢ and 4.4¢ |
| A window with 6 lines, new screen | 2.1¢ and 2.5¢ |
| A follow-up on the same screen, no picture | 0.75¢ to 1.4¢ |

## The packet's shape

- **The window's text** is its own text block after the pictures, one line of the window per line:
  `t2 12 34 640 14 error: cannot find 'packet' in scope`. That is the line's id, its box in
  thousandths of the picture, then its words (`LivePacket.textLines`).
- **Only the lines nearest the ink go, up to 4,500 characters** (`LivePacket.lines(near:)`). A
  window with less text sends all of it. The cap is in characters because the characters are the
  cost: Vision splits some rows into pieces, and a line of code can be ten times a prompt's length.
  - Ids still number every line Vision read, in reading order, so they stay the same across
    follow-ups. An answer's `line` counts only when it names a line that was sent, since a guessed
    id would land on a line Claude never saw.
  - Claude still sees far text in the picture. It points at far text by copying the words, which
    Vignette looks for in every line it read, or by a `box`.
  - New ink on the same window, showing the same text, sends no picture, only the nearby lines not
    sent yet.
  - The packet no longer stops reading at 300 lines. That cap kept the first 300 in reading order,
    so a dense window lost its bottom, where a terminal's newest output is.
- **The JSON comes last**, so the note comes after the pictures and the text. It holds the app, the
  window's title, the location, the note, the ink and the close-up's box. Its keys are sorted and its
  slashes are not escaped.
- **Boxes and points are in thousandths of the picture, both ways.** The responder's boxes become
  fractions at its edge (`LiveAnswer(responder:)`). A session's answer still gives fractions, as the
  skill tells it to.
- **The prompt says what the close-up and a follow-up are.** The packet carries only data.
- **The answer's schema is fixed text with `say` first** (`LiveAnswer.schema`). Built from a Swift
  dictionary, its property order changed from launch to launch: five launches gave five orders. That
  also changed the cached prompt with every Vignette launch.

It was checked end to end with a synthetic terminal window through the real packet code and the
real responder. Claude named the error line by its id. Its box round a red square came back as x
0.553, y 0.486, width 0.049, height 0.075, for a square at 0.556, 0.489, 0.044, 0.071. The reply
began streaming 0.7 to 1.1 s before each answer ended.

The nearby lines were checked on rendered windows read by the real Vision code:

| Window | Lines read | Sent |
|---|---|---|
| 129 rows of Swift, ink near the bottom | 140 | `t70` to `t140`, 47% of the characters |
| 100 rows of a load test, ink round the failed request | 303 | 149 lines, the circled one among them |

The second was also asked of Claude with the responder's flags, as "why did this one fail? show me
the cause". The cause, `REQUEST_TIMEOUT_MS=500`, was 94 rows above the ink and not among the lines
sent. Claude read it from the picture, circled it with a `box`, and named the error under the ink
by its id. The ask wrote 8,416 tokens to the cache and cost 3.6¢ at API prices.

## Open

- **Why a reply starts 1.5 to 5 s after an ask** with a picture, where a text-only ask's first words
  came at 0.7 s. The log's `firstToken`, `firstWord` and `thinking` can now say whether it is the
  reading of the screen or thinking. No ask has been logged with them yet.
