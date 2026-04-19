# Week 5 — Migration Incident Lab

5주차 주제인 **EKS 운영 중 경험한 장애/이슈에 대한 기술적 대응**을 가상 시나리오로 재현합니다. 두 가지 마이그레이션 흐름을 실제로 밟으면서, 각 단계에서 의도적 오설정을 적용하고 진단과 복구를 수행하는 방식으로 진행합니다.

## Documents

- **[docs/week5/5_lab.md](../../docs/week5/5_lab.md)** — 사후 보고 형식의 사례 narrative. 각 incident의 상황, 탐지, 원인, 교훈, 재현 절차가 정리되어 있습니다.
- 이 README — 랩 진행을 위한 환경 구성과 실행 순서

## Scenarios

| 번호 | 주제 | 핵심 incident |
|------|------|---------------|
| [Scenario 1](./manifests/scenario1/) | Ingress(ALB) → Gateway API | Rolling update 5xx (readiness gate), Hostname claim conflict |
| [Scenario 2](./manifests/scenario2/) | Cluster Autoscaler → Karpenter | PDB 설계 결함(과도한 엄격), NodeClaim Launch Failure |

## Prerequisites

- AWS 계정 (`ap-northeast-2` 기준)
- 공개 도메인 + Route53 Hosted Zone + ACM Wildcard 인증서
- `terraform`, `kubectl`, `helm`, `awscli`, `jq`
- `mise` 또는 환경 변수 `TF_VAR_MyDomain` 설정

## Directory

```
labs/week5/
├── 00_env.sh                    # 환경 변수 로딩 (source 로 실행)
├── provider.tf / variables.tf / vpc.tf / outputs.tf
├── eks.tf / iam.tf / karpenter.tf / lbc.tf
├── scripts/
│   ├── 01_install-gateway-crd.sh
│   ├── 02_install-external-dns.sh
│   ├── 03_install-cas.sh
│   └── 04_install-karpenter.sh
└── manifests/
    ├── scenario1/
    └── scenario2/
```

## Progression

1. **Terraform apply** — 클러스터 + 2개 Managed NG (`ng-cas`, `ng-system`) + Karpenter IAM + LBC Helm + Pod Identity association 생성

    ```bash
    cd labs/week5
    terraform init
    terraform apply
    source 00_env.sh
    aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"
    ```

2. **Controller / add-on 설치**

    ```bash
    ./scripts/01_install-gateway-crd.sh
    ./scripts/02_install-external-dns.sh
    ./scripts/03_install-cas.sh
    ./scripts/04_install-karpenter.sh
    ```

3. **Scenario 1** — [manifests/scenario1/README.md](./manifests/scenario1/README.md) 참조

4. **Scenario 2** — [manifests/scenario2/README.md](./manifests/scenario2/README.md) 참조

## Docs Mapping

각 incident는 `docs/week5/`의 다음 섹션과 연결됩니다. 진행 중에 이론이 모호하면 해당 문서를 먼저 열어 맥락을 맞춘 뒤 실습합니다.

| Incident | 연결 문서 |
|----------|----------|
| S1 #1 Rolling update 5xx | `3_availability-and-scale.md` — Zero 5xx on Rolling Update |
| S1 #2 Hostname claim conflict | `3_availability-and-scale.md` — IP target type |
| S2 #1 PDB 차단 | `3_availability-and-scale.md` — Rate-limit with PDB |
| S2 #2 NodeClaim Launch Failure | `1_common-failures.md` — Scoping Before Diagnosis |
| 관찰/알림 설계 | `4_observability-and-aiops.md` — Alert Design at Scale |

## Cost Warning

본 랩은 다음 자원을 동시에 사용합니다.

- ALB 2개 (Ingress와 Gateway 공존 구간)
- NAT Gateway 1개
- Managed Node Group 2개 (`ng-cas`, `ng-system`)
- Karpenter-provisioned EC2 (spot / on-demand)

2~3시간 내에 `terraform destroy`로 정리하는 것을 권장합니다.

## Teardown

!!! warning "Destroy order matters"

    `terraform destroy`를 바로 실행하면 ALB와 target group이 남아 VPC 삭제가 실패합니다. 아래 순서를 반드시 지킵니다.

1. Gateway API와 Ingress 리소스를 먼저 삭제해 ALB를 정리합니다.

    ```bash
    kubectl delete httproute,gateway,ingress -A --all
    ```

2. Karpenter NodePool을 삭제해 Karpenter 노드를 drain합니다.

    ```bash
    kubectl delete nodepool --all
    kubectl delete ec2nodeclass --all
    ```

3. Helm release를 uninstall합니다.

    ```bash
    helm -n kube-system uninstall cluster-autoscaler karpenter aws-load-balancer-controller || true
    helm -n external-dns uninstall external-dns || true
    ```

4. Terraform 리소스를 정리합니다.

    ```bash
    terraform destroy
    ```
