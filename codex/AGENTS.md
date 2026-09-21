# builder-journey 공용 지침 (Codex)

## 미팅 녹음 — rec-meeting

Apple Silicon Mac에서 시스템 오디오 + 마이크를 동시 녹음하고 자동 전사한다.
스크립트는 `~/.codex/rec-meeting/` 에 있다 (ai-skills repo 심볼릭 링크).

| 요청 | 실행 |
|---|---|
| "녹음 시작" | `~/.codex/rec-meeting/rec-start.sh` |
| "녹음 종료" | `~/.codex/rec-meeting/rec-stop.sh` |
| "설치 점검" | `~/.codex/rec-meeting/check-setup.sh` |
| 설치 안 됨 | `~/.codex/rec-meeting/install.sh` |
| 기존 파일 전사 | `python3 ~/.codex/rec-meeting/transcribe.py <파일>` |

규칙:
- 녹음 관련 요청이면 **먼저 `check-setup.sh`** 를 돌려 종료 코드로 분기한다.
  exit 0 → 진행, 그 외 → `install.sh` 안내.
- 결과물은 `~/meeting-log/meeting-YYYYMMDD-HHMMSS.{m4a,txt}`.
- 문제 발생 시 `~/.codex/rec-meeting/docs/troubleshooting.md` 참조.
