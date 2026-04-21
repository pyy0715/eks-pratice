<!-- WEEK: 6 -->
<!-- TOPIC: gitops -->
<!-- CREATED: 2026-04-21 -->

# Week 6 Staging — GitOps on EKS

각 문서(1~5)가 참조할 원본 입력과 레퍼런스를 섹션별로 분리합니다.
공통 출처는 아래 "Common References"에 모아두고, 문서별로 필요한 링크만 인용합니다.

---

## Common References

문서 여러 곳에서 공통으로 참조할 출처입니다.

| ID | URL | 용도 |
|---|---|---|
| AWS-PG-INTRO | https://docs.aws.amazon.com/prescriptive-guidance/latest/eks-gitops-tools/introduction.html | EKS GitOps 도구 개요 |
| AWS-PG-USECASES | https://docs.aws.amazon.com/prescriptive-guidance/latest/eks-gitops-tools/use-cases.html | ArgoCD vs Flux 비교 표 |
| AWS-PG-ARGOCD | https://docs.aws.amazon.com/prescriptive-guidance/latest/eks-gitops-tools/argo-cd.html | ArgoCD 개요 |
| EKS-ARGOCD | https://docs.aws.amazon.com/eks/latest/userguide/argocd.html | EKS Capability for Argo CD |
| EKS-CAPABILITIES | https://docs.aws.amazon.com/eks/latest/userguide/capabilities.html | EKS Capabilities 개요 |
| EKS-ACK | https://docs.aws.amazon.com/eks/latest/userguide/ack-considerations.html | ACK considerations |
| AWS-BLOG-ARGOCD-DEEP | https://aws.amazon.com/blogs/containers/deep-dive-streamlining-gitops-with-amazon-eks-capability-for-argo-cd/ | EKS Managed ArgoCD 심화 |
| AWS-BLOG-CAPABILITIES-KR | https://aws.amazon.com/ko/blogs/korea/announcing-amazon-eks-capabilities-for-workload-orchestration-and-cloud-resource-management/ | EKS Capabilities 발표 (한글) |
| OPENGITOPS | https://opengitops.dev | GitOps 4 원칙 |
| SAAS-WHITEPAPER | https://docs.aws.amazon.com/whitepapers/latest/security-practices-multi-tenant-saas-applications-eks/ | SaaS on EKS Silo/Pool |
| SAAS-HYBRID | https://docs.aws.amazon.com/prescriptive-guidance/latest/multi-tenancy-amazon-neptune/hybrid-model.html | Hybrid tenancy |
| BLUX-CASE | https://aws.amazon.com/blogs/apn/aws-saas-architecture-patterns-implementation-on-amazon-eks-blux-a-korean-startup/ | 한국 SaaS 사례 |
| ARGO-EVENTS | https://argoproj.github.io/argo-events/concepts/architecture/ | Argo Events 아키텍처 |
| EKS-SAAS-REPO | https://github.com/ianychoi/eks-saas-gitops | 워크숍 원본 레포 (README-korean) |

---

## Doc 1 — GitOps Principles and Platform Engineering

### Key Topics

- 플랫폼 엔지니어링의 필요성 (개발팀 vs 인프라팀 병목 문제)
- IDP(Internal Developer Platform) 정의
- 3대 이점 (Velocity, Governance, Efficiency)
- AWS 구현 패턴 (Account / Template / Cluster / Namespace / PaaS as a Service)
- OpenGitOps 4 Principles
- Auto Reconciliation 메커니즘
- SaaS DevOps와 GitOps 필요성
- Silo / Pool / Hybrid 배포 모델
- EKS GitOps 도구 Landscape (9개 도구)

### OpenGitOps 4 Principles (verbatim, from OPENGITOPS)

