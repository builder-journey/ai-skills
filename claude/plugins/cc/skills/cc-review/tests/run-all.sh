#!/usr/bin/env bash
# collect.sh 검증. 수집이 정확한지만 본다 — 판정은 LLM 몫이라 여기서 테스트하지 않는다.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n     기대: %s\n     실제: %s\n' "$1" "$2" "$3"; }
eq()   { [ "$2" = "$3" ] && ok "$1" || bad "$1" "$2" "$3"; }

F="tests/fixtures"
J=$(CLAUDE_CONFIG_DIR="$PWD/$F/config" bash collect.sh --json --project-dir "$PWD/$F/project" 2>/dev/null)
RC=$?

q() { printf '%s' "$J" | python3 -c "import json,sys;d=json.load(sys.stdin);$1" 2>/dev/null; }

echo "--- 기본 ---"
eq "종료 코드 0" "0" "$RC"
printf '%s' "$J" | python3 -c 'import json,sys;json.load(sys.stdin)' 2>/dev/null && ok "JSON 파싱 가능" || bad "JSON 파싱 가능" "valid" "invalid"

echo; echo "--- 종류별 개수 ---"
# claude_md: 전역1 + 프로젝트1 + 로컬1 + 하위1 = 4
eq "claude_md 4개"  "4" "$(q 'print(d["summary"]["by_kind"]["claude_md"])')"
eq "agents_md 1개"  "1" "$(q 'print(d["summary"]["by_kind"]["agents_md"])')"
# rules: 전역 scoped+unscoped, 프로젝트 nested/deep = 3
eq "rules 3개"      "3" "$(q 'print(d["summary"]["by_kind"]["rules"])')"
# skill: alpha, nofm, beta = 3  (synced 제외)
eq "skill 3개"      "3" "$(q 'print(d["summary"]["by_kind"]["skill"])')"
eq "agent 2개"      "2" "$(q 'print(d["summary"]["by_kind"]["agent"])')"

echo; echo "--- synced 제외 ---"
eq "synced 스킬 미포함" "0" "$(q 'print(sum(1 for f in d["files"] if "/synced/" in f["path"]))')"

echo; echo "--- rules 로드 시점 판정 ---"
eq "paths 있는 룰 = conditional" "conditional" "$(q 'print([f["load"] for f in d["files"] if f["path"].endswith("scoped.md")][0])')"
eq "paths 없는 룰 = always"      "always"      "$(q 'print([f["load"] for f in d["files"] if f["path"].endswith("unscoped.md")][0])')"
eq "paths 패턴 2개 파싱"          "2"           "$(q 'print(len([f["paths"] for f in d["files"] if f["path"].endswith("scoped.md")][0]))')"
eq "중첩 룰 재귀 발견"            "1"           "$(q 'print(sum(1 for f in d["files"] if f["path"].endswith("deep.md")))')"

echo; echo "--- CLAUDE.md 로드 시점 ---"
eq "루트 CLAUDE.md = always"   "always"    "$(q 'print([f["load"] for f in d["files"] if f["path"].endswith("project/CLAUDE.md")][0])')"
eq "하위 CLAUDE.md = on_demand" "on_demand" "$(q 'print([f["load"] for f in d["files"] if f["path"].endswith("pkg/sub/CLAUDE.md")][0])')"
eq "CLAUDE.local.md = local 스코프" "local" "$(q 'print([f["scope"] for f in d["files"] if f["path"].endswith("CLAUDE.local.md")][0])')"

echo; echo "--- frontmatter 파싱 ---"
eq "alpha name"                   "alpha" "$(q 'print([f["name"] for f in d["files"] if f.get("dir")=="alpha"][0])')"
eq "alpha disable-model-invocation" "True" "$(q 'print([f["disable_model_invocation"] for f in d["files"] if f.get("dir")=="alpha"][0])')"
eq "beta disable-model-invocation"  "False" "$(q 'print([f["disable_model_invocation"] for f in d["files"] if f.get("dir")=="beta"][0])')"
eq "frontmatter 없는 스킬 감지"      "False" "$(q 'print([f["has_frontmatter"] for f in d["files"] if f.get("dir")=="nofm"][0])')"
eq "에이전트 tools 파싱"            "Read, Grep" "$(q 'print([f["tools"] for f in d["files"] if f["path"].endswith("explorer.md")][0])')"
eq "에이전트 model 파싱"            "sonnet" "$(q 'print([f["model"] for f in d["files"] if f["path"].endswith("explorer.md")][0])')"

