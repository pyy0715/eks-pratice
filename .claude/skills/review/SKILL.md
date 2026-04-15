---
name: review
description: "Post-editing verification checklist for Korean EKS documentation. Checks writing style, terminology, expressions, and factual accuracy against established rules. Use after writing or editing any .md file in docs/, or when the user asks to review a document."
---

# Document Review Checklist

Verify Korean EKS documentation against established writing rules.
Run this AFTER writing/editing — read the target file(s), check every rule, report violations as a numbered list.

<role>
You are a strict Korean technical writing reviewer. Check each rule mechanically.
Find violations, apply fixes immediately, then report a concise summary of changes.
</role>

---

## Workflow

1. Read the target file(s) completely
2. Run every check in the checklist below
3. Apply all violations immediately — no approval loop
4. Report a concise summary of what was changed

---

## Checklist

### Style & Tone

- [ ] **경어체** — All sentence-ending verbs use polite form (~합니다, ~됩니다, ~입니다). Plain forms (~한다, ~된다, ~이다) are only allowed in subordinate clauses (~다는, ~다면, ~다고).
- [ ] **No exaggerated expressions** — No 수천 배, 수백 배, 가장 단순한, 가장 빠른, 최고의, 초고속, ~이 핵심입니다, ~이 포인트입니다. Describe behavior directly without ranking or emphasis.
- [ ] **No marketing/flowery phrasing** — No 범용 해법, 어디서나 동작, 줄타기를 하게 됩니다, or other dramatic metaphors. Write plain, precise sentences.
- [ ] **No anthropomorphic quotes** — No VPA가 "너무 적다"고 판단하여. Describe the behavior directly.
- [ ] **Parallel list structure** — When listing related items (e.g., Lower Bound / Target / Upper Bound), use the same sentence frame for each item.

### Terminology

- [ ] **Official English terms** — Pod (not 파드), DaemonSet (not 데몬셋), kubelet, Managed Node Group, ENI, bootstrapping, etc. Do not translate official AWS/K8s terms to Korean.
- [ ] **No invented translations** — Keep English for ambiguous terms: Issuer (not 발급자), Subject (not 주체), Audience (not 대상), Trust Policy (not 신뢰 정책), Identity Provider (not 신원 제공자). If a Korean form exists that engineers actually use (e.g., 개인 키 for private key), use that.
- [ ] **No "주입"** — Replace with context-appropriate verb: 설정됩니다, 추가됩니다, 반영됩니다, 적용됩니다. "mutate"는 K8s webhook 용어로 허용.
- [ ] **Korean particles for English words** — Pod이 (not Pod가), Pod을 (not Pod를), Pod은 (not Pod는), Pod으로 (not Pod로). English terms ending in consonant sound take consonant-ending particles.

### Formatting

- [ ] **No middle dot separator** — 보안 그룹·VPC Flow Logs (X) → 보안 그룹, VPC Flow Logs (O). Use comma or bullet list.
- [ ] **Admonition titles in English** — No Korean titles on tip/warning/info boxes. Box body must add new value, not restate surrounding prose.
- [ ] **Design rationale in prose** — No separate `!!! note "설계 의도"` boxes. Weave rationale into the paragraph naturally.
- [ ] **Section headers: full name only** — `## Horizontal Pod Autoscaler` (O), `## HPA - Horizontal Pod Autoscaler` (X). Abbreviation goes in the intro paragraph.
- [ ] **Table over def_list for 4+ items** — When defining many parameters, fields, or options, use a table for scannability.

### Content Quality

- [ ] **Concrete language** — No vague expressions like "Pod 밀도가 높은 경우". Write specifically: "노드당 Pod 수가 많아 IP 소진이 빠른 경우".
- [ ] **Explicit scope** — When content applies only to a specific config (MNG, self-managed, AL2, AL2023), state the scope in the first sentence.
- [ ] **Numeric facts verified** — Every number, threshold, or behavioral claim must be verified against official AWS/K8s docs. Flag any unverified values.
- [ ] **No content duplication** — If a concept is already covered in another file, link to it instead of re-explaining.

---

## Non-document rules (not checked in review)

These rules apply to skill files and workflow, not document content:
- Skill file content must be in English
- Verify facts via AWS Knowledge MCP before writing
