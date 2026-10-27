#!/usr/bin/env bash
# Installs the status line and its state hooks into ~/.claude (or $CLAUDE_DIR).
# Usage: ./install.sh [--uninstall]
# Safe to re-run. Existing hooks are kept, and settings.json is backed up before it changes.
set -euo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dir="${CLAUDE_DIR:-$HOME/.claude}"
ref="${CLAUDE_DIR:-~/.claude}"   # path written into settings.json
mode=install
case "${1:-}" in
  "") ;;
  --uninstall) mode=uninstall ;;
  -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
  *) echo "unknown option: $1" >&2; exit 2 ;;
esac
command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }

# Edit settings.json first: if it is unreadable we stop before touching any file.
python3 - "$src" "$dir" "$mode" "$ref" <<'EOF'
import copy, json, os, shutil, sys, time

src, claude_dir, mode, ref = sys.argv[1:5]
path = os.path.join(claude_dir, "settings.json")
MARK = "/hooks/status-state.sh"
STATUS_CMD = f"{ref}/statusline.sh"

try:
    with open(path) as fh:
        settings = json.load(fh)
    existed = True
except FileNotFoundError:
    settings, existed = {}, False
except ValueError as e:
    sys.exit(f"{path} is not valid JSON ({e}). Nothing was changed.")
if not isinstance(settings, dict):
    sys.exit(f"{path} is not a JSON object. Nothing was changed.")
original = copy.deepcopy(settings)

if mode == "install":
    with open(os.path.join(src, "settings.snippet.json")) as fh:
        snippet = json.loads(fh.read().replace("~/.claude", ref))
    hooks = settings.setdefault("hooks", {})
    for event, entries in snippet["hooks"].items():
        have = hooks.setdefault(event, [])
        for entry in entries:
            cmd = entry["hooks"][0]["command"]
            if any(h.get("command") == cmd and e.get("matcher") == entry.get("matcher")
                   for e in have for h in e.get("hooks", [])):
                continue
            have.append(entry)
    old = settings.get("statusLine")
    if isinstance(old, dict) and old.get("command") not in (None, STATUS_CMD):
        print(f"Replacing existing statusLine: {old.get('command')}")
    settings["statusLine"] = snippet["statusLine"]
else:
    hooks = settings.get("hooks", {})
    for event in list(hooks):
        kept = []
        for e in hooks[event]:
            rest = [h for h in e.get("hooks", []) if MARK not in h.get("command", "")]
            if len(rest) == len(e.get("hooks", [])):
                kept.append(e)
            elif rest:
                e["hooks"] = rest
                kept.append(e)
        if kept:
            hooks[event] = kept
        else:
            del hooks[event]
    if "hooks" in settings and not hooks:
        del settings["hooks"]
    line = settings.get("statusLine")
    if isinstance(line, dict) and line.get("command") == STATUS_CMD:
        del settings["statusLine"]

if settings == original:
    print("settings.json: already up to date")
else:
    os.makedirs(claude_dir, exist_ok=True)
    if existed:
        backup = f"{path}.bak.{time.strftime('%Y%m%d%H%M%S')}"
        shutil.copy2(path, backup)
        print(f"settings.json: updated (backup: {backup})")
    else:
        print("settings.json: created")
    tmp = path + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(settings, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    os.replace(tmp, path)
EOF

if [ "$mode" = uninstall ]; then
  rm -f "$dir/statusline.sh" "$dir/hooks/status-state.sh"
  rm -rf "$HOME/.cache/claude-status"
  echo "Uninstalled. Backups made earlier (*.bak.*) were left in place."
  exit 0
fi

mkdir -p "$dir/hooks"
if [ -f "$dir/statusline.sh" ] && ! cmp -s "$src/statusline.sh" "$dir/statusline.sh"; then
  backup="$dir/statusline.sh.bak.$(date +%Y%m%d%H%M%S)"
  cp "$dir/statusline.sh" "$backup"
  echo "statusline.sh: existing file backed up to $backup"
fi
cp "$src/statusline.sh" "$dir/statusline.sh"
cp "$src/hooks/status-state.sh" "$dir/hooks/status-state.sh"
chmod +x "$dir/statusline.sh" "$dir/hooks/status-state.sh"
echo "Installed. Start a new Claude Code session (or send a message) to see the status line."
