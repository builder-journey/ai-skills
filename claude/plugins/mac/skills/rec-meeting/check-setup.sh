#!/bin/bash
# rec-meeting 설치 상태 한 번에 점검
# 사용: 이 스크립트를 직접 실행하거나 Claude에서 rec-meeting 스킬 호출
# m5: 미정의 변수/파이프 실패 즉시 감지.
set -uo pipefail

MULTI_OUTPUT_NAME="${MULTI_OUTPUT_NAME:-Multi-Output Device}"

# n2: TTY가 아닐 땐 ANSI 코드 빼서 plain text로.
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    GREEN=''; RED=''; YELLOW=''; NC=''
fi

ok=0
fail=0

pass() { echo -e "${GREEN}✅${NC} $1"; ok=$((ok+1)); }
err() { echo -e "${RED}❌${NC} $1"; echo -e "   ${YELLOW}→${NC} $2"; fail=$((fail+1)); }

echo "rec-meeting 설치 점검 시작"
echo "──────────────────────────────────"

# 0. Apple Silicon (M4: Intel Mac에서는 mlx-whisper가 import 단계에서 fail)
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    pass "Apple Silicon ($ARCH) — Metal GPU 가속 지원"
else
    err "Intel Mac은 미지원 (arch=$ARCH)" "mlx-whisper는 Apple Silicon (M1/M2/M3/M4) 전용. Intel Mac은 openai-whisper로 fallback 필요."
fi

# 1. brew
if command -v brew >/dev/null 2>&1; then
    pass "Homebrew 설치됨"
else
    err "Homebrew 없음" "https://brew.sh 에서 한 줄 설치 명령어 실행"
fi

# 2. ffmpeg
if command -v ffmpeg >/dev/null 2>&1; then
    pass "ffmpeg 설치됨 ($(ffmpeg -version 2>&1 | head -1 | awk '{print $3}'))"
else
    err "ffmpeg 없음" "brew install ffmpeg"
fi

# 3. switchaudio-osx
if command -v SwitchAudioSource >/dev/null 2>&1; then
    pass "switchaudio-osx 설치됨"
else
    err "switchaudio-osx 없음" "brew install switchaudio-osx"
fi

# 4. BlackHole 2ch (avfoundation) — ffmpeg가 항상 nonzero 종료하므로 출력 캡처 후 grep.
if command -v ffmpeg >/dev/null 2>&1; then
    FFMPEG_DEVICES=$(ffmpeg -f avfoundation -list_devices true -i "" 2>&1 || true)
    if echo "$FFMPEG_DEVICES" | grep -q "BlackHole 2ch"; then
        pass "BlackHole 2ch 인식됨 (가상 오디오 드라이버)"
    else
        err "BlackHole 2ch 없음 또는 미인식" "brew install blackhole-2ch 후 ⚠️ 반드시 재부팅"
    fi
fi

# 5. Multi-Output Device
if command -v SwitchAudioSource >/dev/null 2>&1; then
    if SwitchAudioSource -a | grep -q "^${MULTI_OUTPUT_NAME}$"; then
        pass "'$MULTI_OUTPUT_NAME' 존재"
    else
        err "'$MULTI_OUTPUT_NAME' 없음" "Audio MIDI Setup에서 생성 (README Step 3)"
    fi
fi

# 6. 기본 마이크 입력
if command -v SwitchAudioSource >/dev/null 2>&1; then
    MIC=$(SwitchAudioSource -t input -c 2>/dev/null)
    if [ -n "$MIC" ]; then
        pass "기본 마이크: $MIC"
    else
        err "기본 마이크 감지 실패" "시스템 설정 → 사운드 → 입력에서 마이크 선택"
    fi
fi

# 7. mlx-whisper (Python 패키지)
if PATH="/opt/homebrew/bin:$PATH" python3 -c "import mlx_whisper" 2>/dev/null; then
    pass "mlx-whisper 설치됨 (Apple Silicon 가속 Whisper)"
else
    err "mlx-whisper 없음" "python3 -m pip install mlx-whisper"
fi

# 8. 모델 캐시 (선택 — 없어도 첫 실행 시 자동 다운로드)
MODEL_DIR="$HOME/.cache/huggingface/hub/models--mlx-community--whisper-large-v3-turbo"
if [ -d "$MODEL_DIR" ]; then
    SIZE=$(du -sh "$MODEL_DIR" 2>/dev/null | cut -f1)
    pass "Whisper 모델 캐시 존재 ($SIZE)"
else
    echo -e "${YELLOW}ℹ️${NC}  Whisper 모델 미다운로드 (첫 녹음 시 자동, ~1.5GB)"
fi

# 9. macOS 권한 안내 (자동 점검 불가)
echo -e "${YELLOW}ℹ️${NC}  macOS 마이크 권한: 첫 ffmpeg 실행 시 시스템 팝업이 뜨면 '허용' 클릭 필요"
echo -e "${YELLOW}ℹ️${NC}  macOS Sequoia(15+): 일부 케이스에서 '화면 녹화' 권한도 요구. 시스템 설정 → 개인정보 보호 → 화면 녹화에서 사용 중인 터미널 앱 허용"
echo -e "${YELLOW}ℹ️${NC}  알림 권한: 첫 알림 실행 시 시스템 팝업에서 '허용' 클릭 (시스템 설정 → 알림 → 스크립트 편집기)"

echo "──────────────────────────────────"
if [ "$fail" -eq 0 ]; then
    echo -e "${GREEN}✓ 모두 정상 (${ok}개 항목 통과). 사용 준비 완료.${NC}"
    echo "  녹음 시작: $(cd "$(dirname "$0")" && pwd)/rec-start.sh"
    exit 0
else
    echo -e "${RED}✗ ${fail}개 항목 실패. 위 안내대로 조치 후 다시 실행하세요.${NC}"
    exit 1
fi
