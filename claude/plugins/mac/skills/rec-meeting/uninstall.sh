#!/bin/bash
# rec-meeting 완전 제거 스크립트
# 사용:
#   ./uninstall.sh         # dry-run (무엇이 지워질지 미리 보기)
#   ./uninstall.sh --yes   # 실제 삭제
set -uo pipefail

DRY_RUN=1
[ "${1:-}" = "--yes" ] && DRY_RUN=0

if [ -t 1 ]; then
    BOLD='\033[1m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'
else
    BOLD=''; YELLOW=''; GREEN=''; NC=''
fi

echo -e "${BOLD}rec-meeting uninstall${NC}"
if [ "$DRY_RUN" -eq 1 ]; then
    echo -e "${YELLOW}DRY-RUN 모드. 실제 삭제하려면 ./uninstall.sh --yes 실행.${NC}"
fi
echo "──────────────────────────────────"

run() {
    local desc="$1"; shift
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "  [skip] $desc"
        echo "         → $*"
    else
        echo "  $desc"
        "$@" 2>/dev/null || echo "    (이미 없거나 실패 — 무시)"
    fi
}

# 0. 진행 중인 녹음 정리
echo -e "\n${BOLD}1/6. 진행 중인 ffmpeg / 워처 프로세스 정리${NC}"
run "ffmpeg(BlackHole) 종료" pkill -f "ffmpeg.*BlackHole"
run "세그먼트 워처 종료" pkill -f "watch-segments.sh"
run "알림 워처 종료" pkill -f "notify-watcher.sh"

# 1. 임시 상태 파일
echo -e "\n${BOLD}2/6. 임시 상태 파일${NC}"
for f in .rec-pid .rec-watcher-pid .rec-notify-pid .rec-session .rec-prev-output .notify-errors.log; do
    if [ -e "$HOME/meeting-log/$f" ]; then
        run "$HOME/meeting-log/$f 삭제" rm -f "$HOME/meeting-log/$f"
    fi
done

# 2. 미팅 녹음 데이터 (사용자 확인)
echo -e "\n${BOLD}3/6. 미팅 녹음/트랜스크립트 (~/meeting-log/)${NC}"
if [ -d "$HOME/meeting-log" ]; then
    SIZE=$(du -sh "$HOME/meeting-log" 2>/dev/null | cut -f1)
    M4A_COUNT=$(find "$HOME/meeting-log" -maxdepth 1 -name "meeting-*.m4a" 2>/dev/null | wc -l | tr -d ' ')
    echo "  현재 ${SIZE} / 합본 m4a ${M4A_COUNT}개 발견"
    echo -e "  ${YELLOW}⚠️ 녹음 데이터는 보존하려면 별도 백업 후 진행하세요.${NC}"
    if [ "$DRY_RUN" -eq 0 ]; then
        printf "  녹음 데이터까지 삭제할까요? (yes/no, 기본 no): "
        read -r ANSWER
        if [ "$ANSWER" = "yes" ]; then
            rm -rf "$HOME/meeting-log"
            echo "    → 삭제됨"
        else
            echo "    → 보존됨 ($HOME/meeting-log)"
        fi
    else
        echo "  [skip] $HOME/meeting-log 삭제 여부는 --yes 모드에서 사용자 확인"
    fi
fi

# 3. Whisper 모델 캐시 (~1.5GB)
echo -e "\n${BOLD}4/6. Whisper 모델 캐시 (~1.5GB)${NC}"
MODEL_DIR="$HOME/.cache/huggingface/hub/models--mlx-community--whisper-large-v3-turbo"
if [ -d "$MODEL_DIR" ]; then
    SIZE=$(du -sh "$MODEL_DIR" 2>/dev/null | cut -f1)
    echo "  발견: $SIZE"
    run "모델 캐시 삭제" rm -rf "$MODEL_DIR"
else
    echo "  (이미 없음)"
fi

# 4. brew 패키지 (선택)
echo -e "\n${BOLD}5/6. Homebrew 패키지 (blackhole-2ch / switchaudio-osx)${NC}"
echo -e "  ${YELLOW}⚠️ 다른 앱이 의존할 수 있어 자동 제거하지 않습니다.${NC}"
echo "  수동 제거:"
echo "    brew uninstall blackhole-2ch    # 가상 오디오 드라이버 (재부팅 권장)"
echo "    brew uninstall switchaudio-osx  # 오디오 장치 전환 CLI"
echo "  (ffmpeg는 보통 다른 용도로 쓰이므로 제거 권장 안 함)"

# 5. Python 패키지
echo -e "\n${BOLD}6/6. mlx-whisper (Python 패키지)${NC}"
if python3 -c "import mlx_whisper" 2>/dev/null; then
    run "pip uninstall mlx-whisper" python3 -m pip uninstall -y mlx-whisper
fi

# 6. 메뉴바 플러그인 (등록된 경우)
echo -e "\n${BOLD}메뉴바 플러그인 (등록되었다면 해제)${NC}"
SCRIPT_DIR_FOR_INSTALL="$(cd "$(dirname "$0")" && pwd)"
if [ -x "$SCRIPT_DIR_FOR_INSTALL/install-menubar.sh" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "  [skip] 메뉴바 플러그인 해제"
        echo "         → $SCRIPT_DIR_FOR_INSTALL/install-menubar.sh remove"
    else
        "$SCRIPT_DIR_FOR_INSTALL/install-menubar.sh" remove 2>/dev/null || true
    fi
fi

# 7. Multi-Output Device 자동 삭제 (Swift)
echo -e "\n${BOLD}Multi-Output Device${NC}"
if command -v swift >/dev/null 2>&1 && [ -f "$SCRIPT_DIR_FOR_INSTALL/setup-multi-output.swift" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "  [skip] swift로 Multi-Output Device 삭제"
        echo "         → swift $SCRIPT_DIR_FOR_INSTALL/setup-multi-output.swift --remove"
    else
        printf "  Multi-Output Device를 삭제할까요? [y/N]: "
        read -r ANS
        if [ "$ANS" = "y" ] || [ "$ANS" = "Y" ]; then
            swift "$SCRIPT_DIR_FOR_INSTALL/setup-multi-output.swift" --remove 2>/dev/null || true
        fi
    fi
else
    echo "  swift 없음. 수동 삭제: Audio MIDI Setup에서 좌측 'Multi-Output Device' 선택 → '−' 버튼"
fi

echo ""
echo "  스킬 자체를 지우려면 Claude Code에서:"
echo "    /plugin uninstall bj-mac@builder-journey"

echo "──────────────────────────────────"
if [ "$DRY_RUN" -eq 1 ]; then
    echo -e "${YELLOW}DRY-RUN 완료. 실제 실행: ./uninstall.sh --yes${NC}"
else
    echo -e "${GREEN}✓ 제거 완료.${NC}"
fi
