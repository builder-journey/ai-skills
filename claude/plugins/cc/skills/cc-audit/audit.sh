#!/usr/bin/env bash
# cc-audit: Claude Code 설정 안티패턴 감사 스크립트
#
# 읽기 전용. 어떤 파일도 수정하지 않는다.
# 출력은 Claude가 읽고 해석하는 용도이므로, 판정과 근거만 짧게 낸다.
#
# 사용법:
#   audit.sh [--json] [--scope global|project|all] [--project-dir DIR]
#
# 종료 코드:
#   0 = HIGH 없음 / 1 = HIGH 있음 / 2 = 스캔 실패(설정 파일을 하나도 못 찾음)

set -uo pipefail
# UTF-8 로케일이 아니면 한글 패턴 매칭이 깨질 수 있으므로 가능한 것으로 맞춘다
case "${LC_ALL:-${LANG:-}}" in
  *UTF-8*|*utf8*) ;;
  *) if locale -a 2>/dev/null | grep -qi '^en_US.UTF-8$'; then export LC_ALL=en_US.UTF-8; fi ;;
esac

# ---------------------------------------------------------------- 인자 파싱
OUT_JSON=0
SCOPE="all"
PROJ_DIR="$PWD"

while [ $# -gt 0 ]; do
  case "$1" in
    --json) OUT_JSON=1 ;;
    --scope)
      shift
      [ $# -gt 0 ] || { echo "오류: --scope 값 누락" >&2; exit 2; }
      SCOPE="$1"
      ;;
    --scope=*) SCOPE="${1#--scope=}" ;;
    --project-dir)
      shift
      [ $# -gt 0 ] || { echo "오류: --project-dir 값 누락" >&2; exit 2; }
      PROJ_DIR="$1"
      ;;
    --project-dir=*) PROJ_DIR="${1#--project-dir=}" ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "오류: 알 수 없는 인자 '$1'" >&2; exit 2 ;;
  esac
  shift
done

case "$SCOPE" in
  global|project|all) ;;
  *) echo "오류: --scope 는 global|project|all 중 하나" >&2; exit 2 ;;
esac

DO_GLOBAL=0; DO_PROJECT=0
[ "$SCOPE" = "global" ] || [ "$SCOPE" = "all" ] && DO_GLOBAL=1
[ "$SCOPE" = "project" ] || [ "$SCOPE" = "all" ] && DO_PROJECT=1

# CLAUDE_CONFIG_DIR 이 있으면 ~/.claude 대신 그것을 쓴다
CFG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# ---------------------------------------------------------------- 공용 상태
SEP=$'\037'            # 필드 구분자 (unit separator)
NL=$'\n'         # 개행 (공백 포함 항목을 모을 때 사용)
FINDINGS_FILE="$(mktemp -t ccaudit.XXXXXX)"
SCANNED_FILE="$(mktemp -t ccaudscan.XXXXXX)"
NOTES_FILE="$(mktemp -t ccaudnote.XXXXXX)"
trap 'rm -f "$FINDINGS_FILE" "$SCANNED_FILE" "$NOTES_FILE"' EXIT

# 기준 문서(reference/antipatterns.md)에 실제로 존재하며, 기계적으로 판정 가능한 ID만 구현한다.
PASS_IDS=" CM01 CM02 CM03 CM06 CM08 CM09 CM10 CM11 RU01 SK01 SK02 SK03 SK04 PM01 PM03 PM04 PM05 PM06 MEM01 SET01 SET02 SET03 SET04 HK02 HK05 AG01 MC01 "
TOTAL_RULES=27

# 경로를 사람이 읽기 좋게 줄인다 (설정 디렉토리/프로젝트 디렉토리/$HOME 접두어 축약)
shorten() {
  case "$1" in
    "$CFG_DIR"/*) printf '<config>/%s' "${1#$CFG_DIR/}" ;;
    "$PROJ_DIR"/*) printf './%s' "${1#$PROJ_DIR/}" ;;
    "$HOME"/*) printf '~/%s' "${1#$HOME/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# finding 등록: add SEVERITY ID FILE LINES MESSAGE EVIDENCE
add() {
  printf '%s%s%s%s%s%s%s%s%s%s%s\n' \
    "$1" "$SEP" "$2" "$SEP" "$3" "$SEP" "$4" "$SEP" "$5" "$SEP" "$6" \
    >> "$FINDINGS_FILE"
}

note() { printf '%s\n' "$1" >> "$NOTES_FILE"; }

scanned() { printf '%s\n' "$(shorten "$1")" >> "$SCANNED_FILE"; }

# ---------------------------------------------------------------- JSON 엔진
JSON_ENGINE="none"
if command -v jq >/dev/null 2>&1; then
  JSON_ENGINE="jq"
elif command -v python3 >/dev/null 2>&1; then
  JSON_ENGINE="python3"
fi

# cfg_get FILE DOTTED_PATH MODE(raw|array|keys)
# raw   : 스칼라를 그대로 (false 도 false 로 출력됨)
# array : 배열 원소를 한 줄씩
# keys  : 객체의 키를 한 줄씩
cfg_get() {
  local f="$1" p="$2" mode="$3"
  [ -f "$f" ] || return 0
  case "$JSON_ENGINE" in
    jq)
      local pe
      if [ -z "$p" ]; then
        pe='[]'
      else
        pe=$(printf '%s' "$p" | awk -F. '{printf "["; for(i=1;i<=NF;i++){printf "%s\"%s\"",(i>1?",":""),$i}; printf "]"}')
      fi
      case "$mode" in
        array) jq -r "try (getpath($pe)) catch null | if type==\"array\" then .[] | (if type==\"string\" then . else tojson end) else empty end" "$f" 2>/dev/null ;;
        keys)  jq -r "try (getpath($pe)) catch null | if type==\"object\" then keys_unsorted[] else empty end" "$f" 2>/dev/null ;;
        raw)   jq -r "try (getpath($pe)) catch null | if .==null then empty elif type==\"string\" then . else tojson end" "$f" 2>/dev/null ;;
      esac
      ;;
    python3)
      python3 - "$f" "$p" "$mode" <<'PYEOF' 2>/dev/null
import json, sys
f, p, mode = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    d = json.load(open(f, encoding='utf-8'))
except Exception:
    sys.exit(0)
cur = d
if p:
    for k in p.split('.'):
        if isinstance(cur, dict) and k in cur:
            cur = cur[k]
        else:
            sys.exit(0)
def s(v):
    return v if isinstance(v, str) else json.dumps(v, ensure_ascii=False)
if mode == 'array':
    if isinstance(cur, list):
        for x in cur: print(s(x))
elif mode == 'keys':
    if isinstance(cur, dict):
        for k in cur: print(k)
else:
    if cur is not None: print(s(cur))
PYEOF
      ;;
    none)
      # 폴백: grep 기반. 최상위 키 추출만 근사적으로 지원한다.
      if [ "$mode" = "keys" ] && [ -z "$p" ]; then
        grep -oE '^[[:space:]]{2}"[A-Za-z0-9_]+"[[:space:]]*:' "$f" 2>/dev/null \
          | sed -E 's/^[[:space:]]*"([^"]+)".*/\1/'
      fi
      ;;
  esac
}

