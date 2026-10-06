# Live ink: workflows worth building (research, 2026-10-05)

Live ink means drawing on the live screen and getting an answer drawn back in place. This note
ranks the workflows that would benefit most from it. It takes the measured limits as given
(`docs/live-ink-integration-2026-10-04.md`, `docs/live-ink-anchoring-spike-2026-10-04.md`):

- The responder answers in about 2 s.
- It has no tools. It knows only the packet: a capture, OCR lines with ids, the ink, and the app,
  window and URL.
- Chromium apps give coarse Accessibility positions.
- Marks hide while content scrolls.

Each claim is marked as either what a source shows or what I infer. Ratings are mine.

## Build these first

1. **"Check this" on numbers and text you can see.** Loop a total, a date, a clause or a cell, and
   ask whether it is right. The answer loops the lines that prove or disprove it. This fits the
   responder as it is: the step 2 trial already found a $3.61 error and marked its evidence. It
   applies to dashboards, invoices, forms, spreadsheets and papers.
2. **Guided steps for "where do I click".** The answer is a sequence of marks. Each mark advances
   when the person clicks its target. The spike built this in Safari. Microsoft ships the same idea
   as Copilot Vision "Highlights". The best study found stencil-style tutorials 26% faster.
3. **Ink handed to a coding session, with the source attached.** Loop a button in your running app
   or an error in the terminal. The session gets the ink, the packet and a pointer into the source.
   This is the highest-value developer workflow. It needs a source lookup and a way for a session's
   reply to come back as live marks.
4. **Explain this in place.** Loop a stack trace line, a dense sentence, a term in a foreign-language
   UI or a form field. The answer underlines the words that matter and notes what they mean. It
   works now, with word-level marks and terminal-line anchors.
5. **Ask back by looping two candidates.** When the ink is ambiguous, the answer loops both
   candidates. The person taps one. This is cheap to build, and it makes every workflow above more
   reliable.

Why these: 1, 4 and 5 run on the responder as it is today. 2 builds on code the spike already
proved. 3 is the most valuable, but it needs the most new work.

## What the evidence says about pointing and drawing

