#!/bin/bash
# 녹음 진행 상황 알림 워처
# 인자: $1 = ffmpeg PID, $2 = 녹음 시작 시각(epoch 초)
# m5: 미정의 변수/파이프 실패 즉시 감지.
set -uo pipefail
#
# 알림 일정:
#   - 시작 즉시: "녹음 시작" (소리 Glass)
#   - 15/30/45분: 짧은 진행 알림 (무음)
#   - 60분: "계속 녹음할까요?" 알림 (소리 Hero)
#   - 이후 30분마다 동일한 장시간 경고

FFMPEG_PID="${1:-}"
START_EPOCH="${2:-}"

if [ -z "$FFMPEG_PID" ] || [ -z "$START_EPOCH" ]; then
    echo "usage: $0 <ffmpeg-pid> <start-epoch>" >&2
    exit 1
fi

# n3: 공통 헬퍼 source (notify, escape_as, is_our_ffmpeg).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

# 시작 알림 (소리 있음)
notify "🎙 녹음 시작" "BlackHole + 마이크 캡처 중. 끝내려면 Claude에 '녹음 끝'" "Glass"

NEXT_TARGET=15  # 분 단위. 다음 알림 시점.

# m10: 다음 타겟 시각까지 정확히 sleep해서 ±30초 오차를 ±1초로 축소.
while is_our_ffmpeg "$FFMPEG_PID"; do
    NOW=$(date +%s)
    NEXT_TARGET_EPOCH=$((START_EPOCH + NEXT_TARGET * 60))
    REMAIN=$((NEXT_TARGET_EPOCH - NOW))
    # 30초 간격으로 ffmpeg 생사 체크 (장시간 sleep 중 ffmpeg 죽으면 빠른 종료 위해)
    if [ "$REMAIN" -gt 30 ]; then
        sleep 30
        continue
    fi
    [ "$REMAIN" -gt 0 ] && sleep "$REMAIN"

    # 타겟 시각 도달
    if [ "$NEXT_TARGET" -ge 60 ]; then
        notify "⏱ ${NEXT_TARGET}분째 녹음 중" "계속 녹음할까요? 끝내려면 Claude에 '녹음 끝'" "Hero"
    else
        notify "⏱ ${NEXT_TARGET}분 경과" "녹음 진행 중. 끝내려면 '녹음 끝'" ""
    fi
    # 다음 타겟: 1시간 전엔 15분 간격, 이후엔 30분 간격
    if [ "$NEXT_TARGET" -lt 60 ]; then
        NEXT_TARGET=$((NEXT_TARGET + 15))
    else
        NEXT_TARGET=$((NEXT_TARGET + 30))
    fi
done
