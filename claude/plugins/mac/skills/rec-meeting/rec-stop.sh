#!/bin/bash
# 미팅 녹음 종료 → 남은 세그먼트 전사 → 합본 → TextEdit 열기
# m5: 미정의 변수와 파이프 실패 즉시 감지.
set -uo pipefail
PID_FILE="$HOME/meeting-log/.rec-pid"
WATCHER_PID_FILE="$HOME/meeting-log/.rec-watcher-pid"
NOTIFY_PID_FILE="$HOME/meeting-log/.rec-notify-pid"
SESSION_FILE="$HOME/meeting-log/.rec-session"
PREV_OUTPUT_FILE="$HOME/meeting-log/.rec-prev-output"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# n3: 공통 헬퍼 (notify, is_our_ffmpeg, escape_as, REC_BREW_PREFIX).
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
BREW_PREFIX="$REC_BREW_PREFIX"

# 1. 녹음 중인지 확인
if [ ! -f "$PID_FILE" ]; then
    echo "진행 중인 녹음이 없습니다."
    exit 1
fi

PID=$(cat "$PID_FILE")
SESSION_DIR=$(cat "$SESSION_FILE" 2>/dev/null)

if [ -z "$SESSION_DIR" ] || [ ! -d "$SESSION_DIR" ]; then
    echo "세션 디렉토리를 찾을 수 없습니다: $SESSION_DIR"
    exit 1
fi

# 2. ffmpeg 종료 (C1/M5: SIGINT → 5초 대기 → SIGTERM → 3초 대기 → SIGKILL escalation)
if is_our_ffmpeg "$PID"; then
    kill -INT "$PID" 2>/dev/null
    # SIGINT 응답 대기 (최대 5초, 0.1초 polling)
    for _ in $(seq 1 50); do
        kill -0 "$PID" 2>/dev/null || break
        sleep 0.1
    done
    # SIGINT 무응답 → SIGTERM
    if kill -0 "$PID" 2>/dev/null; then
        echo "⚠️ ffmpeg가 SIGINT에 응답 안 함, SIGTERM 시도"
        kill -TERM "$PID" 2>/dev/null
        for _ in $(seq 1 30); do
            kill -0 "$PID" 2>/dev/null || break
            sleep 0.1
        done
    fi
    # 최후 SIGKILL
    if kill -0 "$PID" 2>/dev/null; then
        echo "⚠️ SIGTERM 무응답, SIGKILL"
        kill -KILL "$PID" 2>/dev/null
    fi
    # 디스크 flush 대기 (mux 헤더 안전 확보용)
    sleep 0.5
elif kill -0 "$PID" 2>/dev/null; then
    # PID는 살아있지만 우리 ffmpeg가 아님 (PID 재사용 오탐). 무시하고 진행.
    echo "ℹ️ PID ${PID}는 ffmpeg가 아님 (재사용된 PID). 정리만 진행."
fi

# 3. 이전 출력 장치로 복원
if [ -f "$PREV_OUTPUT_FILE" ]; then
    if ! command -v SwitchAudioSource >/dev/null 2>&1; then
        echo "⚠️ SwitchAudioSource를 찾을 수 없어 출력 장치 복원 실패."
        echo "   시스템 설정 → 사운드 → 출력에서 수동으로 원래 장치 선택 필요."
        notify "⚠️ 출력 장치 복원 실패" "시스템 설정 → 사운드에서 수동 변경" "Basso"
    else
        PREV_OUTPUT=$(cat "$PREV_OUTPUT_FILE")
        if SwitchAudioSource -s "$PREV_OUTPUT" >/dev/null 2>&1; then
            echo "출력 복원: $PREV_OUTPUT"
        else
            echo "⚠️ 출력 복원 실패: $PREV_OUTPUT"
            echo "   시스템 설정 → 사운드 → 출력에서 수동 변경 필요."
            notify "⚠️ 출력 장치 복원 실패" "현재 시스템 출력이 Multi-Output에 묶여있을 수 있음" "Basso"
        fi
    fi
fi

# 4. 알림 워처 즉시 종료 (ffmpeg 죽기 전 마지막 알림 막기 위해 먼저 죽임)
if [ -f "$NOTIFY_PID_FILE" ]; then
    NOTIFY_PID=$(cat "$NOTIFY_PID_FILE")
    kill "$NOTIFY_PID" 2>/dev/null
    rm -f "$NOTIFY_PID_FILE"
fi

# 5. PID 파일 삭제 → 세그먼트 워처가 다음 루프에서 자연 종료 + caffeinate도 ffmpeg 사망 감지하고 자동 종료
rm -f "$PID_FILE"

