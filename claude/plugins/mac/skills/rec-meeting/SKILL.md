---
name: rec-meeting
description: 미팅 녹음 → 텍스트 변환 자동화. 첫 사용 시 install.sh로 자동 설치/세팅, 이후엔 BlackHole + ffmpeg + mlx-whisper로 녹음·전사. Apple Silicon Mac 전용.
disable-model-invocation: false
argument-hint: "[m4a 파일 경로] (생략 시 새 녹음 시작/종료 모드)"
---

# 미팅 녹음 & 트랜스크립션

## ⚙️ 0단계: 설치 상태 자동 체크 (반드시 먼저 실행)

스킬 호출 시 **무조건 먼저** 다음을 실행한다:

```bash
${CLAUDE_SKILL_DIR}/check-setup.sh
```

이 명령의 종료 코드로 분기:

- **exit 0** (모든 항목 ✅) → 1단계 모드 판단으로 진행
- **exit 1** (어떤 항목 ❌) → 자동 설치 흐름 진입 (아래)

### 자동 설치 흐름

설치 미완료가 감지되면 사용자에게 한 줄로 상황 알리고 (예: "BlackHole 미설치 — 자동 설치 시작합니다") **install.sh를 실행**:

```bash
${CLAUDE_SKILL_DIR}/install.sh
```

install.sh 종료 코드로 분기:

- **exit 0** → 설치 완료. 다시 check-setup.sh 한 번 더 돌려서 ✅ 확인 후 사용자 요청 진행.
- **exit 2** → **재부팅 필요** (BlackHole 커널 드라이버 미인식). 사용자에게 명확히 안내:
  > ⚠️ BlackHole 가상 오디오 드라이버 활성화를 위해 **Mac 재부팅이 필요**합니다.
  > 재부팅 후 다시 "녹음 시작해줘" 또는 같은 요청을 하시면 자동으로 다음 단계가 진행됩니다.
  >
  > 지금 재부팅 하시겠어요? (직접 재부팅하시거나, 작업 저장 후 알려주세요)

  여기서 사용자 입력 대기. 사용자가 재부팅 후 다시 스킬을 호출하면 0단계부터 다시 시작 → install.sh가 idempotent라 다음 단계(Multi-Output Device 자동 생성)부터 자동 진행 → 최종 ✅까지.
- **exit 1** → 에러. 출력 그대로 사용자에게 보여주고, 어느 단계에서 막혔는지 안내.

설치/세팅이 모두 끝났으면 **반드시 사용자에게 "설치 완료. 이제 녹음 시작합니다" 같이 알린 뒤** 원래 요청(녹음 시작 등)으로 넘어간다.

## 🎙 1단계: 모드 판단

`$ARGUMENTS` 값으로 분기:

- **파일 경로가 있으면** (예: `~/Music/foo.m4a`) → 트랜스크립션만 실행 (아래 4단계)
- **비어있으면** → 녹음 시작 (2단계)

## 🔴 2단계: 녹음 시작

```bash
${CLAUDE_SKILL_DIR}/rec-start.sh
```

사용자에게 "녹음 시작됨. 끝나면 '녹음 끝'이라고 알려주세요." 안내 후 대기.

## ⏹ 3단계: 녹음 종료 + 트랜스크립션 + TextEdit 열기

사용자가 종료(`녹음 끝`/`종료`/`중지` 등)를 알리면:

```bash
${CLAUDE_SKILL_DIR}/rec-stop.sh
```

이 스크립트가 녹음 중지 → 파일 저장 → whisper 트랜스크립션 → TextEdit 열기까지 모두 처리한다.

## 📝 4단계: 기존 파일 트랜스크립션만 (모드 분기 시)

```bash
${CLAUDE_SKILL_DIR}/lib.sh  # PATH 설정용
PATH="$REC_BREW_PREFIX/bin:$PATH" python3 ${CLAUDE_SKILL_DIR}/transcribe.py "$ARGUMENTS"
open -a TextEdit "${ARGUMENTS%.*}.txt"
```

또는 더 간단히:

```bash
PATH="$(brew --prefix)/bin:$PATH" python3 ${CLAUDE_SKILL_DIR}/transcribe.py "$ARGUMENTS"
open -a TextEdit "${ARGUMENTS%.*}.txt"
```

## 🩺 사용자가 "녹음 결과가 이상하다"고 할 때

(상대방 목소리 안 잡힘 / 무음 / 중간 끊김 등)

먼저 다음 두 가지 우선 확인 안내:
1. **Audio MIDI Setup → Multi-Output Device → Master Device가 BlackHole 2ch 인지** (가장 흔한 함정)
2. **macOS 마이크 / 화면 녹화 권한**이 사용 중인 터미널 앱(또는 xbar)에 허용돼 있는지

심층 진단 필요 시 `${CLAUDE_SKILL_DIR}/docs/troubleshooting.md` 증상 1~15 참조.

## 💡 비고

- install.sh는 **idempotent** (재실행해도 안전). 이미 된 항목은 건너뜀.
- check-setup.sh는 9개 항목(arch/brew/ffmpeg/switchaudio/BlackHole/Multi-Output/마이크/mlx-whisper/모델 캐시)을 한 번에 검증.
- Multi-Output Device는 swift Core Audio API로 자동 생성됨 (Audio MIDI Setup GUI 4단계 클릭이 자동화됨).
- 사용자가 명시적으로 "설치 다시 해줘" / "세팅 점검해줘"라고 하면 무조건 install.sh 또는 check-setup.sh 실행.
