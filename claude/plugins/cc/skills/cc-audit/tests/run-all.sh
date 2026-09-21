#!/usr/bin/env bash
# cc-audit 테스트 러너
#   ./tests/run-all.sh            → 전체 케이스
#   ./tests/run-all.sh -v         → 각 케이스의 출력 전문도 함께
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
AUDIT="$HERE/../audit.sh"
FIX="$HERE/fixtures"
VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

PASS=0; FAIL=0
OUT=""; CODE=0

run_case() { # run_case NAME CONFIG_DIR PROJECT_DIR [extra args...]
  local name="$1" cfg="$2" proj="$3"; shift 3
  OUT=$(CLAUDE_CONFIG_DIR="$cfg" "$AUDIT" --project-dir "$proj" "$@" 2>&1)
  CODE=$?
  printf '\n--- 케이스: %s (exit=%d) ---\n' "$name" "$CODE"
  [ "$VERBOSE" = "1" ] && printf '%s\n' "$OUT"
  return 0
}

ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; }

# finding 으로 보고된 rule ID 인지 (참고/note 줄은 세지 않는다)
has() {
  printf '%s\n' "$OUT" | grep -qE "^(HIGH|MED|INFO)[[:space:]]+$1([[:space:]]|$)" && return 0
  printf '%s\n' "$OUT" | grep -q "\"id\":\"$1\"" && return 0
  return 1
}

expect_hit()  { if has "$1"; then ok "$1 탐지됨"; else bad "$1 미탐 (탐지돼야 함)"; fi; }
expect_miss() { if has "$1"; then bad "$1 오탐 (탐지되면 안 됨)"; else ok "$1 오탐 없음"; fi; }
expect_code() { if [ "$CODE" = "$1" ]; then ok "종료 코드 $1"; else bad "종료 코드 기대 $1, 실제 $CODE"; fi; }

# ============================================================ 1. clean fixture
run_case "clean fixture" "$FIX/clean/config" "$FIX/clean/project"
expect_code 0
for id in CM01 CM02 CM03 CM06 CM08 CM09 CM10 CM11 RU01 SK01 SK02 SK03 SK04 \
          PM01 PM03 PM04 PM05 PM06 MEM01 SET01 SET02 SET03 SET04 HK02 HK05 AG01 MC01; do
  expect_miss "$id"
done

# ============================================================ 2. dirty fixture
run_case "dirty fixture" "$FIX/dirty/config" "$FIX/dirty/project"
expect_code 1
for id in CM01 CM02 CM03 CM06 CM08 CM09 CM10 RU01 SK01 SK02 SK03 SK04 \
          PM01 PM03 PM04 PM05 PM06 MEM01 SET01 SET02 SET03 SET04 HK02 HK05 AG01 MC01; do
  expect_hit "$id"
done
expect_miss CM11  # dirty fixture 에는 4 MiB 파일이 없다 (별도 케이스에서 확인)

# ============================================================ 3. JSON 출력
run_case "dirty fixture --json" "$FIX/dirty/config" "$FIX/dirty/project" --json
expect_code 1
if command -v python3 >/dev/null 2>&1; then
  if printf '%s' "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["findings"] and d["summary"]["HIGH"]>0 and d["scanned"]' >/dev/null 2>&1; then
    ok "JSON 파싱 가능 + 구조 정상"
  else
    bad "JSON 파싱 실패 또는 구조 이상"
  fi
fi
if printf '%s' "$OUT" | grep -q '"severity"'; then ok "JSON 에 severity 필드"; else bad "JSON severity 누락"; fi

# ============================================================ 4. scope 분리
run_case "scope=project only" "$FIX/dirty/config" "$FIX/dirty/project" --scope project
expect_miss PM01     # 전역 settings 의 deny 는 안 봐야 함
expect_miss CM01     # 전역 CLAUDE.md 는 안 봐야 함
expect_hit  MC01     # 프로젝트 .mcp.json 은 봐야 함
expect_hit  SET04    # 프로젝트 .claude/settings.json 의 defaultMode

run_case "scope=global only" "$FIX/dirty/config" "$FIX/dirty/project" --scope global
expect_hit  PM01
expect_hit  CM01

# ============================================================ 4a. CM02/CM03 좁히기 회귀
# 실환경 ~/.claude/CLAUDE.md 재현:
#   "풀지 말 것"(4행) / "부가 섹션 금지"(5행) = 순수 서술형 → 걸리면 안 됨
#   "`EnterWorktree` ... 사용 금지"(11행) = 백틱 토큰 대상 → 계속 걸려야 함
run_case "CM03 좁히기 (서술형 제외 / 도구명 포함)" "$FIX/cm03-narrow/config" "$FIX/cm03-narrow/project" --scope global
expect_hit  CM03
expect_miss CM02
CM03_LINES=$(printf '%s\n' "$OUT" | grep -E '^MED +CM03' | sed -E 's/.*CLAUDE\.md:([0-9,-]+).*/\1/')
if [ "$CM03_LINES" = "11" ]; then
  ok "CM03 이 11행(백틱 줄)만 지목 — 4/5행 서술형 오탐 없음"
