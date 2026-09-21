#!/bin/bash
# rec-meeting 통합 테스트 러너 (bats 의존성 없는 순수 bash).
# 사용: ./tests/run-all.sh
# 각 시나리오는 PASS/FAIL을 출력하고 마지막에 요약.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_LOG="/tmp/rec-meeting-test-$$.log"

# 테스트 중에는 TextEdit 자동 오픈 비활성화 (rec-stop이 여러 번 호출되므로).
export REC_NO_OPEN=1

if [ -t 1 ]; then
    GREEN='\033[0;32m'; RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'
else
    GREEN=''; RED=''; BOLD=''; NC=''
fi

PASS=0
FAIL=0

run_test() {
    local name="$1"
    shift
    echo -e "\n${BOLD}▶ $name${NC}"
    if "$@" >>"$TEST_LOG" 2>&1; then
        echo -e "  ${GREEN}✅ PASS${NC}"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}❌ FAIL${NC} (로그: $TEST_LOG)"
        FAIL=$((FAIL + 1))
    fi
}

# ─── Test 1: 모든 스크립트 syntax check ───
test_syntax() {
    for f in rec-start.sh rec-stop.sh watch-segments.sh notify-watcher.sh \
             check-setup.sh uninstall.sh lib.sh \
             install-menubar.sh menubar/rec-meeting.1s.sh; do
        bash -n "$SCRIPT_DIR/$f" || return 1
    done
    python3 -c "import ast; ast.parse(open('$SCRIPT_DIR/transcribe.py').read())"
}

# ─── Test 2: lib.sh 함수 단위 테스트 ───
test_lib_functions() {
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/lib.sh"

    # escape_as
    [ "$(escape_as 'hello "world"')" = 'hello \"world\"' ] || return 1
    [ "$(escape_as 'a\b')" = 'a\\b' ] || return 1
    [ "$(escape_as '')" = '' ] || return 1

    # is_our_ffmpeg — 빈 PID는 false
    is_our_ffmpeg "" && return 1
    is_our_ffmpeg "999999" && return 1  # 존재 안 하는 PID

    # 현재 쉘 PID로는 ffmpeg가 아니므로 false
    is_our_ffmpeg "$$" && return 1

    return 0
}

# ─── Test 3: check-setup.sh 종료 코드 ───
test_check_setup() {
    "$SCRIPT_DIR/check-setup.sh" >/dev/null
}

# ─── Test 4: 짧은 녹음 (5초) — 정상 시작/종료/합본 ───
test_short_recording() {
    [ -f "$HOME/meeting-log/.rec-pid" ] && return 1  # 사전 정리 안 됐으면 fail

    BEFORE_OUTPUT=$(SwitchAudioSource -c)
    "$SCRIPT_DIR/rec-start.sh" >/dev/null || return 1

    # 시작 직후 PID 파일 / 출력장치 전환 확인
    [ -f "$HOME/meeting-log/.rec-pid" ] || return 1
    [ "$(SwitchAudioSource -c)" = "Multi-Output Device" ] || return 1

    sleep 4
    "$SCRIPT_DIR/rec-stop.sh" >/dev/null || return 1

    # 종료 후 정리 확인
    [ -f "$HOME/meeting-log/.rec-pid" ] && return 1
    [ -f "$HOME/meeting-log/.rec-watcher-pid" ] && return 1
    [ -f "$HOME/meeting-log/.rec-notify-pid" ] && return 1
    [ -f "$HOME/meeting-log/.rec-session" ] && return 1
    [ -f "$HOME/meeting-log/.rec-prev-output" ] && return 1

    # 출력 장치 복원 확인
    [ "$(SwitchAudioSource -c)" = "$BEFORE_OUTPUT" ] || return 1

    # 합본 파일 존재 확인 (가장 최근 meeting-*.m4a)
    LATEST=$(find "$HOME/meeting-log" -maxdepth 1 -name "meeting-*.m4a" -mmin -1 | head -1)
    [ -s "$LATEST" ] || return 1

    return 0
}