1. **Declarative** — "A system managed by GitOps must have its desired state expressed declaratively."
2. **Versioned and Immutable** — "Desired state is stored in a way that enforces immutability, versioning and retains a complete version history."
3. **Pulled Automatically** — "Software agents automatically pull the desired state declarations from the source."
4. **Continuously Reconciled** — "Software agents continuously observe actual system state and attempt to apply the desired state."

### SaaS Tenancy Models

| Model | 설명 | 격리 | 비용 | 대표 활용 |
|---|---|---|---|---|
| Silo | 테넌트마다 전용 인프라 | 높음 | 높음 | Premium tier |
| Pool | 인프라 공유 | 낮음 | 낮음 | Basic tier |
| Hybrid | 티어별 혼합 | 중간 | 중간 | 실무 대부분 |

### Blux Case (국내 사례)

- Standard: 공유 리소스
- Premium: 전용 리소스
- Enterprise: 전용 + 고성능
- HPA + Karpenter 자동 스케일링
- ArgoCD + Jenkins CI/CD
- 이후 Istio 도입 계획

### EKS GitOps Tools (from AWS-PG-INTRO)

Argo CD, Flux, Weave GitOps, Jenkins X, GitLab CI/CD, Spinnaker, Rancher Fleet, Codefresh, Pulumi.

### References (Doc 1)

- OPENGITOPS
- AWS-PG-INTRO
- SAAS-WHITEPAPER
- SAAS-HYBRID
- BLUX-CASE
- re:Invent 2023 CON311 "Platform engineering with Amazon EKS"
    - 영상: https://www.youtube.com/watch?v=eLxBnGoBltc
    - Deck: https://d1.awsstatic.com/events/Summits/reinvent2023/CON311_Platform-engineering-with-Amazon-EKS.pdf
- 국내 사례
    - 당근: https://speakerdeck.com/outsider/danggeun-gaebalja-peulraespomeun-eoddeon-munjereul-haegyeolhago-issneunga
    - 무신사: https://youtu.be/9FKbQRu6lVs

---

## Doc 2 — ArgoCD: Architecture, Patterns, Comparison

### Key Topics

- ArgoCD 아키텍처 (api-server, application-controller, repo-server, redis, applicationset-controller, notifications-controller, dex)
- 리소스 계층 — Application, ApplicationSet, AppProject
- Sync model — Manual/Automatic, prune, self-heal, sync waves, partial sync
- App-of-Apps 패턴 + Cascading vs Non-cascading deletion
- ApplicationSet generators (Git, Cluster, List, Matrix)
- ArgoCD vs Flux 비교
- EKS Capability for Argo CD (Managed)

### ArgoCD vs Flux (from AWS-PG-USECASES, 확인 완료)

| Area | Argo CD | Flux |
|---|---|---|
| GitOps 원칙 지원 | Yes | Yes |
| 아키텍처 | End-to-end 애플리케이션 | CRD와 컨트롤러 집합 |
| 설정 | 간편 | 복잡 |
| Helm 지원 | Yes | Yes |
| Kustomize 지원 | Yes | Yes |
| 통합 GUI | 완전한 웹 UI | 선택적 경량 웹 |
| RBAC | 세분화된 자체 제어 | Kubernetes 네이티브 |
| 멀티테넌시/멀티클러스터 | 멀티클러스터 탁월 | 멀티테넌시 탁월 |
| SSO | Yes | Yes |
| 동기화 자동화 | Sync window | Reconciliation interval |
| 부분 동기화 | Yes | No |
| 조정 방식 | 수동/자동 + 다양한 전략 | 수동/자동 |
| 확장성 | 커스텀 플러그인 (제한적) | 커스텀 컨트롤러 (광범위) |
| 커뮤니티 | 크고 활발 | 성장 중 |
| Scalability | 수만 앱 (UI 속도 제약) | 수만 앱 (수평/수직 가이드) |

### EKS Managed ArgoCD (from AWS-BLOG-ARGOCD-DEEP)

