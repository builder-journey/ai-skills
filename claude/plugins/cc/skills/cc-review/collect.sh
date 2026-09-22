#!/usr/bin/env bash
# cc-review 수집기 — 클로드를 조종하는 "지시부 텍스트" 인벤토리를 만든다.
#
# 이 스크립트는 판정하지 않는다. 찾고, 세고, frontmatter 를 뽑을 뿐이다.
# 좋은지 나쁜지는 최신 공식 문서를 읽은 판정 에이전트가 결정한다.
#
# 읽기 전용. 어떤 파일도 수정하지 않는다.
set -uo pipefail

usage() {
  cat <<'USAGE'
사용법: collect.sh [옵션]

  --json              JSON 으로 출력 (기본: 사람이 읽는 표)
  --project-dir DIR   프로젝트 루트 (기본: $PWD)
  --max-depth N       하위 디렉토리 CLAUDE.md 탐색 깊이 (기본: 4)
  -h, --help          이 도움말

종료 코드:  0 정상  ·  2 대상 파일 없음  ·  3 의존성 없음
USAGE
}

OUT_JSON=0
PROJ_DIR="$PWD"
MAX_DEPTH=4

while [ $# -gt 0 ]; do
  case "$1" in
    --json) OUT_JSON=1 ;;
    --project-dir) shift; PROJ_DIR="${1:-$PWD}" ;;
    --max-depth) shift; MAX_DEPTH="${1:-4}" ;;
    -h|--help) usage; exit 0 ;;
    *) printf '알 수 없는 옵션: %s\n\n' "$1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

command -v python3 >/dev/null 2>&1 || { echo "python3 가 필요하다 (JSON 출력·frontmatter 파싱)" >&2; exit 3; }

CFG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
[ -d "$PROJ_DIR" ] || { echo "프로젝트 디렉토리가 없다: $PROJ_DIR" >&2; exit 1; }

# ---------------------------------------------------------------- 대상 수집
# 형식: <kind>\t<scope>\t<load>\t<path>
#   kind  claude_md | agents_md | rules | skill | agent
#   load  always(상시) | conditional(조건부) | on_demand(호출 시)
TMP=$(mktemp) || exit 1
cleanup() { rm -f "$TMP"; }
trap cleanup EXIT INT TERM

emit() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$TMP"; }

# --- 유저 스코프 -------------------------------------------------
[ -f "$CFG_DIR/CLAUDE.md" ] && emit claude_md user always "$CFG_DIR/CLAUDE.md"

if [ -d "$CFG_DIR/rules" ]; then
  # 유저 룰은 재귀적으로 발견된다
  while IFS= read -r f; do
    [ -n "$f" ] && emit rules user unknown "$f"
  done <<EOF
$(find "$CFG_DIR/rules" -type f -name '*.md' 2>/dev/null | sort)
EOF
fi

if [ -d "$CFG_DIR/skills" ]; then
  # synced/ 는 벤더가 동기화하는 스킬이라 사용자가 고칠 수 없다 → 제외
  while IFS= read -r f; do
    [ -n "$f" ] && emit skill user on_demand "$f"
  done <<EOF
$(find "$CFG_DIR/skills" -maxdepth 2 -type f -name 'SKILL.md' 2>/dev/null | grep -v '/skills/synced/' | sort)
EOF
fi

if [ -d "$CFG_DIR/agents" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] && emit agent user on_demand "$f"
  done <<EOF
$(find "$CFG_DIR/agents" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort)
EOF
fi

# --- 프로젝트 스코프 ---------------------------------------------
[ -f "$PROJ_DIR/CLAUDE.md" ]         && emit claude_md project always      "$PROJ_DIR/CLAUDE.md"
[ -f "$PROJ_DIR/.claude/CLAUDE.md" ] && emit claude_md project always      "$PROJ_DIR/.claude/CLAUDE.md"
[ -f "$PROJ_DIR/CLAUDE.local.md" ]   && emit claude_md local   always      "$PROJ_DIR/CLAUDE.local.md"
[ -f "$PROJ_DIR/AGENTS.md" ]         && emit agents_md project conditional "$PROJ_DIR/AGENTS.md"

# 하위 디렉토리 CLAUDE.md — 해당 디렉토리에서 작업할 때만 로드된다
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in
    "$PROJ_DIR/CLAUDE.md"|"$PROJ_DIR/.claude/CLAUDE.md") continue ;;
  esac
  emit claude_md project on_demand "$f"
