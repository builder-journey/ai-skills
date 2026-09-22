> ⚠️ **날짜 박힌 스냅샷이다. 실행 기준이 아니다.**
>
> 2026-09-21, Claude Code v2.1.278 시점의 조사 결과다.
> Claude Code 는 하루 한두 개꼴로 릴리스되므로 이 문서는 시간이 갈수록 낡는다.
>
> `cc-review` 스킬은 **이 문서를 쓰지 않는다.** 실행할 때마다 공식 문서를 직접 읽는다.
> 이 파일은 사람이 배경을 훑기 위한 자료다. 최신 기준이 필요하면 원문을 보라.

# Claude Code 설정 안티패턴 기준 문서

- 문서 기준일: **2026-09-21**
- 기준 버전: **Claude Code v2.1.278**
- 출처 우선순위: 공식문서(code.claude.com / platform.claude.com) > Anthropic 공개 자료(blog, support) > 실사용 사례

---

## 한 줄 요약

**모든 안티패턴의 근본 원인은 두 가지다: 컨텍스트는 유한하고, 지시는 강제력이 없다.**

> "Most best practices are based on one constraint: Claude's context window fills up fast, and performance degrades as it fills."
> — [Best practices](https://code.claude.com/docs/en/best-practices)

> "Claude treats them as context, not enforced configuration. To block an action regardless of what Claude decides, use a PreToolUse hook instead."
> — [Memory](https://code.claude.com/docs/en/memory)

---

## 수단 선택 표

| 수단 | 로드 시점 | 강제력 | 컨텍스트 비용 | 쓸 곳 |
|---|---|---|---|---|
| **CLAUDE.md** | 세션 시작, 전문 로드 | 없음(조언). Claude가 해석 | 매 요청마다 전액. 서브에이전트에도 다시 로드 | 매 세션 필요한 규약·빌드 명령·프로젝트 구조 |
| **.claude/rules/** | `paths` 없으면 세션 시작 / 있으면 매칭 파일 접근 시 | 없음(조언) | paths 있으면 조건부, 없으면 CLAUDE.md와 동일 | 언어별·디렉토리별 가이드라인 |
| **Skill** | 시작 시 description만, 호출 시 본문 전체 | 없음(조언) | 낮음(description만 상시). 본문은 호출 시 | 가끔 필요한 레퍼런스, `/name` 워크플로 |
| **Hook** | 라이프사이클 이벤트 발생 시 | **있음**(결정적, 항상 발동) | 0. 단, 출력을 반환하면 그만큼 | 린트·포맷·차단·로깅·알림 |
| **Permissions** | 툴 호출마다 평가 | **있음**(클라이언트 강제). 단 Bash 패턴은 보안 경계 아님 | 0 | 툴/경로/도메인 허용·차단 |
| **Subagent** | 스폰 시 | 없음 | 메인 세션과 격리(별도 컨텍스트) | 파일을 많이 읽는 탐색, 병렬 작업, 검증 |
| **MCP** | 세션 시작(툴 이름 + 서버 instructions) | 없음 | 낮음. tool search 기본 on이라 유휴 툴은 최소 | 외부 서비스 데이터/액션 |

근거: [Extend Claude Code](https://code.claude.com/docs/en/features-overview) "Context cost by feature" / "Compare similar features" 표, [Memory](https://code.claude.com/docs/en/memory).

핵심 분기 두 개:
- **"매번 반드시"가 필요한가** → Hook 또는 Permissions. CLAUDE.md는 보장하지 않는다.
- **매 세션 필요한가** → 아니면 Skill. CLAUDE.md/rules는 매 요청 비용을 낸다.

---

## CLAUDE.md

### CM01 — 200줄 초과 / 비대한 CLAUDE.md

**증상**: CLAUDE.md(또는 AGENTS.md)가 200줄 초과. `/context`의 Memory files 토큰이 큼.
**왜 문제**: 공식 권장은 "target under 200 lines per CLAUDE.md file. Longer files consume more context and reduce adherence." 실패 패턴으로도 명시됨 — "The over-specified CLAUDE.md. If your CLAUDE.md is too long, Claude ignores half of it because important rules get lost in the noise." 게다가 CLAUDE.md 계층 전체는 서브에이전트 시작 시에도 다시 로드되므로 비용이 곱해진다.
**대신**: 각 줄에 "이걸 지우면 Claude가 실수하나?"를 물어 잘라낸다. 레퍼런스는 Skill로, 도메인 한정 규칙은 `paths` 붙인 rules로. 체크인된 CLAUDE.md는 `/doctor`가 트림 제안을 준다(v2.1.206+).
**출처**: [Memory](https://code.claude.com/docs/en/memory), [Best practices](https://code.claude.com/docs/en/best-practices), [Sub-agents](https://code.claude.com/docs/en/sub-agents)

### CM02 — "매번 X하면 Y해라" 류 자동화 지시

**증상**: "커밋 전에 항상 lint 실행", "파일 수정 후 매번 포맷" 같은 문장이 CLAUDE.md에 있음.
**왜 문제**: "Unlike CLAUDE.md instructions which are advisory, hooks are deterministic and guarantee the action happens." 지시는 컨텍스트가 차면 무시될 수 있다.
**대신**: PostToolUse / Stop / PreCommit 성격의 훅으로 옮긴다. "If the instruction is something that must run at a specific point, such as before every commit or after each file edit, write it as a hook instead."
**출처**: [Best practices](https://code.claude.com/docs/en/best-practices), [Memory](https://code.claude.com/docs/en/memory)

### CM03 — "절대 X하지 마라" 류 금지 지시

**증상**: "never edit `.env`", "migrations 폴더 건드리지 마라" 등이 CLAUDE.md/스킬 본문에만 있음.
**왜 문제**: "An instruction like 'never edit `.env`' in CLAUDE.md or a skill is a request, not a guarantee. A `PreToolUse` hook that blocks the edit is enforcement."
**대신**: `permissions.deny`에 `Read(./.env)` / `Edit(./migrations/**)` 를 넣거나 PreToolUse 훅으로 차단. 참고: `Read` deny는 같은 경로의 Edit/Write도 막지만 NotebookEdit은 안 막으므로 `Edit` deny를 함께 건다.
**출처**: [Extend Claude Code](https://code.claude.com/docs/en/features-overview), [Permissions](https://code.claude.com/docs/en/permissions)

### CM04 — 자명한 지시

**증상**: "클린 코드를 작성하라", "테스트를 잘 하라", "적절히 포맷하라" 같은 줄.
**왜 문제**: 공식 Exclude 목록에 "Self-evident practices like 'write clean code'", "Standard language conventions Claude already knows"가 명시돼 있다. 검증 불가능한 문장은 토큰만 쓴다.
**대신**: 검증 가능한 구체 문장으로. "Use 2-space indentation" instead of "Format code properly", "Run `npm test` before committing" instead of "Test your changes".
**출처**: [Best practices](https://code.claude.com/docs/en/best-practices), [Memory](https://code.claude.com/docs/en/memory)

### CM05 — 코드 읽으면 알 수 있는 내용

**증상**: 디렉토리 트리 나열, 파일별 설명, 의존성 목록, 아키텍처 덤프가 CLAUDE.md에 있음.
**왜 문제**: Exclude 목록 1번이 "Anything Claude can figure out by reading code", "File-by-file descriptions of the codebase". `/doctor` 트림 체크도 "cuts content Claude can derive from the codebase, such as directory layouts, dependency lists, and architecture overviews"를 기준으로 동작한다.
**대신**: 남길 것은 "pitfalls, rationale, and conventions that differ from tool defaults" — 즉 추론 불가능한 것만.
**출처**: [Memory](https://code.claude.com/docs/en/memory), [Best practices](https://code.claude.com/docs/en/best-practices)

### CM06 — 스코프 오용

**증상**: 개인 에디터 취향/개인 워크플로가 팀 공유 `./CLAUDE.md`에. 반대로 프로젝트 빌드 규약이 `~/.claude/CLAUDE.md`에.
**왜 문제**: 프로젝트 CLAUDE.md는 "shared with your team through version control, so focus on project-level standards rather than personal preferences." 스코프 표상 `~/.claude/CLAUDE.md`는 "Personal preferences for all projects", `./CLAUDE.local.md`는 "Personal project-specific preferences; add to `.gitignore`".
**대신**: 개인+전역 → `~/.claude/CLAUDE.md` 또는 `~/.claude/rules/`. 개인+이 프로젝트 → `./CLAUDE.local.md`(gitignore). 팀+이 프로젝트 → `./CLAUDE.md`. 워크트리를 쓰면 `CLAUDE.local.md`는 생성한 워크트리에만 존재하므로 `@~/.claude/...` 임포트를 쓴다.
**출처**: [Memory](https://code.claude.com/docs/en/memory)

### CM07 — 서로 모순되는 규칙

**증상**: 상위/하위 CLAUDE.md, rules, 임포트 파일 간 같은 주제에 다른 지시.
**왜 문제**: "if two rules contradict each other, Claude may pick one arbitrarily." 로드 순서상 CLAUDE.md는 덮어쓰기가 아니라 **전부 concat**되므로 모순이 그대로 공존한다.
**대신**: 주기적으로 CLAUDE.md / nested CLAUDE.md / `.claude/rules/`를 훑어 낡거나 충돌하는 지시를 제거. 모노레포에서 남의 팀 파일이 딸려오면 `claudeMdExcludes`로 제외.
**출처**: [Memory](https://code.claude.com/docs/en/memory)

### CM08 — 다단계 절차를 CLAUDE.md에 박음

**증상**: 릴리스 절차, 배포 체크리스트 등 10~30줄짜리 순서가 CLAUDE.md에 있음.
**왜 문제**: "If an entry is a multi-step procedure or only matters for one part of the codebase, move it to a skill or a path-scoped rule instead." 블로그도 "30-line procedures in CLAUDE.md → move to skills where bodies load only on invocation"을 안티패턴으로 든다.
**대신**: `.claude/skills/<name>/SKILL.md`. `/name`으로 호출하고, 본문은 호출 시에만 로드된다.
**출처**: [Memory](https://code.claude.com/docs/en/memory), [Steering Claude Code (blog)](https://claude.com/blog/steering-claude-code-skills-hooks-rules-subagents-and-more)

### CM09 — IMPORTANT / 대문자 강조 남발

**증상**: 여러 줄이 IMPORTANT, MUST, NEVER, 전부 대문자로 강조돼 있음.
**왜 문제**: "If Claude keeps skipping one instruction, add emphasis such as 'IMPORTANT' to that line alone. If you emphasize many lines, none of them stands out."
**대신**: 강조는 1~2줄만. 강조로 해결하려던 게 "매번 반드시"라면 애초에 훅/퍼미션 대상이다(CM02/CM03).
**출처**: [Best practices](https://code.claude.com/docs/en/best-practices)

### CM10 — @import 과다

**증상**: CLAUDE.md는 짧지만 `@docs/...` 임포트가 여러 개 걸려 실질 로드량이 큼.
**왜 문제**: "Imported files are expanded and loaded into context at launch alongside the CLAUDE.md that references them." / "Splitting into `@path` imports helps organization but doesn't reduce context, since imported files load at launch." 재귀 임포트는 최대 4홉까지 따라간다.
**대신**: 컨텍스트를 줄이려면 임포트가 아니라 (a) `paths` 붙인 rules, (b) Skill로 옮긴다. 조직 목적의 분할만 임포트로.
추가 함정: 프로젝트 메모리에서 작업 디렉토리 밖을 가리키는 임포트는 **외부 임포트**로 승인 다이얼로그가 뜨고, 거절하면 영구 비활성화된다. 경로를 리터럴로 쓰고 싶으면 백틱(`` `@README` ``)으로 감싼다.
**출처**: [Memory](https://code.claude.com/docs/en/memory)

### CM11 — 4 MiB 초과 메모리 파일 (조용한 전체 스킵)

**증상**: 생성 로그·데이터 덤프 등이 섞여 CLAUDE.md가 수 MB.
**왜 문제**: "Claude Code loads a CLAUDE.md file of up to 4 MiB in full and skips a larger file." 일부가 아니라 **파일 전체**가 로드되지 않는다.
**대신**: `/context`의 Memory files에 파일이 보이는지 확인. 안 보이면 로드 안 된 것.
**출처**: [Memory](https://code.claude.com/docs/en/memory)

---

## .claude/rules/

### RU01 — `paths` 프론트매터 없이 도메인 한정 규칙 작성

**증상**: `rules/frontend.md`, `rules/python.md` 등이 프론트매터 없이 존재.
**왜 문제**: "Rules without `paths` frontmatter are loaded at launch with the same priority as `.claude/CLAUDE.md`." 즉 무관한 작업에도 상시 로드돼 CLAUDE.md를 비대하게 만든 것과 같은 효과.
**대신**: 프론트매터에 `paths:` 글롭을 붙인다. 예: `paths: ["src/api/**/*.ts"]`. 브레이스 확장은 규칙당 1,000 패턴/4 MiB 예산을 공유하며, 초과하면 패턴이 확장되지 않은 채 쓰여 아무 파일도 매칭하지 않는다.
**출처**: [Memory](https://code.claude.com/docs/en/memory)

### RU02 — rules를 CLAUDE.md 분할 용도로만 사용

**증상**: CLAUDE.md를 300줄에서 80줄로 줄였는데, 나머지 220줄이 `paths` 없는 rules 파일들로 이동했을 뿐.
**왜 문제**: 총 컨텍스트가 그대로다. 무조건 로드되는 rules는 CLAUDE.md와 동일 우선순위로 launch 시 들어간다. 블로그도 "Unscoped rules with narrow applicability"를 안티패턴으로 든다.
**대신**: 분할 자체가 목적이면 효과 없음을 인정하고, 실제로 줄이려면 `paths` 스코프 또는 Skill 전환. `/context`로 전후 토큰을 비교해 검증한다.
**출처**: [Memory](https://code.claude.com/docs/en/memory), [Steering Claude Code (blog)](https://claude.com/blog/steering-claude-code-skills-hooks-rules-subagents-and-more)

### RU03 — 작업 중에만 필요한 내용을 rules에 둠

**증상**: 배포 절차, 마이그레이션 플레이북, API 레퍼런스가 rules에 있음.
**왜 문제**: 공식 Note — "Rules load into context every session or when matching files are opened. For task-specific instructions that don't need to be in context all the time, use skills instead, which only load when you invoke them or when Claude determines they're relevant to your prompt."
**대신**: Skill로 옮긴다. rules는 "그 파일을 만질 때 항상 적용되는 가이드라인"만.
**출처**: [Memory](https://code.claude.com/docs/en/memory)

---

## Skills

### SK01 — description이 모호하거나 다른 스킬과 겹침

**증상**: `description: Helps with documents` 수준. 또는 두 스킬의 description이 같은 트리거 단어를 공유.
**왜 문제**: "Claude matches your task against skill descriptions to decide which are relevant. If descriptions are vague or overlap, Claude may load the wrong skill or miss one that would help." description은 시스템 프롬프트에 주입되므로 1인칭/2인칭도 발동 문제를 일으킨다.
**대신**: 3인칭으로, **무엇을 하는지 + 언제 쓰는지**를 모두 쓰고 트리거 키워드를 명시한다. 예: `Extract text and tables from PDF files, fill forms, merge documents. Use when working with PDF files or when the user mentions PDFs, forms, or document extraction.` 핵심 유스케이스를 앞에 둔다(description + when_to_use 합계가 스킬 목록에서 1,536자로 잘림). `name`은 64자 이하 소문자/숫자/하이픈, `description`은 1,024자 이하.
**출처**: [Skills](https://code.claude.com/docs/en/skills), [Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)

### SK02 — 부작용 있는 워크플로에 `disable-model-invocation: true` 미설정

**증상**: `deploy`, `commit`, `send-slack-message` 류 스킬에 해당 프론트매터가 없음.
**왜 문제**: 기본값에서는 description이 상시 로드되고 Claude가 스스로 발동할 수 있다. "Use this for workflows with side effects or that you want to control timing, like `/commit`, `/deploy`, or `/send-slack-message`. You don't want Claude deciding to deploy because your code looks ready."
**대신**: `disable-model-invocation: true`. 컨텍스트 비용도 0이 된다("User-only skills have zero cost until invoked"). 남이 만든 스킬은 파일을 고치지 않고 settings의 `skillOverrides`로 같은 효과를 낼 수 있다. 반대로 사용자가 호출할 일이 없는 배경지식 스킬은 `user-invocable: false`.
**출처**: [Skills](https://code.claude.com/docs/en/skills), [Extend Claude Code](https://code.claude.com/docs/en/features-overview)

### SK03 — 스킬 내부 파일 경로를 절대경로로 하드코딩

**증상**: SKILL.md 본문이나 `allowed-tools`에 `/Users/me/.claude/skills/foo/scripts/run.sh` 같은 경로.
**왜 문제**: 스킬은 사용자·프로젝트·플러그인 스코프 어디에도 설치될 수 있고, 플러그인은 설치 경로가 머신마다 다르다. 공식적으로 치환 변수를 제공한다.
**대신**: `${CLAUDE_SKILL_DIR}`(SKILL.md가 있는 디렉토리), 플러그인이면 `${CLAUDE_PLUGIN_ROOT}` / `${CLAUDE_PLUGIN_DATA}`. 프로젝트 루트는 `${CLAUDE_PROJECT_DIR}`. 예: `allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/render.sh *)`. 번들 문서는 `reference/guide.md` 같은 **상대경로 + 슬래시**로 참조한다(백슬래시 금지).
**출처**: [Skills](https://code.claude.com/docs/en/skills), [Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)

### SK04 — SKILL.md 본문이 과도하게 큼

**증상**: SKILL.md가 500줄 초과. 또는 API 레퍼런스 전문이 본문에 인라인.
**왜 문제**: "Keep `SKILL.md` under 500 lines. Move detailed reference material to separate files." 그리고 "the rendered `SKILL.md` content enters the conversation as a single message and stays there across later turns" — 한 번 들어오면 남은 세션 내내 자리를 차지한다.
**대신**: progressive disclosure. SKILL.md는 목차 겸 네비게이션으로 두고 상세는 `reference/*.md`로 분리(파일은 읽기 전까지 토큰 0). 단 **참조는 SKILL.md에서 1단계 깊이까지만** — 중첩 참조는 Claude가 부분 읽기로 끝낼 수 있다. 100줄 넘는 레퍼런스 파일에는 목차를 붙인다.
**출처**: [Skills](https://code.claude.com/docs/en/skills), [Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)

---

## Permissions / 안전

### PM01 — 전역 deny에 일상 개발 명령

**증상**: `~/.claude/settings.json`의 `permissions.deny`에 `Bash(npm *)`, `Bash(docker *)`, `Bash(curl *)` 등.
**왜 문제**: deny는 리스트가 스코프 간 **병합**되고, 평가 순서가 deny → ask → allow라 최상위 우선이다. "If a tool is denied at any level, no other level can allow it." / "a user-level deny blocks a project-level allow". 즉 특정 프로젝트에서만 완화할 방법이 없다. 또 `Bash(aws *)` 같은 광범위 deny는 `Bash(aws s3 ls)` 같은 좁은 allow까지 전부 막는다("An allow rule can't carve an exception out of a deny rule").
**대신**: 전역 deny는 진짜 절대 금지(자격증명 파일 읽기 등)만. 일상 명령 제어는 `ask` 규칙 또는 프로젝트 스코프에서. 네트워크 제한이 목적이면 샌드박스 네트워크 허용목록을 쓴다.
**출처**: [Permissions](https://code.claude.com/docs/en/permissions), [Settings](https://code.claude.com/docs/en/settings)

### PM02 — deny 패턴을 진짜 가드레일로 오해

**증상**: `Bash(rm -rf *)`, `Bash(curl http://github.com/ *)` 같은 문자열 패턴을 보안 경계로 신뢰.
**왜 문제**: "A Bash rule matches the command text Claude writes... It doesn't match the same program invoked in a different form, so a deny or ask rule covers the invocation Claude usually produces and **isn't a security boundary around the program**." 공식 표의 예: `Bash(rm *)`는 `rm -rf build/`는 막지만 `/bin/rm -rf build/`, `bash -c 'rm -rf build/'`는 못 막는다. `Bash(git push *)`는 `git -C . push origin main`을 못 막는다. 인자 제약 패턴은 "fragile"이라고 명시됨(옵션 순서, 프로토콜, 리다이렉트, 변수).
**대신**: 명령 텍스트에 의존하지 않는 강제가 필요하면 **샌드박스**(파일시스템/네트워크, OS 강제) 또는 전체 명령 텍스트를 직접 검사하는 **PreToolUse 훅**. deny 패턴은 "보통의 오작동 방지" 수준으로만 취급.
**출처**: [Permissions](https://code.claude.com/docs/en/permissions)

### PM03 — auto 모드를 쓰면서 거대한 allow 리스트를 병행 유지

**증상**: auto 모드가 기본인데 `permissions.allow`에 `Bash(*)`, `Bash(python*)`, `Bash(npm run *)`, `Agent`, `Monitor` 같은 광범위 항목이 쌓여 있음.
**왜 문제**: auto 모드 진입 시 임의 코드 실행을 허용하는 광범위 allow는 **자동으로 드롭된다** — "On entering auto mode, broad allow rules that grant arbitrary code execution are dropped: Blanket `Bash(*)` or `PowerShell(*)`, Wildcarded interpreters like `Bash(python*)`, Package-manager run commands, `Agent` allow rules, `Monitor` allow rules." 즉 유지 비용만 내고 효과는 없으며, auto를 끄는 순간 되살아나 실제 위험이 된다. 보호 경로 쓰기와 크리티컬 경로 `rm`은 allow가 매칭돼도 분류기/프롬프트로 간다.
**대신**: allow는 `Bash(npm test)` 같은 좁은 규칙만 남긴다("Narrow rules like `Bash(npm test)` stay in effect"). 광범위 항목은 삭제하거나 샌드박스로 대체.
**출처**: [Permission modes](https://code.claude.com/docs/en/permission-modes)

### PM04 — bypassPermissions 상시화 / `skipDangerousModePermissionPrompt` 무심코 켜기

**증상**: `permissions.defaultMode: "bypassPermissions"`가 사용자 설정에 박혀 있거나, `--dangerously-skip-permissions`가 셸 alias. `skipDangerousModePermissionPrompt: true`.
**왜 문제**: "In `bypassPermissions` mode, Claude Code skips permission prompts, including for writes to protected paths such as `.git` and `.claude`... **Only use this mode in isolated environments like containers or VMs where Claude Code can't cause damage.**" `skipDangerousModePermissionPrompt`는 "Skip the confirmation dialog before bypassPermissions mode" — 마지막 사람 확인 절차를 없앤다. 그리고 이 모드에서는 allow 규칙 자체가 무의미해진다("Allow rules have no effect in `bypassPermissions`").
**대신**: 무인 실행은 컨테이너/VM/샌드박스 런타임 안에서만, non-root로. 로컬에서 프롬프트를 줄이는 게 목적이면 auto 모드 + 샌드박스, 또는 좁은 allow 리스트. 조직 차원 차단은 `permissions.disableBypassPermissionsMode`(관리 설정).
**출처**: [Permission modes](https://code.claude.com/docs/en/permission-modes), [Permissions](https://code.claude.com/docs/en/permissions), [Settings reference](https://code.claude.com/docs/en/settings-reference)

### PM05 — 샌드박스 미사용 상태로 deny 리스트에만 의존

**증상**: `sandbox.enabled` 미설정. 비밀 파일 보호를 `Read(./.env)` deny 하나로만 처리.
**왜 문제**: Read/Edit deny는 Claude의 파일 툴과 Claude Code가 인식하는 Bash 파일 명령(`cat`, `head`, `sed`, `tee`)·리다이렉션까지만 적용된다. "They don't apply to a command that reads files without naming them, such as `grep -r pattern .`... or to arbitrary subprocesses that read or write files indirectly, like a Python or Node script that opens files itself. **For OS-level enforcement that blocks all processes from accessing a path, enable the sandbox.**" 샌드박스는 "the operating system enforces that boundary for every Bash, PowerShell, or Monitor command and its child processes."
**대신**: `/sandbox` 또는 `sandbox.enabled: true`(macOS/Linux/WSL2). 네트워크 제한은 샌드박스 네트워크 허용목록으로. deny 리스트는 그 위의 편의 계층으로만 취급.
**출처**: [Permissions](https://code.claude.com/docs/en/permissions), [Sandboxing](https://code.claude.com/docs/en/sandboxing)

### PM06 — 평가되지 않는 툴에 경로 규칙을 씀

**증상**: `Write(src/**)`, `Glob(docs/**)`, `NotebookEdit(...)`, `MultiEdit(...)` 형태의 경로 규칙.
**왜 문제**: "Claude Code checks file permissions against `Edit(path)` and `Read(path)` rules only. If you write a path rule for `Write`, `NotebookEdit`, `Glob`, or the legacy `MultiEdit` tool instead, Claude Code accepts the rule but never consults it, and warns at startup." 즉 막고 있다고 믿지만 아무 효과가 없다.
**대신**: `Write(docs/**)` → `Edit(docs/**)`, `Glob(docs/**)` → `Read(docs/**)`. 시작 시 경고와 `claude doctor` 출력으로 확인.
**출처**: [Permissions](https://code.claude.com/docs/en/permissions)

---

## Hooks

### HK01 — 결정적이어야 하는 규칙을 훅이 아니라 프롬프트/CLAUDE.md에 둠

**증상**: "반드시", "항상", "예외 없이"가 붙은 규칙이 CLAUDE.md나 스킬 본문에만 존재.
**왜 문제**: 결정성 비교가 공식 표에 있다 — Hook: "Always fires on its event; the trigger is guaranteed" vs Skill: "Claude interprets the instructions; outcome can vary." 그리고 "Put guardrails in hooks... If a rule must hold every time, make it a hook rather than a prompt instruction."
**대신**: PreToolUse(차단) / PostToolUse(린트·포맷) / Stop(완료 게이트)로 옮긴다. Stop 훅은 검사 통과 전까지 턴 종료를 막지만, 연속 8회 블록되면 Claude Code가 훅을 무시하고 턴을 끝낸다는 점은 알고 설계한다.
**출처**: [Extend Claude Code](https://code.claude.com/docs/en/features-overview), [Best practices](https://code.claude.com/docs/en/best-practices)

### HK02 — 훅이 장황한 출력을 반환해 컨텍스트 오염

**증상**: PostToolUse 린트 훅이 전체 로그를 stdout으로 뱉음. UserPromptSubmit/SessionStart 훅이 긴 상태 덤프를 출력.
**왜 문제**: 훅의 컨텍스트 비용은 "Zero, unless hook returns output that gets added as messages to your conversation." 그런데 `UserPromptSubmit`, `UserPromptExpansion`, `SessionStart`, `PostModelSwitch`는 **plain-text stdout을 그대로 컨텍스트에 추가**한다. 매 프롬프트마다 수천 토큰이 쌓일 수 있다.
**대신**: 이벤트별 출력 규약을 지킨다. 조용히 지나가야 하면 exit 0 + 출력 없음(exit 0의 stderr는 디버그 로그로만 가고 Claude는 못 본다). Claude에게 보여야 하는 것만 `hookSpecificOutput.additionalContext`로 최소 분량 전달. 차단은 exit 2 + stderr에 짧은 사유.
**출처**: [Extend Claude Code](https://code.claude.com/docs/en/features-overview), [Hooks](https://code.claude.com/docs/en/hooks)

### HK03 — 느리거나 블로킹되는 훅을 매 이벤트에 검

**증상**: 매처 없는 `PreToolUse`/`PostToolUse` 훅이 전체 테스트나 무거운 스크립트를 실행. `MessageDisplay`/`FileChanged`에 무거운 훅.
**왜 문제**: PreToolUse/PostToolUse는 에이전틱 루프의 **모든 툴 호출마다** 발동하고, 매칭 훅은 전부 병렬 실행되며 기본적으로 턴을 블로킹한다. 기본 타임아웃은 command/http/mcp_tool 600초(단 `UserPromptSubmit`·`PreModelSwitch`·`PostModelSwitch`는 30초, `MessageDisplay`는 10초), prompt 30초, agent 60초. 타임아웃된 훅은 출력이 버려져 대부분의 이벤트에서 아무 결정도 내리지 못한다. `SessionEnd` 훅들은 1.5초 예산을 공유한다.
**대신**: 좁은 matcher와 `if` 조건으로 발동을 줄이고, 비차단 작업은 `async: true`, 적절한 `timeout`을 명시한다.
**출처**: [Hooks](https://code.claude.com/docs/en/hooks)

### HK04 — 훅으로 충분한 것을 서브에이전트/모델 호출로 처리

**증상**: 단순 문자열/경로 검사를 `type: "prompt"` 또는 `type: "agent"` 훅으로 구현. 포맷팅을 서브에이전트에 시킴.
**왜 문제**: "Use a hook when the action must happen the same way every time and doesn't need Claude to think." 반대로 prompt 훅(기본 30초)과 agent 훅(기본 60초, **experimental**, "Agent hooks are experimental and may change")은 레이턴시·비용·비결정성을 더한다.
**대신**: 판단이 필요 없으면 `type: "command"` 스크립트. 모델 판단이 정말 필요한 경우(예: 자연어 커밋 메시지 검열)만 prompt/agent 훅.
**출처**: [Extend Claude Code](https://code.claude.com/docs/en/features-overview), [Hooks](https://code.claude.com/docs/en/hooks)

### HK05 — exit 0 + stderr로 Claude에게 피드백하려 함

**증상**: 훅이 경고를 stderr에 찍고 exit 0으로 끝내면서 Claude가 고쳐주길 기대.
**왜 문제**: "Stderr from a hook that exits 0 goes to the debug log only, never the transcript, and **Claude never sees it**."
**대신**: 차단이 목적이면 exit 2(+ stderr에 사유). 차단 없이 정보만 주려면 JSON `hookSpecificOutput.additionalContext`.
**출처**: [Hooks](https://code.claude.com/docs/en/hooks)

---

## MCP / 서브에이전트

### MC01 — 안 쓰는 MCP 서버 상시 연결

**증상**: `/mcp`에 이번 달 한 번도 안 쓴 서버가 여러 개 connected.
**왜 문제**: 시작 시 로드되는 것은 "Tool names and server instructions from connected servers"다. 서버 instructions는 길이가 제한되지 않으므로 서버가 많을수록 상시 비용이 붙고, 시작 시 연결·인증 지연도 생긴다. 단 **툴 스키마 자체는 지연 로드**된다 — "Tool search is on by default, so idle MCP tools consume minimal context." (과대평가 주의: 안 쓰는 MCP의 비용은 흔히 알려진 것보다 작다.)
**대신**: `/context all`로 로드된 MCP 툴의 실제 토큰을 확인한 뒤 판단한다. 안 쓰는 서버는 `/mcp` 패널에서 토글 off — "Toggle a server off in the `/mcp` panel to stop Claude Code from connecting to it without losing its configuration." 프로젝트 `.mcp.json` 서버는 `enabledMcpjsonServers` / `disabledMcpjsonServers`로 제어. MCP 툴 출력이 10,000 토큰을 넘으면 경고가 뜨고 기본 25,000 토큰에서 잘린다.
**출처**: [Extend Claude Code](https://code.claude.com/docs/en/features-overview), [MCP](https://code.claude.com/docs/en/mcp), [Settings reference](https://code.claude.com/docs/en/settings-reference)

### AG01 — 서브에이전트를 안 써서 탐색이 메인 컨텍스트를 다 먹음

**증상**: 한 세션에서 "조사해줘"로 수십~수백 파일을 메인 대화에서 직접 읽음. 이후 지시 누락·품질 저하.
**왜 문제**: 공식 실패 패턴 — "**The infinite exploration.** You ask Claude to 'investigate' something without scoping it. Claude reads hundreds of files, filling the context." 그리고 "Since context is your fundamental constraint, use subagents to keep research out of it."
**대신**: 탐색 범위를 좁히거나 `"use subagents to investigate X"`로 위임한다. 서브에이전트는 별도 컨텍스트에서 읽고 요약만 돌려준다. 구현 후 검증도 fresh 컨텍스트 서브에이전트(`/code-review` 등)에 맡긴다.
**출처**: [Best practices](https://code.claude.com/docs/en/best-practices)

### AG02 — 단순 작업에 서브에이전트 남발

**증상**: 한 줄 수정, 이미 대화에 있는 내용에 대한 질문까지 서브에이전트로 보냄.
**왜 문제**: 공식 가이드는 메인 대화를 쓰라고 명시한다 — "Use the main conversation when: the task needs frequent back-and-forth or iterative refinement; multiple phases share significant context; you're making a quick, targeted change; **latency matters. A subagent that isn't a fork starts fresh and may need time to gather context.**" 게다가 서브에이전트는 시작 시 CLAUDE.md 계층 전체·git status·preload 스킬을 다시 로드한다.
**대신**: 이미 대화에 있는 내용에 대한 질문은 `/btw`(풀 컨텍스트를 보되 히스토리에 안 쌓임). 메인 컨텍스트에서 돌아도 되는 재사용 프롬프트/워크플로는 Skill.
**출처**: [Sub-agents](https://code.claude.com/docs/en/sub-agents)

---

## Auto memory

### MEM01 — MEMORY.md가 200줄 / 25KB 초과

**증상**: `~/.claude/projects/<project>/memory/MEMORY.md`가 200줄 또는 25KB 초과.
**왜 문제**: "The first 200 lines of `MEMORY.md`, or the first 25KB, whichever comes first, are loaded at the start of every conversation. **Content beyond that threshold is not loaded at session start.**" 쓰기는 성공하므로 유실이 조용히 일어난다(한계 초과 시 인덱스를 다시 쓰라는 에러는 반환된다).
**대신**: MEMORY.md는 **인덱스**로 유지한다 — 항목당 한 줄, 상세는 토픽 파일로 이동, 낡은 항목은 병합·삭제. 이 제한은 MEMORY.md에만 적용된다.
**출처**: [Memory](https://code.claude.com/docs/en/memory)

### MEM02 — CLAUDE.md와 auto memory 내용 중복

**증상**: 같은 규칙("always use pnpm")이 CLAUDE.md와 메모리 토픽 파일 양쪽에 있음.
**왜 문제**: 둘 다 매 세션 로드되므로 토큰을 이중 지불한다. 설계상으로도 중복은 배제 대상이다 — "It also skips anything your CLAUDE.md files already say."
**대신**: `/memory`로 메모리 폴더를 훑어 CLAUDE.md와 겹치는 항목을 지운다. 역할 분담: CLAUDE.md = 네가 쓰는 규칙, auto memory = Claude가 축적하는 선호·교정·코드에서 못 얻는 프로젝트 맥락.
**출처**: [Memory](https://code.claude.com/docs/en/memory)

### MEM03 — 코드베이스에서 유추 가능한 것을 메모리에 저장

**증상**: 메모리 파일에 아키텍처 설명, 파일 경로 목록, 과거 디버깅 수정 내역이 쌓임.
**왜 문제**: "Claude skips anything it can derive from the codebase, such as architecture, file paths, or debugging fixes." 이런 항목이 있다면 규약 위반이자 순수 낭비다.
**대신**: 메모리에 남길 네 가지 타입만 유지 — `user`(역할·전문성·작업 선호), `feedback`(교정과 승인된 접근), `project`(코드나 git 히스토리에서 유추 불가한 진행 상황·결정), `reference`(이슈 트래커·대시보드 등 외부 위치).
**출처**: [Memory](https://code.claude.com/docs/en/memory)

---

## settings.json

### SET01 — 존재하지 않는 키 / 오타

**증상**: 설정을 바꿨는데 동작이 안 변함. `claude doctor`에 rejected 항목이 있음.
**왜 문제**: 항목 단위 실패는 그 값만 버려지고 나머지 파일은 유효하게 유지된다 — "**Settings Warning**: only individual entries fail, such as a malformed permission rule or an unknown hook event name. Claude Code skips those values and keeps the rest of the file in effect." 그리고 `-p` 실행에서는 다이얼로그가 아예 뜨지 않는다 — "A `-p` run shows no dialog... after a `-p` run that ignores a setting, run `claude doctor` to see what it dropped." 즉 자동화에서는 완전히 조용히 유실된다.
**대신**: 설정 파일에 `"$schema": "https://json.schemastore.org/claude-code-settings.json"`을 넣어 에디터 검증을 받는다(스키마는 최신 CLI보다 뒤처질 수 있으므로 최근 추가 키의 경고는 오탐일 수 있음). 변경 후 `/status`로 로드된 파일을, `claude doctor`로 거부된 항목을 확인한다.
**출처**: [Settings](https://code.claude.com/docs/en/settings)

### SET02 — deprecated 키 사용

**증상**: 아래 키가 설정에 남아 있음.

| 키 | 상태 | 대체 |
|---|---|---|
| `includeCoAuthoredBy` | Deprecated | `attribution` — 커밋/PR 귀속 표기를 숨기거나 변경 |
| `disableArtifact` | Deprecated | `enableArtifact` — `false`로 Artifact 툴 끄기 |
| `keybindingFlavor` | Deprecated, **효과 없음** | 없음. 단어 편집 단축키는 항상 readline 규약을 따름 |
| `permissionExplainerEnabled` | **제거됨 (v2.1.257)** | 없음. 셸 권한 프롬프트의 `Ctrl+E` 설명과 함께 삭제 |

**왜 문제**: deprecated/removed 키는 의도한 효과를 내지 않으며, `keybindingFlavor`처럼 명시적으로 "has no effect"인 것도 있다.
**대신**: 위 표대로 교체하거나 삭제. 감사 시점에 반드시 [Settings reference](https://code.claude.com/docs/en/settings-reference)에서 현재 목록을 재확인할 것(버전마다 바뀜).
**출처**: [Settings reference](https://code.claude.com/docs/en/settings-reference)

### SET03 — 설정 스코프 오용

**증상**: 팀 공유해야 할 훅/퍼미션이 `.claude/settings.local.json`에만. 반대로 개인 API 키·개인 도구 경로가 커밋되는 `.claude/settings.json`에.
**왜 문제**: 각 레이어의 대상이 문서에 정의돼 있다 — managed = "Your organization", `--settings` = "You, this session", `.claude/settings.local.json` = "You, this project", `.claude/settings.json` = "Everyone in the project", `~/.claude/settings.json` = "You, every project". 위 레이어가 같은 키를 덮어쓰며, 리스트형 키는 병합된다.
**대신**: 공유 대상에 맞춰 레이어를 고른다. 추가 함정 — `.claude/settings.json`의 `permissions.allow`와 `additionalDirectories`는 **워크스페이스 신뢰 다이얼로그를 수락한 뒤에만** 적용된다(deny/ask는 제한만 하므로 영향 없음).
**출처**: [Settings](https://code.claude.com/docs/en/settings), [Permissions](https://code.claude.com/docs/en/permissions)

### SET04 — 프로젝트/로컬 설정에서 `defaultMode: auto` 또는 `bypassPermissions`

**증상**: `.claude/settings.json` 또는 `.claude/settings.local.json`에 `permissions.defaultMode: "auto"` / `"bypassPermissions"`.
**왜 문제**: "`permissions.defaultMode` values `auto` and `bypassPermissions` don't take effect from project or local settings; set them in user or managed settings instead, or pass `--permission-mode` for one session." (v2.1.257 이전에는 `bypassPermissions`가 아무 파일에서나 적용됐다.) 또한 클라우드 세션은 설정 파일의 `bypassPermissions`/`dontAsk`를 **조용히 무시**한다.
**대신**: 사용자 또는 관리 설정에 두거나 세션 단위로 `--permission-mode`. 리포지토리 체크인으로 모드를 강제하려는 시도는 애초에 동작하지 않는다.
**출처**: [Settings](https://code.claude.com/docs/en/settings), [Permission modes](https://code.claude.com/docs/en/permission-modes)

---

## 감사 체크 순서 (요약)

1. `/context` — CLAUDE.md·rules·skills·MCP가 실제로 몇 토큰을 먹는지 먼저 측정.
2. `/status` — 어떤 설정 파일이 로드됐는지.
3. `claude doctor` — 거부된 설정 항목, 잘못된 퍼미션 규칙, 툴 이름 오타 경고.
4. `/doctor` — 체크인된 CLAUDE.md 트림 제안(v2.1.206+).
5. `/memory` — auto memory 내용과 CLAUDE.md 중복 확인, MEMORY.md 길이 확인.
6. `/mcp` — 연결된 서버와 툴 개수.
7. `/hooks` — 등록된 훅과 매처 범위.

---

## 참고 문서

- [How Claude remembers your project (Memory)](https://code.claude.com/docs/en/memory)
- [Best practices for Claude Code](https://code.claude.com/docs/en/best-practices)
- [Extend Claude Code (features overview)](https://code.claude.com/docs/en/features-overview)
- [Settings files and precedence](https://code.claude.com/docs/en/settings)
- [Settings reference](https://code.claude.com/docs/en/settings-reference)
- [Configure permissions](https://code.claude.com/docs/en/permissions)
- [Choose a permission mode](https://code.claude.com/docs/en/permission-modes)
- [Configure the sandboxed Bash tool](https://code.claude.com/docs/en/sandboxing)
- [Skills (Claude Code)](https://code.claude.com/docs/en/skills)
- [Skill authoring best practices (platform)](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
- [Hooks reference](https://code.claude.com/docs/en/hooks)
- [Subagents](https://code.claude.com/docs/en/sub-agents)
- [MCP](https://code.claude.com/docs/en/mcp)
- [Steering Claude Code: when to use CLAUDE.md, skills, hooks, and subagents (blog)](https://claude.com/blog/steering-claude-code-skills-hooks-rules-subagents-and-more)
- [Claude Code power user tips (support)](https://support.claude.com/en/articles/14554000-claude-code-power-user-tips)