**AWS 관리 영역**
- 설치, 스케일링, HA, 소프트웨어 업그레이드
- Inter-cluster 통신
- SSO via AWS IAM Identity Center
- ECR 토큰 자동 갱신 (12시간 주기 수동 작업 불필요)
- AWS Backup 연동

**사용자 관리 영역**
- Application, ApplicationSet 정의
- Git repo 구성
- Project/RBAC
- Cluster 등록

**기술적 제약**
- ARN 기반 cluster 등록 (Kubernetes API URL 아님) → 프라이빗 클러스터 자동 연결
- Global token 12시간 제한 (자동화 부적합)
- Project-scoped token 365일까지
- Controller log 직접 접근 불가 → Kubernetes events와 resource status로만 확인
- `argocd admin`, `argocd login` 미지원
- EKS 전용

**Cross-account 접근**
- EKS Access Entries 기반 → 복잡한 IAM role chaining 불필요

### EKS Capabilities 전체 (from EKS-CAPABILITIES)

세 가지가 함께 설계됨:
- **ArgoCD**: 애플리케이션 CD
- **ACK**: AWS 리소스를 Kubernetes API로 관리
- **kro**: 여러 리소스를 조합해 상위 추상화 생성

GitOps 워크플로우 지원, 모든 EKS 컴퓨트 타입 지원, 활성 시간 기준 과금.

### References (Doc 2)

- EKS-ARGOCD
- EKS-CAPABILITIES
- AWS-BLOG-ARGOCD-DEEP
- AWS-PG-ARGOCD
- AWS-PG-USECASES
- https://argo-cd.readthedocs.io/en/stable/operator-manual/architecture/
- https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/ (App-of-Apps)
- https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/
- https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/
- 악분일상 블로그 (App-of-Apps): https://malwareanalysis.tistory.com/478
- 예제 repo: https://github.com/argoproj/argocd-example-apps

---

## Doc 3 — ArgoCD Ecosystem Extensions

### Key Topics

- Argo CD Image Updater
- Argo Rollouts (Blue-green, Canary, Analysis)
- GitOps Bridge
- kro (Kube Resource Orchestrator)
- ACK (AWS Controllers for Kubernetes)
- Terraform vs ACK vs kro vs Crossplane 비교

### Argo CD Image Updater

- GitOps에서 이미지 태그 업데이트는 수동 PR 필요 → Image Updater가 해결
- 레지스트리 감시 → 매칭 정책 기준 Application 파라미터 또는 Git write-back
- ECR 연동 시 12시간 토큰 갱신 주의

### Argo Rollouts

- Kubernetes Deployment rolling update 한계
    - 트래픽 제어 부재
    - 외부 메트릭 검증 불가
    - 자동 롤백 불가
- 전략: Blue-green, Canary, Canary Analysis
- 1.8+: Gateway API v1.0 지원
- ArgoCD + Rollouts + ApplicationSet = progressive delivery

### GitOps Bridge

- 커뮤니티 프로젝트
- IaC(Terraform)로 EKS 생성 + ArgoCD 애드온 동시 부트스트랩
- Hub and Spoke 멀티 클러스터 패턴
- terraform-aws-eks-blueprints 결합

### kro

- 문제: 앱 하나가 Deployment + Service + Ingress + IAM Role + DynamoDB 같은 리소스 조합 요구
- ResourceGraphDefinition CRD로 조합 패턴 정의
- ArgoCD가 이를 Application으로 배포
- Kubernetes 리소스 + AWS 리소스(ACK, Crossplane) 함께 조립

### ACK

- AWS 리소스를 Kubernetes API로 관리 (S3, RDS, IAM 등)
- GitOps로 AWS 인프라 통제 → Terraform 대안
- Pod Identity 기반 권한 구성 권장
- 기존 AWS 리소스 adopt 가능 (zero-downtime 마이그레이션)

### IaC Tool Comparison (작성 시 완성)

