# Replies are authorized by a ticket for each request

A `vignette://` URL has no authenticated sender. So each screenshot request gets a secret in its
own private folder, and only a reply that presents it is accepted. The secret never travels in the
request line, because the log records every URL. Holding the ticket permits replies to one request
and proves nothing about which process wrote them, and the design accepts that limit.

## Consequences

Acceptance and publication are separate states. An accepted reply's file name is reserved and
hidden from every listing until its record says it is published, so an interrupted import never
shows half a reply.

Sources: `docs/closed-agent-loop-implementation-2026-09-20.md`, commit 7761ea9.
