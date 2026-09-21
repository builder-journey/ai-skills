---
name: cc-audit
description: Claude Code 설정 점검. CLAUDE.md·.claude/rules·스킬·권한·훅·샌드박스·auto memory·settings.json을 공식 문서 기준 안티패턴과 대조해 문제를 찾고 고칠 방법을 제안한다. "설정 점검해줘", "CLAUDE.md 괜찮은지 봐줘", "권한 설정 문제 있나" 같은 요청에 사용.
disable-model-invocation: false
argument-hint: "[global|project|all] (기본 all)"
---

# Claude Code 설정 점검

사용자의 Claude Code 설정을 **공식 문서 기준 안티패턴**과 대조한다.
판정 기준은 전부 `reference/antipatterns.md`에 문서화돼 있고, 사용자가 직접 확인할 수 있다.

## 원칙

- **읽기 전용으로 시작한다.** 스캔 단계에서 사용자 파일을 절대 수정하지 않는다.
- **수정은 항상 사용자 승인 후.** 발견 → 설명 → 제안 → 승인 → 적용 순서를 건너뛰지 않는다.
- **근거 없는 지적 금지.** 모든 지적에는 rule ID와 기준 문서의 해당 항목을 붙인다.
- 스크립트가 못 잡는 것(모순되는 규칙, 자명한 지시, 코드에서 유추 가능한 내용)은 **파일을 직접 읽고 판단**한다.

---

## 1단계 — 스캔

```bash
bash "${CLAUDE_SKILL_DIR}/audit.sh" --scope all
```

`$ARGUMENTS`로 `global` / `project` / `all` 이 오면 `--scope`에 그대로 넘긴다.

종료 코드:
- **0** — HIGH 없음
- **1** — HIGH 있음
- **2** — 스캔 실패 (설정 파일을 하나도 못 찾음). 이 경우 사용자에게 Claude Code 설정 위치를 확인받는다.

## 2단계 — 기준 문서 대조

스크립트가 뱉은 각 rule ID에 대해 `reference/antipatterns.md`에서 해당 섹션을 읽는다:

```bash
grep -n "^### " "${CLAUDE_SKILL_DIR}/reference/antipatterns.md"
```

필요한 ID 섹션만 `sed -n`으로 읽어라. **문서 전체를 통째로 읽지 마라** — 컨텍스트 낭비다.

## 3단계 — 스크립트가 못 잡는 항목 직접 점검

스캔 결과와 별개로, 발견된 CLAUDE.md / rules 파일을 **직접 읽고** 아래를 판단한다:

| 확인할 것 | 기준 |
|---|---|
| 서로 모순되는 규칙 (CM07) | 두 지시가 충돌하면 Claude가 임의로 하나를 고른다 |
| 자명한 지시 (CM04) | "클린 코드 작성", "테스트 잘 하기" 류 |
| 코드에서 유추 가능 (CM05) | 파일별 설명, 디렉토리 나열, 아키텍처 덤프 |
| 스코프 오용 (CM06/SET03) | 개인 취향이 프로젝트 파일에, 프로젝트 규칙이 전역에 |
| 스킬 description 품질 (SK01) | 모호하거나 다른 스킬과 겹쳐서 오발동할 것 같은가 |

각 줄에 대해 던질 질문은 하나다: **"이 줄을 지우면 Claude가 실수를 하게 되나?"** 아니면 지운다.

## 4단계 — 보고

심각도 순으로 정리해서 보고한다. 형식:

```
## HIGH

**PM01 — 전역 deny에 일상 개발 명령**
`~/.claude/settings.json` → npm, npx, pip, docker, curl, wget
deny 리스트는 병합되고 최상위 우선이라 프로젝트에서 완화할 수 없다.
→ `ask`로 내리고 실제 차단은 sandbox에 맡긴다.

## MED
...

## INFO
...
```

- 전체 나열 말고 **심각도 순으로 위에서부터**. INFO는 한 줄씩.
- 통과한 항목은 개수만 (`통과 18`).
- 마지막에 기준 문서 경로를 안내한다: `${CLAUDE_SKILL_DIR}/reference/antipatterns.md`

## 5단계 — 수정 제안

사용자가 고치길 원하면:

1. **한 번에 하나씩.** 파일 하나 고치고 → 보여주고 → 다음.
2. 수정 전 해당 파일을 백업한다 (`<파일>.bak-<타임스탬프>`).
3. `permissions.deny` 를 건드릴 때는 **반드시 사용자 확인을 받는다.** 잘못 지우면 가드레일이 사라진다.
4. 수정 후 `audit.sh`를 다시 돌려 해결됐는지 확인한다.

### CLAUDE.md 줄이기 (CM01)

무작정 자르지 말고 목적지를 정해서 옮긴다:

| 옮길 내용 | 목적지 |
|---|---|
| "매번 ~해라" 자동화 | 훅 (`.claude/settings.json`의 `hooks`) |
| "절대 ~하지 마라" | `permissions.deny` 또는 PreToolUse 훅 |
| 다단계 절차 | `.claude/skills/<name>/SKILL.md` |
| 특정 경로에만 해당하는 규칙 | `.claude/rules/<topic>.md` + `paths:` 프론트매터 |
| 개인 취향 | `~/.claude/CLAUDE.md` 또는 `~/.claude/rules/` |
| 코드에서 유추 가능 | 삭제 |

참고: 커밋된 CLAUDE.md는 Claude Code 내장 `/doctor`도 정리 제안을 준다. 같이 쓰면 좋다.

---

## 확인 명령

수정 후 실제로 반영됐는지는 사용자가 직접 확인해야 한다. 안내할 것:

| 확인할 것 | 명령 |
|---|---|
| CLAUDE.md·룰이 로드됐나 | `/context` |
| CLAUDE.md가 비대한가 | `/doctor` |
| 훅이 등록됐나 | `/hooks` |
| 권한 규칙 | `/permissions` |
| 메모리 내용 | `/memory` |
| MCP 토큰 비용 | `/context all` |

---

## 하지 말 것

- 사용자 승인 없이 설정 파일 수정
- `permissions.deny` 항목을 임의로 삭제
- 기준 문서에 없는 항목을 지적
- 안티패턴을 전부 고치라고 밀어붙이기 — **INFO는 대부분 그냥 둬도 된다**
- 문서 전체를 컨텍스트에 로드
