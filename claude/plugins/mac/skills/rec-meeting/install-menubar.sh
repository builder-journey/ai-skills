#!/bin/bash
# 메뉴바 플러그인 설치/해제 (xbar 또는 SwiftBar 자동 감지).
# 사용:
#   ./install-menubar.sh           # 등록
#   ./install-menubar.sh remove    # 해제
#   ./install-menubar.sh status    # 상태 확인
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_SRC="$SCRIPT_DIR/menubar/rec-meeting.1s.sh"
# 메뉴바에는 링크가 아니라 런처를 "복사"해 넣는다.
# 플러그인 버전이 올라가 경로가 바뀌어도 런처가 매번 현재 경로를 다시 찾는다.
LAUNCHER_SRC="$SCRIPT_DIR/menubar/launcher.sh"

XBAR_DIR="$HOME/Library/Application Support/xbar/plugins"
SWIFTBAR_DIR="$HOME/Library/Application Support/SwiftBar"

cmd="${1:-install}"

detect_host() {
    if [ -d "$XBAR_DIR" ]; then
        echo "xbar"
    elif [ -d "$SWIFTBAR_DIR" ]; then
        echo "swiftbar"
    else
        echo "none"
    fi
}

case "$cmd" in
    install)
        chmod +x "$PLUGIN_SRC" "$LAUNCHER_SRC" 2>/dev/null || true
        HOST=$(detect_host)
        case "$HOST" in
            xbar)
                rm -f "$XBAR_DIR/rec-meeting.1s.sh"
                cp "$LAUNCHER_SRC" "$XBAR_DIR/rec-meeting.1s.sh"
                chmod +x "$XBAR_DIR/rec-meeting.1s.sh"
                echo "✅ xbar에 등록 완료"
                echo "   런처: $XBAR_DIR/rec-meeting.1s.sh (플러그인 경로 자동 추적)"
                echo ""
                echo "메뉴바에 🎙 아이콘이 5초 내 나타납니다."
                echo "안 보이면 xbar 메뉴 → Refresh All 클릭."
                ;;
            swiftbar)
                # SwiftBar는 Plugins 폴더 위치를 사용자가 설정. 가장 흔한 기본값 시도.
                SWIFTBAR_PLUGINS="$SWIFTBAR_DIR/Plugins"
                mkdir -p "$SWIFTBAR_PLUGINS"
                rm -f "$SWIFTBAR_PLUGINS/rec-meeting.1s.sh"
                cp "$LAUNCHER_SRC" "$SWIFTBAR_PLUGINS/rec-meeting.1s.sh"
                chmod +x "$SWIFTBAR_PLUGINS/rec-meeting.1s.sh"
                echo "✅ SwiftBar에 등록 완료"
                echo "   런처: $SWIFTBAR_PLUGINS/rec-meeting.1s.sh (플러그인 경로 자동 추적)"
                echo ""
                echo "메뉴바 아이콘 표시. 안 보이면 SwiftBar Preferences에서"
                echo "Plugin Folder를 '$SWIFTBAR_PLUGINS'로 지정해주세요."
                ;;
            none)
                echo "❌ xbar 또는 SwiftBar가 설치돼 있지 않습니다."
                echo ""
                echo "둘 중 하나를 설치하세요 (둘 다 무료, 기능 비슷):"
                echo "  brew install --cask xbar       # 더 오래된, 안정적"
                echo "  brew install --cask swiftbar   # 가벼움, Apple Silicon 네이티브"
                echo ""
                echo "설치하고 한 번 실행한 다음 이 명령어를 다시 돌리세요."
                exit 1
                ;;
        esac
        ;;
    remove|uninstall)
        REMOVED=0
        if [ -L "$XBAR_DIR/rec-meeting.1s.sh" ] || [ -f "$XBAR_DIR/rec-meeting.1s.sh" ]; then
            rm -f "$XBAR_DIR/rec-meeting.1s.sh"
            echo "✅ xbar에서 제거"
            REMOVED=1
        fi
        SWIFTBAR_PLUGINS="$SWIFTBAR_DIR/Plugins"
        if [ -L "$SWIFTBAR_PLUGINS/rec-meeting.1s.sh" ] || [ -f "$SWIFTBAR_PLUGINS/rec-meeting.1s.sh" ]; then
            rm -f "$SWIFTBAR_PLUGINS/rec-meeting.1s.sh"
            echo "✅ SwiftBar에서 제거"
            REMOVED=1
        fi
        [ "$REMOVED" -eq 0 ] && echo "ℹ️ 등록된 메뉴바 플러그인 없음"
        ;;
    status)
        HOST=$(detect_host)
        echo "감지된 호스트: $HOST"
        if [ -e "$XBAR_DIR/rec-meeting.1s.sh" ]; then
            echo "✅ xbar 등록됨"
        fi
        SWIFTBAR_PLUGINS="$SWIFTBAR_DIR/Plugins"
        if [ -e "$SWIFTBAR_PLUGINS/rec-meeting.1s.sh" ]; then
            echo "✅ SwiftBar 등록됨"
        fi
        echo ""
        echo "메뉴바 플러그인 출력 미리보기:"
        echo "──────────────────────────────────"
        bash "$PLUGIN_SRC"
        ;;
    *)
        echo "Usage: $0 {install|remove|status}"
        exit 1
        ;;
esac
