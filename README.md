# ai-skills

builder-journey 공용 AI 스킬 모음. Claude Code와 Codex CLI 양쪽에서 쓴다.

```
.claude-plugin/marketplace.json   Claude Code 마켓플레이스 정의
claude/plugins/<plugin>/          Claude Code 플러그인 (설치 단위)
codex/                            Codex CLI용 지침·프롬프트
```

---

## Claude Code

```bash
/plugin marketplace add builder-journey/ai-skills
/plugin install bj-mac@builder-journey
```

업데이트:

```bash
/plugin marketplace update builder-journey
```

### 플러그인 목록

| 플러그인 | 내용 | 비고 |
|---|---|---|
| `bj-mac` | `rec-meeting` — 미팅 녹음 → 자동 전사 | Apple Silicon Mac 전용 |

---

## Codex CLI

Codex엔 마켓플레이스가 없어서 심볼릭 링크로 연결한다.

```bash
git clone https://github.com/builder-journey/ai-skills.git
cd ai-skills && ./codex/install.sh
```

`git pull` 하면 바로 반영된다.

---

## 스킬 추가하기

### Claude 플러그인에 스킬 추가

1. `claude/plugins/<plugin>/skills/<skill-name>/SKILL.md` 생성
2. frontmatter에 `name`, `description` 필수
3. 스킬 안의 파일 경로는 **`${CLAUDE_SKILL_DIR}`** 로 참조
   (플러그인 설치 경로는 버전마다 달라지므로 절대경로 하드코딩 금지)

### 플러그인 자체를 추가

1. `claude/plugins/<new>/.claude-plugin/plugin.json` 생성
2. 루트 `.claude-plugin/marketplace.json`의 `plugins` 배열에 등록

쪼개는 기준은 **같이 켜고 끌 것끼리**.

---

## 라이선스

MIT
