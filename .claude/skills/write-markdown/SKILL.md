---
name: pymdown
description: Restructures Markdown content for readability using PyMdown Extensions — admonitions, tabs, collapsibles, def_list, tasklist, and superfences.
---

# PyMdown Markdown Restructure Skill

Transform plain or poorly structured Markdown into richly formatted MkDocs-ready docs
using PyMdown Extensions. The goal is **maximum readability** with the right component
for each type of content — not decoration for its own sake.

---

## Step 1 — Read the file first

**This step is mandatory before any analysis or rewriting.**

If the user provides a file path, read it with the `view` tool or `bash`:
```bash
cat /path/to/file.md
```

If the user pastes content inline, use that directly.

**Do not skip this step.** Do not try to rewrite from memory or partial context.
Read the entire file, then proceed.

---

## Step 2 — Semantic analysis pass (BEFORE rewriting)

After reading, annotate each content block with its **semantic role** — not based on
keywords, but based on what the content is actually *doing* for the reader.

For each paragraph or section, ask:

> "What would a reader *do* with this information?"

| Semantic role | Signal (not keyword — infer from meaning) | PyMdown component |
|---|---|---|
| **Caution** — reader could make a mistake or break something | Mentions irreversibility, data loss, wrong order, common pitfall | `!!! warning` or `!!! danger` |
| **Recommendation** — a better way exists, but it's not the only way | "it's safer to...", "prefer X over Y", "avoid doing Z unless..." | `!!! tip` |
| **Context / background** — helps understanding but not required to act | History, rationale, theory, "why this works" | `???+ info` collapsible |
| **Parallel implementations** — same task, different environments | Same steps repeated for Python/JS, macOS/Linux, CLI/GUI | `=== "Tab"` tabs |
| **Definitions** — term + what it means | A list of terms, config keys, CLI flags, glossary entries | `def_list` |
| **Completion state** — a list of tasks done/not done | Items that can be checked off, progress tracking | `- [x]` tasklist |
| **Extended detail** — supplementary, not on the critical path | "See also", full config dump, advanced options | `???` collapsible |
| **Worked example** — code + explanation together | Code block immediately followed by prose that explains it | `!!! example` with nested fence |
| **Known issue** — documented broken behavior or workaround | "Currently X doesn't work when...", "as a workaround..." | `!!! bug` |
| **Citation / source** — external reference the reader should verify | "According to...", links to specs, RFCs, external docs | `[^footnote]` |

**Key principle:** Do NOT rely on the author having written "Tip:" or "Warning:" or
"Note:" — most writers don't. Read the sentence's *intent* and classify from that.

### Semantic signal examples (no explicit labels)

These should all be recognized even without a label:

```
"환경변수를 직접 코드에 하드코딩하는 것보다 .env 파일을 사용하는 것이 보안상 안전합니다."
→ !!! tip  (implicit best practice)

"이 명령어를 실행하면 기존 데이터가 모두 삭제됩니다."
→ !!! danger  (implicit destructive action)

"OAuth 2.0은 2012년 RFC 6749로 표준화된 인증 프레임워크입니다. 이 섹션에서는..."
→ ???+ info  (background context, can be skipped)

"Python 설치 방법 ... Node.js 설치 방법 ... (동일한 구조 반복)"
→ === "Python" / === "Node.js" tabs

"현재 Windows에서는 이 기능이 동작하지 않습니다. 대안으로 WSL2를 사용하세요."
→ !!! bug
```

### Produce an analysis summary before rewriting

Before outputting the rewritten file, briefly list your decisions:

```
분석 결과:
- L12-15: 하드코딩 경고 → !!! danger
- L23: .env 권장 → !!! tip
- L40-80: OAuth 배경 설명 → ???+ info (접힘)
- L90-130: Python/JS 동일 구조 반복 → 탭으로 통합
- L145-160: CLI 플래그 목록 → def_list
```

This lets the user review the logic before seeing the full rewrite.

---

## Step 3 — Apply transformations

### Admonitions (`admonition` + `pymdownx.details`)

```
!!! type "Title"    → always visible
??? type "Title"    → collapsible, closed by default
???+ type "Title"   → collapsible, open by default
```

**Types:** `note` `info` `tip` `success` `warning` `danger` `bug` `example` `question` `quote` `abstract` `failure`

```markdown
!!! danger "데이터가 삭제됩니다"
    이 작업은 되돌릴 수 없습니다. 실행 전 반드시 백업하세요.

!!! tip
    `--dry-run` 플래그로 실제 변경 없이 먼저 확인할 수 있습니다.

???+ info "배경 — OAuth 2.0이란?"
    OAuth 2.0은 2012년 RFC 6749로 표준화된... [긴 설명]
```

---

### Tabs (`pymdownx.tabbed`)

Use when the **same operation** is repeated for different environments/languages.
Do NOT use for unrelated content — that's just a list.

```markdown
=== "macOS / Linux"
    ```bash
    export API_KEY=your_key_here
    ```

=== "Windows (PowerShell)"
    ```powershell
    $env:API_KEY = "your_key_here"
    ```
```

---

### Collapsible blocks (`pymdownx.details`)

```markdown
??? example "전체 설정 예시"
    ```yaml
    server:
      port: 8080
    ```

??? "더 보기"
    관련 문서: [X](x.md), [Y](y.md)
```

---

### Definition lists (`def_list`)

```markdown
`--verbose`
:   상세 로그를 출력합니다.

`--dry-run`
:   실제 변경 없이 시뮬레이션만 실행합니다.
```

---

### SuperFences — nesting and Mermaid (`pymdownx.superfences`)

````markdown
!!! example "인증 흐름"
    ```python
    token = get_access_token(client_id, secret)
    ```

```mermaid
graph LR
  A[클라이언트] --> B[인증 서버] --> C[리소스 서버]
```
````

---

### Other components

```markdown
# Tasklist
- [x] 완료된 항목
- [ ] 미완료 항목

# Inline highlight
`#!python def main():` 를 진입점으로 사용합니다.

# Footnote
이 동작은 스펙에 명시되어 있습니다[^1].
[^1]: [RFC 7234](https://tools.ietf.org/html/rfc7234) 참고.
```

---

## Step 4 — Rewriting rules

### DO
- Infer semantic role from content meaning, not just explicit labels
- Nest code blocks inside admonitions when they belong together
- Collapse background/context sections with `???+` (open by default so nothing is hidden)
- Merge repeated parallel sections into tabs
- Convert `**Term**: definition` patterns into `def_list`
- Keep the original heading hierarchy intact

### DON'T
- Add admonitions just to decorate — every box must earn its place
- Use tabs for content that isn't truly parallel
- Make everything collapsible (defeats readability)
- Remove or alter original content — only reformat it
- Add labels like "팁:" "주의:" inside the admonition body (the box type already communicates this)

---

## Step 5 — Output format

1. **Analysis summary** — your classification decisions (see Step 2 format above)
2. **Full rewritten `.md` file**
3. **Change log** — 3–5 bullet points: what was changed and why

If the user's mkdocs.yml doesn't include required extensions, note which ones to add at the end.

**Required extensions:**
```yaml
markdown_extensions:
  - admonition
  - footnotes
  - attr_list
  - md_in_html
  - def_list
  - pymdownx.highlight:
      anchor_linenums: true
  - pymdownx.inlinehilite
  - pymdownx.details
  - pymdownx.superfences
  - pymdownx.tabbed:
      alternate_style: true
  - pymdownx.tasklist:
      custom_checkbox: true
```

See references.md for full before/after examples.
