#!/bin/sh
# Delivers the requests Vignette sends to this Claude Code session. Claude Code runs this monitor for
# the whole session, and each line it prints reaches Claude as a notification. Claude acts on one
# that starts a turn but treats one arriving mid-turn as background output, so a request waits while
# a turn runs. The inbox is named by the Claude Code process, since /clear gives the process a new
# session id and this monitor keeps running.
root=$(cat "$(dirname "$0")/inbox-root" 2>/dev/null)
[ -n "$root" ] && [ -n "$CLAUDE_PID" ] || exit 0
box="$root/$CLAUDE_PID"
mkdir -p "$box" 2>/dev/null && chmod 700 "$box" || exit 0

# One monitor per session. A plugin reload can start a second one, which would print each request twice.
owner=$(cat "$box/monitor" 2>/dev/null)
if [ -n "$owner" ] && [ "$owner" != "$$" ] && kill -0 "$owner" 2>/dev/null; then exit 0; fi
echo $$ > "$box/monitor"

[ -n "$CLAUDE_CODE_SESSION_ID" ] && printf '%s\n' "$CLAUDE_CODE_SESSION_ID" > "$box/session"
[ -f "$box/turn" ] || echo idle > "$box/turn"
pwd -P > "$box/cwd"

# Stop does not run when the person interrupts a turn, so `turn` still says busy. The transcript's
# last entry is then Claude Code's interrupt marker.
between_turns() {
    [ "$(cat "$box/turn" 2>/dev/null)" != busy ] && return 0
    transcript=$(cat "$box/transcript" 2>/dev/null)
    [ -n "$transcript" ] && tail -n 1 "$transcript" 2>/dev/null | grep -q '\[Request interrupted by user'
}

ticks=0
while kill -0 "$CLAUDE_PID" 2>/dev/null; do
    if between_turns; then
        # Vignette names each file by the time it was written, so the glob's order is the order sent.
        for request in "$box"/*.line; do
            [ -f "$request" ] || continue
            cat "$request" && rm -f "$request"
        done
    fi
    [ $((ticks % 10)) -eq 0 ] && touch "$box/alive"
    ticks=$((ticks + 1))
    sleep 0.3
done
# The folder stays when Claude Code stops this monitor first. Vignette removes an inbox whose process has exited.
rm -rf "$box"
