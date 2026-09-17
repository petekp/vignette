# TODOs

Things decided or raised but not built. Each entry says what, why, and what it waits on.

## Ship the agent skill with the app (decided 2026-09-16)

Someone who downloads the app needs their agent to learn the `shotnote://` contract, and the
app is the only thing they are guaranteed to have and the only thing that knows which commands
its version supports. So the app is the source of the skill.

- Bundle `skills/shotnote/SKILL.md` in the app the way `LICENSE-tldraw.md` is bundled (project.yml).
  The draft is in the appendix below; its repo home is `skills/shotnote/SKILL.md`.
- Offer it once. On first launch, when `~/.claude` or `~/.codex` exists, the first-launch toast
  offers the skill. A toggle in Settings, in a new "Agents" section, does the work: copy the skill
  into `~/.claude/skills/shotnote` and `~/.codex/skills/shotnote`, rewrite it on launch when the
  app is newer, remove it when the toggle goes off. `shotnote://install-skill` does the same for
  scripts and answers with one `[install-skill] ok|error` line.
- The installer never touches a skill directory it did not create. Mark its own copies (a
  sidecar version file) so a hand-linked copy is left alone.
- Publish the same file on skills.sh from the public repo, as herdr does, for Cursor and whatever
  else people run. Waits on the public repo.
- Default: detected and offered, not silently installed. Writing into another tool's config
  directory needs a yes, even if the yes is one click on the toast.
- Not doing: an MCP server (a config step in every agent and a second protocol beside the URLs;
  revisit if a non-Claude, non-Codex user asks) and writing into anyone's CLAUDE.md.
- On this machine the installer replaces the manual link. Until it exists, link
  `claude-code-setup/skills/shotnote` to `~/Code/shotnote/skills/shotnote` and run
  `gen-skills-manifest.sh`; the agent-browser skill is owned by skills.sh and must not carry this.

## Open from the same session

- `shotnote://add?file=<path>[&annotate]` is built, unit-tested, and verified live, and not yet
  committed (Commands.swift, AppDelegate.swift, CommandsTests.swift, README.md, AGENTS.md).
- The skill checks the `help` list for `add` and falls back to saving into the watch folder, so a
  newer skill on an older app still works.

## Discussed, not decided

- `shotnote://marks?file=`: print the stored draft's shapes as markdown, one line per shape with
  its type and percent position, and put the same block on the pasteboard beside the PNG in Copy
  Annotated. Verified by hand on 2026-09-16 with `jq` over a draft: one ellipse, center x 26%,
  y 30%, enough to crop the marked region from the original. Per-mark crops are the follow-on.
  Pete: keep using the app and see whether the need shows up.
- A vendor's own logo on the agent badge (Claude, ChatGPT) instead of the one fallback glyph.
  `Agent.symbol(for:)` is the lookup, empty today. Those logos are trademark assets Pete has to
  review before they ship, so it waits on that, not on code.
- Agent pushes piling up in the screenshots folder: a name rule or a second watched folder. Only
  if the push loop proves itself in use.
- A name convention for pushed files, `Agent <what> <state>.png`, so the card reads at a glance.

## Queued by Pete, 2026-09-16 (before sleep)

Handed to agents overnight; each item's branch and verification are in the overnight report.

1. Remove the dotted outline placeholder when an image leaves the stack. A blank space is fine.
2. Add nuance to the spatial transitions: arc and depth, so a card does not move on a single
   vector but has subtle character, charm, and elegance.
3. The orange "edited" badge is probably not needed. Remove it for now.
4. Let agents annotate when they add an image, in a way the human can edit afterward, the same
   way user-annotated images work (go back and edit the shapes and text).
5. The control bar under the stack gets lost. Position it closer to the selected thumbnails: to
   the left, vertically centered between the topmost and bottommost selected card, with the
   controls arranged vertically.
6. Drop the count from the control bar; put the count in the circular selection indicator on
   the cards instead.
7. Stitch animation: the selected thumbnails leave the stack and conjoin into the stitched
   image, which takes its place at the bottom of the stack, or opens in the annotator when that
   is enabled. The choreography needs more thought; do an initial pass.
8. A purple robot icon on images an agent added, or the vendor's logo (Claude, ChatGPT) with the
   robot as the fallback for unknown vendors. Probably an `agent` parameter on `add`.
9. A way to send an image to Claude or Codex automatically instead of copy and paste: in the
   annotator, a call to action to send it to an agent the app detects. Explore how to do this
   robustly, with high confidence, before building.

## Appendix: skill draft (2026-09-16)

    ---
    name: shotnote
    description: Show the user an image through Shotnote, the screenshot tool on this Mac, and read back what they marked on it. Use when you want the user to see a screenshot or rendering you produced (agent-browser, screencapture, a before-and-after), when they ask to see what something looks like, or when you need their circled answer. Not for images the user captured themselves; Shotnote already shows those.
    ---
    
    # Shotnote
    
    Shotnote watches the screenshots folder, shows each new image as a thumbnail in the corner,
    keeps the last thirty in a stack, and lets the user circle things and press Return. Every command
    is a `shotnote://` URL that answers with one line in `~/Library/Logs/Shotnote.log`.
    
    ## Show the user an image
    
    ```sh
    open -g "shotnote://add?file=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "/abs/path/Agent checkout 390px.png")"
    ```
    
    - `add` copies the file into the watch folder and shows its thumbnail. It leaves the clipboard
      alone and does not open the editor, whatever the user's capture settings say. Add `&annotate`
      to open the editor instead, only when you are asking for marks right away.
    - `open -g` keeps focus where it is. Always percent-encode the path; `open` does not.
    - Wait for `[add] ok <name>` and then `[watcher] new <name>` in the log. The name gains a counter
      (`x 2.png`) when one already exists. Errors end with one of `missing-file`, `unreadable-image`,
      `unsupported-type` (png, jpg, jpeg, or heic only, never a `-annotated` name), `write-failed`.
    - Push what the user should see, not every screenshot you take. Name the file for them: what it
      shows, at what size or state.
    
    ## Read back what they marked
    
    When the user annotates the image and presses Return, Shotnote writes `<name>-annotated.png`
    beside the copy in the watch folder and logs `[annotate] done <name>-annotated.png`. Read that
    file. The folder is `screenshotsFolder` in `~/.config/shotnote/settings.json`.
    
    ## Is Shotnote running, and does it have `add`
    
    `open -g shotnote://help` logs a `[help]` line per command; none within a second means it is not
    running. If the list has no `add`, the app predates this skill: save the file straight into
    `screenshotsFolder` instead, which any version shows as a capture. `open -g
    "shotnote://state?tag=<id>"` logs one `[state] {json}` line carrying the tag.