# 5-1. 세그먼트 미리 수집 (C2: 전사 timeout 계산용 + 이후 합본에서 재사용)
shopt -s nullglob
SEGS=("$SESSION_DIR"/seg_*.m4a)
shopt -u nullglob
SEG_COUNT=${#SEGS[@]}

# 6. 워처 종료 대기 + transcribe.py 자식 종료 대기 (C2: timeout 도입)
if [ -f "$WATCHER_PID_FILE" ]; then
    WATCHER_PID=$(cat "$WATCHER_PID_FILE")
    echo "워처 종료 대기 중..."
    WATCHER_TIMEOUT=10
    ELAPSED=0
    while kill -0 "$WATCHER_PID" 2>/dev/null; do
        sleep 1
        ELAPSED=$((ELAPSED + 1))
        if [ "$ELAPSED" -ge "$WATCHER_TIMEOUT" ]; then
            echo "⚠️ 워처 timeout(${WATCHER_TIMEOUT}초). 강제 종료."
            kill -KILL "$WATCHER_PID" 2>/dev/null
            break
        fi
    done

    # 워처의 자식 transcribe가 남아있을 수 있음 (orphan 방지)
    # 직렬 처리라 in-flight는 최대 1개. 세그먼트당 60초 + 최대 600초 cap.
    TRANSCRIBE_TIMEOUT=$(( 60 * SEG_COUNT ))
    [ "$TRANSCRIBE_TIMEOUT" -lt 60 ] && TRANSCRIBE_TIMEOUT=60
    [ "$TRANSCRIBE_TIMEOUT" -gt 600 ] && TRANSCRIBE_TIMEOUT=600
    ELAPSED=0
    while pgrep -f "transcribe.py.*$SESSION_DIR" >/dev/null 2>&1; do
        sleep 1
        ELAPSED=$((ELAPSED + 1))
        if [ "$ELAPSED" -ge "$TRANSCRIBE_TIMEOUT" ]; then
            echo "⚠️ 전사 자식 프로세스 timeout(${TRANSCRIBE_TIMEOUT}초). SIGKILL 후 부분 합본 진행."
            pkill -KILL -f "transcribe.py.*$SESSION_DIR" 2>/dev/null
            notify "⚠️ 전사 timeout" "일부 세그먼트가 timeout. 부분 합본만 진행." "Basso"
            break
        fi
    done
    rm -f "$WATCHER_PID_FILE"
fi

# 7. 세그먼트 존재 확인
if [ "$SEG_COUNT" -eq 0 ]; then
    echo "녹음된 세그먼트가 없습니다: $SESSION_DIR"
    rm -f "$SESSION_FILE" "$PREV_OUTPUT_FILE"
    exit 1
fi

echo "총 세그먼트: ${SEG_COUNT}개"

# 8. 남은 세그먼트 전사 (워처가 미처리한 마지막 세그먼트 포함)
REMAINING=0
for SEG in "${SEGS[@]}"; do
    TXT="${SEG%.m4a}.txt"
    if [ ! -f "$TXT" ]; then
        REMAINING=$((REMAINING + 1))
    fi
done

if [ "$REMAINING" -gt 0 ]; then
    echo "남은 세그먼트 ${REMAINING}개 전사 중..."
    for SEG in "${SEGS[@]}"; do
        TXT="${SEG%.m4a}.txt"
        if [ ! -f "$TXT" ]; then
            # M3: stdout 도배 방지(stderr는 살림). M8: BREW_PREFIX 동적.
            PATH="$BREW_PREFIX/bin:$PATH" python3 "$SCRIPT_DIR/transcribe.py" "$SEG" "$TXT" >/dev/null
        fi
    done
fi

# 9. m4a 합치기
TIMESTAMP=$(basename "$SESSION_DIR" | sed 's/session-//')
FINAL_M4A="$HOME/meeting-log/meeting-$TIMESTAMP.m4a"
FINAL_TXT="$HOME/meeting-log/meeting-$TIMESTAMP.txt"
CONCAT_LIST="$SESSION_DIR/concat.txt"

: > "$CONCAT_LIST"
for SEG in "${SEGS[@]}"; do
    echo "file '$SEG'" >> "$CONCAT_LIST"
done

# concat 실패 시 사용자가 원인을 볼 수 있도록 stderr는 살리고 stdout(진행 표시)만 버림
ffmpeg -y -f concat -safe 0 -i "$CONCAT_LIST" -c copy "$FINAL_M4A" </dev/null >/dev/null

# 10. 텍스트 합치기 (세그먼트 순서대로)
: > "$FINAL_TXT"
for SEG in "${SEGS[@]}"; do
    TXT="${SEG%.m4a}.txt"
    if [ -f "$TXT" ]; then
        cat "$TXT" >> "$FINAL_TXT"
        echo "" >> "$FINAL_TXT"
    fi
done

# 11. 세션 디렉토리 정리 (최종 파일들이 정상 생성됐을 때만)
rm -f "$SESSION_FILE" "$PREV_OUTPUT_FILE"

if [ -s "$FINAL_M4A" ] && [ -f "$FINAL_TXT" ]; then
    rm -rf "$SESSION_DIR"
    SIZE=$(du -h "$FINAL_M4A" | cut -f1)
    echo "녹음 합본: $FINAL_M4A ($SIZE)"
    echo "트랜스크립트: $FINAL_TXT"
    notify "✅ 녹음 종료" "트랜스크립트 준비 완료 ($SIZE). TextEdit에서 열림" "Glass"
else
    echo "⚠️ 최종 파일 생성 실패. 세션 데이터 보존됨: $SESSION_DIR"
    notify "⚠️ 녹음 종료 (오류)" "최종 파일 생성 실패. 세션 보존됨" "Basso"
fi

# 12. TextEdit으로 열기 (REC_NO_OPEN=1이면 자동 오픈 안 함 — 테스트/배치 모드용)
if [ -f "$FINAL_TXT" ] && [ "${REC_NO_OPEN:-0}" != "1" ]; then
    open -a TextEdit "$FINAL_TXT"
fi

echo "완료"
