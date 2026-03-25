# EKS 문서 작성 스타일 가이드

<skills>
## 스킬 활용

- EKS 학습 내용 정리 → `write-eks-notes` 스킬 사용
- PyMdown 구조 개선(admonition, tabs, def_list 등) → `write-markdown` 스킬 사용
</skills>

<verification>
## 검증 원칙

- 수치/동작 설명은 먼저 `mcp__aws-knowledge__aws___search_documentation` 또는 `mcp__aws-knowledge__aws___read_documentation`으로 확인 후 작성. 추론 금지
- EKS 애드온 버전별 변경 이력: `userguide/managing-*.html` + AWS containers blog (`containers.amazon.com`) 모두 확인 — userguide 단독으로는 불완전할 수 있음
- 사용자 제안도 독자 관점에서 독립적으로 평가 — "이게 진짜 맞나?" 검토 후 반영. 틀렸으면 먼저 말할 것
- 각주 출처는 해당 내용이 실제로 있는 페이지로 연결 — 관련 페이지 대체 금지
</verification>

<scope>
## 범위 명시 원칙

- 특정 구성(Managed Node Group, self-managed, AL2, AL2023 등)에만 해당하는 내용은 첫 문장에서 범위를 밝힐 것
- Flowchart 시작 노드는 적용 대상을 명확히 나타낼 것 — "Node Bootstrap" 같은 모호한 레이블 금지
- Self-managed node group처럼 해당하지 않는 케이스도 명시할 것
</scope>

<structure>
## 구조 원칙

컴포넌트는 semantic role로만 선택 — 꾸밈용 박스 남발 금지.

- 반직관적 설계 설명 → prose에 자연스럽게 녹임. `???+ info` collapsible은 최후 수단
- 3개 이상 옵션 비교 → grid cards
- config/env var/CLI flag 설명 → def_list 또는 `**bold key**` bullet (문서 내 기존 패턴 따를 것)
- 배경 지식 (필수가 아닌 컨텍스트) → `???` or `???+` collapsible
- 주의/파괴적 작업 → `!!! warning` / `!!! danger`
- 권장 사항 → `!!! tip`
- Worked example (code + 설명) → `!!! example` 또는 코드 annotations

새 섹션 작성 시 "이 박스가 없으면 독자가 뭘 놓치는가?" 자문. 없어도 된다면 박스 쓰지 말 것.

warning/tip/info/example 제목은 영어. prose에서 이미 설명한 내용 요약 금지 — 독자에게 새로운 가치가 있어야 함.
</structure>

<visualization>
## 시각화 원칙

- 패킷/프레임 구조 → Mermaid `packet-beta`
- 흐름/순서 → Mermaid `flowchart` / `sequenceDiagram`
- 공식 (MaxENI × IPv4/ENI 같은 것) → 코드 블록 + def_list. LaTeX(`$$`) 지양
- 수학 공식이 진짜 필요할 때만 `pymdownx.arithmatex` 사용
- ASCII art는 최후 수단
</visualization>

<writing>
## 서술 원칙

**금지 패턴:**

- 중간점(·) 열거: `Service·EndpointSlice`, `VPC CIDR·Pod CIDR·노드 IP` → `A와 B`, `A, B, C`로 풀어 쓸 것
- 설계 의도를 별도 callout box로 분리 (`!!! note "설계 의도: ..."`) → 문장 흐름에 녹일 것
- 직역 조어: "강제 상한", "주입값" 같은 억지 복합명사 → AWS 공식 용어 또는 구체적 수치/동사 구조로 대체
- 추상적 번역어: "노드 초기화" 같은 모호한 표현 → AWS 원문 용어 우선 (예: node bootstrapping)
- "언제" 레이블 패턴 — 사용 시나리오는 첫 문장에 자연스럽게 통합
- 어색한 수식어: "범용 해법", "어디서나 동작", "클라우드 환경과 무관하게" 류

**표현 원칙:**

- 설계 의도/WHY는 문장 안에 녹임
- 구체적 표현 사용: "Pod 밀도가 높은 경우" (X) → "노드당 Pod 수가 많아 IP 소진이 빠른 경우" (O)
- "A + B 조합" (X) → "A와 B를 함께" (O)
- 공식 AWS/K8s 용어 그대로: Pod, ENI, Managed Node Group, DaemonSet, kubelet, bootstrapping 등
- 기술 약어 첫 등장 시 풀네임 병기: 예) CEL(Common Expression Language)
- 섹션 헤더는 간결한 영어, 본문은 한국어
- 파일 간 내용 중복 없이 — 한 파일이 단일 출처
- 기존 페이지에서 설명한 개념이 현 페이지에 등장하면 반드시 링크로 명시 — "독자가 이미 배운 것과 어떻게 맞물리는가"를 문장 안에 녹일 것
</writing>

<tooling>
## MkDocs Material / PyMdown 활용

- `content.tooltips` + `abbr` + `pymdownx.snippets auto_append` → 전역 약어 툴팁
- 약어 설명은 단순 풀네임이 아닌 "무엇을 하는가" 한 줄
- 자명한 약어(VPC, CNI, IAM, EC2 등)는 abbreviations.md에 넣지 않음
- 독자가 모를 기술 용어(RFC 번호, 프로토콜 약어 등)는 abbreviations.md에 추가
- Magic link: 외부 GitHub 이슈 참조 시 `owner/repo#number` 형식
</tooling>
