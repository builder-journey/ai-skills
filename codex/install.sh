#!/bin/bash
# Codex CLI에 builder-journey 스킬 연결 (심볼릭 링크).
# 사용: ./codex/install.sh
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CODEX="$HOME/.codex"

mkdir -p "$CODEX/prompts"

# 1. rec-meeting 스크립트 디렉터리
ln -sfn "$REPO/claude/plugins/mac/skills/rec-meeting" "$CODEX/rec-meeting"
echo "✅ $CODEX/rec-meeting → repo"

# 2. 슬래시 프롬프트
for f in "$REPO/codex/prompts/"*.md; do
    ln -sf "$f" "$CODEX/prompts/$(basename "$f")"
    echo "✅ /$(basename "$f" .md)"
done

# 3. AGENTS.md — 기존 파일이 있으면 덮어쓰지 않는다
if [ -e "$CODEX/AGENTS.md" ] && [ ! -L "$CODEX/AGENTS.md" ]; then
    echo ""
    echo "⚠️  $CODEX/AGENTS.md 가 이미 있어 건너뜁니다."
    echo "   아래 내용을 직접 합쳐주세요:"
    echo "   $REPO/codex/AGENTS.md"
else
    ln -sf "$REPO/codex/AGENTS.md" "$CODEX/AGENTS.md"
    echo "✅ $CODEX/AGENTS.md → repo"
fi

echo ""
echo "완료. 업데이트는 repo에서 'git pull' 만 하면 됩니다."
