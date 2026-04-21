# GitOps Principles and Platform Engineering

새 서비스 하나가 들어올 때마다 개발팀은 전용 SQS 큐, DynamoDB 테이블, IAM 역할이 필요합니다. 개발자는 요청 티켓을 만들고 인프라팀의 큐에 밀어 넣습니다. 서비스 수가 늘어날수록 티켓은 쌓이고 인프라팀이 병목이 됩니다. 테넌트가 늘수록 요청량도 비례해 증가하므로 수동 프로비저닝 방식은 유지되기 어렵습니다. 이 흐름을 깨기 위해 등장한 접근이 플랫폼 엔지니어링과 GitOps이며, 이 문서는 두 개념의 관계와 EKS에서의 구현 도구를 정리합니다.

## Why Platform Engineering

플랫폼 엔지니어링은 개발팀이 인프라 관리 부담에서 벗어나 애플리케이션 개발에 집중할 수 있도록 추상화를 제공하는 실무 영역입니다. 플랫폼팀이 VPC, IAM, 큐, 데이터베이스 같은 공통 구성 요소를 사전 조합해 표준 단위로 제공하면, 개발자는 서비스 코드와 그에 필요한 메타데이터만 선언해도 배포가 가능합니다.

플랫폼팀이 제공하는 결과물은 셀프 서비스 API, 도구, 문서, 지원 체계가 결합된 내부 개발자 플랫폼(Internal Developer Platform, IDP)입니다. IDP는 단순한 도구 모음이 아니라 내부 고객을 대상으로 하는 제품으로 취급되므로, 일반 SaaS 제품처럼 UX, 온보딩, 피드백 루프를 갖춰야 합니다.

### Three Benefits

IDP 도입이 조직에 제공하는 이점은 세 가지로 정리할 수 있습니다.

`Velocity`
:   셀프 서비스 배포로 아이디어에서 프로덕션까지의 시간이 단축됩니다. 개발자가 인프라 티켓을 기다리지 않고 표준 템플릿으로 즉시 환경을 생성합니다.

`Governance`
:   보안, 신뢰성, 확장성 요구 사항이 플랫폼 차원에서 자동 적용됩니다. 개발자가 규칙을 의식하지 않아도 기본값으로 규정을 준수하는 리소스가 생성됩니다.

`Efficiency`
:   멀티테넌시 구성으로 인프라 비용을 절감하고, 전문 지식을 플랫폼팀에 집중해 조직 전반의 운영 비용을 낮춥니다.

### AWS Implementation Patterns

