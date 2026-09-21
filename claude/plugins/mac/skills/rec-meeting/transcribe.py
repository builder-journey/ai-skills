#!/usr/bin/env python3
"""Whisper 기반 음성 → 텍스트 변환 스크립트 (mlx-whisper + large-v3-turbo).

사용법:
    python3 transcribe.py <audio_file> [output_file]

- output_file 미지정 시 같은 경로에 .txt 확장자로 저장
- Apple Silicon MLX 네이티브 가속 (openai-whisper + mps 대비 2-3배 빠름)
- 최초 실행 시 HuggingFace에서 모델 자동 다운로드 (~1.6GB)
"""

import sys
import os
import warnings

warnings.filterwarnings("ignore")

MODEL_REPO = "mlx-community/whisper-large-v3-turbo"
# m7: REC_LANG 환경변수로 언어 선택. "auto"면 자동 감지.
LANG = os.environ.get("REC_LANG", "ko")


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 transcribe.py <audio_file> [output_file]", file=sys.stderr)
        sys.exit(1)

    audio_path = os.path.expanduser(sys.argv[1])
    if not os.path.exists(audio_path):
        print(f"Error: {audio_path} not found", file=sys.stderr)
        sys.exit(1)

    output_path = (
        os.path.expanduser(sys.argv[2])
        if len(sys.argv) >= 3
        else os.path.splitext(audio_path)[0] + ".txt"
    )

    import mlx_whisper

    lang_arg = None if LANG == "auto" else LANG
    print(f"트랜스크립션 중... (model: {MODEL_REPO}, lang: {LANG})", file=sys.stderr)
    result = mlx_whisper.transcribe(
        audio_path,
        path_or_hf_repo=MODEL_REPO,
        language=lang_arg,
        # 환각(hallucination) 방지 옵션:
        # - condition_on_previous_text=False: 이전 세그먼트에 의존 안 해서 반복 환각 차단
        # - no_speech_threshold=0.6: 무음 임계값 ↑ → "감사합니다 / 다음 영상에서 만나요" 같은 패턴 환각 줄임
        # - logprob_threshold=-1.0: 모델 신뢰도 낮은 출력 버림
        # - temperature=0.0: 결정론적 출력 (랜덤 환각 차단)
        condition_on_previous_text=False,
        no_speech_threshold=0.6,
        logprob_threshold=-1.0,
        temperature=0.0,
    )
    text = result["text"].strip()

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(text + "\n")

    print(f"완료: {output_path}", file=sys.stderr)
    print(text)


if __name__ == "__main__":
    main()
