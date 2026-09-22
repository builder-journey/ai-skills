# 판정 기준 출처

이 스킬은 **판정 기준을 저장하지 않는다.** 실행할 때마다 아래 공식 문서를 읽어
그것을 기준으로 삼는다. Claude Code 는 하루 한두 개꼴로 릴리스되므로,
어떤 기준 스냅샷도 몇 주면 낡는다.

이 파일이 담는 것은 **어디서 읽을지와 무엇을 뽑을지**뿐이다.

## 목차

- [사용법](#사용법)
- [문서 목록](#문서-목록)
- [URL 이 죽었을 때](#url-이-죽었을-때)
- [비용 조절](#비용-조절)

## 사용법

각 행을 `WebFetch(url, prompt)` 로 호출한다.

### 필요한 것만 읽어라

인벤토리의 `summary.by_kind` 를 보고 **대상이 0개인 종류의 문서는 건너뛴다.**

| 조회 조건 | 문서 |
|---|---|
| 항상 | 1 memory · 2 best-practices · 3 features-overview |
| `by_kind.skill > 0` | 4 agent-skills/best-practices · 5 skills |
| `by_kind.agent > 0` | 6 sub-agents |

### 출력 상한을 반드시 붙여라

각 프롬프트 끝에 아래 문장을 **그대로** 덧붙인다:

> 전체 40줄 이내로 답하라. 항목마다 인용은 1개, 최대 2줄까지만.
> 페이지를 그대로 옮기지 마라 — 판정에 쓸 규칙만 남겨라.

이 상한이 없으면 요약 모델이 페이지를 통째로 돌려준다 (실측: 한 페이지 50KB).
"원문을 인용하라"와 "압축하라"가 서로 싸우기 때문이다. **상한이 그 싸움을 끝낸다.**

## 문서 목록

### 1. CLAUDE.md · rules · auto memory

- **URL**: `https://code.claude.com/docs/en/memory`
- **프롬프트**:
  > CLAUDE.md 와 .claude/rules/ 에 대해 이 페이지가 **명시한 규칙**만 뽑아라.
  > 권장 크기 한도(숫자 그대로), 파일 위치와 스코프별 용도, 로드 순서,
  > `@import` 규칙과 그 비용, `paths` frontmatter 의 동작,
  > CLAUDE.md 에 넣어야 할 것과 넣지 말아야 할 것, 지시가 안 먹힐 때의 원인.
  > 각 항목에 원문을 짧게 인용해 붙여라. 페이지에 없는 내용은 만들지 마라.

### 2. CLAUDE.md 작성법 · 실패 패턴

- **URL**: `https://code.claude.com/docs/en/best-practices`
- **프롬프트**:
  > CLAUDE.md 작성에 대한 포함/제외 기준표와, "흔한 실패 패턴" 항목을 그대로 뽑아라.
  > 특히 과도한 CLAUDE.md 가 일으키는 문제와 그 처방, 강조 표현 사용 지침.
  > 원문 인용을 붙여라.

### 3. 수단 선택 — CLAUDE.md vs rules vs 스킬 vs 훅

- **URL**: `https://code.claude.com/docs/en/features-overview`
- **프롬프트**:
  > 어떤 내용을 CLAUDE.md / .claude/rules/ / 스킬 / 훅 / 권한 중 어디에 두어야 하는지,
  > 이 페이지가 제시하는 분기 기준과 안티패턴을 뽑아라.
  > 각 수단의 로드 시점과 컨텍스트 비용, 그리고 "이건 훅으로 가야 한다"는 판단 기준.
  > 원문 인용을 붙여라.

### 4. 스킬 작성 규칙

- **URL**: `https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices`
- **프롬프트**:
  > 스킬 작성 규칙을 뽑아라. SKILL.md 본문 길이 한도(숫자 그대로),
  > description 작성 요건(인칭·구체성·트리거 명시), 이름 규칙,
  > 참조 파일의 깊이 제한, 긴 참조 파일의 목차 요건,
  > 점진적 공개(progressive disclosure) 패턴, 그리고 "피해야 할 안티패턴" 목록.
  > 원문 인용을 붙여라.

### 5. Claude Code 스킬 규격

- **URL**: `https://code.claude.com/docs/en/skills`
- **프롬프트**:
  > SKILL.md frontmatter 에서 지원되는 필드 전부와 각각의 효과를 뽑아라.
  > 특히 `disable-model-invocation`, `context`, `allowed-tools`, `model`,
  > `argument-hint` 의 용도와, 스킬이 언제 자동 발동하는지의 규칙.
  > 원문 인용을 붙여라.

### 6. 서브에이전트 정의

- **URL**: `https://code.claude.com/docs/en/sub-agents`
- **프롬프트**:
  > 서브에이전트 정의 파일의 frontmatter 필드 전부와 효과, 스코프 우선순위,
  > 서브에이전트 시작 시 무엇이 로드되고 무엇이 로드되지 않는지를 뽑아라.
  > 원문 인용을 붙여라.

## URL 이 죽었을 때

404 가 나면 **추측해서 다른 URL 을 시도하지 마라.** 문서 인덱스를 읽어 찾는다:

```
https://code.claude.com/docs/llms.txt
```

여기서 해당 주제의 현재 경로를 찾아 다시 시도한다.
그래도 못 찾으면 그 항목은 **기준 없음**으로 두고, 보고서에 그렇게 밝힌다.
기준을 확보하지 못한 영역은 판정하지 않는다.

문서 도메인이 통째로 바뀐 이력이 있다 (`docs.claude.com` → `code.claude.com`, 301).
같은 일이 또 생기면 이 파일의 URL 을 갱신해야 한다.

## 비용 조절

문서 6개를 읽는 비용이 과하면 아래 우선순위로 줄인다.
판정 대상에 없는 종류의 문서는 처음부터 읽지 않는다.

| 우선순위 | 문서 | 없으면 판정 불가한 것 |
|---|---|---|
| 1 | memory | CLAUDE.md · rules 전반 |
| 2 | features-overview | 수단 선택(어디에 둘 것인가) |
| 3 | best-practices | CLAUDE.md 내용 기준 |
| 4 | agent-skills/best-practices | 스킬 품질 |
| 5 | skills | 스킬 frontmatter |
| 6 | sub-agents | 에이전트 정의 |
