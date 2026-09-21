# 설치 가이드 (Step by Step)

> 이 가이드는 실제 개발 중 마주친 모든 함정을 포함한다. 순서대로 따라하면 한 번에 성공한다.

## Step 1. 필수 패키지 설치

```bash
brew install blackhole-2ch switchaudio-osx ffmpeg
python3 -m pip install mlx-whisper
```

| 패키지 | 역할 |
|---|---|
| `blackhole-2ch` | 시스템 오디오를 가상 입력으로 라우팅하는 가상 오디오 드라이버 |
| `switchaudio-osx` | CLI로 macOS 오디오 입출력 장치 전환 |
| `ffmpeg` | 오디오 캡처 + 믹싱 + 인코딩 |
| `mlx-whisper` | 로컬 트랜스크립션 (Apple Silicon 네이티브 MLX 프레임워크) |

**모델 최초 다운로드(~1.5GB)는 첫 전사 시 자동 수행**되고 `~/.cache/huggingface/hub/`에 영구 저장된다. 기본 모델은 `mlx-community/whisper-large-v3-turbo`.

### 성능 참고 (MacBook Pro 기준, 45분 오디오)

| 구성 | 소요 |
|---|---|
| openai-whisper (medium) + mps | ~20분 |
| **mlx-whisper (large-v3-turbo), 단일 실행** | **~2분 50초** |
| mlx-whisper + 4-way 병렬 | 오히려 더 느림 (GPU 경합) |

→ mlx-whisper는 단일 프로세스가 Metal GPU를 꽉 채워서, **병렬 전사는 오히려 손해**. 스킬은 녹음 중 세그먼트를 **순차 처리**해서 녹음 시간에 계산을 묻는 방식이다.

## Step 2. 재부팅 ⚠️ 필수

BlackHole은 커널 확장이므로 **설치 후 반드시 재부팅**해야 장치가 잡힌다.

**검증:**

```bash
ffmpeg -f avfoundation -list_devices true -i "" 2>&1 | grep BlackHole
```

기대 출력:
```
[AVFoundation indev @ ...] [0] BlackHole 2ch
```

안 나오면 재부팅이 안 됐거나 BlackHole 설치가 실패한 것.

## Step 3. Multi-Output Device 생성 ⚠️ 가장 중요

> **이 스킬 세팅에서 가장 함정이 많은 부분이다.** Master Device 설정을 놓치면 Chrome/Meet 오디오가 녹음에 들어가지 않는다. Step 3.3을 특히 주의할 것.

### 3.1. Audio MIDI Setup 열기

Spotlight(⌘+Space)에서 `audio midi` 검색해서 실행.

### 3.2. Multi-Output Device 생성

1. 좌측 하단 **`+` 버튼** → **Create Multi-Output Device**
2. 우측 장치 목록에서 다음 2개 체크:
   - ✅ **MacBook Pro Speakers** (또는 상시 쓰는 출력장치)
   - ✅ **BlackHole 2ch**

### 3.3. Master Device를 BlackHole로 설정 ⚠️

우측 장치 목록 위쪽의 **Master Device** 드롭다운을 **`BlackHole 2ch`** 로 변경.

**이유:**
Chrome(Google Meet, 일부 웹 앱 포함)은 Multi-Output Device의 **Master Device로만 오디오를 보낸다**. Master가 Speakers로 되어 있으면:

- ✅ 사용자는 Speakers로 소리를 듣지만
- ❌ BlackHole에는 아무것도 안 흘러서 **녹음에 상대방 목소리가 안 잡힌다**

Master를 BlackHole로 설정하면 Chrome이 BlackHole로 출력 → Multi-Output이 이를 Speakers에도 복제 → 사용자는 듣고 ffmpeg는 녹음할 수 있다.

### 3.4. Drift Correction 설정

- ✅ **MacBook Pro Speakers** 행: Drift Correction 체크
- ❌ **BlackHole 2ch** 행: Drift Correction 해제

(Master가 아닌 장치에만 체크하는 것이 원칙)