else
  bad "CM03 지목 줄이 11 이 아님: '$CM03_LINES' (4행/5행 오탐 의심)"
fi

# ============================================================ 4b. CM11 (4 MiB 초과)
printf '\n--- 케이스: CM11 4 MiB 초과 ---\n'
BIG=$(mktemp -d)
mkdir -p "$BIG/rules"
cp "$FIX/clean/config/settings.json" "$BIG/settings.json"
# 4 MiB 를 살짝 넘기는 CLAUDE.md 생성 (커밋하지 않고 실행 시 생성)
{ echo "# 거대한 메모리"; i=0; while [ $i -lt 70000 ]; do
    echo "이 줄은 CLAUDE.md 를 4 MiB 이상으로 부풀리기 위한 더미 내용입니다. ------------------"; i=$((i+1)); done; } > "$BIG/CLAUDE.md"
printf 'CLAUDE.md 크기: %s bytes\n' "$(wc -c < "$BIG/CLAUDE.md" | tr -d ' ')"
run_case "4 MiB CLAUDE.md" "$BIG" "$FIX/clean/project" --scope global
expect_hit CM11
expect_code 1
rm -rf "$BIG"

# ============================================================ 4c. HK05 판정 skip (스크립트 못 읽음)
SKIPD=$(mktemp -d)
cat > "$SKIPD/settings.json" <<'JSON'
{ "sandbox": { "enabled": true },
  "hooks": { "PostToolUse": [ { "hooks": [ { "type": "command", "command": "/nonexistent/path/to/hook.sh | head -3" } ] } ] } }
JSON
run_case "HK05 스크립트 못 읽음 → skip" "$SKIPD" "$FIX/clean/project" --scope global
expect_miss HK05
if printf '%s' "$OUT" | grep -q 'HK05: 훅 스크립트를 읽을 수 없어'; then ok "HK05 skip 표시됨"; else bad "HK05 skip 표시 누락"; fi
rm -rf "$SKIPD"

# ============================================================ 5. 스캔 실패 (exit 2)
EMPTY=$(mktemp -d); EMPTY_P=$(mktemp -d)
run_case "설정 없음" "$EMPTY" "$EMPTY_P"
expect_code 2
rmdir "$EMPTY" "$EMPTY_P" 2>/dev/null

# ============================================================ 6. 읽기 전용 보장
printf '\n--- 케이스: 읽기 전용 검증 ---\n'
SNAP_A=$(mktemp); SNAP_B=$(mktemp)
snapshot() { find "$FIX" -type f -exec shasum {} \; 2>/dev/null | sort; }
snapshot > "$SNAP_A"
CLAUDE_CONFIG_DIR="$FIX/dirty/config" "$AUDIT" --project-dir "$FIX/dirty/project" >/dev/null 2>&1
CLAUDE_CONFIG_DIR="$FIX/dirty/config" "$AUDIT" --project-dir "$FIX/dirty/project" --json >/dev/null 2>&1
CLAUDE_CONFIG_DIR="$FIX/clean/config" "$AUDIT" --project-dir "$FIX/clean/project" >/dev/null 2>&1
snapshot > "$SNAP_B"
if diff -q "$SNAP_A" "$SNAP_B" >/dev/null 2>&1; then
  ok "fixture 파일이 전혀 변경되지 않음 (읽기 전용)"
else
  bad "fixture 파일이 변경됨!"; diff "$SNAP_A" "$SNAP_B"
fi
rm -f "$SNAP_A" "$SNAP_B"

# ============================================================ 7. 실제 사용자 환경 (스모크)
printf '\n--- 케이스: 실제 사용자 환경 스모크 ---\n'
OUT=$("$AUDIT" 2>&1); CODE=$?
if [ "$CODE" = "0" ] || [ "$CODE" = "1" ]; then ok "실환경 실행 (exit=$CODE)"; else bad "실환경 실행 실패 (exit=$CODE)"; fi
OUT=$("$AUDIT" --json 2>&1); CODE=$?
if command -v python3 >/dev/null 2>&1; then
  if printf '%s' "$OUT" | python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1; then
    ok "실환경 --json 파싱 가능"
  else
    bad "실환경 --json 파싱 실패"
  fi
fi

printf '\n===========================================\n결과: PASS %d / FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
