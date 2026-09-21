#!/bin/bash
# 미팅 녹음 시작 (BlackHole + ffmpeg + Multi-Output 자동 전환 + 세그먼트 병렬 전사 + 알림 + 슬립 방지)
# m5: 미정의 변수와 파이프 실패 즉시 감지 (-e는 기존 || true 패턴 유지를 위해 의도적으로 제외).
set -uo pipefail
PID_FILE="$HOME/meeting-log/.rec-pid"
WATCHER_PID_FILE="$HOME/meeting-log/.rec-watcher-pid"
NOTIFY_PID_FILE="$HOME/meeting-log/.rec-notify-pid"
PREV_OUTPUT_FILE="$HOME/meeting-log/.rec-prev-output"
SESSION_FILE="$HOME/meeting-log/.rec-session"
MULTI_OUTPUT_NAME="${REC_MULTI_OUTPUT_NAME:-Multi-Output Device}"
SEGMENT_SECONDS="${REC_SEGMENT_SECONDS:-300}"  # 기본 5분 단위 세그먼트
RETENTION_DAYS="${REC_RETENTION_DAYS:-0}"      # m1: 0=영구. >0이면 N일 지난 합본 자동 삭제
STALE_DAYS="${REC_STALE_SESSION_DAYS:-30}"     # m6: 30일 이상 된 비정상 종료 세션 dir 자동 정리
NO_NOTIFY="${REC_NO_NOTIFY:-0}"                # m8: 1=알림 워처 비활성화
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# n3: 공통 헬퍼 라이브러리 (is_our_ffmpeg, notify, escape_as, REC_BREW_PREFIX).
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
BREW_PREFIX="$REC_BREW_PREFIX"

# M1: meeting-log는 미팅 녹음을 담아서 700으로 보호 (다른 사용자 차단).
mkdir -p "$HOME/meeting-log"
chmod 700 "$HOME/meeting-log" 2>/dev/null || true

# m1: retention 정책 (보관 기간 초과 합본 자동 삭제)
if [ "$RETENTION_DAYS" -gt 0 ] 2>/dev/null; then
    find "$HOME/meeting-log" -maxdepth 1 -type f \( -name "meeting-*.m4a" -o -name "meeting-*.txt" \) -mtime "+$RETENTION_DAYS" -delete 2>/dev/null || true
fi

# m6: 30일+ 된 stale session-* 자동 정리 (비정상 종료 후 미회수된 디렉토리)
if [ "$STALE_DAYS" -gt 0 ] 2>/dev/null; then
    find "$HOME/meeting-log" -maxdepth 1 -type d -name "session-*" -mtime "+$STALE_DAYS" -exec rm -rf {} + 2>/dev/null || true
fi

# C4: 자동 복구가 실패해도 사용자가 영구 차단되지 않도록 강제 정리 fallback.
force_clean_state() {
    rm -f "$PID_FILE" "$WATCHER_PID_FILE" "$NOTIFY_PID_FILE" \
          "$SESSION_FILE" "$PREV_OUTPUT_FILE"
    pkill -f "ffmpeg.*BlackHole" 2>/dev/null || true
    pkill -f "watch-segments.sh" 2>/dev/null || true
    pkill -f "notify-watcher.sh" 2>/dev/null || true
}

# BlackHole 존재 확인 (pipefail: ffmpeg는 항상 nonzero로 종료하므로 출력을 먼저 캡처).
FFMPEG_DEVICES=$(ffmpeg -f avfoundation -list_devices true -i "" 2>&1 || true)
if ! echo "$FFMPEG_DEVICES" | grep -q "BlackHole"; then
    echo "BlackHole 2ch가 설치되어 있지 않습니다. brew install blackhole-2ch"
    exit 1
fi

# switchaudio-osx 확인
if ! command -v SwitchAudioSource >/dev/null 2>&1; then
    echo "switchaudio-osx가 설치되어 있지 않습니다. brew install switchaudio-osx"
    exit 1
fi

# Multi-Output Device 존재 확인
if ! SwitchAudioSource -a | grep -q "^$MULTI_OUTPUT_NAME$"; then
    echo "'$MULTI_OUTPUT_NAME'가 없습니다. Audio MIDI Setup에서 생성하세요."
    exit 1
fi

# M7: 디스크 공간 사전 점검. 1GB 미만이면 경고 후 5초 대기.
AVAIL_KB=$(df -k "$HOME/meeting-log" 2>/dev/null | awk 'NR==2 {print $4}')
if [ -n "$AVAIL_KB" ] && [ "$AVAIL_KB" -lt 1048576 ]; then
    AVAIL_MB=$((AVAIL_KB / 1024))
    echo "⚠️ 디스크 여유 ${AVAIL_MB}MB (1GB 미만). 1시간 녹음에 약 60MB 필요."
    echo "   계속 진행하려면 5초 후 자동 시작. 중단하려면 Ctrl+C."
    sleep 5