| Tool | Scope | Language | Kubernetes Integration | 적합 상황 |
|---|---|---|---|---|
| Terraform | 범용 IaC | HCL | 외부 도구 | 기존 IaC 표준 유지 |
| ACK | AWS 리소스 | YAML (K8s) | 네이티브 | AWS 중심, GitOps 통합 |
| kro | 리소스 조합 | YAML (K8s) | 네이티브 | 플랫폼 팀의 상위 추상화 |
| Crossplane | 멀티 클라우드 | YAML (K8s) | 네이티브 | 멀티 클라우드 리소스 |

### References (Doc 3)

- EKS-CAPABILITIES
- EKS-ACK
- Argo CD Image Updater
    - 공식: https://argocd-image-updater.readthedocs.io/en/stable/
    - Helm 가이드: https://www.cncf.io/blog/2024/11/05/mastering-argo-cd-image-updater-with-helm-a-complete-configuration-guide/
    - 한국 블로그: https://kmaster.tistory.com/85 / https://techblog.woowahan.com/19548/
- Argo Rollouts
    - 공식: https://argoproj.github.io/argo-rollouts/
    - 트래픽 관리: https://argo-rollouts.readthedocs.io/en/stable/features/traffic-management/
    - Gateway API 플러그인: https://rollouts-plugin-trafficrouter-gatewayapi.readthedocs.io/en/latest/
    - Gateway API 블로그: https://blog.argoproj.io/argo-rollouts-now-supports-version-1-0-of-the-kubernetes-gateway-api-acc429729e42
- GitOps Bridge
    - 본 repo: https://github.com/gitops-bridge-dev/gitops-bridge
    - Control Plane 템플릿: https://github.com/gitops-bridge-dev/gitops-bridge-argocd-control-plane-template
    - EKS Blueprints 패턴: https://aws-ia.github.io/terraform-aws-eks-blueprints/patterns/gitops/gitops-getting-started-argocd/
    - Multi-cluster Hub-Spoke: https://aws-ia.github.io/terraform-aws-eks-blueprints/patterns/gitops/gitops-multi-cluster-hub-spoke-argocd/
- kro: https://kro.run/ (최신 정보는 작성 시 확인)
- ACK: https://aws-controllers-k8s.github.io/community/

---

## Doc 4 — Event-Driven Workflows for SaaS Automation

### Key Topics

- Argo Workflows vs ArgoCD (서로 다른 문제 도메인)
- WorkflowTemplate, Workflow 개념
- Argo Events 4 계층 (EventSource / EventBus / Sensor / Trigger)
- 주요 EventSource 타입 (SQS, SNS, webhook, Kafka, NATS, Calendar 등 25종+)
- 테넌트 온보딩 자동화 흐름
- ArgoCD / Argo Workflows / ACK / kro / Crossplane — When to use what

### Argo Events Architecture (from ARGO-EVENTS)

- **EventSource**: 외부 시스템 이벤트 캡처 (SQS, webhook 등)
- **EventBus**: 이벤트 라우팅, 분산 (NATS 또는 Jetstream 기반)
- **Sensor**: EventBus 구독, 이벤트 패턴 매칭
- **Trigger**: Sensor 조건 충족 시 실행 (Workflow, HTTP, K8s 리소스 등)

25종 이상 EventSource — AWS SNS/SQS, Azure Service Bus, GCP Pub/Sub, AMQP, Kafka, NATS, Redis, MQTT, Pulsar, GitHub/GitLab/Bitbucket, Webhook, Calendar, File system 등.

### Tenant Onboarding Flow (원본 워크숍 기반, ArgoCD 관점으로 각색)

원본 흐름:
```
SQS 메시지 (tenant_id, tier, version)
  → Argo Events Sensor
  → tenant-onboarding-template Workflow 실행
  → Gitea 저장소 클론
  → 티어 템플릿 기반 HelmRelease 파일 생성
  → Git commit & push
  → Flux v2 감지 → EKS 배포
```