# ─── Test 5: stale 자동 복구 (PID 파일만 있고 ffmpeg 없음) ───
test_stale_recovery() {
    # 모든 상태 파일 정리
    rm -f "$HOME/meeting-log/.rec-pid" "$HOME/meeting-log/.rec-watcher-pid" \
          "$HOME/meeting-log/.rec-notify-pid" "$HOME/meeting-log/.rec-session" \
          "$HOME/meeting-log/.rec-prev-output"

    # 가짜 stale PID (절대 ffmpeg가 아닐 PID)
    echo "1" > "$HOME/meeting-log/.rec-pid"  # init/launchd PID
    echo "$HOME/meeting-log/session-fake-stale" > "$HOME/meeting-log/.rec-session"
    mkdir -p "$HOME/meeting-log/session-fake-stale"

    # rec-start가 자동 복구 후 정상 시작해야 함
    output=$("$SCRIPT_DIR/rec-start.sh" 2>&1)
    echo "$output" | grep -q "비정상 종료\|복구" || return 1

    # 정리
    "$SCRIPT_DIR/rec-stop.sh" >/dev/null
    rm -rf "$HOME/meeting-log/session-fake-stale" 2>/dev/null

    return 0
}

# ─── Test 6: REC_NO_NOTIFY=1 환경변수 동작 ───
test_no_notify() {
    REC_NO_NOTIFY=1 "$SCRIPT_DIR/rec-start.sh" >/dev/null || return 1
    # notify-watcher가 안 떠야 함
    pgrep -f "notify-watcher.sh" >/dev/null && return 1
    [ ! -f "$HOME/meeting-log/.rec-notify-pid" ] || return 1
    "$SCRIPT_DIR/rec-stop.sh" >/dev/null
    return 0
}

# ─── Test 7: 디렉토리 권한 700 ───
test_perms() {
    "$SCRIPT_DIR/rec-start.sh" >/dev/null
    PERMS=$(stat -f "%Lp" "$HOME/meeting-log")
    "$SCRIPT_DIR/rec-stop.sh" >/dev/null
    [ "$PERMS" = "700" ]
}

# ─── Test 8: uninstall.sh dry-run은 실제 삭제하지 않음 ───
test_uninstall_dry_run() {
    "$SCRIPT_DIR/rec-start.sh" >/dev/null
    "$SCRIPT_DIR/rec-stop.sh" >/dev/null

    BEFORE=$(find "$HOME/meeting-log" -maxdepth 1 -name "meeting-*.m4a" 2>/dev/null | wc -l | tr -d ' ')
    "$SCRIPT_DIR/uninstall.sh" >/dev/null  # dry-run
    AFTER=$(find "$HOME/meeting-log" -maxdepth 1 -name "meeting-*.m4a" 2>/dev/null | wc -l | tr -d ' ')
    [ "$BEFORE" = "$AFTER" ]
}

# ─── 실행 ───
echo -e "${BOLD}rec-meeting 통합 테스트${NC}"
echo "로그: $TEST_LOG"
: > "$TEST_LOG"

run_test "T1: 모든 스크립트 syntax check" test_syntax
run_test "T2: lib.sh 함수 단위 테스트 (escape_as / is_our_ffmpeg)" test_lib_functions
run_test "T3: check-setup.sh 정상 종료" test_check_setup
run_test "T4: 짧은 녹음 (5초) 정상 동작 + 정리 + 출력 복원" test_short_recording
run_test "T5: 비정상 종료 자동 복구 (stale PID 파일)" test_stale_recovery
run_test "T6: REC_NO_NOTIFY=1로 알림 워처 비활성화" test_no_notify
run_test "T7: meeting-log 권한 700" test_perms
run_test "T8: uninstall.sh dry-run은 실제 삭제 안 함" test_uninstall_dry_run

echo ""
echo "──────────────────────────────────"
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✓ 모두 통과 ($PASS/$TOTAL)${NC}"
    rm -f "$TEST_LOG"
    exit 0
else
    echo -e "${RED}${BOLD}✗ ${FAIL}건 실패 ($PASS/$TOTAL)${NC}"
    echo "  실패 로그: $TEST_LOG"
    exit 1
fi
