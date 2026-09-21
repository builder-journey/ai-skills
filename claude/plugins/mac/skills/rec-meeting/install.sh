#!/bin/bash
# rec-meeting 통합 설치 스크립트.
#
# 새 Mac에서 처음 실행하면 자동으로:
#   1. 환경 확인 (Apple Silicon 필수)
#   2. Homebrew 설치 (없으면)
#   3. blackhole-2ch / switchaudio-osx / ffmpeg / mlx-whisper 설치
#   4. BlackHole 인식 → 미인식이면 재부팅 안내 (재부팅 후 다시 실행)
#   5. Multi-Output Device 확인 → 없으면 Audio MIDI Setup 열고 4단계 가이드
#   6. xbar 설치 (선택) + 메뉴바 플러그인 등록
#   7. 첫 권한 안내 (마이크/화면녹화/알림)
#   8. 최종 점검 (check-setup.sh)
#
# 재실행해도 안전 — 이미 설정된 항목은 건너뜀 (idempotent).
set -uo pipefail

if [ -t 1 ]; then
    GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
    BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
else
    GREEN=''; RED=''; YELLOW=''; BOLD=''; DIM=''; NC=''
fi

ok()    { echo -e "${GREEN}✅${NC} $1"; }
warn()  { echo -e "${YELLOW}⚠️${NC}  $1"; }
fail()  { echo -e "${RED}❌${NC} $1"; }
step()  { echo -e "\n${BOLD}━━━ $1 ━━━${NC}"; }
hint()  { echo -e "  ${DIM}$1${NC}"; }

ask() {
    local prompt="$1" default="${2:-y}" ans
    if [ ! -t 0 ]; then return 0; fi  # 비대화식 환경에선 yes로 진행
    printf "  ${prompt} [${default}]: "
    read -r ans
    ans="${ans:-$default}"
    [ "$ans" = "y" ] || [ "$ans" = "Y" ] || [ "$ans" = "yes" ]
}

pause() {
    if [ -t 0 ]; then
        printf "  ${DIM}완료했으면 Enter를 누르세요...${NC}"
        read -r _
    fi
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo -e "${BOLD}🎙  rec-meeting 통합 설치 스크립트${NC}"
echo -e "${DIM}    한 번 실행으로 모든 세팅을 끝냅니다. 재실행해도 안전합니다.${NC}"

# ─── Step 0: 환경 확인 ───
step "0/8. 환경 확인"
ARCH=$(uname -m)
if [ "$ARCH" != "arm64" ]; then
    fail "Apple Silicon Mac이 아닙니다 (arch=$ARCH)"
    hint "rec-meeting은 mlx-whisper(Apple Silicon Metal 가속)에 의존합니다."
    hint "Intel Mac은 미지원."
    exit 1
fi
ok "Apple Silicon ($ARCH)"
ok "macOS $(sw_vers -productVersion)"

# ─── Step 1: Homebrew ───
step "1/8. Homebrew"
if command -v brew >/dev/null 2>&1; then
    ok "Homebrew 설치됨"
else
    warn "Homebrew 없음."
    if ask "Homebrew를 자동 설치할까요? (https://brew.sh)" "y"; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
            fail "Homebrew 설치 실패"
            exit 1
        }
    else
        hint "브라우저로 https://brew.sh 에서 직접 설치 후 이 스크립트를 다시 실행하세요."
        exit 1
    fi
fi
BREW_PREFIX="$(brew --prefix)"
export PATH="$BREW_PREFIX/bin:$PATH"

# ─── Step 2: 패키지 ───
step "2/8. brew 패키지 설치"
PKGS_NEEDED=()
for pkg in blackhole-2ch switchaudio-osx ffmpeg; do
    if brew list "$pkg" >/dev/null 2>&1; then
        ok "$pkg 설치됨"
    else
        PKGS_NEEDED+=("$pkg")
    fi
