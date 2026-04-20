# Week 5 — Migration Incident Lab

EKS 운영 중 마이그레이션에서 발생할 수 있는 장애를 재현하는 랩입니다. 상세 해설은 [docs/week5/5_lab.md](../../docs/week5/5_lab.md) 를 참고하세요.

## Scenarios

| Scenario | 주제 | Incident |
|----------|------|----------|
| Scenario 1 | Ingress(ALB) → Gateway API | Rolling update 5xx (readiness gate, preStop) |
| Scenario 2 | Cluster Autoscaler → Karpenter | Consolidation blocked by overly strict PDB |

## Prerequisites

- AWS 계정 (`ap-northeast-2`)
- 공개 도메인 + Route53 Hosted Zone + ACM wildcard 인증서
- `terraform`, `kubectl`, `helm`, `awscli`, `jq`
- `mise` 또는 환경 변수 `TF_VAR_MyDomain`

## Layout

```
labs/week5/
├── 00_env.sh
├── *.tf
├── scripts/
│   ├── 01_install-gateway-crd.sh
│   ├── 02_install-cas.sh
│   └── 03_install-karpenter.sh
└── manifests/
    ├── scenario1/
    │   ├── deployment.yaml
    │   ├── ingress.yaml
    │   ├── gateway.yaml
    │   ├── httproute.yaml
    │   └── rolling-update-5xx.yaml
    └── scenario2/
        ├── pdb.yaml
        ├── workload.yaml
        ├── ec2nodeclass.yaml
        ├── nodepool.yaml
        └── consolidation-pdb-violation.yaml
```

## Setup

```bash
cd labs/week5
terraform init
terraform apply
source 00_env.sh
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"

./scripts/01_install-gateway-crd.sh
./scripts/02_install-cas.sh
./scripts/03_install-karpenter.sh
```

이후 각 시나리오는 [docs/week5/5_lab.md](../../docs/week5/5_lab.md) 의 Reproduction 블록대로 진행합니다.

## Cost Warning

랩 운영 중에는 ALB 2 개, NAT Gateway 1 개, Managed Node Group 2 개, Karpenter EC2 인스턴스가 동시에 과금됩니다. 2 ~ 3 시간 내에 `terraform destroy` 로 정리합니다.

## Teardown

Terraform 이 ALB 를 직접 관리하지 않으므로 Kubernetes 리소스를 먼저 정리한 뒤 Terraform 을 실행합니다.

```bash
kubectl delete httproute,gateway,ingress -A --all
kubectl delete nodepool --all
kubectl delete ec2nodeclass --all
helm -n kube-system uninstall cluster-autoscaler karpenter aws-load-balancer-controller || true
terraform destroy
```
