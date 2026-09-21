#!/bin/bash
# rec-meeting 공통 헬퍼 라이브러리.
# 사용: 호출 측에서 `source "$SCRIPT_DIR/lib.sh"`.
# n3: 4개 스크립트(rec-start, rec-stop, watch-segments, notify-watcher)에서 중복되던 함수 통합.

# brew prefix 동적 감지 (Apple Silicon=/opt/homebrew, Intel=/usr/local).
# 호출 측이 PATH 구성에 사용.
REC_BREW_PREFIX="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"
export REC_BREW_PREFIX

# PATH 보강 — xbar/launchd 등에서 호출될 때 Homebrew 경로가 누락될 수 있어 명시적으로 추가.
# 이미 PATH에 있으면 중복 방지.
case ":$PATH:" in
    *":$REC_BREW_PREFIX/bin:"*) ;;
    *) export PATH="$REC_BREW_PREFIX/bin:/usr/local/bin:/usr/bin:/bin:$PATH" ;;
esac

# C5: PID + 명령어 검증으로 PID 재사용 오탐 방지.
# 사용: if is_our_ffmpeg "$pid"; then ...
is_our_ffmpeg() {
    local pid="${1:-}"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && \
        ps -p "$pid" -o command= 2>/dev/null | grep -q "ffmpeg"
}

# m4: AppleScript 인자 escape (따옴표/백슬래시 안전 처리).
escape_as() {
    printf '%s' "${1:-}" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# C3 + m3: AppleScript notification.
# 빈 sound 인자 안전 처리 + osascript 실패 시 진단 로그.
# 환경변수 REC_NOTIFY_LOG로 로그 경로 override 가능.
REC_NOTIFY_LOG="${REC_NOTIFY_LOG:-$HOME/meeting-log/.notify-errors.log}"
notify() {
    local title msg sound err
    title=$(escape_as "${1:-}")
    msg=$(escape_as "${2:-}")
    sound="${3:-}"
    if [ -n "$sound" ]; then
        sound=$(escape_as "$sound")
        err=$(osascript -e "display notification \"$msg\" with title \"$title\" sound name \"$sound\"" 2>&1 >/dev/null) || true
    else
        err=$(osascript -e "display notification \"$msg\" with title \"$title\"" 2>&1 >/dev/null) || true
    fi
    if [ -n "$err" ]; then
        {
            echo "[$(date)] osascript notification failed:"
            echo "  title: ${1:-}"
            echo "  msg:   ${2:-}"
            echo "  err:   $err"
            echo "  hint:  시스템 설정 → 알림 → 스크립트 편집기 알림 허용 확인"
        } >> "$REC_NOTIFY_LOG" 2>/dev/null || true
    fi
}