- **Pointing makes speech shorter.** Bolt's "Put-That-There" (1980) let people say "that" and
  "there" while pointing, "with a corresponding gain in naturalness and economy of expression"
  ([MIT Media Lab](https://www.media.mit.edu/publications/put-that-there-voice-and-gesture-at-the-graphics-interface/)).
- **Drawing beats a cursor.** In remote physical tasks, Fussell et al. found that gesture tools
  "need to be able to convey representational as well as pointing gestures to be effective"
  ([CMU](https://kilthub.cmu.edu/articles/journal_contribution/Gestures_Over_Video_Streams_to_Support_Remote_Collaboration_on_Physical_Tasks/6470090/1)).
  I infer that a drawn arrow or loop in the answer does more than a highlight box.
- **Acting on the thing beats describing it.** DirectGPT users edited text, code and images 50%
  faster, with 50% fewer and 72% shorter prompts, than with plain ChatGPT
  ([arXiv](https://arxiv.org/abs/2310.03691)).
- **Sketches carry edit intent.** Code Shaping (CHI 2025 best paper) let programmers sketch over
  code, and an AI turned the sketch into edits ([arXiv](https://arxiv.org/abs/2502.03719)).
  Penquiry let students ask about study material by writing on it with a pen. It "significantly
  reduces the cognitive and physical overhead of inquiry" ([arXiv](https://arxiv.org/abs/2609.19870)).
- **In-place help works.** Stencils-based tutorials were 26% faster, with fewer errors and less
  need for a human helper, and learning was the same as with paper
  ([CHI 2005](https://dl.acm.org/doi/10.1145/1054972.1055047)). Pause-and-Play kept a video tutorial
  in step with the app ([Adobe Research](https://research.adobe.com/publication/pause-and-play-automatically-linking-screencast-video-tutorials-with-applications)).
- **Choosing the right element is the hard part.** On GuideWeb, frontier models picked the right
  guide targets on web pages at 23 to 25% F1, and the best agent reached about 31%
  ([arXiv](https://arxiv.org/abs/2602.01917)). That task has no ink, so the model must guess the
  person's intent. I infer that live ink narrows the search, and that guided steps should start in
  apps whose Accessibility tree is good.
- **Anchors get lost.** Brush et al. studied what people expect when the text under an annotation
  changes ([MSR](https://www.microsoft.com/en-us/research/publication/robust-annotation-positioning-in-digital-documents/)).
  Hypothesis stores three kinds of anchor and shows the ones it loses in an "orphans" tab
  ([fuzzy anchoring](https://web.hypothes.is/blog/fuzzy-anchoring/),
  [orphans](https://web.hypothes.is/blog/showing-orphaned-annotations)).

## What exists in products

- **Pointing in, answer in a panel.** Circle to Search, Raycast Screen Awareness and ChatGPT
  "Work with Apps" take a region or a window and answer in a separate panel
  ([Raycast](https://manual.raycast.com/ai/screen-awareness),
  [OpenAI](https://help.openai.com/en/articles/10119604-work-with-apps-on-macos)). Windows Click to
  Do offers actions on recognized screen content
  ([Microsoft](https://eus.prod.support.services.microsoft.com/en-us/windows/click-to-do-in-recall-do-more-with-what-s-on-your-screen-967304a8-32d1-4812-a904-fad59b5e6abf)).
  Of 9to5Google readers who answered a poll, 48.8% used Circle to Search at least daily
  ([9to5Google](https://9to5google.com/2024/04/01/heres-how-often-9to5google-readers-use-circle-to-search/)).
  That poll is self-selected.
- **The answer drawn in place.** Only two shipped examples turned up. Copilot Vision "Highlights"
  shows where to click ([Microsoft](https://blogs.windows.com/windowsexperience/2025/06/12/copilot-vision-on-windows-with-highlights-now-available-in-us/)).
  Circle to Search's "scroll and translate" replaces text in place as you scroll
  ([GSMArena](https://m.gsmarena.com/googles_circle_to_search_now_translates_while_you_scroll-news-69357.php)).
- **Click an element, brief an agent.** React Grab copies the file, component and HTML of the
  element under the pointer ([react-grab.com](https://react-grab.com)). Agentation turns clicked
  elements and notes into grep-friendly selectors for an agent ([agentation.dev](https://agentation.dev)).
  Cursor's visual editor edits code from a clicked element
  ([Cursor](https://cursor.com/blog/browser-visual-editor)). All three need the DOM, inside a
  browser they control.
- **Review comments on the running product.** Vercel pins comments to elements of preview
  deployments ([Vercel](https://vercel.com/docs/comments)). Figma pins comments only to coordinates
  on a top-level frame, and users have asked for years for pins on nested layers
  ([forum](https://forum.figma.com/t/keep-comments-pinned-to-design-elements-including-nested/4632?page=8)).
- **Explaining a selected value.** Tableau's Explain Data explains one selected mark
  ([Tableau](https://help.tableau.com/current/pro/desktop/en-us/explain_data_basics.htm)). Gemini in
  Sheets explains and fixes a formula error in one click
  ([Google](https://workspaceupdates.googleblog.com/2026/06/troubleshoot-formula-errors-in-sheets.html)).
- **Agents shown at work.** Claude in Chrome can ask before each action
  ([Anthropic](https://support.claude.com/en/articles/12902446-claude-in-chrome-permissions-guide)).
  Magentic-UI adds "action guards", which ask before an irreversible step
  ([MSR](https://www.microsoft.com/en-us/research/blog/magentic-ui-an-experimental-human-centered-web-agent/)).
  I found neither one marking the element it is about to act on in the person's other apps.

What I infer: products either take a point and answer elsewhere, or answer in place with no point.
Live ink would do both, in any Mac app.

## Workflows by who does them

Ratings: **V** is value (high, medium, low). **F** is feasibility now, given the measured limits.

### Developers

- **UI element to source, for a coding session.** Who: frontend developers, many times a day.
  Today: they describe "the blue button in the sidebar" or use a browser-only picker. What live ink
  changes: one loop works in any browser, simulator or native app, and the session gets the element
  with it. Needs: a source lookup, for example React Grab's data from a dev page, or `AXDOMIdentifier`
  and the visible text used as a grep key; and session replies drawn live, which decision 6 defers.
  V high, F medium.
- **Terminal errors and logs.** Who: every developer, daily. Developers spend about 58% of their
  time on comprehension ([Xia et al.](https://researchportalplus.anu.edu.au/en/publications/measuring-program-comprehension-a-large-scale-field-study-with-pr/)).
  Today: copy the trace into a chat. What changes: loop the failing line, and the answer underlines
  the frame that matters. Needs: nothing for the explanation, since terminal-line anchors exist;
  a session for the fix. V high, F high.
- **PR diff review.** Who: reviewers, a few times a day. Today: they read the hunk in GitHub and
  open the file to see context. What changes: loop a hunk and ask "is this safe?". The answer marks
  the risky lines. Needs: repository context, which only a session has, and stable anchors in a
  Chromium diff view. V medium, F medium.

### Designers

- **Running product against a Figma frame.** Who: designers and design engineers, at every review.
  Today: screenshots side by side and comments in Figma or Linear. What changes: draw a line from
  the Figma frame to the build, and the answer marks each difference on the build. Needs: a packet
  that covers two windows. Today it covers the window under the ink. V high, F medium.
- **Spacing and alignment checks.** Today: inspector overlays and manual measuring. Needs: Vignette
  to measure edges in the capture itself. I infer a model reading a 1568 px image is not reliable
  to the pixel. V medium, F low.

### Data

- **A dashboard number that looks wrong.** Who: analysts and managers, weekly. Today: they open the
  query or ask the owner. What changes: loop the number, and the answer checks it against the
  visible numbers and marks the ones that disagree. Needs: nothing for visible arithmetic. A query
  needs tools. V high, F high for visible checks.
- **Spreadsheets.** Panko's compiled audits found significant errors in roughly 80 to 90% of
  spreadsheets, though with uneven definitions ([summary](https://arxiv.org/abs/0808.2045)). The grid
  shows values, not formulas. Whether Excel or Numbers exposes a cell's formula through
  Accessibility is unverified. V high, F medium.

### Reading and learning

- **Dense docs, papers, and legal or financial forms.** Loop a clause or a field to have it
  explained, or to cross-check it against another line on the page. The answer marks the lines it
  used, so the person can check it. V high, F high, inside one window.
- **Foreign-language UI.** Loop a label to get its translation drawn beside it. Circle to Search
  shows demand. V medium, F high.

### Everyday Mac use

- **Settings hunting.** Who: everyone, occasionally. Today: a web search, then a hunt through
  System Settings. What changes: "turn off X" draws step 1 on the screen and waits for the click.
  Needs: multi-step marks across window changes, and a check that each step happened. System
  Settings is native, so its Accessibility tree should be good. That is inferred, not measured. V
  medium, F medium.

### Support and teaching

- **Guiding someone else.** Today: screen share with a pointer, as in Tuple, which lets people draw
  on a shared screen ([Tuple](https://tuple.app/)). What changes: record your ink and its answer as
  steps, and the other person replays them on their own Mac. Needs: steps stored by app and URL,
  plus sharing. V medium, F low.

### Agent oversight

- **The agent shows where it is looking or what it changed.** A coding session marks the element it
  edited in the running app, and the mark becomes a check once the change is seen. Needs: session
  to live-mark protocol, and a recapture to confirm the change. V high, F low now.

## Patterns that only a drawn answer allows

- **Steps that advance on click.** One mark at a time. A click on the target passes through, and
  the next mark draws on. Built in the spike.
- **Asking back with two loops.** The answer loops two candidates and asks "this one or that one?".
  A tap picks one. It needs a tap on an agent mark to send a reply, not to erase it.
- **Before and after.** The answer draws the proposed change over the real element, as a ghost the
  person can toggle. Needs a mark kind that holds an image.
- **A mark that turns into a check.** After a step or a session's edit, Vignette recaptures the
  target. The mark turns into a check if the change is there and stays red if not. Needs a recapture
  and a second short ask.
- **Ink kept per page.** Marks keyed by URL or document path return when the page comes back. They
  use the text-quote approach Hypothesis uses, and lost marks go to a list rather than vanishing.
- **Evidence marks.** Every claim in `say` points at a line it drew. A claim with no mark reads as
  unsupported. This is a prompt rule, not new code.
- **Ink to a session.** The note panel's target is a session. The reply comes back on the screen
  when its anchors still resolve, and as a card when they do not
  (`docs/live-ink-spike-2026-10-04.md`).

## What Vignette needs, by how many workflows each unblocks

1. **A tap on an agent mark that answers instead of erasing** (asking back, steps). Small.
2. **Multi-step marks with advance-on-click and a recapture check** (settings, support,
   verification, oversight). The spike proved steps. The check is new.
3. **Session replies drawn live** (UI to source, PR review, oversight). Decision 6 defers this
   until sessions answer faster. One reason to revisit it: a session's reply could be drawn when
   it arrives, if its anchors still resolve.
4. **A source pointer in the packet** (developer workflows). `AXDOMIdentifier` and class lists in
   WebKit and Chromium. For React apps, a dev-server bridge like React Grab's.
5. **A packet that spans two windows** (Figma against build, cross-app checks).
6. **Ink kept by URL or path** (support, review, reading).
7. **Voice while inking.** It fits Bolt's finding. `SFSpeechRecognizer` runs on device on macOS 15
   (`docs/live-ink-apis-2026-10-04.md`). It helps every workflow but unblocks none.

## Limits of this research

- No source measures live ink itself. The studies above test related tasks: tutorials, remote
  gesture, pen questions and direct manipulation.
- The usage figures come from a self-selected poll and from audits with uneven definitions.
- Ratings are judgements from the measured limits, not tests.
