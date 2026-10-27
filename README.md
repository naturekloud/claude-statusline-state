# claude-statusline-state

A Claude Code status line that shows whether the session is **Running**, **Needs approval**, or **Idle**, plus the number of background tasks still in flight.

```
● Running + 2 background | Opus 5.5 high | my-repo (main) | context 42% used | 5h 12% used | 7d 3% used
```

## How it works

- Claude Code does not put a run state in the status line JSON, so hooks record it.
- `hooks/status-state.sh` writes the state to `~/.cache/claude-status/<session_id>`.
  - `SessionStart` → idle, `UserPromptSubmit` / `PostToolUse` → running, `PermissionRequest` → approval, `Stop` → idle, `SessionEnd` → removed.
- On `Stop`, the hook also reads the `background_tasks` snapshot and writes the count of unfinished tasks to `<session_id>.bg`.
- `statusline.sh` reads those files. It also checks the transcript for `[Request interrupted by user]`, because Esc does not fire `Stop`. A newer marker turns Running or Needs approval into Idle.
- `refreshInterval: 1` re-runs the script every second so the state updates without waiting for an event.

## Install

1. Copy the files:

   ```bash
   mkdir -p ~/.claude/hooks
   cp statusline.sh ~/.claude/statusline.sh
   cp hooks/status-state.sh ~/.claude/hooks/status-state.sh
   chmod +x ~/.claude/statusline.sh ~/.claude/hooks/status-state.sh
   ```

2. Merge `settings.snippet.json` into `~/.claude/settings.json`. Keep your existing `hooks` entries and add these to them. Don't replace the whole file.

Requires `python3`. The scripts use `bash` and `git`.

## Limitations

- The background count is a snapshot taken at `Stop`. It updates when the next `Stop` fires, for example when a finished background task wakes Claude for a new turn.
- Scheduled wakeups (`/loop`, `ScheduleWakeup`) are not counted.
- The interrupt check reads the last 128 KB of the transcript every second.
