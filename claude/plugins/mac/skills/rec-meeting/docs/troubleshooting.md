# 트러블슈팅 (증상별)

> 실제 개발 중 마주친 문제들을 전부 기록함.

## 🔴 증상 1: 녹음 시작 후 소리가 하나도 안 남

**원인:** 시스템 출력이 BlackHole만 가리키고 있거나, Multi-Output Device에 Speakers가 빠져있음.

**해결:**
1. `SwitchAudioSource -c` 로 현재 출력 확인 → `Multi-Output Device`여야 함
2. Audio MIDI Setup → Multi-Output Device에 **MacBook Pro Speakers** 체크 확인
3. Drift Correction이 Speakers에 체크되어 있는지 확인

## 🔴 증상 2: 내 목소리만 녹음되고 상대방 목소리 안 들어감 (가장 흔한 함정)

**원인:** Multi-Output Device의 **Master Device가 BlackHole이 아님**. Chrome/Meet이 BlackHole로 오디오를 안 보냄.

**해결:**
1. Audio MIDI Setup 실행
2. Multi-Output Device 선택
3. 우측 **Master Device** 드롭다운 → `BlackHole 2ch`
4. 녹음 재시도

## 🔴 증상 3: Meet 통화 중엔 상대방 목소리 잡히다가 중간에 끊김

**원인:** 녹음 도중 시스템 출력을 바꾸거나, Meet이 내부 스피커 설정을 재협상하는 순간.

**해결:**
- 녹음 중엔 시스템 출력을 건드리지 않는다
- Meet 설정 → 오디오 → 스피커를 `Multi-Output Device`로 고정 설정

## 🟡 증상 4: 녹음 시작 후 볼륨 조정(F11/F12, 메뉴바 슬라이더)이 안 됨

**원인:** macOS의 Multi-Output Device는 설계상 볼륨 컨트롤이 불가능.

**해결:**
- 앱 자체 볼륨으로 조정 (유튜브 플레이어 슬라이더, Meet 볼륨 등)
- 녹음 종료되면 이전 장치로 자동 복원 → 정상 볼륨 컨트롤 복귀

## 🟡 증상 5: 녹음 끝났는데 Music.app이 자동으로 열림

**원인:** m4a 파일을 `open` 명령으로 열면 macOS 기본 연결 앱인 Music.app이 실행됨.

**해결:** `rec-stop.sh`는 **m4a를 자동으로 열지 않음**. 트랜스크립트(.txt)만 TextEdit으로 연다. 녹음 파일을 수동으로 들어볼 때 Music이 싫으면:

```bash
open -a QuickTime\ Player ~/meeting-log/meeting-*.m4a
```

## 🟡 증상 6: 트랜스크립션 결과가 비어있음

**원인:** whisper가 오디오를 무음으로 판단. 대부분 실제로 녹음된 소리가 너무 작거나 거의 없는 경우.

**해결:**
1. 녹음 파일 직접 재생해서 소리가 있는지 확인: `open -a QuickTime\ Player ~/meeting-log/meeting-*.m4a`
2. 소리는 있는데 텍스트가 비면 음량이 너무 작은 것 → 앱 볼륨을 키우거나 마이크 감도 확인
3. 소리도 없으면 **증상 1·2**를 다시 확인

## 🟡 증상 7: `이미 녹음 중입니다` 에러 (실제로는 녹음 중이 아님)

**원인:** 이전 녹음이 비정상 종료되어 상태 파일이 남음. **현재 버전은 이걸 자동 감지하고 복구**하므로 보통 만나지 않음.

**해결:**
- 정상 자동 복구가 실패한 경우에만 수동 정리:
```bash
# 임시 파일 전체 정리
rm -f ~/meeting-log/.rec-pid ~/meeting-log/.rec-watcher-pid \
      ~/meeting-log/.rec-notify-pid \
      ~/meeting-log/.rec-session ~/meeting-log/.rec-prev-output
# 잔존 ffmpeg/워처/알림 워처 정리
pkill -f "ffmpeg.*BlackHole"
pkill -f "watch-segments.sh"
pkill -f "notify-watcher.sh"
```

세션 디렉토리(`~/meeting-log/session-*`)는 남아있을 수 있다. 필요 없으면 삭제, 복구하려면 내부 `seg_*.m4a` / `seg_*.txt` 수동 확인.

## 🟡 증상 8: `BlackHole 2ch가 설치되어 있지 않습니다`