플랫폼 엔지니어링은 하나의 정답이 있지 않습니다. 조직의 규제 요구, 격리 수준, 운영 역량에 따라 제공 단위가 달라집니다. AWS는 플랫폼 팀과 개발팀의 책임 경계를 [EKS Capabilities](https://aws.amazon.com/blogs/aws/announcing-amazon-eks-capabilities-for-workload-orchestration-and-cloud-resource-management/)로 다음과 같이 정리합니다.

![Platform engineer and application developer roles](https://d2908q01vomqb2.cloudfront.net/da4b9237bacccdf19c0760cab7aec4a8359010b0/2025/11/05/2025-eks-capabilities-1.png)
*[Source: Announcing Amazon EKS Capabilities for workload orchestration and cloud resource management](https://aws.amazon.com/blogs/aws/announcing-amazon-eks-capabilities-for-workload-orchestration-and-cloud-resource-management/)*

플랫폼 팀은 클러스터 및 공통 기능을 제공하고, 애플리케이션 개발팀은 워크로드와 AWS 리소스를 선언적으로 요청합니다. 이 역할 분리가 실무에서 어떻게 구현되는지는 아래 패턴 표로 정리할 수 있습니다.

| Pattern | Unit | Characteristic | When to apply |
|---|---|---|---|
| Account as a Service | AWS account | 완전한 blast radius 격리 | 규제 환경, 비용 분리 필요 |
| Template as a Service | IaC template | 팀이 자체 운영 | 성숙한 DevOps 조직 |
| Cluster as a Service | EKS cluster | 클러스터 단위 격리 | 중대형 조직의 공통 표준 |
| Namespace as a Service | Kubernetes namespace | 클러스터 공유, 네임스페이스 분리 | 비용 효율과 관리 집중 필요 |
| Platform as a Service | Higher-level abstraction | 개발자는 앱 코드만 제공 | 소규모 팀의 빠른 실험 |

국내 사례로는 [당근](https://speakerdeck.com/outsider/danggeun-gaebalja-peulraespomeun-eoddeon-munjereul-haegyeolhago-issneunga)과 [무신사](https://youtu.be/9FKbQRu6lVs)가 내부 플랫폼 구축 경험을 공개한 바 있고, AWS 블로그에는 한국 B2B SaaS인 [Blux가 EKS 기반 플랫폼으로 테넌트 온보딩을 자동화한 사례](https://aws.amazon.com/blogs/apn/aws-saas-architecture-patterns-implementation-on-amazon-eks-blux-a-korean-startup/)가 정리되어 있습니다. Blux의 전체 구조는 SaaS에서 자주 쓰이는 control plane과 application plane 분리를 따릅니다.

![SaaS control plane and application plane](https://d2908q01vomqb2.cloudfront.net/77de68daecd823babbb58edb1c8e14d7106e83bb/2025/12/09/fig2-1.png)
*[Source: AWS SaaS architecture patterns implementation on Amazon EKS — Blux](https://aws.amazon.com/blogs/apn/aws-saas-architecture-patterns-implementation-on-amazon-eks-blux-a-korean-startup/)*

Control plane은 테넌트 온보딩, 과금, 관리 기능을 담당하고 application plane은 실제 비즈니스 로직을 실행합니다. 플랫폼팀이 제공하는 IDP는 control plane에 해당하고, 개발자가 배포하는 서비스는 application plane에 배치됩니다.

## OpenGitOps Principles

플랫폼 엔지니어링이 어떤 단위로 추상화할지를 결정한다면, GitOps는 그 추상화를 어떤 방식으로 운영할지를 규정합니다. CNCF OpenGitOps 프로젝트는 네 가지 원칙으로 GitOps를 정의합니다[^opengitops].

`Declarative`
:   시스템의 목표 상태를 절차가 아니라 최종 상태로 기술합니다. Kubernetes 매니페스트 YAML이 대표 예입니다.

`Versioned and Immutable`
:   선언된 상태는 버전 관리 시스템에 불변으로 저장되며 전체 이력이 보존됩니다. 과거 시점으로의 롤백과 변경 추적이 가능합니다.

`Pulled Automatically`
:   소프트웨어 에이전트가 소스에서 목표 상태를 자동으로 가져옵니다. 사용자가 직접 명령어로 배포하지 않고 에이전트가 Git 변경을 감지해 반영합니다.

`Continuously Reconciled`
:   에이전트가 실제 시스템 상태를 지속 관찰하면서 목표 상태와의 차이(drift)를 감지하면 자동으로 수정합니다.

네 번째 원칙인 Auto Reconciliation이 GitOps 에이전트의 실제 동작을 결정합니다. 운영자가 `kubectl`로 클러스터 상태를 직접 바꿔도 에이전트가 이를 drift로 판단해 Git의 정의로 되돌리므로, 클러스터 상태 변경은 Git 커밋을 거쳐야만 지속성을 가집니다.

```mermaid
flowchart LR
    Dev[Developer] -->|git push| Git[(Git repository<br/>desired state)]
    Git -.poll.-> Agent[GitOps Agent<br/>ArgoCD / Flux]
    Agent -->|apply| K8s[Kubernetes cluster]
    K8s -.observe.-> Agent
    Admin[Operator] -.manual change.-> K8s
    Agent -->|drift detected → revert| K8s
```

## Why GitOps for SaaS

SaaS 애플리케이션은 다수 테넌트를 동일한 프로세스로 관리해야 하고 고객에게는 지속적인 기능 공급을 약속합니다. 이 특성이 DevOps의 일반 요구와 맞물려 GitOps의 선언적 파이프라인이 유리해집니다.

`Frequent releases`
:   빠른 피드백과 기능 공급을 위해 릴리스 주기를 짧게 가져가야 합니다.

`Operational consistency`
:   같은 프로세스로 모든 테넌트를 다뤄야 개별 테넌트의 예외를 줄일 수 있습니다.

`Automated onboarding`
:   신규 테넌트 생성이 빠르고 일관되어야 테넌트 수 확장이 가능합니다.

### Deployment Models

SaaS 환경에서는 배포 모델에 따라 테넌트 온보딩 시 필요한 리소스 구성이 달라집니다. AWS가 SaaS on EKS 백서와 prescriptive guidance에서 권하는 세 모델은 다음과 같습니다[^saas-whitepaper] [^saas-hybrid].

| Model | Isolation | Cost | When to apply |
|---|---|---|---|
| Silo | High | High | Premium tier, 컴플라이언스 요구 고객 |
| Pool | Low | Low | Basic tier, 대량 고객 |
| Hybrid | Mixed | Mixed | 티어별로 Silo와 Pool을 혼합 |

Blux는 Standard 테넌트에 공유 리소스를 제공하고 Premium 테넌트에는 전용 리소스, Enterprise 테넌트에는 전용 고성능 리소스를 배정하는 혼합 모델을 채택했습니다. 티어별로 다른 격리 수준을 제공하면서 단일 클러스터에서 운영 비용을 제어하는 방식입니다.

![Tier-based deployment model](https://d2908q01vomqb2.cloudfront.net/77de68daecd823babbb58edb1c8e14d7106e83bb/2025/12/09/Fig6.png)
*[Source: AWS SaaS architecture patterns implementation on Amazon EKS — Blux](https://aws.amazon.com/blogs/apn/aws-saas-architecture-patterns-implementation-on-amazon-eks-blux-a-korean-startup/)*

Standard 티어는 공유 Recommender API와 Recommender Workload를 사용하고, Premium과 Enterprise 티어는 온보딩 시점에 전용 API와 Workload를 프로비저닝합니다.

단일 클러스터에서 티어별로 다른 배포 모델을 적용하려면 파이프라인이 테넌트마다 다른 매니페스트를 일관되게 생성하고 반영해야 합니다. GitOps가 이 요구에 부합합니다. 테넌트 구성은 Git 저장소의 파일로 표현되고, 테넌트 추가는 파일 생성과 커밋으로, 삭제는 파일 제거와 커밋으로 대체됩니다. 모든 변경이 이력에 남으므로 롤백과 감사가 자연스럽게 가능합니다.

## EKS GitOps Tools Landscape

EKS에서 GitOps를 구현할 수 있는 도구는 다양합니다. AWS prescriptive guidance는 아래 아홉 가지 도구를 비교 대상으로 제시합니다[^aws-pg-intro].

| Tool | Kubernetes focus | Characteristic |
|---|---|---|
| Argo CD | Strong | 웹 UI 중심, App-of-Apps, 멀티 클러스터 관리 |
| Flux v2 | Strong | CRD 조합형, Image Automation, Terraform 통합 |
| Weave GitOps | Strong | Flux 기반 엔터프라이즈 UI |
| Rancher Fleet | Strong | 수천 클러스터 대규모 관리 특화 |
| Jenkins X | Moderate | Jenkins 기반 풀 파이프라인 |
| GitLab CI/CD | Moderate | GitLab 플랫폼 통합 |
| Codefresh | Moderate | ArgoCD 기반 엔터프라이즈 SaaS |
| Pulumi | Moderate | 범용 프로그래밍 언어로 IaC 정의 |
| Spinnaker | Moderate | 멀티 클라우드, 복잡한 배포 전략 |

이 중 Argo CD와 Flux가 CNCF 졸업 프로젝트이자 실질적 표준입니다. AWS prescriptive guidance도 둘을 별도 문서로 상세 비교하고 있으며, 2025년 re:Invent에서는 [EKS Capability for Argo CD](https://docs.aws.amazon.com/eks/latest/userguide/argocd.html)가 공개되어 관리형 선택지가 하나 더 생겼습니다.

Week 6의 나머지 문서는 이 두 도구 중 ArgoCD를 중심으로, 다음과 같이 이어집니다.

- [ArgoCD: Architecture and Patterns](2_argocd.md) — 컴포넌트 구성, App-of-Apps, ApplicationSet, Flux 비교, EKS Managed 모드
- [ArgoCD Ecosystem Extensions](3_argocd-extensions.md) — Argo Rollouts, Image Updater, GitOps Bridge, kro, ACK
- [Event-Driven Workflows](4_argo-workflows.md) — Argo Workflows와 Argo Events로 구현하는 테넌트 온보딩 자동화
- Lab — ArgoCD 기반 미니 SaaS 재현 (준비 중)

[^opengitops]: [OpenGitOps — Principles v1.0.0](https://opengitops.dev/)
[^aws-pg-intro]: [AWS Prescriptive Guidance — Choosing the right GitOps tool for your Amazon EKS cluster](https://docs.aws.amazon.com/prescriptive-guidance/latest/eks-gitops-tools/introduction.html)
[^saas-whitepaper]: [AWS Whitepaper — Security Practices for Multi-Tenant SaaS Applications using Amazon EKS](https://docs.aws.amazon.com/whitepapers/latest/security-practices-multi-tenant-saas-applications-eks/security-practices-multi-tenant-saas-applications-eks.html)
[^saas-hybrid]: [AWS Prescriptive Guidance — Hybrid model multi-tenancy](https://docs.aws.amazon.com/prescriptive-guidance/latest/multi-tenancy-amazon-neptune/hybrid-model.html)
