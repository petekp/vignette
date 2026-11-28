# Gemini CLI and Antigravity as agents Vignette can send to

Vignette sends drawings, replies and pin comments to two agents today: Claude Code and Codex. This
note says what a third agent would need and what Gemini CLI and Google Antigravity offer for each
part. It ends with a recommendation and the decisions it needs. Nothing here is built.

Everything about this Mac was read on 2026-11-27 without sending a prompt or signing in. The one
call made to a running app was a read-only `ListConversations` to the Antigravity app's local
server. Web sources were read the same day. A claim marked *unverified* is one no source or local
check settled.

## Recommendation

Aim at the Antigravity app, not Gemini CLI. Build nothing until one live check shows that the
app's send command starts a turn the way a person's message does.

- Gemini CLI has no way for another process to put a message into a session a person has open.
  Its hooks run only inside a turn, and ACP drives a process of its own. The only route is typing
  into its terminal with Herdr's `hc send`, which Vignette's rules forbid today.
- The Antigravity app has a local server that lists conversations with their titles and run
  state. Its `agentapi send-message` command "Sends a message to an existing conversation". No
  terminal is involved.
- That command may not be Send. Its help calls it messaging "to another conversation or yourself
  (useful for async notifications)", and it takes a `--title`. Whether it starts a turn on an idle
  conversation, and whether the agent reads it as the person's words, are unknown until one test
  message is sent. That uses Pete's account, so it needs his yes.
- If the check passes, the first step is Send, Reply and pin comments to a conversation the app has
  open. The vignette skill goes into Antigravity too, so its agent can push cards with
  `agent=antigravity`. If it fails, the next candidate is `agy -p --conversation <id>`, which sends
  a real user prompt through a separate process.
- Either route reads the server's address and token from a file Google has not documented for
  other apps. Pete has to accept that dependency, or the work waits.

The detail is in four parts:

- [What Vignette needs from an agent](gemini-antigravity-2026-11-27/what-vignette-needs.md), and what is installed on this Mac.
- [Gemini CLI](gemini-antigravity-2026-11-27/gemini-cli.md): what it offers, its first step and full parity.
- [Antigravity](gemini-antigravity-2026-11-27/antigravity.md): what it offers, the live check, its first step and full parity.
- [Sources](gemini-antigravity-2026-11-27/sources.md).

## Risks side by side

| Risk | Antigravity app | Gemini CLI |
| --- | --- | --- |
| Release pace | Every 1 to 3 days (53 app releases since 2026-05-19) | Weekly |
| What the route depends on | The hub file's address and token, undocumented for other apps. Google blocked its own agents' file tools from such files in 2.35.0. One rename breaks every Antigravity send | Herdr's `hc send` and its draft guard, and hooks the extension owns. A change to Gemini's session file format breaks only the session list |
| Delivery proven | No. `send-message` is documented for sidecars and reads as messaging between conversations | Hooks cannot deliver to an idle session. `hc send` delivers, by typing |
| Fits Vignette's rules | Addresses a conversation by its id, as Codex does | Types into a terminal, which `docs/rules/send.md` forbids |
| App closed | Send fails: nothing keeps the line | Send fails: no terminal |
| Access | Vignette reads another app's access token, as `agentapi` must. The read-only `ListConversations` call for this note used it | No token; Herdr's own connection |

## Decisions for Pete

1. Allow one live check that sends a test message to a throwaway Antigravity conversation, on his
   account, to answer the questions in [the Antigravity part](gemini-antigravity-2026-11-27/antigravity.md). Nothing else should be decided
   before it.
2. After it, choose the direction: the Antigravity app first, Gemini CLI first, or neither for now.
   The recommendation is the Antigravity app if the check passes, since Gemini CLI has no delivery
   route that fits Vignette's rules.
3. Accept reading the server's address and token from `~/.gemini/antigravity/daemon/hub_<port>.json`,
   an undocumented route, or ask Google for a documented entry for outside apps first.
4. For Gemini CLI, if it is wanted at all: pushes only, delivery by typing into its Herdr terminal,
   or nothing.

## Not verified

- Whether `agentapi send-message` starts a turn, and whether the agent reads it as the person's
  message.
- Whether `agy -p --conversation <id>` can send to a conversation the app has loaded.
- Whether `agentapi send-message` works from a process the app did not start, how it finds the
  server, and what it does when the conversation is running, idle, archived or unknown.
- Whether the Antigravity server refuses an unknown conversation id.
- Which conversation the Antigravity app's window shows.
- Whether a running `agy` serves `ConversationService`.
- Whether either agent's file tool shows a PNG at a path in a message to the model.
- Whether a Gemini CLI hook can learn its process id. A hook gets `session_id` but no documented
  process id.
- How the Gemini CLI model treats an `AfterAgent` `reason` used to carry a message.
