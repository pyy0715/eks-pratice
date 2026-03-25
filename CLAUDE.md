---
name: EKS 문서 작성 스타일 가이드
description: eks-pratice 레포 문서 작성 시 따라야 할 구조·시각화·서술 원칙
type: feedback
---

## 검증 원칙

- 수치/동작 설명은 AWS Knowledge MCP + WebFetch로 먼저 확인. 추론으로 작성 금지
- 사용자 제안도 독자 관점에서 독립적으로 평가 — "이게 진짜 맞나?" 검토 후 반영. 맞지 않으면 먼저 말할 것

## 구조 원칙

컴포넌트는 semantic role로만 선택 — 꾸밈용 박스 남발 금지.

- 반직관적 설계 설명 → `???+ info` (prose에 자연스럽게 녹이는 게 우선, 별도 callout box 지양)
- 3개 이상 옵션 비교 → grid cards
- config/env var/CLI flag 설명 → def_list 또는 `**bold key**` bullet (문서 내 기존 패턴 따를 것)
- 배경 지식 (필수가 아닌 컨텍스트) → `???` or `???+` collapsible
- 주의/파괴적 작업 → `!!! warning` / `!!! danger`
- 권장 사항 → `!!! tip`
- Worked example (code + 설명) → `!!! example` 또는 코드 annotations

**Why:** 매번 `!!! note "설계 의도: ..."` 박스를 써서 기계적으로 설명을 분리했다가 사용자가 명시적으로 지적. 설명은 문장 흐름 안에 녹이는 것이 원칙.

**How to apply:** 새 섹션 작성 시 "이 박스가 없으면 독자가 뭘 놓치는가?" 자문. 없어도 된다면 박스 쓰지 말 것.

## 시각화 원칙

- 패킷/프레임 구조 → Mermaid `packet-beta`
- 흐름/순서 → Mermaid `graph` / `sequenceDiagram`
- ASCII art는 최후 수단
- Operational 공식 (MaxENI × IPv4/ENI 같은 것) → 코드 블록 + def_list, LaTeX(`$$`) 지양
- 수학 공식이 진짜 필요할 때만 `pymdownx.arithmatex` 사용

**Why:** `$$\text{maxPods} = (\text{MaxENI} \times (\text{IPv4addr/ENI} - 1)) + 2$$` 같은 표기가 API 파라미터명에는 어색함. ASCII 중첩 박스도 가독성 낮음.

## 서술 원칙

- 설계 의도/WHY는 문장 안에 녹임 — 별도 callout box(`!!! note "설계 의도: ..."`) 금지
- warning/tip/info/example 제목은 영어
- Tip/Warning은 위 prose에서 이미 설명된 내용 요약 금지 — 독자에게 새로운 가치가 있어야 함
- "언제" 레이블 패턴 미사용 — 사용 시나리오는 첫 문장에 자연스럽게 통합
- 새 용어 첫 등장 시 문장 안에 소개 (괄호 또는 각주) — 별도 정의 섹션 금지
- 구체적 표현 사용: "Pod 밀도가 높은 경우" (X) → "노드당 Pod 수가 많아 IP 소진이 빠른 경우" (O)
- "A + B 조합" 표현 (X) → "A와 B를 함께" 형식 (O)
- 공식 AWS/K8s 용어 그대로 사용: Pod, ENI, Managed Node Group, DaemonSet, kubelet 등
- 어색한 수식어 배제: "범용 해법", "어디서나 동작", "클라우드 환경과 무관하게" 류 표현 금지
- 파일 간 내용 중복 없이 — 한 파일이 단일 출처 (single source of truth)
- 섹션 헤더는 간결한 영어, 본문은 한국어

**Why:** 사용자가 직접 "매번 설계 의도를 쓰는 게 아닙니다. 글을 작성하면서 자연스럽게 설명하라는 거에요" 및 "어색한 표현 쓰지 마세요" 명시적 피드백.

## MkDocs Material / PyMdown 활용

- `content.tooltips` + `abbr` + `pymdownx.snippets auto_append` → 전역 약어 툴팁
- 약어 설명은 단순 풀네임이 아닌 "무엇을 하는가" 한 줄
- 자명한 약어(VPC, CNI, IAM, EC2 등)는 abbreviations.md에 넣지 않음
- 독자가 모를 기술 용어(RFC 번호, 프로토콜 약어 등)는 abbreviations.md에 추가
- Magic link: 외부 GitHub 이슈 참조 시 `owner/repo#number` 형식
- `packet-beta` mermaid: 패킷 구조 시각화에 우선 사용