done <<EOF
$(find "$PROJ_DIR" -mindepth 2 -maxdepth "$MAX_DEPTH" -type f -name 'CLAUDE.md' \
    -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/vendor/*' \
    -not -path '*/dist/*' -not -path '*/build/*' -not -path '*/.venv/*' 2>/dev/null | sort)
EOF

if [ -d "$PROJ_DIR/.claude/rules" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] && emit rules project unknown "$f"
  done <<EOF
$(find "$PROJ_DIR/.claude/rules" -type f -name '*.md' 2>/dev/null | sort)
EOF
fi

if [ -d "$PROJ_DIR/.claude/skills" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] && emit skill project on_demand "$f"
  done <<EOF
$(find "$PROJ_DIR/.claude/skills" -maxdepth 2 -type f -name 'SKILL.md' 2>/dev/null | sort)
EOF
fi

if [ -d "$PROJ_DIR/.claude/agents" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] && emit agent project on_demand "$f"
  done <<EOF
$(find "$PROJ_DIR/.claude/agents" -type f -name '*.md' 2>/dev/null | sort)
EOF
fi

# ---------------------------------------------------------------- 파싱 + 출력
OUT_JSON="$OUT_JSON" CFG_DIR="$CFG_DIR" PROJ_DIR="$PROJ_DIR" python3 - "$TMP" <<'PY'
import json, os, sys

TMP = sys.argv[1]
AS_JSON = os.environ.get("OUT_JSON") == "1"
CFG_DIR = os.environ.get("CFG_DIR", "")
PROJ_DIR = os.environ.get("PROJ_DIR", "")


def split_frontmatter(text):
    """--- 로 둘러싸인 선두 블록을 (frontmatter, body) 로 가른다.

    YAML 파서를 쓰지 않는다. 필요한 건 최상위 스칼라와 단순 리스트뿐이고,
    의존성을 늘리지 않는 편이 낫다.
    """
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return "", text
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return "\n".join(lines[1:i]), "\n".join(lines[i + 1:])
    return "", text  # 닫는 --- 가 없으면 frontmatter 로 치지 않는다


def parse_frontmatter(fm):
    """최상위 key: value 와 `- item` 리스트만 읽는다."""
    out, key = {}, None
    for raw in fm.split("\n"):
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        indented = raw[:1] in (" ", "\t")
        stripped = raw.strip()
        if indented and stripped.startswith("- ") and key:
            out.setdefault(key, [])
            if isinstance(out[key], list):
                out[key].append(stripped[2:].strip().strip("\"'"))
            continue
        if ":" in stripped and not indented:
            k, _, v = stripped.partition(":")
            key = k.strip()
            v = v.strip().strip("\"'")
            out[key] = v if v else []
    return out


def as_list(v):
    if isinstance(v, list):
        return [x for x in v if x]
    return [v] if v else []


records, warnings = [], []
seen = set()

with open(TMP, encoding="utf-8", errors="replace") as fh:
    rows = [ln.rstrip("\n") for ln in fh if ln.strip()]

for row in rows:
    parts = row.split("\t")
    if len(parts) != 4:
        continue
    kind, scope, load, path = parts
    real = os.path.realpath(path)
    if real in seen:
        continue
    seen.add(real)

    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError as exc:
        warnings.append(f"읽기 실패: {path} ({exc.strerror})")
        continue

    nbytes = len(text.encode("utf-8"))
    rec = {
        "kind": kind,
        "scope": scope,
        "load": load,
        "path": path,
        "lines": text.count("\n") + (1 if text and not text.endswith("\n") else 0),
        "bytes": nbytes,
        "est_tokens": nbytes // 4,
    }

    fm_raw, body = split_frontmatter(text)
    fm = parse_frontmatter(fm_raw) if fm_raw else {}
    body_lines = body.count("\n") + (1 if body and not body.endswith("\n") else 0)

    if kind == "rules":
        paths = as_list(fm.get("paths"))
        rec["paths"] = paths
        # paths 가 있으면 매칭 파일을 열 때만, 없으면 매 세션 로드된다
        rec["load"] = "conditional" if paths else "always"

    elif kind == "skill":
        rec["name"] = fm.get("name") or ""
        rec["description"] = fm.get("description") or ""
        rec["disable_model_invocation"] = str(fm.get("disable-model-invocation", "")).lower() == "true"
        rec["body_lines"] = body_lines
        rec["has_frontmatter"] = bool(fm_raw)
        d = rec["description"]
        # description 은 매 세션 상주한다 — 그 비용만 따로 센다
        rec["description_est_tokens"] = len(d.encode("utf-8")) // 4 if d else 0
        skill_dir = os.path.dirname(path)
        rec["dir"] = os.path.basename(skill_dir)
        # 스킬이 번들한 참조 파일. 판정 에이전트가 참조 깊이와 목차 요건을
        # 보려면 이 목록이 있어야 한다 (인벤토리에 없으면 존재를 모른다).
        refs = []
        for root, dirs, files in os.walk(skill_dir):
            dirs[:] = [x for x in dirs if not x.startswith(".")]
            if root.replace(skill_dir, "").count(os.sep) > 2:
                dirs[:] = []
                continue
            for fn in sorted(files):
                if fn.startswith("."):   # .DS_Store 등 잡파일
                    continue
                fp = os.path.join(root, fn)
                if fp == path:
                    continue
                try:
                    n = sum(1 for _ in open(fp, encoding="utf-8", errors="replace"))
                except OSError:
                    continue
                refs.append({
                    "path": os.path.relpath(fp, skill_dir),
                    "lines": n,
                    "linked_from_skill_md": os.path.relpath(fp, skill_dir) in body,
                })
        rec["ref_files"] = refs

    elif kind == "agent":
        rec["name"] = fm.get("name") or ""
        rec["description"] = fm.get("description") or ""
        rec["tools"] = fm.get("tools") or ""
        rec["model"] = fm.get("model") or ""
        rec["body_lines"] = body_lines
        rec["has_frontmatter"] = bool(fm_raw)

    elif kind in ("claude_md", "agents_md"):
        # @path 임포트도 시작 시 함께 로드된다. 코드 블록·백틱 안은 임포트가 아니다.
        imports, in_fence = [], False
        for ln in text.split("\n"):
            if ln.lstrip().startswith("```"):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            for tok in ln.split():
                if tok.startswith("@") and len(tok) > 1 and "`" not in ln:
                    imports.append(tok[1:])
        rec["imports"] = imports

    records.append(rec)

always = sum(r["est_tokens"] for r in records
             if r["load"] == "always" and r["kind"] in ("claude_md", "agents_md", "rules"))
listing = sum(r.get("description_est_tokens", 0) for r in records if r["kind"] == "skill")

summary = {
    "count": len(records),
    "by_kind": {k: sum(1 for r in records if r["kind"] == k)
                for k in ("claude_md", "agents_md", "rules", "skill", "agent")},
    "always_loaded_est_tokens": always,
    "skill_listing_est_tokens": listing,
}
payload = {
    "files": records,
    "summary": summary,
    "warnings": warnings,
    "context": {"config_dir": CFG_DIR, "project_dir": PROJ_DIR},
}

if AS_JSON:
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    sys.exit(0 if records else 2)

if not records:
    print("지시부 텍스트 파일을 하나도 찾지 못했다.")
    print(f"  설정 위치: {CFG_DIR}")
    print(f"  프로젝트 : {PROJ_DIR}")
    sys.exit(2)

LOAD_KO = {"always": "상시", "conditional": "조건부", "on_demand": "호출 시", "unknown": "?"}
print(f"지시부 텍스트 {summary['count']}개")
print(f"  설정 위치: {CFG_DIR}")
print(f"  프로젝트 : {PROJ_DIR}\n")
print(f"{'종류':<10} {'스코프':<8} {'로드':<7} {'줄':>5} {'est.토큰':>8}  경로")
print("-" * 92)
for r in sorted(records, key=lambda x: (x["kind"], x["path"])):
    print(f"{r['kind']:<10} {r['scope']:<8} {LOAD_KO.get(r['load'], r['load']):<7} "
          f"{r['lines']:>5} {r['est_tokens']:>8}  {r['path']}")
print()
print(f"상시 로드 합계        est. {summary['always_loaded_est_tokens']} 토큰")
print(f"스킬 description 합계 est. {summary['skill_listing_est_tokens']} 토큰")
for w in warnings:
    print(f"경고: {w}")

sys.exit(0 if records else 2)
PY
