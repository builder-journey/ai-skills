#!/usr/bin/env bash
# 잘못된 패턴: 경고를 stderr 로만 내보내고 exit 0 → Claude 는 이걸 절대 못 본다
echo "경고: 테스트를 안 돌렸습니다" >&2
exit 0
