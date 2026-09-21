#!/usr/bin/env bash
# 올바른 패턴: 차단하려면 exit 2 + stderr
if [ -n "${BLOCK:-}" ]; then
  echo "차단 사유" >&2
  exit 2
fi
echo '{"hookSpecificOutput":{"additionalContext":"ok"}}'
