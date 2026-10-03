# The app ships and installs its own agent integration

Vignette carries its agent plugin, with the skill inside it, in the app bundle, and installs it with
each agent client's own tool. The version that answers the `vignette://` commands is the version
that should teach them, and someone who downloads Vignette has the app and nothing else. The line
an agent receives names only the image; the skill carries the rest of the protocol.

## Considered options

- A link from a personal setup repository, or a skill directory listing alone.
- An MCP server.
- A plugin marketplace on GitHub. Rejected because the plugin would drift from the app's version.
- A long request line carrying the helper command. Shortened on 2026-09-25, because an agent that
  receives a request looks up Vignette's skill anyway.

Sources: commits 87ad165, 76b4bd4 and 72695f0, `docs/claude-code-without-herdr-2026-09-27.md`.
