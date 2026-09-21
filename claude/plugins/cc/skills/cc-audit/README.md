# cc-audit — Claude Code 설정 점검

네 Claude Code 설정(`CLAUDE.md`, `.claude/rules/`, 스킬, 권한, 훅, 샌드박스, auto memory, `settings.json`)을
**공식 문서 기준 안티패턴**과 대조해서 문제를 찾아준다.

판정 기준은 전부 [`reference/antipatterns.md`](reference/antipatterns.md)에 문서화돼 있다.
지적당한 항목의 근거를 직접 확인할 수 있다는 뜻이다.

---

## 설치

```bash
/plugin marketplace add builder-journey/ai-skills
/plugin install bj-cc@builder-journey
```

## 사용

```
설정 점검해줘
```

또는 직접 호출:

```
/bj-cc:cc-audit          # 전역 + 현재 프로젝트
/bj-cc:cc-audit global   # 전역만
/bj-cc:cc-audit project  # 현재 프로젝트만
```

스크립트만 단독으로 돌릴 수도 있다:

```bash
bash audit.sh --scope all
bash audit.sh --json      # 기계 판독용
```

---

## 동작

1. **스캔** — `audit.sh`가 설정 파일을 읽고 rule ID별로 판정 (읽기 전용)
2. **대조** — Claude가 `reference/antipatterns.md`에서 해당 항목의 근거를 읽음
3. **직접 점검** — 스크립트가 못 잡는 것(모순되는 규칙, 자명한 지시, 코드에서 유추 가능한 내용)은 Claude가 파일을 읽고 판단
4. **보고** — 심각도 순으로 정리
5. **수정** — 원하면 건별 승인 받고 수정. 수정 전 백업

> **스캔 단계는 절대 파일을 수정하지 않는다.** 수정은 항상 사용자 승인 후에만.

---

## 점검 항목

| 분류 | ID | 내용 |
|---|---|---|
| CLAUDE.md | `CM01`–`CM11` | 비대, 자동화 지시, 금지 지시, 자명한 지시, 코드 중복, 스코프 오용, 모순, 절차 삽입, 강조 남발, import 과다, 4 MiB 초과 |
| rules | `RU01`–`RU03` | `paths` 누락, 무의미한 분할, 스킬로 가야 할 내용 |
| Skills | `SK01`–`SK04` | description 중복, 부작용 스킬 노출, 절대경로 하드코딩, 본문 과대 |
| 권한 | `PM01`–`PM06` | 전역 deny 오용, deny 우회 가능성, 무효 allow, bypass 상시화, 샌드박스 미사용, 평가 안 되는 규칙 |
| 훅 | `HK01`–`HK05` | 훅으로 가야 할 규칙, 출력 오염, 블로킹, 과잉 설계, exit 0 + stderr |
| MCP/에이전트 | `MC01`, `AG01`–`AG02` | 유휴 서버, 서브에이전트 미사용/남용 |
| 메모리 | `MEM01`–`MEM03` | MEMORY.md 초과, CLAUDE.md 중복, 유추 가능한 내용 |
| settings | `SET01`–`SET04` | 미문서화 키, deprecated 키, 스코프 오용, 적용 안 되는 defaultMode |

### 심각도

| 등급 | 의미 |
|---|---|
| `HIGH` | 실제로 동작을 망가뜨리거나 조용히 실패함. 고쳐야 함 |
| `MED` | 컨텍스트 낭비·신뢰성 저하. 고치면 좋음 |
| `INFO` | 참고. **대부분 그냥 둬도 됨** |

종료 코드: `0` = HIGH 없음 / `1` = HIGH 있음 / `2` = 스캔 실패

---

## 알려진 한계

휴리스틱이라 오탐이 가능한 항목:

| ID | 한계 |
|---|---|
| `SET01` | 알려진 키 목록을 하드코딩해서 비교한다. **CLI가 문서보다 앞서가면 신규 키가 걸린다** → 그래서 INFO, "확인 필요"로만 표시 |
| `SK01` | 어절 단위 중복도. 한국어 description에는 약하다 |
| `HK05` | 훅 커맨드에서 스크립트 경로가 직접 보일 때만 판정. 래퍼로 감싸면 못 본다 |
| `HK02` | 출력 제한 장치 유무만 본다. 원래 짧은 훅도 걸릴 수 있다 |
| `SET03` | 문자열 패턴 매칭이라 오탐 가능 |
| `CM06` | 키워드 기반. 고유명사(레포명 등)는 못 잡는다 |

`skills/synced/` 아래 벤더 동기화 스킬은 사용자가 고칠 수 없으므로 스캔에서 제외한다.

---

## 같이 쓰면 좋은 것

이 스킬은 Claude Code 내장 명령을 대체하지 않는다. 보완재다.

| 확인할 것 | 내장 명령 |
|---|---|
| 뭐가 실제로 로드됐나 | `/context` |
| CLAUDE.md 정리 제안 | `/doctor` |
| 훅 목록 | `/hooks` |
| 권한 규칙 | `/permissions` |
| 메모리 내용 | `/memory` |
| MCP 토큰 비용 | `/context all` |

---

## 기준

- 기준일 **2026-09-21**, Claude Code **v2.1.278**
- 출처: [code.claude.com/docs](https://code.claude.com/docs/en/best-practices) · [platform.claude.com](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices) · [Anthropic 블로그](https://claude.com/blog/steering-claude-code-skills-hooks-rules-subagents-and-more)
- 각 항목의 근거 URL은 `reference/antipatterns.md`에 항목별로 명시돼 있다

Claude Code가 업데이트되면 기준 문서와 `audit.sh`의 키 목록도 갱신이 필요하다.