ArgoCD 대체 흐름:
```
SQS 메시지 (tenant_id, tier, version)
  → Argo Events Sensor
  → tenant-onboarding Workflow 실행
  → GitHub 저장소 클론
  → 티어 템플릿 기반 Application/values 파일 생성
  → Git commit & push
  → ArgoCD ApplicationSet Git generator 감지 → 신규 Application 생성 → EKS 배포
```

### Decision Guide

| Need | Tool |
|---|---|
| 지속 동기화 | ArgoCD |
| 이벤트 기반 일회성 Job | Argo Workflows |
| AWS 리소스 선언적 관리 | ACK 또는 Crossplane |
| 리소스 조합 추상화 | kro |
| IaC 표준 유지 | Terraform (+ Tofu Controller / GitOps Bridge) |

### References (Doc 4)

- ARGO-EVENTS
- https://argo-workflows.readthedocs.io/
- https://argoproj.github.io/argo-events/
- EKS-SAAS-REPO (워크숍 원본 Sensor, WorkflowTemplate 참고)

---

## Doc 5 — ArgoCD-based Mini SaaS Lab

### Lab Goals

- 워크숍의 Flux + Tofu Controller 흐름을 ArgoCD + ApplicationSet + Argo Workflows 조합으로 재구성
- 3 tier (Basic / Advanced / Premium) 구현
- 이벤트 드리븐 온보딩 자동화

### Scenario Summary

| Scenario | Goal | Key Tech |
|---|---|---|
| 1. App-of-Apps 부트스트랩 | addons와 테넌트 Application 계층 선언 | ArgoCD Application, Sync waves |
| 2. ApplicationSet tier 배포 | 단일 helm-tenant-chart + values 차이로 3 tier 생성 | ApplicationSet Git generator, Helm |
| 3. SQS 이벤트로 자동 온보딩 | 메시지 하나로 전체 파이프라인 기동 | Argo Events + Argo Workflows + Git commit |
| 4. (선택) Image Updater | ECR 이미지 태그 자동 반영 | Argo CD Image Updater + Argo Rollouts |

### Environment Setup

- `labs/week6/`에 Terraform으로 EKS 설치
- ArgoCD는 self-managed Helm 설치 (EKS Capability 대안 주석)
- Git은 GitHub repo 사용
- SQS 큐 Terraform으로 생성

### Lab Structure (Week 5 Lab 참고 양식)

각 Scenario는 다음 구조:

- Background — 무엇을 왜 하는가
- Goal — 검증하려는 동작
- Manifests — 경로와 내용 요약
- Reproduction — 실행 명령
- Verification — 결과 확인 방법

### References (Doc 5)

- ArgoCD ApplicationSet: https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/
- Argo Events EventSource SQS: https://argoproj.github.io/argo-events/eventsources/setup/aws-sqs/
- 워크숍 원본 참고: EKS-SAAS-REPO

### Original Workshop Notes (참고용, 문서로 넣지 않음)

사용자 입력의 워크숍 실습 절차(실습 1~3)는 Flux 기반이고 Lab 문서는 ArgoCD로 재구성하므로, 워크숍 단계 재현을 그대로 옮기지 않습니다. 대신 워크숍이 검증한 **설계 원칙(단일 Helm chart + values만으로 tier 결정, 이벤트 드리븐 온보딩, IaC 추상화)**을 Lab scenario 목표에 반영합니다.

---

## User Intent (재확인)

- 주요 학습 대상: ArgoCD (Flux는 비교 관점으로만)
- 실습은 ArgoCD 기반 미니 SaaS 직접 구현
- 워크숍 단계별 재현은 하지 않음
- Extensions (Rollouts, Image Updater, GitOps Bridge, kro, ACK) 포함
- 5개 문서 구조: 1 GitOps 원칙 → 2 ArgoCD → 3 Extensions → 4 Workflows → 5 Lab