done
if [ ${#PKGS_NEEDED[@]} -gt 0 ]; then
    hint "설치 필요: ${PKGS_NEEDED[*]}"
    if ask "지금 brew install 진행할까요?" "y"; then
        brew install "${PKGS_NEEDED[@]}"
    else
        fail "필수 패키지 누락. 종료."
        exit 1
    fi
fi

# ─── Step 3: mlx-whisper ───
step "3/8. mlx-whisper (Python AI 모델)"
if python3 -c "import mlx_whisper" 2>/dev/null; then
    ok "mlx-whisper 설치됨"
else
    hint "pip로 mlx-whisper 설치 (~50MB, 모델 캐시는 첫 녹음 시 추가 1.5GB)"
    if ask "지금 설치할까요?" "y"; then
        python3 -m pip install --user mlx-whisper || python3 -m pip install mlx-whisper
    else
        fail "mlx-whisper 누락. 종료."
        exit 1
    fi
fi

# ─── Step 4: BlackHole 인식 (재부팅 분기) ───
step "4/8. BlackHole 커널 드라이버 인식"
DEVICES=$(ffmpeg -f avfoundation -list_devices true -i "" 2>&1 || true)
if echo "$DEVICES" | grep -q "BlackHole 2ch"; then
    ok "BlackHole 2ch 인식됨"
else
    warn "BlackHole이 아직 인식되지 않습니다."
    echo ""
    echo "  ┌──────────────────────────────────────────────┐"
    echo "  │  ⚠️  Mac 재부팅이 필요합니다.                │"
    echo "  │                                              │"
    echo "  │  BlackHole은 커널 드라이버라 재부팅 후에야   │"
    echo "  │  시스템에서 인식됩니다. 1회성 작업입니다.    │"
    echo "  └──────────────────────────────────────────────┘"
    echo ""
    hint "재부팅 후 이 스크립트를 다시 실행하면 다음 단계가 자동 진행됩니다:"
    hint "  $0"
    echo ""
    if ask "지금 바로 재부팅할까요? (저장 안 한 작업 손실 주의)" "n"; then
        echo "10초 후 재부팅합니다. Ctrl+C로 취소 가능..."
        sleep 10
        sudo shutdown -r now
    fi
    # Exit 2: 재부팅 필요 신호 (Claude/SKILL.md가 이 코드 보고 사용자에게 재부팅 안내)
    exit 2
fi

# ─── Step 5: Multi-Output Device (Swift Core Audio API로 자동 생성) ───
step "5/8. Multi-Output Device 자동 생성"
if SwitchAudioSource -a | grep -q "^Multi-Output Device$"; then
    ok "Multi-Output Device 존재"
else
    warn "Multi-Output Device가 없습니다. Swift Core Audio API로 자동 생성을 시도합니다."
    if command -v swift >/dev/null 2>&1; then
        if swift "$SCRIPT_DIR/setup-multi-output.swift"; then
            ok "Multi-Output Device 자동 생성 완료 (Master=BlackHole 2ch)"
        else
            fail "Swift 자동 생성 실패. GUI 수동 모드로 전환합니다."
            MULTI_OUTPUT_MANUAL=1
        fi
    else
        warn "Xcode Command Line Tools(swift)가 없어 GUI 수동 모드로 전환합니다."
        hint "다음에 'xcode-select --install'로 CLT를 설치하면 자동화 가능."
        MULTI_OUTPUT_MANUAL=1
    fi

    if [ "${MULTI_OUTPUT_MANUAL:-0}" = "1" ]; then
        echo ""
        echo "  Audio MIDI Setup 앱을 자동으로 열어드립니다. 다음 4단계 따라해주세요:"
        echo -e "    ${BOLD}1)${NC} 좌측 하단 ${BOLD}'+'${NC} → ${BOLD}'Create Multi-Output Device'${NC}"
        echo -e "    ${BOLD}2)${NC} 우측 목록 ${BOLD}둘 다 체크${NC}: ✅ MacBook Pro Speakers + ✅ BlackHole 2ch"
        echo -e "    ${BOLD}3)${NC} 위쪽 ${BOLD}'Master Device'${NC} → ${BOLD}'BlackHole 2ch'${NC} ${RED}⚠️ 가장 중요${NC}"
        echo -e "    ${BOLD}4)${NC} 'MacBook Pro Speakers' 줄의 ${BOLD}'Drift Correction'${NC} 체크"
        echo ""
        open -a "Audio MIDI Setup"
        pause
    fi

    if ! SwitchAudioSource -a | grep -q "^Multi-Output Device$"; then
        fail "여전히 'Multi-Output Device'가 감지되지 않습니다."
        exit 1
    fi
    ok "Multi-Output Device 등록 확인"
fi

# ─── Step 6: xbar 메뉴바 (선택) ───
step "6/8. 메뉴바 아이콘 (xbar, 선택사항)"
echo "  메뉴바에서 클릭으로 녹음 시작/종료 가능. (선택사항)"
XBAR_OK=0
if [ -d "/Applications/xbar.app" ]; then
    ok "xbar 설치됨"
    XBAR_OK=1
else
    if ask "xbar를 설치할까요?" "y"; then
        brew install --cask xbar
        if [ -d "/Applications/xbar.app" ]; then
            open -a xbar
            sleep 3
            ok "xbar 설치 완료 + 첫 실행"
            XBAR_OK=1
        else
            warn "xbar 설치 실패. 메뉴바 없이 진행."
        fi
    else
        hint "건너뛰기 (Claude에 '녹음 시작해줘'로만 사용)"
    fi
fi

if [ "$XBAR_OK" = "1" ]; then
    "$SCRIPT_DIR/install-menubar.sh" install || true
fi

# ─── Step 7: 권한 안내 ───
step "7/8. macOS 권한 (첫 녹음 시 자동 팝업)"
echo "  처음 'rec-start' 실행 시 macOS가 권한 팝업을 띄웁니다."
echo "  모두 ${BOLD}'허용'${NC} 클릭하세요:"
echo ""
echo "    🎤 ${BOLD}마이크 사용 권한${NC}"
echo "    🖥  ${BOLD}화면 녹화 권한${NC} (macOS Sequoia 15+ 필수)"
echo "    🔔 ${BOLD}알림 권한${NC} (스크립트 편집기 / xbar)"
echo ""
hint "거부했다면 시스템 설정 → 개인정보 보호 및 보안에서 토글로 변경 가능."

# ─── Step 8: 최종 점검 ───
step "8/8. 최종 점검"
"$SCRIPT_DIR/check-setup.sh"

# ─── 완료 ───
echo ""
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  ✅ 설치 완료!${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  ${BOLD}사용 방법${NC}"
echo "    1. Claude에 ${BOLD}'녹음 시작해줘'${NC}"
[ "$XBAR_OK" = "1" ] && echo "       ${DIM}또는 메뉴바 🎙 클릭${NC}"
echo "    2. 미팅 진행"
echo "    3. Claude에 ${BOLD}'녹음 끝'${NC}"
[ "$XBAR_OK" = "1" ] && echo "       ${DIM}또는 메뉴바 🔴 → ⏹ 녹음 종료${NC}"
echo "    4. TextEdit이 트랜스크립트 자동 오픈"
echo ""
echo "  ${BOLD}저장 위치${NC}: ~/meeting-log/meeting-YYYYMMDD-HHMMSS.{m4a,txt}"
echo "  ${BOLD}자세한 내용${NC}: $SCRIPT_DIR/README.md"
