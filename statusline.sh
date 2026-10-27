#!/usr/bin/env bash
input=$(cat)

IFS=$'\t' read -r model effort dir ctx h5 d7 h5r d7r state bg < <(printf '%s' "$input" | python3 -c '
import json, os, sys, time
from datetime import datetime
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
def g(*path):
    v = d
    for p in path:
        if not isinstance(v, dict) or v.get(p) is None:
            return ""
        v = v[p]
    return str(v)
def pct(*path):
    v = g(*path)
    try:
        return str(round(float(v)))
    except ValueError:
        return ""
def left(*path):
    v = g(*path)
    if not v:
        return ""
    try:
        t = float(v)
    except ValueError:
        try:
            t = datetime.fromisoformat(v.replace("Z", "+00:00")).timestamp()
        except ValueError:
            return ""
    if t > 1e12:
        t /= 1000
    s = int(t - time.time())
    if s <= 0:
        return ""
    d, s = divmod(s, 86400)
    h, s = divmod(s, 3600)
    m = s // 60
    if d:
        return f"{d}d{h}h"
    if h:
        return f"{h}h{m}m"
    return f"{m}m"
TAIL = 131072
def interrupted_after(path, since):
    # Esc does not fire the Stop hook; the only trace is the marker Claude Code appends to the transcript.
    if not path:
        return False
    try:
        with open(path, "rb") as fh:
            size = fh.seek(0, 2)
            fh.seek(max(0, size - TAIL))
            lines = fh.read().split(b"\n")
    except OSError:
        return False
    if size > TAIL:
        lines = lines[1:]  # first line is cut mid-way
    for raw in reversed(lines):
        if b"[Request interrupted by user" not in raw:
            continue
        try:
            e = json.loads(raw)
        except ValueError:
            continue
        if e.get("type") != "user":
            continue
        c = (e.get("message") or {}).get("content")
        texts = [c] if isinstance(c, str) else [
            b.get("text") or "" for b in c or [] if isinstance(b, dict) and b.get("type") == "text"]
        if not any(t.startswith("[Request interrupted by user") for t in texts):
            continue
        try:
            ts = datetime.fromisoformat(e["timestamp"].replace("Z", "+00:00")).timestamp()
        except (KeyError, ValueError, AttributeError):
            return False
        return ts > since
    return False
def run_state():
    # Written by ~/.claude/hooks/status-state.sh; a newer interrupt marker overrides running/approval.
    sid = g("session_id")
    if not sid:
        return ""
    p = os.path.join(os.path.expanduser("~/.cache/claude-status"), sid)
    try:
        with open(p) as fh:
            st = fh.read().strip()
        since = os.path.getmtime(p)
    except OSError:
        return ""
    if st in ("running", "approval") and interrupted_after(g("transcript_path"), since):
        return "idle"
    return st
def bg_count():
    # Background tasks in flight at the last Stop; written by ~/.claude/hooks/status-state.sh.
    sid = g("session_id")
    if not sid:
        return ""
    try:
        with open(os.path.join(os.path.expanduser("~/.cache/claude-status"), sid + ".bg")) as fh:
            n = int(fh.read().strip() or 0)
    except (OSError, ValueError):
        return ""
    return str(n) if n > 0 else ""
print("\t".join([
    g("model", "display_name") or "-",
    g("effort", "level") or "-",
    g("workspace", "current_dir") or g("cwd") or "-",
    pct("context_window", "used_percentage") or "-",
    pct("rate_limits", "five_hour", "used_percentage") or "-",
    pct("rate_limits", "seven_day", "used_percentage") or "-",
    left("rate_limits", "five_hour", "resets_at") or "-",
    left("rate_limits", "seven_day", "resets_at") or "-",
    run_state() or "-",
    bg_count() or "-",
]))
')
for v in model effort dir ctx h5 d7 h5r d7r state bg; do [ "${!v}" = "-" ] && printf -v "$v" ''; done

short="$dir"
case "$dir" in
  "$HOME") short="~" ;;
  "$HOME"/*) short="~${dir#"$HOME"}" ;;
esac

branch=""
if [ -n "$dir" ] && [ -d "$dir" ]; then
  branch=$(git --no-optional-locks -C "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null \
    || git --no-optional-locks -C "$dir" rev-parse --short HEAD 2>/dev/null)
fi

color() {
  local label=$1 v=$2 r=$3 c
  if   [ "$v" -lt 25 ]; then c='\033[92m'        # bright green
  elif [ "$v" -lt 50 ]; then c='\033[93m'        # bright yellow
  elif [ "$v" -lt 75 ]; then c='\033[38;5;214m'  # bright orange
  else                       c='\033[91m'        # bright red
  fi
  [ -n "$r" ] && r="\033[90m($r)\033[0m$c"   # dark gray
  printf '%b%s %s%%%b used\033[0m' "$c" "$label" "$v" "$r"
}

case "${model,,}" in
  *opus*)   mc='\033[38;5;183m' ;;  # light purple
  *sonnet*) mc='\033[38;5;216m' ;;  # light orange
  *haiku*)  mc='\033[38;5;117m' ;;  # sky blue
  *)        mc='' ;;
esac
case "$state" in
  running)  badge_color='\033[92m'; label='● Running' ;;                 # bright green
  approval) badge_color='\033[1;38;5;214m'; label='◐ Needs approval' ;;  # bold orange
  idle)     badge_color='\033[90m'; label='○ Idle' ;;                    # dark gray
  *)        label='' ;;
esac
[ -n "$label" ] && [ -n "$bg" ] && label="$label + $bg background"
badge=""
[ -n "$label" ] && badge="$badge_color$label\033[0m"

out="$model"
[ -n "$effort" ] && out="$out $effort"
[ -n "$mc" ] && out="$mc$out\033[0m"
name="$short"
[[ "$short" == */* && "$short" != "/" ]] && name="${short##*/}"
loc=""
[ -n "$name" ] && loc="\033[97m$name\033[0m"
[ -n "$branch" ] && loc="$loc \033[94m($branch)\033[0m"
[ -n "$loc" ] && out="$out | $loc"
[ -n "$ctx" ] && out="$out | $(color context "$ctx")"
[ -n "$h5" ] && out="$out | $(color 5h "$h5" "$h5r")"
[ -n "$d7" ] && out="$out | $(color 7d "$d7" "$d7r")"
[ -n "$badge" ] && out="$badge | $out"
printf '%b\n' "$out"
