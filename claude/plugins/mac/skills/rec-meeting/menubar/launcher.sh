#!/bin/bash
# rec-meeting 메뉴바 런처 (xbar/SwiftBar에 이 파일이 "복사"되어 설치된다).
#
# 왜 심볼릭 링크가 아니라 런처인가:
#   플러그인은 ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/ 에 설치되고
#   버전이 올라가면 경로가 바뀐다. 링크를 걸어두면 업데이트 때마다 끊긴다.
#   이 런처는 매 실행마다 현재 설치 경로를 다시 찾으므로 끊기지 않는다.
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

find_skill_dir() {
    # 1순위: 플러그인 캐시 (가장 최근 수정된 버전)
    local d
    d=$(ls -td "$HOME"/.claude/plugins/cache/*/*/*/skills/rec-meeting 2>/dev/null | head -1)
    [ -n "$d" ] && { echo "$d"; return 0; }
    # 2순위: 로컬 스킬 디렉터리 (개발용 설치)
    [ -d "$HOME/.claude/skills/rec-meeting" ] && { echo "$HOME/.claude/skills/rec-meeting"; return 0; }
    return 1
}

SKILL_DIR=$(find_skill_dir) || {
    echo "🎙⚠️"
    echo "---"
    echo "rec-meeting 스킬을 찾을 수 없습니다"
    echo "Claude Code에서: /plugin install bj-mac@builder-journey"
    exit 0
}

exec "$SKILL_DIR/menubar/rec-meeting.1s.sh"
