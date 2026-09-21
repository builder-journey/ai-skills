#!/bin/bash
#
# <xbar.title>rec-meeting</xbar.title>
# <xbar.version>v1.0</xbar.version>
# <xbar.author>kezi</xbar.author>
# <xbar.desc>미팅 녹음 시작/종료 토글 + 경과시간 표시</xbar.desc>
# <xbar.refreshInterval>1s</xbar.refreshInterval>
#
# <swiftbar.refreshEvery>1</swiftbar.refreshEvery>
# <swiftbar.runInBash>true</swiftbar.runInBash>
#
# rec-meeting 메뉴바 플러그인 (xbar / SwiftBar 호환).
# 1초마다 갱신해서 녹음 상태 + 경과 시간을 실시간 표시.
#
# 설치: 스킬 디렉터리의 install-menubar.sh

# xbar는 PATH가 비어 있을 수 있으므로 명시적으로 설정.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# xbar/SwiftBar에는 심볼릭 링크로 등록되므로 링크를 역추적해 스킬 디렉터리를 찾는다.
_rec_src="${BASH_SOURCE[0]}"
[ -L "$_rec_src" ] && _rec_src="$(readlink "$_rec_src")"
REC_SKILL_DIR="$(cd "$(dirname "$_rec_src")/.." && pwd)"
PID_FILE="$HOME/meeting-log/.rec-pid"
SESSION_FILE="$HOME/meeting-log/.rec-session"

# ─── 녹음 상태 판정 ───
RECORDING=0
ELAPSED_DISPLAY=""
START_HMS=""

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        if ps -p "$PID" -o command= 2>/dev/null | grep -q "ffmpeg"; then
            RECORDING=1
            if [ -f "$SESSION_FILE" ]; then
                SESSION_DIR=$(cat "$SESSION_FILE" 2>/dev/null || echo "")
                BASENAME=$(basename "$SESSION_DIR" 2>/dev/null || echo "")
                # session-YYYYMMDD-HHMMSS → HH:MM:SS
                STAMP="${BASENAME#session-}"
                if [ ${#STAMP} -ge 15 ]; then
                    HMS="${STAMP:9:2}:${STAMP:11:2}:${STAMP:13:2}"
                    START_HMS="$HMS"
                    # 경과 시간 계산
                    START_EPOCH=$(date -j -f "%Y%m%d-%H%M%S" "$STAMP" +%s 2>/dev/null || echo "")
                    if [ -n "$START_EPOCH" ]; then
                        NOW=$(date +%s)
                        DIFF=$((NOW - START_EPOCH))
                        MIN=$((DIFF / 60))
                        SEC=$((DIFF % 60))
                        ELAPSED_DISPLAY=$(printf "%d:%02d" "$MIN" "$SEC")
                    fi
                fi
            fi
        fi
    fi
fi

# ─── 메뉴바 (--- 위) ───
if [ "$RECORDING" -eq 1 ]; then
    if [ -n "$ELAPSED_DISPLAY" ]; then
        echo "🔴 ${ELAPSED_DISPLAY}"
    else
        echo "🔴 REC"
    fi
else
    echo "🎙"
fi

# ─── 드롭다운 (--- 아래) ───
echo "---"

if [ "$RECORDING" -eq 1 ]; then
    [ -n "$START_HMS" ] && echo "녹음 시작 ${START_HMS} | color=#888"
    [ -n "$ELAPSED_DISPLAY" ] && echo "경과 ${ELAPSED_DISPLAY} | color=#888"
    echo "---"
    echo "⏹ 녹음 종료 | bash='$REC_SKILL_DIR/rec-stop.sh' terminal=false refresh=true"
else
    echo "🎙 녹음 시작 | bash='$REC_SKILL_DIR/rec-start.sh' terminal=false refresh=true"
fi

# 출력 장치 경고: 녹음 안 하는데 Multi-Output에 묶여있으면 표시
if [ "$RECORDING" -eq 0 ]; then
    if command -v SwitchAudioSource >/dev/null 2>&1; then
        CUR_OUT=$(SwitchAudioSource -c 2>/dev/null || echo "")
        if [ "$CUR_OUT" = "Multi-Output Device" ]; then
            echo "---"
            echo "⚠️ 출력이 Multi-Output에 묶여 있음 | color=orange"
            echo "원래 스피커로 복원 (Speakers) | shell=SwitchAudioSource param1=-s param2='MacBook Pro Speakers' terminal=false refresh=true"
        fi
    fi
fi

echo "---"
echo "📁 녹음 폴더 열기 | shell=open param1='$HOME/meeting-log' terminal=false"
echo "🩺 설치 점검 (check-setup) | bash='$REC_SKILL_DIR/check-setup.sh' terminal=true"
echo "📝 README 열기 | shell=open param1='$REC_SKILL_DIR/README.md' terminal=false"
echo "---"
echo "메뉴바 새로고침 | refresh=true"
