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

## Verification

Tested on Claude Code 2.1.308 with Linux (WSL2), bash and python3. macOS and Windows were not tested.

**Checked in a real session**
- The hooks write `running` during a turn, and the status line reads it.
- Background shell task: with `sleep 600` running in the background, the `Stop` hook wrote `1` to `<session_id>.bg`. After the task was stopped, the next `Stop` wrote `0`.
- Render time is about 0.05 s per run with a 1 MB transcript.

**Checked only with synthetic input** (built to match the documented hook JSON)
- Idle and approval transitions, and the `+ N background` label in each state.
- Counting only unfinished tasks, keeping the count when an event has no snapshot, clearing on `SessionStart` and `SessionEnd`.
- The hook printing nothing and exiting 0 on malformed input.
- Esc interrupt detection. Both marker strings exist in the Claude Code binary, but no real transcript with a marker was available, so the entry shape (a `user` entry whose text starts with the marker) is an assumption. Esc was never pressed in a real session.

**Not checked**
- `Needs approval` during a real permission prompt or `AskUserQuestion` dialog.
- Background subagents, monitors and workflows. Only a shell task was tried.
- A background task finishing on its own and waking Claude for a new turn, so that `Stop` refreshes the count.
- The rendered `Idle` label after a real `Stop`. The `Stop` branch ran on real input, but the label itself was not checked.

## Limitations

- The background count is a snapshot taken at `Stop`. It updates when the next `Stop` fires, for example when a finished background task wakes Claude for a new turn.
- Scheduled wakeups (`/loop`, `ScheduleWakeup`) are not counted.
- The interrupt check reads the last 128 KB of the transcript every second.