echo; echo "--- import 탐지 ---"
eq "전역 CLAUDE.md import 1개" "1" "$(q 'print(len([f["imports"] for f in d["files"] if f["path"].endswith("config/CLAUDE.md")][0]))')"

echo; echo "--- 스킬 참조 파일 ---"
eq "alpha 참조 2개 (잡파일 제외)" "2" "$(q 'print(len([f["ref_files"] for f in d["files"] if f.get("dir")=="alpha"][0]))')"
eq "링크된 참조 감지"   "True"  "$(q 'print([r["linked_from_skill_md"] for f in d["files"] if f.get("dir")=="alpha" for r in f["ref_files"] if r["path"].endswith("linked.md")][0])')"
eq "미링크 참조 감지"   "False" "$(q 'print([r["linked_from_skill_md"] for f in d["files"] if f.get("dir")=="alpha" for r in f["ref_files"] if r["path"].endswith("orphan.md")][0])')"
eq ".DS_Store 제외"     "0"     "$(q 'print(sum(1 for f in d["files"] if f["kind"]=="skill" for r in f.get("ref_files",[]) if r["path"].startswith(".")))')"

echo; echo "--- 집계 ---"
eq "상시 로드 토큰 > 0" "yes" "$(q 'print("yes" if d["summary"]["always_loaded_est_tokens"]>0 else "no")')"
eq "스킬 description 토큰 > 0" "yes" "$(q 'print("yes" if d["summary"]["skill_listing_est_tokens"]>0 else "no")')"
# 스킬 본문은 상시 로드가 아니다 — 합계에 들어가면 안 된다
eq "스킬은 상시합계 제외" "yes" "$(q 'print("yes" if d["summary"]["always_loaded_est_tokens"] < sum(f["est_tokens"] for f in d["files"]) else "no")')"

echo; echo "--- 빈 환경 ---"
E=$(mktemp -d) || exit 1
CLAUDE_CONFIG_DIR="$E/cfg" bash collect.sh --json --project-dir "$E" >/dev/null 2>&1
eq "대상 없으면 종료 코드 2" "2" "$?"
# 파이프로 검사하면 pipefail 이 collect.sh 의 종료 코드 2 를 물려받는다 — 먼저 변수에 담는다
EJ=$(CLAUDE_CONFIG_DIR="$E/cfg" bash collect.sh --json --project-dir "$E" 2>/dev/null)
printf '%s' "$EJ" | python3 -c 'import json,sys;json.load(sys.stdin)' 2>/dev/null \
  && ok "빈 환경 JSON 파싱 가능" || bad "빈 환경 JSON 파싱 가능" "valid" "invalid"
EK=$(printf '%s' "$EJ" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(",".join(sorted(d.keys())))' 2>/dev/null)
FK=$(printf '%s' "$J"  | python3 -c 'import json,sys;d=json.load(sys.stdin);print(",".join(sorted(d.keys())))' 2>/dev/null)
eq "빈 환경도 같은 최상위 스키마" "$FK" "$EK"
ES=$(printf '%s' "$EJ" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(",".join(sorted(d["summary"].keys())))' 2>/dev/null)
FS=$(printf '%s' "$J"  | python3 -c 'import json,sys;d=json.load(sys.stdin);print(",".join(sorted(d["summary"].keys())))' 2>/dev/null)
eq "빈 환경도 같은 summary 스키마" "$FS" "$ES"
rm -r "$E"

echo; echo "--- 읽기 전용 ---"
B=$(find "$F" -type f -exec shasum {} \; | shasum | awk '{print $1}')
CLAUDE_CONFIG_DIR="$PWD/$F/config" bash collect.sh --json --project-dir "$PWD/$F/project" >/dev/null 2>&1
CLAUDE_CONFIG_DIR="$PWD/$F/config" bash collect.sh --project-dir "$PWD/$F/project" >/dev/null 2>&1
A=$(find "$F" -type f -exec shasum {} \; | shasum | awk '{print $1}')
eq "fixture 무변경" "$B" "$A"

echo; echo "==========================================="
echo "결과: PASS $PASS / FAIL $FAIL"
[ "$FAIL" -eq 0 ]
