#!/bin/bash
# 세그먼트 워처: 녹음 중 완성된 세그먼트를 백그라운드로 whisper 전사
# 인자: $1 = 세션 디렉토리
# m5: 미정의 변수와 파이프 실패 즉시 감지.
set -uo pipefail
SESSION_DIR="${1:-}"
PID_FILE="$HOME/meeting-log/.rec-pid"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# n3: 공통 헬퍼 source (is_our_ffmpeg, REC_BREW_PREFIX).
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
BREW_PREFIX="$REC_BREW_PREFIX"
POLL_INTERVAL=5  # 초

if [ -z "$SESSION_DIR" ] || [ ! -d "$SESSION_DIR" ]; then
    echo "usage: $0 <session-dir>" >&2
    exit 1
fi

# 녹음이 진행 중인 동안 루프
while [ -f "$PID_FILE" ] && is_our_ffmpeg "$(cat "$PID_FILE" 2>/dev/null)"; do
    # 세그먼트 리스트 수집 (오름차순)
    shopt -s nullglob
    SEGS=("$SESSION_DIR"/seg_*.m4a)
    shopt -u nullglob
    COUNT=${#SEGS[@]}

    # 마지막 세그먼트는 아직 기록 중이므로 제외하고 처리
    if [ "$COUNT" -gt 1 ]; then
        LAST_IDX=$((COUNT - 1))
        for (( i=0; i<LAST_IDX; i++ )); do
            SEG="${SEGS[$i]}"
            TXT="${SEG%.m4a}.txt"
            # 이미 처리됐으면 skip
            if [ ! -f "$TXT" ]; then
                PATH="$BREW_PREFIX/bin:$PATH" python3 "$SCRIPT_DIR/transcribe.py" "$SEG" "$TXT" >/dev/null 2>&1
            fi
        done
    fi

    sleep "$POLL_INTERVAL"
done