# JSON 유효성 확인
json_valid() {
  local f="$1"
  [ -f "$f" ] || return 1
  case "$JSON_ENGINE" in
    jq) jq -e . "$f" >/dev/null 2>&1 ;;
    python3) python3 -c 'import json,sys; json.load(open(sys.argv[1],encoding="utf-8"))' "$f" >/dev/null 2>&1 ;;
    none) return 0 ;;
  esac
}

if [ "$JSON_ENGINE" = "none" ]; then
  note "jq / python3 둘 다 없음 → settings.json 기반 체크(PM*, SET*, HK02, MC01)는 정확도가 크게 떨어지거나 생략됨"
fi

# ---------------------------------------------------------------- 텍스트 유틸

# HTML 주석을 제거하고 남은 '내용 있는' 줄 수
eff_lines() {
  awk '
    {
      l=$0; out=""
      while (length(l) > 0) {
        if (!inc) {
          i = index(l, "<!--")
          if (i == 0) { out = out l; l = "" }
          else { out = out substr(l, 1, i-1); l = substr(l, i+4); inc = 1 }
        } else {
          i = index(l, "-->")
          if (i == 0) { l = "" }
          else { l = substr(l, i+3); inc = 0 }
        }
      }
      if (out ~ /[^ \t\r]/) c++
    }
    END { print c+0 }
  ' "$1" 2>/dev/null
}

# 매칭 줄 번호를 콤마로, 최대 8개까지
lines_of() {
  awk -v FS='\n' '{print}' /dev/null 2>/dev/null
  cut -d: -f1 | head -8 | paste -sd, - 2>/dev/null || true
}

join_commas() { paste -sd, - 2>/dev/null | sed 's/,$//'; }

