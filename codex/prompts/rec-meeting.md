미팅 녹음/전사를 처리한다. 스크립트 위치: `~/.codex/rec-meeting/`

1. `~/.codex/rec-meeting/check-setup.sh` 실행. exit 0이 아니면 `install.sh` 안내 후 중단.
2. 인자가 오디오 파일 경로면 → `python3 ~/.codex/rec-meeting/transcribe.py <경로>`
3. 인자가 없으면 → `~/meeting-log/.rec-pid` 존재 여부로 판단:
   - 있으면 `rec-stop.sh` (종료 + 전사)
   - 없으면 `rec-start.sh` (시작)
4. 완료 후 결과 파일 경로를 알려준다.

인자: $ARGUMENTS
