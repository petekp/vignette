# Agent delivery and enablement

Keep the existing Claude Code monitor until a current interactive session establishes its turn behavior. Consumption of an inbox file proves the monitor read it. It does not prove the agent acted on it.

The installed CLI is Claude Code 2.1.288. The earlier native investigation used 2.1.283. The current plugin checks turn state once before draining all queued lines. Its busy hook is `UserPromptSubmit`; its idle hooks are `Stop` and `StopFailure`. An interrupt falls back to the transcript's last entry. These facts follow from the shipped scripts, not a current model session.

A fresh isolated config reports `loggedIn: false`. The current runtime matrix needs a signed-in disposable session. Keep the person's own config and sessions outside that probe. A config directory alone does not establish that global instructions and credentials are isolated.

The probe must load the test copy's staged plugin, with its own URL scheme and inbox root. Use a scratch working folder, config, home, transcript, and hook log. Inspect the actual CLI flags before launch. Avoid modes that disable the hooks or monitors under test.

Run these observations in order:

1. Deliver one line to an idle session. Record file consumption, queued transcript event, turn start, and completed response separately.
2. Queue two lines before the first is consumed. Determine whether each starts work or one becomes background output.
3. Deliver a second line during a monitor-started turn. Check whether `UserPromptSubmit` marks that turn busy.
4. Interrupt that turn. Verify the next line proceeds and the fallback observes this CLI's actual transcript marker.
5. Deliver an event that starts no turn. Verify a proposed busy transition would not leave the inbox blocked indefinitely.
6. Reload the plugin and clear the session. Verify one live monitor and refusal of the old session address. Queue a line before clear and record which conversation receives it afterward. The inbox belongs to the PID, so an accepted pending line can outlive the session identity recorded by the start hook.

Only modify timing after this matrix distinguishes the failure. Writing busy after printing can overwrite a fast Stop or block permanently when no turn starts. A fixed timeout cannot prove that a turn ended. A second per-line state check is useful only if current runtime hooks reliably set that state.

Agent enablement has a separate confirmed error-reporting gap. `AppDelegate.turnOnAgents` reports plugin installation results while discarding `ClaudeReadRule.apply` failures. The settings read helper also treats any unreadable file as missing. A read failure could therefore authorize a replacement based on an empty dictionary.

The bounded repair belongs in those existing owners and their setup consumer. Setup separately applies the rule for an already-installed Claude plugin and also discards its failure. Distinguish missing settings from unreadable settings. Carry plugin installation and permission-rule outcomes separately, keyed by the same agent root. Keep a successful plugin installed when its read rule fails. Setup and the Agents tab should report that partial result. Retry the permission through its separate switch; toggling an installed plugin off removes it. Turning off should likewise report failure to remove the rule. Script installation continues to install only the plugin.

Add real-file owner coverage for ClaudeReadRule, which currently has none. Extend the existing plugin coverage for partial enablement. A refused or malformed write must preserve the file byte-for-byte. A successful permission update reserializes JSON, so compare unrelated settings by value. Verify that setup and settings report the failed step. Native verification uses fake tools and scratch agent roots.

State: runtime timing requires the isolated session above. Enablement has a concrete implementation boundary. No monitor or enablement code changed in this investigation.