### 3.5. 검증

```bash
SwitchAudioSource -a | grep "Multi-Output Device"
```

기대 출력:
```
Multi-Output Device
```

안 나오면 이름이 다를 수 있음. 이름을 바꿨다면 환경변수 `REC_MULTI_OUTPUT_NAME`로 override.

## Step 4. 기본 입력(마이크) 확인

```bash
SwitchAudioSource -t input -c
```

기대 출력 예:
```
MacBook Pro Microphone
```

외장 마이크를 쓰면 그 이름이 나온다. 이 이름을 스크립트가 자동 감지해서 쓰기 때문에 별도 설정은 필요 없다.

## Step 5. 설치 최종 확인

**한 번에 점검 (권장):**

```bash
REC_DIR=$(find ~/.claude/plugins/cache -type d -name rec-meeting | head -1)
"$REC_DIR"/check-setup.sh
```

9가지 항목(arch/brew/ffmpeg/switchaudio/BlackHole/Multi-Output/마이크/mlx-whisper/모델 캐시)을 한 번에 체크하고, 실패한 항목별로 조치 방법을 ✅/❌ 형식으로 출력한다.

## Step 6. 첫 실행 시 macOS 권한 팝업

처음 `rec-start.sh` 실행 시 macOS가 마이크 + 시스템 오디오 권한을 묻는다. **모두 "허용"** 클릭. 거부하면 무음 파일이 저장된다.

권한 변경은 **시스템 설정 → 개인정보 보호 및 보안 → 마이크** 에서 사용 중인 터미널 앱(Terminal/iTerm/Warp 등) 또는 `ffmpeg` 항목을 토글.
macOS Sequoia(15+)에서는 **화면 녹화** 권한도 함께 요구될 수 있음.

## Step 7. (선택) 메뉴바 아이콘 활성화

매번 터미널/Claude를 거치는 게 귀찮다면 메뉴바에서 한 번 클릭으로 시작/종료 가능.

**1단계.** xbar 또는 SwiftBar 둘 중 하나 설치:

```bash
brew install --cask xbar       # 안정적, 오래된 도구
# 또는
brew install --cask swiftbar   # 가벼움, Apple Silicon 네이티브
```

설치한 도구를 한 번 실행해서 메뉴바에 자리 잡게 하기.

**2단계.** 플러그인 등록:

```bash
REC_DIR=$(find ~/.claude/plugins/cache -type d -name rec-meeting | head -1)
"$REC_DIR"/install-menubar.sh
```

메뉴바에 🎙 아이콘이 나타나며, 녹음 중에는 🔴 + 경과 시간 표시. 클릭으로 시작/종료/폴더 열기/설치 점검 가능.

해제: `./install-menubar.sh remove` (xbar/SwiftBar 자체는 그대로 두고 플러그인만 빠짐)

---

# 사용법

```bash
REC_DIR=$(find ~/.claude/plugins/cache -type d -name rec-meeting | head -1)
# 녹음 시작
"$REC_DIR"/rec-start.sh

# 녹음 종료 + 트랜스크립션 + TextEdit 열기
"$REC_DIR"/rec-stop.sh
```

또는 스킬 호출:
- **"녹음 시작해줘"** → `rec-start.sh`
- **"녹음 끝"** → `rec-stop.sh`

저장 위치: `~/meeting-log/meeting-YYYYMMDD-HHMMSS.{m4a,txt}`

## Google Meet 사용 시 권장 순서

Meet은 macOS 시스템 기본 출력을 **대부분** 따라오지만, 통화 중 시스템 출력이 바뀌면 반영이 늦을 수 있다. 안정적으로 쓰려면:

1. 먼저 **녹음 시작** (`rec-start.sh`)
2. 그 다음 **Meet 입장**

또는 Meet 통화창 우측 하단 `⋮` → 설정 → 오디오 → **스피커**를 `Multi-Output Device`로 명시 설정. Meet은 구글 계정별로 오디오 설정을 기억하므로 한 번 해두면 재사용 가능.