# 금지/자동화 지시 줄 중, "동작 대상"이 같은 줄에 명시된 것만 골라낸다.
#   순수 서술형(문체·형식·태도 지시)은 훅/권한으로 옮길 대상이 아니므로 제외한다.
#   대상 지시자: 백틱 토큰 / 알려진 툴명 / 명령어 / 경로 / 비밀파일 확장자
narrow_lines() { # narrow_lines FILE PROHIB_REGEX
  awk -v P="$2" '
    {
      l = $0; low = tolower(l)
      if (!(low ~ P) && !(l ~ P)) next
      ok = 0
      if (l ~ /`[^`]+`/) ok = 1
      if (!ok && l ~ /(^|[^A-Za-z])(Bash|Write|Edit|Read|Glob|Grep|Task|Agent|Monitor|Skill|WebFetch|WebSearch|NotebookEdit|MultiEdit|EnterWorktree|ExitWorktree|PowerShell)([^A-Za-z]|$)/) ok = 1
      if (!ok && low ~ /(^|[^a-z])(git|npm|npx|pnpm|yarn|pip|pip3|brew|docker|kubectl|curl|wget|make|cargo|rm|sudo|chmod|chown|mv|cp|ssh|scp|kill|psql|mysql|terraform|helm|gh|aws)[ \t]/) ok = 1
      if (!ok && l ~ /[A-Za-z0-9_.~-]+\/[A-Za-z0-9_.*\/-]+/) ok = 1
      if (!ok && low ~ /\.(env|key|pem|pfx|p12|crt|secret)([^a-z]|$)/) ok = 1
      if (ok) printf "%d:%s\n", NR, l
    }' "$1" 2>/dev/null
}

# 프론트매터(첫 --- 블록) 추출
frontmatter() {
  awk 'NR==1 && $0 ~ /^---[[:space:]]*$/ {fm=1; next}
       fm && $0 ~ /^---[[:space:]]*$/ {exit}
       fm {print}' "$1" 2>/dev/null
}

# 프론트매터 제외한 본문
body_after_fm() {
  awk 'NR==1 && $0 ~ /^---[[:space:]]*$/ {fm=1; next}
       fm && $0 ~ /^---[[:space:]]*$/ {fm=0; started=1; next}
       !fm {print}' "$1" 2>/dev/null
}

# ================================================================ 대상 수집
CLAUDEMD_LIST=""     # CLAUDE.md 계열 (CM01,02,03,08,09,10)
GLOBAL_CLAUDEMD=""   # CM06 전용
RULES_LIST=""
SKILLS_LIST=""
AGENT_DIRS=""
SETTINGS_LIST=""
GLOBAL_SETTINGS=""
MEMORY_LIST=""
MCP_FILES=""

addto() { # addto VARNAME PATH
  local v="$1" p="$2"
  eval "local cur=\$$v"
  if [ -z "$cur" ]; then eval "$v=\$p"; else eval "$v=\"\$cur
\$p\""; fi
}

if [ "$DO_GLOBAL" = "1" ]; then
  [ -f "$CFG_DIR/settings.json" ] && { addto SETTINGS_LIST "$CFG_DIR/settings.json"; GLOBAL_SETTINGS="$CFG_DIR/settings.json"; scanned "$CFG_DIR/settings.json"; }
  if [ -f "$CFG_DIR/CLAUDE.md" ]; then
    addto CLAUDEMD_LIST "$CFG_DIR/CLAUDE.md"; GLOBAL_CLAUDEMD="$CFG_DIR/CLAUDE.md"; scanned "$CFG_DIR/CLAUDE.md"
  fi
  if [ -d "$CFG_DIR/rules" ]; then
    while IFS= read -r f; do [ -n "$f" ] && { addto RULES_LIST "$f"; scanned "$f"; }; done <<EOF
$(find "$CFG_DIR/rules" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort)
EOF
  fi
  # maxdepth 2 는 의도적이다: skills/synced/<uuid>/<name>/SKILL.md 에 있는
  # 벤더 동기화 스킬은 사용자가 고칠 수 없으므로 스캔에서 제외한다.
  if [ -d "$CFG_DIR/skills" ]; then
    while IFS= read -r f; do [ -n "$f" ] && { addto SKILLS_LIST "$f"; scanned "$f"; }; done <<EOF
$(find "$CFG_DIR/skills" -maxdepth 2 -type f -name 'SKILL.md' 2>/dev/null | sort)
EOF
    [ -d "$CFG_DIR/skills/synced" ] && note "벤더 동기화 스킬(skills/synced/)은 사용자가 고칠 수 없으므로 스캔에서 제외됨"
  fi
  addto AGENT_DIRS "$CFG_DIR/agents"
  # user-scope MCP 설정 (~/.claude.json). CLAUDE_CONFIG_DIR 가 있으면 그 옆의 것을 본다.
  _uj="$(dirname "$CFG_DIR")/.claude.json"
  [ -f "$_uj" ] && addto MCP_FILES "$_uj"
fi

if [ "$DO_PROJECT" = "1" ]; then
  for rel in CLAUDE.md .claude/CLAUDE.md CLAUDE.local.md AGENTS.md; do
    [ -f "$PROJ_DIR/$rel" ] && { addto CLAUDEMD_LIST "$PROJ_DIR/$rel"; scanned "$PROJ_DIR/$rel"; }
  done
  for rel in .claude/settings.json .claude/settings.local.json; do
    [ -f "$PROJ_DIR/$rel" ] && { addto SETTINGS_LIST "$PROJ_DIR/$rel"; scanned "$PROJ_DIR/$rel"; }
  done
  if [ -d "$PROJ_DIR/.claude/rules" ]; then
    while IFS= read -r f; do [ -n "$f" ] && { addto RULES_LIST "$f"; scanned "$f"; }; done <<EOF
$(find "$PROJ_DIR/.claude/rules" -type f -name '*.md' 2>/dev/null | sort)
EOF
  fi
  if [ -d "$PROJ_DIR/.claude/skills" ]; then
    while IFS= read -r f; do [ -n "$f" ] && { addto SKILLS_LIST "$f"; scanned "$f"; }; done <<EOF
$(find "$PROJ_DIR/.claude/skills" -maxdepth 2 -type f -name 'SKILL.md' 2>/dev/null | sort)
EOF
  fi
  addto AGENT_DIRS "$PROJ_DIR/.claude/agents"
  [ -f "$PROJ_DIR/.mcp.json" ] && { addto MCP_FILES "$PROJ_DIR/.mcp.json"; scanned "$PROJ_DIR/.mcp.json"; }

  # ---- auto memory 위치 결정 (우선순위) ----
  #  1) settings 의 autoMemoryDirectory (절대경로 또는 ~/ 로 시작)
  #  2) CLAUDE_CODE_PROJECT_DIR_NAME 환경변수 (슬러그를 직접 지정)
  #  3) 슬러그 규칙: 프로젝트 루트(git toplevel, 없으면 $PWD)의 절대경로에서
  #     영숫자와 '-' 이외의 모든 문자를 '-' 로 치환 → <config>/projects/<슬러그>/memory/MEMORY.md
  #  위 경로의 디렉토리가 존재할 때만 그것 하나만 검사하고, 없으면 전체 스캔으로 폴백한다.
  mem_dir=""

  # 1) autoMemoryDirectory
  for _sf in "$CFG_DIR/settings.json" "$PROJ_DIR/.claude/settings.json" "$PROJ_DIR/.claude/settings.local.json"; do
    [ -f "$_sf" ] || continue
    _amd=$(cfg_get "$_sf" "autoMemoryDirectory" raw)
    [ -n "$_amd" ] || continue
    case "$_amd" in
      '~'/*) _amd="$HOME/${_amd#\~/}" ;;
      /*) ;;
      *) _amd="$PROJ_DIR/$_amd" ;;
    esac
    if [ -d "$_amd" ]; then mem_dir="$_amd"; fi
  done

  # 2) CLAUDE_CODE_PROJECT_DIR_NAME  /  3) 슬러그 규칙
  if [ -z "$mem_dir" ]; then
    if [ -n "${CLAUDE_CODE_PROJECT_DIR_NAME:-}" ]; then
      proj_slug="$CLAUDE_CODE_PROJECT_DIR_NAME"
    else
      proj_root=$(git -C "$PROJ_DIR" rev-parse --show-toplevel 2>/dev/null)
      [ -n "$proj_root" ] || proj_root="$PROJ_DIR"
      # 영숫자와 '-' 이외의 모든 문자를 '-' 로 치환 (선행 '/' 도 '-' 가 된다)
      proj_slug=$(printf '%s' "$proj_root" | sed 's/[^A-Za-z0-9-]/-/g')
    fi
    [ -d "$CFG_DIR/projects/$proj_slug" ] && mem_dir="$CFG_DIR/projects/$proj_slug/memory"
  fi

  if [ -n "$mem_dir" ]; then
    for _cand in "$mem_dir/MEMORY.md" "$mem_dir/memory/MEMORY.md"; do
      if [ -f "$_cand" ]; then addto MEMORY_LIST "$_cand"; scanned "$_cand"; break; fi
    done
  elif [ -d "$CFG_DIR/projects" ]; then
    while IFS= read -r f; do [ -n "$f" ] && { addto MEMORY_LIST "$f"; scanned "$f"; }; done <<EOF
$(find "$CFG_DIR/projects" -maxdepth 3 -type f -name 'MEMORY.md' 2>/dev/null | sort)
EOF
    [ -n "$MEMORY_LIST" ] && note "현재 프로젝트($PROJ_DIR)의 auto memory 를 특정하지 못해 전체 MEMORY.md 를 스캔함"
  fi
fi

# 스캔 대상이 하나도 없으면 실패
if [ ! -s "$SCANNED_FILE" ]; then
  if [ "$OUT_JSON" = "1" ]; then
    printf '{"findings":[],"summary":{"HIGH":0,"MED":0,"INFO":0,"pass":0,"error":"no-config-found"},"scanned":[]}\n'
  else
    echo "스캔 실패: 검사할 Claude Code 설정 파일을 하나도 찾지 못했습니다. (scope: $SCOPE, project: $PROJ_DIR, config: $CFG_DIR)" >&2
  fi
  exit 2
fi

# ================================================================ CLAUDE.md 체크
for f in $(printf '%s\n' "$CLAUDEMD_LIST"); do
  [ -f "$f" ] || continue
  sf=$(shorten "$f")
  raw=$(wc -l < "$f" | tr -d ' ')
  eff=$(eff_lines "$f")

  # CM11: 4 MiB 초과 → 파일 전체가 조용히 스킵됨
  bytes=$(wc -c < "$f" | tr -d ' ')
  if [ "$bytes" -gt 4194304 ]; then
    mib=$(( bytes / 1048576 ))
    add HIGH CM11 "$sf" "" "4 MiB 초과(약 ${mib} MiB) → 파일 전체가 로드되지 않고 조용히 스킵됨" "bytes=${bytes} limit=4194304"
  fi

  # CM01: 실효 줄 수 > 200
  if [ "${eff:-0}" -gt 200 ]; then
    add HIGH CM01 "$sf" "" "CLAUDE.md 가 너무 김: 실효 ${eff}줄 (원본 ${raw}줄), 기준 200줄" "effective=${eff} raw=${raw}"
  fi

  # CM02: 자동화 지시 패턴 (동작 대상이 명시된 줄만)
  m=$(narrow_lines "$f" '매번|항상|every ?time|after every|always run|whenever you')
  if [ -n "$m" ]; then
    ln=$(printf '%s\n' "$m" | cut -d: -f1 | head -8 | join_commas)
    ev=$(printf '%s\n' "$m" | head -3 | sed 's/^[0-9]*:[[:space:]]*//' | cut -c1-70 | join_commas)
    cnt=$(printf '%s\n' "$m" | wc -l | tr -d ' ')
    add MED CM02 "$sf" "$ln" "자동화 지시 패턴 ${cnt}건 (훅/스킬로 옮겨야 실제로 보장됨)" "$ev"
  fi

  # CM03: 금지 지시 (금지 대상이 도구·명령어·경로인 줄만)
  m=$(narrow_lines "$f" '절대|금지|하지 ?마|하지마|말 것|never|do not ever')
  if [ -n "$m" ]; then
    ln=$(printf '%s\n' "$m" | cut -d: -f1 | head -8 | join_commas)
    ev=$(printf '%s\n' "$m" | head -3 | sed 's/^[0-9]*:[[:space:]]*//' | cut -c1-70 | join_commas)
    cnt=$(printf '%s\n' "$m" | wc -l | tr -d ' ')
    add MED CM03 "$sf" "$ln" "금지형 지시 ${cnt}건 (permissions.deny / 훅이 더 확실함)" "$ev"
  fi

  # CM08: 연속 번호 목록 5단계 이상
  r=$(awk '
    { if ($0 ~ /^[ \t]*[0-9]+[.)][ \t]/) { if (run==0) start=NR; run++; if (run>max){max=run;ms=start;me=NR} }
      else if ($0 ~ /^[ \t]*$/ || $0 ~ /^[ \t]+[^ \t]/) { }
      else { run=0 } }
    END { if (max>=5) print max"\t"ms"\t"me }' "$f" 2>/dev/null)
  if [ -n "$r" ]; then
    n=$(printf '%s' "$r" | cut -f1); s1=$(printf '%s' "$r" | cut -f2); s2=$(printf '%s' "$r" | cut -f3)
    add MED CM08 "$sf" "${s1}-${s2}" "번호 절차가 ${n}단계 연속 (절차는 스킬로 빼는 편이 맞음)" "steps=${n}"
  fi

  # CM09: 대문자 강조 3회 이상
  m=$(grep -nE '\b(IMPORTANT|MUST|NEVER|ALWAYS|CRITICAL|REQUIRED|MANDATORY)\b' "$f" 2>/dev/null)
  if [ -n "$m" ]; then
    cnt=$(grep -oE '\b(IMPORTANT|MUST|NEVER|ALWAYS|CRITICAL|REQUIRED|MANDATORY)\b' "$f" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$cnt" -ge 3 ]; then
      ln=$(printf '%s\n' "$m" | cut -d: -f1 | head -8 | join_commas)
      ev=$(grep -oE '\b(IMPORTANT|MUST|NEVER|ALWAYS|CRITICAL|REQUIRED|MANDATORY)\b' "$f" 2>/dev/null | sort | uniq -c | sort -rn | head -4 | awk '{printf "%s×%s ", $2, $1}')
      add MED CM09 "$sf" "$ln" "대문자 강조 ${cnt}회 (강조가 흔해지면 강조가 아님)" "$ev"
    fi
  fi

  # CM10: @경로 import 3개 이상 (코드블록/백틱 제외)
  imp=$(awk '
    { line=$0
      if (line ~ /^[ \t]*```/) { infence = !infence; next }
      if (infence) next
      gsub(/`[^`]*`/, "", line)
      while (match(line, /(^|[ \t(\[,])@[~.\/A-Za-z0-9_-][A-Za-z0-9_.\/~-]*/)) {
        tok = substr(line, RSTART, RLENGTH)
        line = substr(line, RSTART+RLENGTH)
        sub(/^[ \t(\[,]/, "", tok)
        if (tok ~ /\//) print NR":"tok
      } }' "$f" 2>/dev/null)
  if [ -n "$imp" ]; then
    cnt=$(printf '%s\n' "$imp" | wc -l | tr -d ' ')
    if [ "$cnt" -ge 3 ]; then
      ln=$(printf '%s\n' "$imp" | cut -d: -f1 | head -8 | join_commas)
      ev=$(printf '%s\n' "$imp" | cut -d: -f2- | head -5 | join_commas)
      add MED CM10 "$sf" "$ln" "@경로 import ${cnt}개 (전부 상시 로드됨)" "$ev"
    fi
  fi
done

# CM06: 전역 CLAUDE.md 에 프로젝트 고유 명사/경로
if [ -n "$GLOBAL_CLAUDEMD" ] && [ -f "$GLOBAL_CLAUDEMD" ]; then
  m=$(grep -nE 'src/|npm run|yarn |pnpm |package\.json|node_modules|docker-compose|pytest|go test|\.claude/skills/|requirements\.txt|Gemfile|pom\.xml|build\.gradle|tsconfig|/Users/|/home/' "$GLOBAL_CLAUDEMD" 2>/dev/null)
  if [ -n "$m" ]; then
    ln=$(printf '%s\n' "$m" | cut -d: -f1 | head -8 | join_commas)
    ev=$(printf '%s\n' "$m" | head -3 | sed 's/^[0-9]*:[[:space:]]*//' | cut -c1-70 | join_commas)
    cnt=$(printf '%s\n' "$m" | wc -l | tr -d ' ')
    add INFO CM06 "$(shorten "$GLOBAL_CLAUDEMD")" "$ln" "전역 CLAUDE.md 에 프로젝트 고유로 보이는 항목 ${cnt}건 — 확인 필요 (프로젝트 CLAUDE.md 로 옮길 후보)" "$ev"
  fi
fi

# ================================================================ CM11 (rules 파일)
for f in $(printf '%s\n' "$RULES_LIST"); do
  [ -f "$f" ] || continue
  bytes=$(wc -c < "$f" | tr -d ' ')
  if [ "$bytes" -gt 4194304 ]; then
    mib=$(( bytes / 1048576 ))
    add HIGH CM11 "$(shorten "$f")" "" "4 MiB 초과(약 ${mib} MiB) → 파일 전체가 로드되지 않고 조용히 스킵됨" "bytes=${bytes} limit=4194304"
  fi
done

# ================================================================ RU01
if [ -n "$RULES_LIST" ]; then
  miss=""
  for f in $(printf '%s\n' "$RULES_LIST"); do
    [ -f "$f" ] || continue
    if ! frontmatter "$f" | grep -qE '^[[:space:]]*paths[[:space:]]*:'; then
      miss="$miss $(basename "$f")"
    fi
  done
  if [ -n "$miss" ]; then
    n=$(printf '%s' "$miss" | wc -w | tr -d ' ')
    add MED RU01 "rules/" "" "paths: 프론트매터 없는 rule ${n}개 → 상시 로드됨" "$(printf '%s' "$miss" | sed 's/^ //')"
  fi
fi

# ================================================================ SKILL.md 체크
SK_DESC_FILE="$(mktemp -t ccauddesc.XXXXXX)"
trap 'rm -f "$FINDINGS_FILE" "$SCANNED_FILE" "$NOTES_FILE" "$SK_DESC_FILE"' EXIT

if [ -n "$SKILLS_LIST" ]; then
  sk02=""; sk03=""; sk04=""
  for f in $(printf '%s\n' "$SKILLS_LIST"); do
    [ -f "$f" ] || continue
    name=$(basename "$(dirname "$f")")

    # SK04: 500줄 초과
    n=$(wc -l < "$f" | tr -d ' ')
    [ "$n" -gt 500 ] && sk04="${sk04}${name}(${n}줄) "

    # SK02: disable-model-invocation 없고 본문에 부작용 키워드
    if ! frontmatter "$f" | grep -qE '^[[:space:]]*disable-model-invocation[[:space:]]*:[[:space:]]*true'; then
      kw=$(body_after_fm "$f" | grep -oEi '\b(deploy|push|release|publish|migrate|rm -rf|rm -f)\b|배포|삭제' 2>/dev/null | tr 'A-Z' 'a-z' | sort -u | head -4 | join_commas)
      [ -n "$kw" ] && sk02="${sk02}${name}[${kw}] "
    fi

    # SK03: 절대경로 하드코딩
    hp=$(grep -nE '(/Users/[A-Za-z0-9._-]+|/home/[A-Za-z0-9._-]+)/' "$f" 2>/dev/null | head -3)
    if [ -n "$hp" ]; then
      ln=$(printf '%s\n' "$hp" | cut -d: -f1 | join_commas)
      sk03="${sk03}${name}:${ln} "
    fi

    # SK01용 description 수집
    d=$(frontmatter "$f" | sed -n 's/^[[:space:]]*description[[:space:]]*:[[:space:]]*//p' | head -1)
    [ -n "$d" ] && printf '%s\t%s\n' "$name" "$d" >> "$SK_DESC_FILE"
  done

  # 공백으로 구분된 항목 개수 (멀티바이트 안전)
  count_items() { printf '%s' "$1" | tr ' ' '\n' | grep -c . ; }
  sk02=${sk02% }; sk03=${sk03% }; sk04=${sk04% }
  [ -n "$sk02" ] && add MED SK02 "skills/" "" "부작용 키워드가 있는데 disable-model-invocation 이 없는 스킬 $(count_items "$sk02")개 (모델이 임의 호출 가능)" "$sk02"
  [ -n "$sk03" ] && add MED SK03 "skills/" "" "절대경로 하드코딩 $(count_items "$sk03")개 (\${CLAUDE_SKILL_DIR} 사용 권장)" "$sk03"
  [ -n "$sk04" ] && add MED SK04 "skills/" "" "SKILL.md 500줄 초과 $(count_items "$sk04")개" "$sk04"

  # SK01: description 단어 3개 이상 겹치는 쌍 (휴리스틱)
  if [ -s "$SK_DESC_FILE" ]; then
    pairs=$(awk -F'\t' '
      function norm(s,  t) {
        t = tolower(s); gsub(/[^a-z0-9가-힣 ]/, " ", t); return t
      }
      BEGIN {
        split("the a an and or of to for in on with use used when user this that is are be it its as by from at if not no do does 를 을 이 가 은 는 에 의 로 와 과 및 등 하는 한다 해서 사용 대해", sw, " ")
        for (i in sw) stop[sw[i]] = 1
      }
      { n++; nm[n]=$1; d=norm($2); split(d, w, " ")
        delete seen
        for (i in w) { x=w[i]; if (length(x)>=3 && !(x in stop) && !(x in seen)) { seen[x]=1; W[n,x]=1; cnt[n]++ } }
        for (x in seen) words[n] = words[n] " " x }
      END {
        for (i=1;i<=n;i++) for (j=i+1;j<=n;j++) {
          c=0; shared=""
          split(words[i], a, " ")
          for (k in a) if (a[k] != "" && W[j,a[k]]) { c++; if (c<=5) shared = shared (shared==""?"":",") a[k] }
          if (c>=3) print nm[i] "~" nm[j] "(" c ":" shared ")"
        }
      }' "$SK_DESC_FILE" 2>/dev/null | head -6)
    if [ -n "$pairs" ]; then
      np=$(printf '%s\n' "$pairs" | wc -l | tr -d ' ')
      add INFO SK01 "skills/" "" "description 이 겹치는 스킬 쌍 ${np}건 — 확인 필요 (트리거가 서로 잡아먹을 수 있음)" "$(printf '%s\n' "$pairs" | join_commas)"
    fi
  fi
fi

# ================================================================ settings.json 체크
# settings.json 최상위 키 목록 — 2026-09-21 시점 settings-reference 기준.
# 주의: 이 목록은 실제 CLI 버전보다 뒤처질 수 있다(예: /voice 관련 키는 문서에 없지만 동작함).
#       CLI 업데이트 시 https://code.claude.com/docs/en/settings-reference 로 갱신할 것.
KNOWN_KEYS=" advisorModel agent agentPushNotifEnabled allowAllClaudeAiMcps allowedChannelPlugins allowedHttpHookUrls allowedMcpServers allowManagedHooksOnly allowManagedMcpServersOnly allowManagedPermissionRulesOnly alwaysThinkingEnabled apiKeyHelper askUserQuestionTimeout attribution autoCompactEnabled autoCompactWindow autoConnectIde autoContinueAtUsageLimit autoInstallIdeExtension autoMemoryDirectory autoMemoryEnabled autoMode autoScrollEnabled autoUpdatesChannel availableModels awaySummaryEnabled awsAuthRefresh awsCredentialExport axScreenReader bashEditDiffEnabled bashOutputMaxChars blockedMarketplaces browserExternalPageTools channelsEnabled claudeMd claudeMdExcludes cleanupPeriodDays companyAnnouncements copyOnSelect crossSessionInbound defaultShell deniedMcpServers desktopSessionCleanupPeriodDays dialogExpiry diffTool disableAgentView disableAllHooks disableArtifact disableAutoMode disableBrowserExternalNavigation disableBundledSkills disableClaudeAiConnectors disableCommandPluginSources disabledMcpjsonServers disableDeepLinkRegistration disableDesktopLocalSessions disableMobileSimulatorTools disableRemoteControl disableSideloadFlags disableSkillShellExecution disableWorkflows editorMode effortLevel emojiCompletionEnabled enableAllProjectMcpServers enableArtifact enabledMcpjsonServers enabledPlugins enableWorkflows enforceAvailableModels env externalEditorContext extraKnownMarketplaces fallbackModel fastMode fastModePerSessionOptIn feedbackDrafts feedbackSurveyRate fileCheckpointingEnabled fileSuggestion footerLinksRegexes forceLoginGatewayUrl forceLoginMethod forceLoginOrgUUID forceRemoteSettingsRefresh gatewayInternalNetworks gcpAuthRefresh hooks httpHookAllowedEnvVars includeCoAuthoredBy includeGitInstructions inputNeededNotifEnabled isolatePeerMachines keybindingFlavor language managedMcpServers managedSourcesBehavior maxEffortLevel minimumVersion model modelOverrides modelPicker modelPricing modelSettings otelHeadersHelper outputStyle parentSettingsBehavior permissionExplainerEnabled permissions plansDirectory pluginConfigs pluginSuggestionMarketplaces pluginTrustMessage policyHelper preferredNotifChannel prefersReducedMotion processWrapper promptCacheTtl promptSuggestionEnabled prUrlTemplate remote remoteControlAtStartup requiredMaximumVersion requiredMinimumVersion respectGitignore respondToBashCommands sandbox showClearContextOnPlanAccept showThinkingSummaries showTurnDuration skillListingBudgetFraction skillListingMaxDescChars skillOverrides skipAutoPermissionPrompt skipDangerousModePermissionPrompt skipWebFetchPreflight spellcheck spinnerTipsEnabled spinnerTipsOverride spinnerVerbs sshConfigs sshHostAllowlist statusLine strictKnownMarketplaces strictPluginOnlyCustomization "
DEPRECATED_KEYS=" includeCoAuthoredBy disableArtifact keybindingFlavor permissionExplainerEnabled "
DEV_CMDS=" npm npx pnpm yarn pip pip3 brew docker kubectl curl wget make cargo go "

SANDBOX_OK=0
SETTINGS_SEEN=0
HK05_HITS=""      # exit 0 + stderr 조합이 확인된 훅 스크립트
HK05_UNREAD=""    # 읽지 못한 훅 스크립트 (판정 skip)
HK05_READ=0       # 훅 스크립트를 하나라도 읽었는지

for f in $(printf '%s\n' "$SETTINGS_LIST"); do
  [ -f "$f" ] || continue
  SETTINGS_SEEN=1
  sf=$(shorten "$f")

  if ! json_valid "$f"; then
    note "$sf : JSON 파싱 실패 — 이 파일 기반 체크는 건너뜀"
    continue
  fi

  # ---- PM01: deny 에 일상 개발 명령
  hits=""
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    case "$e" in
      Bash\(*\)) inner=$(printf '%s' "$e" | sed -n 's/^Bash(\(.*\))$/\1/p') ;;
      *) continue ;;
    esac
    cmd=$(printf '%s' "$inner" | sed 's/[:( ].*$//' | sed 's/[^A-Za-z0-9_.-]//g')
    [ -n "$cmd" ] || continue
    case "$DEV_CMDS" in
      *" $cmd "*) case " $hits " in *" $cmd "*) ;; *) hits="$hits $cmd" ;; esac ;;
    esac
  done <<EOF
$(cfg_get "$f" "permissions.deny" array)
EOF
  if [ -n "$hits" ]; then
    n=$(printf '%s' "$hits" | wc -w | tr -d ' ')
    add HIGH PM01 "${sf}:permissions.deny" "" "일상 개발 명령 ${n}개가 deny 에 있음 (되돌릴 수 없이 차단됨 → ask 로 내려야 함)" "$(printf '%s' "$hits" | sed 's/^ //' | tr ' ' ',')"
  fi

  dm=$(cfg_get "$f" "permissions.defaultMode" raw)

  # ---- PM03: auto 모드에서 자동으로 드롭되는 광범위 allow 규칙을 계속 들고 있음
  #   드롭 대상: Bash(*)/PowerShell(*), 인터프리터 와일드카드, 패키지매니저 run, Agent, Monitor
  if [ "$dm" = "auto" ]; then
    broad=""
    while IFS= read -r e; do
      [ -n "$e" ] || continue
      hit=""
      case "$e" in
        'Bash(*)'|'PowerShell(*)'|'Bash(*:*)') hit="$e" ;;
        Agent|Monitor|Agent\(*|Monitor\(*) hit="$e" ;;
      esac
      if [ -z "$hit" ]; then
        inner=""
        case "$e" in
          Bash\(*\))       inner=${e#Bash(};       inner=${inner%)} ;;
          PowerShell\(*\)) inner=${e#PowerShell(}; inner=${inner%)} ;;
        esac
        if [ -n "$inner" ]; then
          first=$(printf '%s' "$inner" | sed 's/[:( *].*$//')
          case "$inner" in
            *'*'*)
              case " python python3 node nodejs ruby perl bash sh zsh php deno bun osascript pwsh " in
                *" $first "*) hit="$e" ;;
              esac
              ;;
          esac
          # 패키지 매니저 run 계열
          case "$inner" in
            npm\ run*|pnpm\ run*|yarn\ run*|bun\ run*|npm\ start*|yarn\ *|pnpm\ *|npx\ *|yarn:*|pnpm:*|npx:*) hit="$e" ;;
          esac
        fi
      fi
      if [ -n "$hit" ]; then
        case "$NL$broad" in *"$NL$hit$NL"*) ;; *) broad="${broad}${hit}${NL}" ;; esac
      fi
    done <<EOF
$(cfg_get "$f" "permissions.allow" array)
EOF
    if [ -n "$broad" ]; then
      nb=$(printf '%s' "$broad" | grep -c .)
      add MED PM03 "${sf}:permissions.allow" "" "auto 모드에서 자동 드롭되는 광범위 allow 규칙 ${nb}개 — auto 에서는 효과가 없고, auto 를 끄는 순간 되살아나 위험" "$(printf '%s' "$broad" | paste -sd, - )"
    fi
  fi

  # ---- PM06: 평가되지 않는 툴에 경로 규칙 (Write/Glob/NotebookEdit/MultiEdit)
  bad_rules=""
  for lst in allow ask deny; do
    while IFS= read -r e; do
      [ -n "$e" ] || continue
      case "$e" in
        Write\(*\)|Glob\(*\)|NotebookEdit\(*\)|MultiEdit\(*\))
          bad_rules="${bad_rules}${lst}:${e}${NL}" ;;
      esac
    done <<EOF
$(cfg_get "$f" "permissions.$lst" array)
EOF
  done
  if [ -n "$bad_rules" ]; then
    nbr=$(printf '%s' "$bad_rules" | grep -c .)
    add MED PM06 "${sf}:permissions" "" "경로 인자를 가진 Write/Glob/NotebookEdit/MultiEdit 규칙 ${nbr}개 — 수락은 되지만 평가되지 않음 (Edit/Read 규칙으로 바꿔야 함)" "$(printf '%s' "$bad_rules" | paste -sd, - )"
  fi

  # ---- SET04: 프로젝트/로컬 설정의 defaultMode=auto|bypassPermissions 는 적용되지 않음
  if [ "$f" != "$GLOBAL_SETTINGS" ]; then
    case "$dm" in
      auto|bypassPermissions)
        add HIGH SET04 "${sf}:permissions.defaultMode" "" "프로젝트/로컬 설정의 defaultMode=${dm} 는 적용되지 않음 (조용히 무시됨) — 사용자/관리 설정 또는 --permission-mode 로" "defaultMode=${dm} scope=project"
        ;;
    esac
  fi

  # ---- PM04: 위험 모드
  sdp=$(cfg_get "$f" "skipDangerousModePermissionPrompt" raw)
  ev=""
  [ "$sdp" = "true" ] && ev="skipDangerousModePermissionPrompt=true"
  if [ "$dm" = "bypassPermissions" ]; then
    [ -n "$ev" ] && ev="$ev, "
    ev="${ev}permissions.defaultMode=bypassPermissions"
  fi
  if [ -n "$ev" ]; then
    add HIGH PM04 "$sf" "" "권한 확인을 건너뛰도록 설정됨 (사실상 무제한 실행)" "$ev"
  fi

  # ---- PM05: sandbox.enabled
  sb=$(cfg_get "$f" "sandbox.enabled" raw)
  [ "$sb" = "true" ] && SANDBOX_OK=1

  # ---- SET01 / SET02: 최상위 키
  unknown=""; deprecated=""
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    case "$DEPRECATED_KEYS" in
      *" $k "*) deprecated="$deprecated $k"; continue ;;
    esac
    case "$KNOWN_KEYS" in
      *" $k "*) ;;
      *) unknown="$unknown $k" ;;
    esac
  done <<EOF
$(cfg_get "$f" "" keys)
EOF
  if [ -n "$unknown" ]; then
    n=$(printf '%s' "$unknown" | wc -w | tr -d ' ')
    add INFO SET01 "$sf" "" "문서화된 키 목록에 없는 최상위 키 ${n}개 — 오타일 수도, 미문서화 신규 키일 수도 있다. 목록이 CLI 버전보다 뒤처질 수 있으니 단정하지 말 것 (오타라면 대화형에서 Settings Warning 이 뜨고, -p 비대화형에서는 조용히 유실됨)" "$(printf '%s' "$unknown" | sed 's/^ //' | tr ' ' ',')"
  fi
  if [ -n "$deprecated" ]; then
    n=$(printf '%s' "$deprecated" | wc -w | tr -d ' ')
    add HIGH SET02 "$sf" "" "deprecated 키 ${n}개 사용 중 (무시되거나 곧 제거됨)" "$(printf '%s' "$deprecated" | sed 's/^ //' | tr ' ' ',')"
  fi

  # ---- HK02: 훅 출력 제한 휴리스틱
  hooks_raw=$(cfg_get "$f" "hooks" raw)
  if [ -n "$hooks_raw" ]; then
    cmds=$(printf '%s' "$hooks_raw" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/^"command"[[:space:]]*:[[:space:]]*"//; s/"$//')
    unbounded=""
    while IFS= read -r c; do
      [ -n "$c" ] || continue
      case "$c" in
        *head*|*tail*|*truncate*|*"cut -c"*|*"-n 1"*|*">/dev/null"*|*"> /dev/null"*) ;;
        *) unbounded="${unbounded}$(printf '%s' "$c" | cut -c1-40)|" ;;
      esac
    done <<EOF
$cmds
EOF
    if [ -n "$unbounded" ]; then
      n=$(printf '%s' "$unbounded" | tr '|' '\n' | grep -c .)
      add INFO HK02 "${sf}:hooks" "" "출력 제한이 안 보이는 훅 명령 ${n}건 — 확인 필요 (출력이 컨텍스트로 통째로 들어갈 수 있음)" "$(printf '%s' "$unbounded" | sed 's/|$//' | tr '|' ',')"
    fi
  fi

  # ---- HK05: exit 0 + stderr 전용 출력 (Claude 에게 전달되지 않음)
  #   훅 커맨드가 가리키는 스크립트 파일을 읽을 수 있을 때만 판정. 못 읽으면 skip.
  if [ -n "$hooks_raw" ]; then
    while IFS= read -r c; do
      [ -n "$c" ] || continue
      # 인라인 커맨드 자체에 '>&2' 와 'exit 0' 이 같이 있는 경우
      if printf '%s' "$c" | grep -q '>&2' && printf '%s' "$c" | grep -q 'exit 0'; then
        HK05_HITS="${HK05_HITS}inline:$(printf '%s' "$c" | cut -c1-40) "
        continue
      fi
      # 커맨드 안에서 스크립트 경로 후보를 뽑아 읽어본다
      for tok in $c; do
        case "$tok" in
          *.sh|*.bash|*.py|*.zsh) ;;
          *) continue ;;
        esac
        # 훅에서 흔히 쓰는 변수부터 먼저 치환한 뒤 절대/상대 경로를 판단한다
        sp=$(printf '%s' "$tok" \
             | sed "s|[\$]{CLAUDE_PROJECT_DIR}|$PROJ_DIR|g; s|[\$]CLAUDE_PROJECT_DIR|$PROJ_DIR|g" \
             | sed "s|[\$]{CLAUDE_CONFIG_DIR}|$CFG_DIR|g; s|[\$]CLAUDE_CONFIG_DIR|$CFG_DIR|g" \
             | sed "s|[\$]{HOME}|$HOME|g; s|[\$]HOME|$HOME|g")
        case "$sp" in
          '~'/*) sp="$HOME/${sp#\~/}" ;;
          /*) ;;
          *) sp="$PROJ_DIR/$sp" ;;
        esac
        if [ -r "$sp" ]; then
          HK05_READ=1
          if grep -q '>&2' "$sp" 2>/dev/null && grep -qE '(^|[[:space:];&])exit 0([[:space:];&]|$)' "$sp" 2>/dev/null; then
            HK05_HITS="${HK05_HITS}$(basename "$sp") "
          fi
        else
          HK05_UNREAD="${HK05_UNREAD}$(basename "$sp") "
        fi
      done
    done <<EOF
$cmds
EOF
  fi

  # ---- SET03: 전역 settings 에 프로젝트 성격 설정
  if [ "$f" = "$GLOBAL_SETTINGS" ]; then
    ev=""
    if [ -n "$hooks_raw" ] && printf '%s' "$hooks_raw" | grep -qE '/Users/|/home/|\.\./'; then
      ev="hooks 에 특정 경로"
    fi
    env_raw=$(cfg_get "$f" "env" raw)
    if [ -n "$env_raw" ] && printf '%s' "$env_raw" | grep -qE '/Users/|/home/|localhost|127\.0\.0\.1|_URL|_TOKEN|_KEY'; then
      [ -n "$ev" ] && ev="$ev, "
      ev="${ev}env 에 프로젝트 고유 값"
    fi
    if [ -n "$ev" ]; then
      add MED SET03 "$sf" "" "전역 settings 에 프로젝트 성격 설정이 섞임 (프로젝트 .claude/settings.json 으로)" "$ev"
    fi
  fi
done

# HK05: 전체 판정
if [ -n "$HK05_HITS" ]; then
  HK05_HITS=${HK05_HITS% }
  n=$(printf '%s' "$HK05_HITS" | tr ' ' '\n' | grep -c .)
  add MED HK05 "hooks" "" "exit 0 로 끝나면서 stderr 로만 출력하는 훅 ${n}건 — exit 0 의 stderr 는 Claude 에게 전달되지 않음 (차단은 exit 2, 정보 전달은 JSON additionalContext)" "$HK05_HITS"
elif [ -n "$HK05_UNREAD" ]; then
  HK05_UNREAD=${HK05_UNREAD% }
  note "HK05: 훅 스크립트를 읽을 수 없어 판정을 건너뜀 → $(printf '%s' "$HK05_UNREAD" | tr ' ' ',')"
fi

# PM05 는 파일별이 아니라 전체 판정 (어디에도 sandbox.enabled=true 가 없으면 경고)
if [ "$SETTINGS_SEEN" = "1" ] && [ "$SANDBOX_OK" = "0" ] && [ "$JSON_ENGINE" != "none" ]; then
  add MED PM05 "settings.json" "" "sandbox.enabled 가 켜져 있지 않음 (미설정 포함) — 샌드박스 없이 명령이 실행됨" "sandbox.enabled != true"
fi

# ================================================================ MEM01
for f in $(printf '%s\n' "$MEMORY_LIST"); do
  [ -f "$f" ] || continue
  n=$(wc -l < "$f" | tr -d ' ')
  b=$(wc -c < "$f" | tr -d ' ')
  if [ "$n" -gt 200 ] || [ "$b" -gt 25600 ]; then
    kb=$(( b / 1024 ))
    add HIGH MEM01 "$(shorten "$f")" "" "auto memory 가 너무 큼: ${n}줄 / ${kb}KB (기준 200줄 / 25KB) — 매 세션 로드됨" "lines=${n} bytes=${b}"
  fi
done

# ================================================================ AG01
agent_count=0
for d in $(printf '%s\n' "$AGENT_DIRS"); do
  [ -d "$d" ] || continue
  c=$(find "$d" -maxdepth 1 -type f -name '*.md' 2>/dev/null | grep -c .)
  agent_count=$(( agent_count + c ))
done
if [ "$agent_count" = "0" ]; then
  add INFO AG01 "-" "" "서브에이전트 정의 없음 (탐색/조사를 서브에이전트로 넘기면 메인 컨텍스트가 덜 더러워짐)" "agents=0"
fi

# ================================================================ MC01
mcp_names=""
for f in $(printf '%s\n' "$MCP_FILES"); do
  [ -f "$f" ] || continue
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    case " $mcp_names " in *" $k "*) ;; *) mcp_names="$mcp_names $k" ;; esac
  done <<EOF
$(cfg_get "$f" "mcpServers" keys)
EOF
done
for f in $(printf '%s\n' "$SETTINGS_LIST"); do
  [ -f "$f" ] || continue
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    case " $mcp_names " in *" $k "*) ;; *) mcp_names="$mcp_names $k" ;; esac
  done <<EOF
$(cfg_get "$f" "mcpServers" keys; cfg_get "$f" "managedMcpServers" keys; cfg_get "$f" "enabledMcpjsonServers" array)
EOF
done
mcp_n=$(printf '%s' "$mcp_names" | wc -w | tr -d ' ')
if [ "$mcp_n" -gt 5 ]; then
  add INFO MC01 "-" "" "등록된 MCP 서버 ${mcp_n}개 — 툴 스키마는 지연 로드되지만 서버 instructions 와 시작 시 연결/인증 지연이 실제 비용. /context all 로 확인 권장" "$(printf '%s' "$mcp_names" | sed 's/^ //' | cut -c1-140 | tr ' ' ',')"
fi

# ================================================================ 출력
nh=$(awk -F"$SEP" '$1=="HIGH"' "$FINDINGS_FILE" 2>/dev/null | grep -c . )
nm=$(awk -F"$SEP" '$1=="MED"'  "$FINDINGS_FILE" 2>/dev/null | grep -c . )
ni=$(awk -F"$SEP" '$1=="INFO"' "$FINDINGS_FILE" 2>/dev/null | grep -c . )
hit_ids=$(awk -F"$SEP" '{print $2}' "$FINDINGS_FILE" 2>/dev/null | sort -u | grep -c . )
npass=$(( TOTAL_RULES - hit_ids ))
[ "$npass" -lt 0 ] && npass=0

json_esc() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\t'/\\t}
  s=${s//$'\r'/\\r}
  s=${s//$'\n'/\\n}
  printf '%s' "$s"
}

if [ "$OUT_JSON" = "1" ]; then
  printf '{"findings":['
  first=1
  while IFS="$SEP" read -r sev id file lines msg ev; do
    [ -n "$sev" ] || continue
    [ "$first" = "1" ] || printf ','
    first=0
    printf '{"id":"%s","severity":"%s","file":"%s","lines":"%s","message":"%s","evidence":"%s"}' \
      "$(json_esc "$id")" "$(json_esc "$sev")" "$(json_esc "$file")" \
      "$(json_esc "$lines")" "$(json_esc "$msg")" "$(json_esc "$ev")"
  done < "$FINDINGS_FILE"
  printf '],"summary":{"HIGH":%d,"MED":%d,"INFO":%d,"pass":%d,"rules_total":%d,"scope":"%s","project_dir":"%s","config_dir":"%s","json_engine":"%s"},"scanned":[' \
    "$nh" "$nm" "$ni" "$npass" "$TOTAL_RULES" "$(json_esc "$SCOPE")" "$(json_esc "$PROJ_DIR")" "$(json_esc "$(shorten "$CFG_DIR")")" "$JSON_ENGINE"
  first=1
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    [ "$first" = "1" ] || printf ','
    first=0
    printf '"%s"' "$(json_esc "$s")"
  done < "$SCANNED_FILE"
  printf '],"notes":['
  first=1
  if [ -s "$NOTES_FILE" ]; then
    while IFS= read -r s; do
      [ -n "$s" ] || continue
      [ "$first" = "1" ] || printf ','
      first=0
      printf '"%s"' "$(json_esc "$s")"
    done < "$NOTES_FILE"
  fi
  printf ']}\n'
else
  echo "Claude Code 설정 점검  (scope: $SCOPE)"
  nscan=$(grep -c . "$SCANNED_FILE")
  head_list=$(head -6 "$SCANNED_FILE" | tr '\n' '@' | sed 's/@$//; s/@/, /g')
  if [ "$nscan" -gt 6 ]; then
    echo "설정 위치(${nscan}개): ${head_list} ... 외 $(( nscan - 6 ))개"
  else
    echo "설정 위치(${nscan}개): ${head_list}"
  fi
  echo
  if [ -s "$FINDINGS_FILE" ]; then
    for want in HIGH MED INFO; do
      while IFS="$SEP" read -r sev id file lines msg ev; do
        [ "$sev" = "$want" ] || continue
        loc="$file"
        [ -n "$lines" ] && loc="${file}:${lines}"
        printf '%-5s %-5s %-46s %s\n' "$sev" "$id" "$(printf '%s' "$loc" | cut -c1-46)" "$msg"
        [ -n "$ev" ] && printf '%s→ %s\n' "                                                      " "$(printf '%s' "$ev" | cut -c1-160)"
      done < "$FINDINGS_FILE"
    done
    echo
  else
    echo "발견된 안티패턴 없음."
    echo
  fi
  echo "요약: HIGH $nh / MED $nm / INFO $ni   (통과 $npass)"
  if [ -s "$NOTES_FILE" ]; then
    echo
    echo "참고:"
    sed 's/^/  - /' "$NOTES_FILE"
  fi
  echo "기준 문서: reference/antipatterns.md 의 각 ID 참조"
fi

[ "$nh" -gt 0 ] && exit 1
exit 0
