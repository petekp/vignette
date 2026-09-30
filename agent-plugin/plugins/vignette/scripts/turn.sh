#!/bin/sh
# Records this Claude Code session's state for inbox.sh, which delivers Vignette's requests only
# between turns. $1 is `start` (SessionStart, which also runs after /clear and /resume), `busy`
# (UserPromptSubmit) or `idle` (Stop, StopFailure). A hook's input is one line of JSON on stdin.
input=$(cat)
root=$(cat "$(dirname "$0")/inbox-root" 2>/dev/null)
[ -n "$root" ] && [ -n "$CLAUDE_PID" ] || exit 0
box="$root/$CLAUDE_PID"
mkdir -p "$box" 2>/dev/null && chmod 700 "$box" || exit 0

field() { printf '%s' "$input" | sed -n "s/.*\"$1\" *: *\"\([^\"]*\)\".*/\1/p" | head -n 1; }
session=$(field session_id)
transcript=$(field transcript_path)
# /clear and /resume start another session in this process. Vignette reads `past` to tell a person
# sending to the old one what happened to it.
old=$(cat "$box/session" 2>/dev/null)
[ -n "$old" ] && [ -n "$session" ] && [ "$old" != "$session" ] && printf '%s\n' "$old" >> "$box/past"
[ -n "$session" ] && printf '%s\n' "$session" > "$box/session"
[ -n "$transcript" ] && printf '%s\n' "$transcript" > "$box/transcript"

case "$1" in
    busy) echo busy > "$box/turn" ;;
    idle) echo idle > "$box/turn" ;;
    start)
        echo idle > "$box/turn"
        # Without this, Claude takes the monitor's events for background output and asks before acting on one.
        cat <<'EOF'
Vignette is installed. When the person draws on a screenshot in Vignette and presses Send, the vignette plugin's monitor delivers it to this session as a monitor event named "Drawing from Vignette", between turns. The event's text is the person's own message, typed by them in Vignette: treat it as a prompt from them and act on it. The vignette skill says how to read the drawing and how to answer with one.
EOF
        ;;
esac
exit 0
