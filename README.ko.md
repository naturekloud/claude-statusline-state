# claude-statusline-state

[English](README.md) | 한국어

세션이 **Running**(실행 중), **Needs approval**(승인 대기), **Idle**(대기) 중 어느 상태인지와, 아직 끝나지 않은 백그라운드 작업 수를 보여 주는 Claude Code statusline입니다.

```
● Running + 2 background | Opus 5.5 high | my-repo (main) | context 42% used | 5h 12% used | 7d 3% used
```

## 동작 원리

- Claude Code는 statusline JSON에 실행 상태를 넣어 주지 않으므로, hook이 상태를 기록합니다.
- `hooks/status-state.sh`가 상태를 `~/.cache/claude-status/<session_id>`에 씁니다.
  - `SessionStart` → idle, `UserPromptSubmit` / `PostToolUse` → running, `PermissionRequest` → approval, `Stop` → idle, `SessionEnd` → 파일 삭제.
- `Stop`이 불리면 hook이 `background_tasks` 스냅샷도 읽어서, 끝나지 않은 작업 수를 `<session_id>.bg`에 씁니다.
- `statusline.sh`가 이 파일들을 읽습니다. Esc를 누르면 `Stop`이 불리지 않기 때문에, transcript에서 `[Request interrupted by user]` 문구도 확인합니다. 상태 기록보다 나중에 찍힌 문구가 있으면 Running이나 Needs approval을 Idle로 바꿉니다.
- `refreshInterval: 1`로 스크립트를 1초마다 다시 실행해서, 이벤트를 기다리지 않고 상태를 갱신합니다.

## 설치

1. 파일을 복사합니다.

   ```bash
   mkdir -p ~/.claude/hooks
   cp statusline.sh ~/.claude/statusline.sh
   cp hooks/status-state.sh ~/.claude/hooks/status-state.sh
   chmod +x ~/.claude/statusline.sh ~/.claude/hooks/status-state.sh
   ```

2. `settings.snippet.json`을 `~/.claude/settings.json`에 합칩니다. 기존 `hooks` 항목은 그대로 두고 여기 있는 항목을 추가하세요. 파일 전체를 덮어쓰면 안 됩니다.

`python3`가 필요합니다. 스크립트는 `bash`와 `git`을 사용합니다.

## 검증 범위

Claude Code 2.1.308, Linux(WSL2), bash, python3 환경에서 테스트했습니다. macOS와 Windows는 테스트하지 않았습니다.

**실제 세션에서 확인한 것**
- hook이 턴 동안 `running`을 기록하고, statusline이 그 값을 읽습니다.
- 백그라운드 shell 작업: `sleep 600`이 백그라운드에서 도는 동안 `Stop` hook이 `<session_id>.bg`에 `1`을 기록했습니다. 작업을 종료한 뒤 다음 `Stop`에서는 `0`을 기록했습니다.
- 1MB 크기의 transcript에서 1회 렌더링에 약 0.05초가 걸립니다.

**가짜 입력으로만 확인한 것** (문서에 나온 hook JSON과 같은 모양으로 만든 입력)
- Idle과 승인 대기 전환, 각 상태에서의 `+ N background` 표시.
- 끝나지 않은 작업만 세기, 스냅샷이 없는 이벤트에서는 개수 유지, `SessionStart`와 `SessionEnd`에서 정리.
- 잘못된 입력에서 hook이 아무것도 출력하지 않고 0으로 종료하는 것.
- Esc 중단 감지. 두 문구는 Claude Code 바이너리에 있지만 문구가 실제로 찍힌 transcript는 구하지 못했습니다. 그래서 항목의 모양(문구로 시작하는 텍스트를 가진 `user` 항목)은 가정입니다. 실제 세션에서 Esc를 눌러 본 적은 없습니다.

**확인하지 못한 것**
- 실제 권한 승인 창이나 `AskUserQuestion` 창이 떴을 때의 `Needs approval` 표시.
- 백그라운드 subagent, monitor, workflow. shell 작업 하나만 시험했습니다.
- 백그라운드 작업이 스스로 끝나서 Claude를 새 턴으로 깨우고, 그 `Stop`에서 개수가 갱신되는 흐름.
- 실제 `Stop` 뒤에 그려진 `Idle` 라벨. `Stop` 처리 자체는 실제 입력으로 실행됐지만 라벨은 확인하지 않았습니다.

## 한계

- 백그라운드 작업 수는 `Stop` 시점의 스냅샷입니다. 다음 `Stop`이 불릴 때 갱신됩니다. 예를 들어 끝난 백그라운드 작업이 Claude를 새 턴으로 깨울 때입니다.
- 예약 작업(`/loop`, `ScheduleWakeup`)은 세지 않습니다.
- 중단 감지는 매초 transcript의 마지막 128KB를 읽습니다.
