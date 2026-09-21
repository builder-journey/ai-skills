# 🎙 rec-meeting

미팅을 녹음하고 자동으로 텍스트로 변환해주는 스킬.
**Apple Silicon Mac 전용** (M1/M2/M3/M4).

---

## 📦 스킬 설치

```bash
/plugin marketplace add builder-journey/ai-skills
/plugin install bj-mac@builder-journey
```

Codex CLI는 repo 클론 후 `./codex/install.sh`.

---

## 🚀 의존성 설치 — Claude한테 말만 걸면 됨

**가장 간단한 방법**: Claude를 켜고 그냥 **"녹음 시작해줘"** 라고 말하기.

Claude가 알아서:
1. 설치 상태 점검 (`check-setup.sh`)
2. 안 된 게 있으면 자동으로 `install.sh` 실행
3. 재부팅 필요하면 안내 → 재부팅 후 다시 같은 말만 하면 이어서 자동 진행
4. 모든 세팅 끝나면 바로 녹음 시작

**또는 터미널에서 직접:**

```bash
REC_DIR=$(find ~/.claude/plugins/cache -type d -name rec-meeting | head -1)
"$REC_DIR"/install.sh
```

어느 쪽이든 스크립트가 묻는 대로 답하면 자동 진행됩니다:
1. ✅ Homebrew 설치 (없으면)
2. ✅ BlackHole, ffmpeg, switchaudio, mlx-whisper 설치
3. ⚠️ **재부팅 필요** (BlackHole이 커널 드라이버라 1회성)
4. (재부팅 후 다시 같은 명령 실행)
5. ✅ Multi-Output Device 자동 가이드 (Audio MIDI Setup 자동 오픈 + 4단계 안내)
6. ✅ xbar 메뉴바 설치 (선택) — 런처가 플러그인 경로를 자동 추적하므로 버전이 올라가도 재설치 불필요
7. ✅ 권한 안내
8. ✅ 최종 점검

**설치 완료 후 사용:**

| 시작 | Claude에 말하기: **"녹음 시작해줘"** <br> 또는 메뉴바 🎙 클릭 |
|---|---|
| **종료** | Claude에 말하기: **"녹음 끝"** <br> 또는 메뉴바 🔴 → **⏹ 녹음 종료** |
| **결과** | TextEdit이 자동으로 트랜스크립트 오픈 <br> `~/meeting-log/meeting-YYYYMMDD-HHMMSS.{m4a,txt}` |

---

## 🆘 문제 생기면

```bash
REC_DIR=$(find ~/.claude/plugins/cache -type d -name rec-meeting | head -1)
# 1. 설치 점검 (9개 항목 한 번에 확인)
"$REC_DIR"/check-setup.sh

# 2. 재실행해도 안전 — 누락된 단계만 자동 진행
"$REC_DIR"/install.sh
```

| 자주 막히는 곳 | 어디 봐야? |
|---|---|
| BlackHole이 인식 안 됨 | 재부팅 필수. 커널 드라이버. |
| 상대 목소리가 녹음 안 됨 | Audio MIDI Setup → Multi-Output Device → **Master Device가 BlackHole 2ch 인지** 확인 (가장 흔함) |
| 무음 파일 | 시스템 설정 → 개인정보 보호 → 마이크 / 화면녹화 권한 |
| 그 외 | [docs/troubleshooting.md](docs/troubleshooting.md) — 증상 1~15 별 해결책 |

---

## 📚 더 자세한 문서

| 문서 | 누가 읽나요 |
|---|---|
| **[docs/quickstart.md](docs/quickstart.md)** | 비전공자용. 왜 BlackHole·Multi-Output·세그먼트가 필요한지 비유로 설명 |
| **[docs/install.md](docs/install.md)** | install.sh 없이 수동 설치하는 단계별 가이드 |
| **[docs/troubleshooting.md](docs/troubleshooting.md)** | 증상별 해결책 (15개 시나리오) |
| **[TASKS.md](TASKS.md)** | 출시 전 개선 작업 트래커 (개발자용) |

---

## 🔧 환경 변수로 커스터마이즈 (선택)

`~/.zshrc`에 추가하면 영구 적용:

```bash
export REC_RETENTION_DAYS=30          # 30일 지난 녹음 자동 삭제 (기본 0=영구)
export REC_NO_NOTIFY=1                # 알림 비활성화 (심야 작업용)
export REC_LANG=auto                  # 자동 언어 감지 (기본 ko)
export REC_SEGMENT_SECONDS=180        # 세그먼트 길이 변경 (기본 300=5분)
export REC_MULTI_OUTPUT_NAME="이름"   # Multi-Output Device 이름 변경 시
export REC_NO_OPEN=1                  # 종료 시 TextEdit 자동 오픈 비활성화 (배치 모드)
```

---

## 🗑 완전 제거

```bash
REC_DIR=$(find ~/.claude/plugins/cache -type d -name rec-meeting | head -1)
"$REC_DIR"/uninstall.sh         # dry-run (미리보기)
"$REC_DIR"/uninstall.sh --yes   # 실제 삭제
```

---

## 🏗 동작 개요 (개발자용)

```
┌────────────────────────┐
│ Meet / Zoom / 기타 앱  │
└───────────┬────────────┘
            │ 시스템 출력
            ▼
 ┌────────────────────────────┐
 │   Multi-Output Device      │
 │  ┌──────────────────────┐  │
 │  │ MacBook Pro Speakers │──┼─▶ 🔊 사용자가 들음
 │  └──────────────────────┘  │
 │  ┌──────────────────────┐  │
 │  │     BlackHole 2ch    │──┼─▶ (가상 입력) ─┐
 │  └──────────────────────┘  │                │
 └────────────────────────────┘                │
                                               │
 ┌────────────────────────┐                    │
 │   MacBook 마이크       │────────────────────┤
 └────────────────────────┘                    │
                                               ▼
                                     ┌────────────────┐
                                     │ ffmpeg amix +  │
                                     │ segment(5분)   │
                                     └────────┬───────┘
                                              ▼
                            seg_000.m4a → mlx-whisper (백그라운드 순차 전사)
                            seg_001.m4a → mlx-whisper
                                ...
                                              │
                                       (녹음 종료 시)
                                              ▼
                                      concat + txt 합본
                                              ▼
                                  meeting-*.m4a + meeting-*.txt
                                              │
                                              ▼
                                         TextEdit
```

자세한 파일 구조 / 테스트 방법은 [docs/install.md](docs/install.md) 참고.

---

## 🧪 통합 테스트

```bash
REC_DIR=$(find ~/.claude/plugins/cache -type d -name rec-meeting | head -1)
"$REC_DIR"/tests/run-all.sh
```

8개 시나리오 자동 검증 (정상 녹음 / 비정상 종료 자동 복구 / 권한 등).
