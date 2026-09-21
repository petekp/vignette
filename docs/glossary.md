# Glossary

The words this project uses for the agent loop, and the ones it avoids. A native connection
addresses the agent session independently of the terminal displaying it, and most of these terms
exist to keep that distinction from collapsing.

**Agent client**: The software running an agent conversation, such as Claude Code or Codex. It is distinct from the model vendor and the terminal displaying it.
_Avoid_: Provider when referring to both an agent client and a terminal host.

**Agent session**: One particular conversation with an agent, including the context accumulated in that conversation. Changing which window displays it does not create a different conversation.
_Avoid_: Session without qualification when it could mean a drawing session.

**Terminal host**: The application or multiplexer containing terminal panes. A pane can host different agent sessions over time.

**Destination**: The agent session the person intends to receive a screenshot request. Its display name helps the person choose it but is not its identity.

**Delivery route**: One available way to send a screenshot request to a destination. A destination may have several routes, each with different delivery guarantees.

**Screenshot request**: A particular sent drawing and any accompanying instruction, addressed to one destination.

**Screenshot reply**: An image and optional agent marks answering a particular screenshot request. Several distinct replies may answer the same request.

**Reply ticket**: Permission to submit a reply to one screenshot request. Possessing the ticket does not establish which agent process produced the reply.