**원인:** Step 1 설치 후 **재부팅을 안 함**. BlackHole은 커널 드라이버라 재부팅 없이는 인식 안 됨.

**해결:** 재부팅 후 install.md Step 2의 검증 명령 재실행.

## 🟡 증상 9: `'Multi-Output Device'가 없습니다`

**원인:** install.md Step 3에서 Multi-Output Device 생성 안 했거나, 이름을 바꿔서 저장함.

**해결:**
- Step 3 절차대로 생성
- 이름을 다르게 지었다면 환경변수 `REC_MULTI_OUTPUT_NAME`로 실제 이름 지정

## 🟡 증상 10: Google Meet이 시스템 출력 변경을 안 따라옴

**원인:** Chrome이 통화 시작 시점의 출력 장치를 캐싱. 통화 도중 시스템이 바뀌어도 즉시 반영 안 됨.

**해결:**
- **녹음 먼저 시작 → 그 다음 Meet 입장** 순서 준수
- 또는 Meet 통화창에서 직접 스피커를 `Multi-Output Device`로 지정

## 🟡 증상 11: 첫 전사가 유난히 오래 걸림

**원인:** mlx-whisper가 HuggingFace에서 모델(~1.5GB)을 자동 다운로드하는 중. 첫 실행에만 해당.

**해결:** 기다리기. 다운로드는 `~/.cache/huggingface/hub/` 에 영구 저장되므로 이후 실행에서는 없음. 진행 상황 확인:

```bash
du -sh ~/.cache/huggingface/hub/models--mlx-community--whisper-large-v3-turbo/
```

1.5GB 근접하면 다운로드 완료. 인터넷 환경에 따라 10-30초 소요.

## 🟡 증상 12: `No module named 'mlx_whisper'` 에러

**원인:** mlx-whisper 미설치 또는 Python 실행 경로가 다른 곳을 바라봄.

**해결:**
```bash
python3 -m pip install mlx-whisper
# 설치 확인
python3 -c "import mlx_whisper; print(mlx_whisper.__file__)"
```

`transcribe.py` 상단의 shebang은 `#!/usr/bin/env python3`를 사용하므로, `python3`가 mlx-whisper가 설치된 환경과 같은지 확인할 것.

## 🔴 증상 13: 녹음 파일이 무음(파일은 만들어졌는데 소리가 없음)

**원인:** macOS 마이크/시스템 오디오 권한이 거부됨. 첫 실행 시 권한 팝업에서 "허용 안 함"을 눌렀거나, 터미널 앱 변경 후 권한을 다시 묻지 않은 경우.

**해결:**
1. **시스템 설정 → 개인정보 보호 및 보안 → 마이크**
2. 사용 중인 터미널 앱 (`Terminal` / `iTerm` / `Warp` 등)의 토글을 ✅ ON
3. `ffmpeg` 항목이 보이면 그것도 ✅ ON
4. 토글을 켤 때 macOS가 "앱을 종료해야 적용됩니다" 묻거든 → 터미널 재시작 후 다시 녹음

권한이 켜져 있는데도 무음이면 → **증상 1·2** 확인 (Audio MIDI Setup 문제).

## 🔴 증상 14: macOS Sequoia에서 시스템 오디오 누락 (화면 녹화 권한)

**원인:** macOS Sequoia(15+) 이상에서 일부 케이스에 BlackHole를 통한 시스템 오디오 캡처가 **화면 녹화 권한**을 추가로 요구. 권한 없으면 녹음에 상대 목소리만 빠짐.

**해결:**
1. **시스템 설정 → 개인정보 보호 및 보안 → 화면 녹화**
2. 사용 중인 터미널 앱 (`Terminal` / `iTerm` / `Warp` 등) 토글 ✅ ON
3. 토글 켤 때 "앱을 종료해야 적용됩니다" 묻거든 → 터미널 재시작 후 다시 녹음

권한 모두 켰는데도 시스템 오디오 안 잡히면 → **증상 1·2** 확인 (Audio MIDI Setup).

## 🔵 증상 15: 알림이 전혀 안 뜸

**원인:** macOS 알림 권한이 osascript / 스크립트 편집기에 거부됨.

**해결:**
1. **시스템 설정 → 알림 → 스크립트 편집기** (또는 `Script Editor` 영문)
2. "알림 허용" ON, "잠금 화면 표시", "알림 센터 표시" 등 원하는대로
3. 진단 로그 확인: `cat ~/meeting-log/.notify-errors.log`
