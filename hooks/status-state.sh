#!/usr/bin/env bash
# Records the session's run state for statusline.sh.
# Usage: status-state.sh running|approval|idle|start|end   (hook JSON on stdin)
#   start: SessionStart. Background tasks die with the old process, so clear their count.
#   idle:  Stop/StopFailure. The Stop input carries the background_tasks snapshot.
# Must print nothing: UserPromptSubmit stdout is injected into the prompt.
input=$(cat)
[[ $input =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]] || exit 0
dir="$HOME/.cache/claude-status"
f="$dir/${BASH_REMATCH[1]}"
case "$1" in
  end)
    rm -f "$f" "$f.bg" ;;
  start)
    mkdir -p "$dir" && printf idle > "$f" && rm -f "$f.bg" ;;
  *)
    mkdir -p "$dir" && printf '%s' "$1" > "$f"
    if [ "$1" = idle ]; then
      # Count background tasks still in flight. Prints nothing when the input has no snapshot.
      n=$(printf '%s' "$input" | python3 -c '
import json, sys
try:
    tasks = json.load(sys.stdin)["background_tasks"]
except Exception:
    sys.exit(0)
print(sum(t.get("status") not in ("completed", "failed", "killed") for t in tasks))
')
      [ -n "$n" ] && printf '%s' "$n" > "$f.bg"
    fi ;;
esac
exit 0
