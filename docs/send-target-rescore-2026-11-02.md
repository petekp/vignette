# The second scoring of Send's starting target (2026-11-02)

Pete chose on 2026-11-02 to keep Send as it is. The rule is not built.

The rule came from the first scoring, in `docs/session-detection-exploration-2026-10-08.md`, "The
plan (2026-10-18)". When Send would start on a Codex thread, and the person's last send in the past
2 hours went to a Claude Code session that is still listed, Send would start on that session. Pete
chose on 2026-10-18 to score it again on new sends before any code changed.

## The result

The sends scored were the 64 from the editor between 2026-10-18 and 2026-11-02, from the shadow
log. Reply sends and sends cancelled during their wait are left out.

| | Right of 64 | 95% interval |
|---|---|---|
| The offer Send makes now | 40 | 0.50 to 0.73 |
| The rule, else the offer | 41 | 0.52 to 0.75 |

- **The rule fired 3 times.** It fixed 2 sends and broke 1. The 2 fixes were 55 s apart, so they
  were one decision.
- **The difference is within chance.** McNemar's one-sided p is 0.50. Resampling days, the interval
  for the difference is −0.03 to +0.14.
- **The case the rule needs was rare.** A Codex offer within 2 hours of a send to Claude Code came
  3 times, against 23 in the first scoring. Drawings offered to a Codex thread still went to
  Claude Code 6 times in 11.

## How it was scored

- **Set before the run:** the unit, the population, the estimator, and what would adopt or reject
  the rule. The rule would be adopted only if it beat the offer with p under 0.05, an interval
  above 0, and a gain that held without its best day.
- **Checked first:** before it scored the new sends, the scorer reproduced the first scoring's table
  exactly.
- **Reviewed:** an independent reviewer recomputed every number from the raw log with its own code.
- **Where the work is:** the main checkout's `.scratch/send-context-2026-11-02/`, which Git
  ignores, holds the pre-registration, the scorer, the copy of the log and the review.

The shadow log was removed the same day. A launch now deletes `send-context.jsonl`.