fi

# 이미 녹음 중인지 확인 + 비정상 종료 세션 자동 회수 (C4/C5)
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if is_our_ffmpeg "$OLD_PID"; then
        echo "이미 녹음 중입니다 (PID $OLD_PID). 먼저 rec-stop.sh로 종료하세요."
        exit 1
    else
        # PID 파일은 있는데 우리 ffmpeg가 아님 (죽었거나 PID 재사용) = 비정상 종료된 세션
        echo "⚠️ 이전 비정상 종료된 녹음 세션을 발견했습니다. 자동 복구 중..."
        if bash "$SCRIPT_DIR/rec-stop.sh"; then
            echo "복구 완료. 새 녹음을 시작합니다."
        else
            echo "⚠️ 자동 복구 실패. 상태 파일을 강제 정리하고 새 녹음 진행."
            echo "   이전 세션 데이터(있다면) ~/meeting-log/session-*에 보존됨."
            force_clean_state
        fi
        echo "──────────────────────────────────"
    fi
fi

# 현재 출력 장치 저장 후 Multi-Output으로 전환
SwitchAudioSource -c > "$PREV_OUTPUT_FILE"
SwitchAudioSource -s "$MULTI_OUTPUT_NAME" >/dev/null

# 세션 디렉토리: 녹음 세그먼트와 개별 전사본 저장
# M2: 분 → 초까지 포함해서 같은 분 내 다중 시작 충돌 방지.
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SESSION_DIR="$HOME/meeting-log/session-$TIMESTAMP"
mkdir -p "$SESSION_DIR"
chmod 700 "$SESSION_DIR" 2>/dev/null || true
echo "$SESSION_DIR" > "$SESSION_FILE"

# 현재 기본 입력(마이크) 장치 가져오기
MIC=$(SwitchAudioSource -t input -c)

# ffmpeg 백그라운드 녹음 시작 (세그먼트 분할 + 시스템 오디오 + 마이크 믹싱)
# stderr를 세션 디렉토리에 살려서 device 접근 실패 등 진단 가능.
ffmpeg \
    -f avfoundation -i ":BlackHole 2ch" \
    -f avfoundation -i ":$MIC" \
    -filter_complex "amix=inputs=2:duration=longest:normalize=0" \
    -f segment -segment_time "$SEGMENT_SECONDS" -reset_timestamps 1 \
    -acodec aac -b:a 128k \
    "$SESSION_DIR/seg_%03d.m4a" \
    </dev/null >/dev/null 2>"$SESSION_DIR/ffmpeg.log" &
FFMPEG_PID=$!
echo "$FFMPEG_PID" > "$PID_FILE"
START_EPOCH=$(date +%s)

# 슬립 방지: ffmpeg가 살아있는 동안만 시스템 idle sleep 차단 (디스플레이는 끌 수 있음)
caffeinate -i -w "$FFMPEG_PID" >/dev/null 2>&1 &

# 세그먼트 워처 백그라운드 실행 (완성된 세그먼트를 바로 전사)
bash "$SCRIPT_DIR/watch-segments.sh" "$SESSION_DIR" </dev/null >/dev/null 2>&1 &
echo $! > "$WATCHER_PID_FILE"

# 알림 워처 백그라운드 실행 (시작 알림 + 15/30/45/60분 진행 알림)
# m8: REC_NO_NOTIFY=1이면 알림 워처 비활성화
if [ "$NO_NOTIFY" != "1" ]; then
    bash "$SCRIPT_DIR/notify-watcher.sh" "$FFMPEG_PID" "$START_EPOCH" </dev/null >/dev/null 2>&1 &
    echo $! > "$NOTIFY_PID_FILE"
fi

echo "녹음 시작됨: $SESSION_DIR"
echo "세그먼트 길이: ${SEGMENT_SECONDS}초 (녹음 중 병렬 전사)"
echo "입력: BlackHole 2ch(시스템) + $MIC(마이크)"
echo "출력 전환: $(cat "$PREV_OUTPUT_FILE") → $MULTI_OUTPUT_NAME"
if [ "$NO_NOTIFY" != "1" ]; then
    echo "보호 기능: 슬립 방지(caffeinate) + 알림 워처 활성화"
else
    echo "보호 기능: 슬립 방지(caffeinate) (REC_NO_NOTIFY=1로 알림 비활성)"
fi
