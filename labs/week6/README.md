# Week 6 — ArgoCD Mini SaaS Lab

GitOps 원칙(OpenGitOps 4 principles)을 ArgoCD 생태계로 실습하는 랩입니다. 상세 해설은 [docs/week6/5_lab.md](../../docs/week6/5_lab.md) 를 참고하세요.

## Scenarios

| Scenario | 주제 | 핵심 기술 |
|----------|------|----------|
| 0. GitOps Bridge 부트스트랩 | Terraform → ArgoCD 상태 인계 | `helm_release.argocd`, cluster Secret annotations/labels |
| 1. App-of-Apps 계층 | root-app → projects / addons / tenants | `Application`, `AppProject`, sync waves |
| 2. ApplicationSet staggered 3-tier 배포 | basic / advanced / premium tier sync-wave | ApplicationSet Git generator, Helm |
| 3. SQS 이벤트 기반 테넌트 온보딩 | 메시지 → Workflow → values 커밋 → 자동 배포 | Argo Events, Argo Workflows |
| 4. Image Updater 로 ECR 태그 자동 반영 | 새 이미지 푸시 → Git write-back → 재동기화 | argocd-image-updater, ECR |
| 5. Rollouts ALB canary + Analysis | ALB traffic 분할 + Job provider 자동 롤백 | Argo Rollouts, ALB, AnalysisTemplate |

## Prerequisites

- AWS 계정 (`ap-northeast-2`)
- 공개 도메인 + Route53 Hosted Zone (`TF_VAR_MyDomain`)
- Git 저장소 하나 (`TF_VAR_GitOpsRepoURL`). 이 저장소에 `manifests/` 디렉터리를 커밋합니다.
- `terraform`, `kubectl`, `helm`, `awscli`, `jq`, `gh`
- `argocd` CLI, `kubectl argo rollouts` plugin

## Layout

```
labs/week6/
├── 00_env.sh
├── *.tf                     # provider / vpc / eks / iam / lbc / aws / gitops-bridge
├── scripts/99_teardown.sh
└── manifests/
    ├── 01_bootstrap/        # root App-of-Apps + projects + addon ApplicationSets
    ├── 02_tenants/          # ApplicationSet + helm-tenant-chart + 3-tier values
    ├── 03_onboarding/       # EventBus / EventSource / Sensor / WorkflowTemplate
    ├── 04_image-updater/    # annotated Application + sample deployment
    └── 05_rollouts/         # Rollout + ALB Ingress + Job-provider AnalysisTemplate
```

## Setup

```bash
cd labs/week6

export TF_VAR_MyDomain="your-domain.com"
export TF_VAR_GitOpsRepoURL="https://github.com/you/gitops-lab.git"

terraform init
terraform apply

source 00_env.sh
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"

# 랩용 Git 저장소에 본 labs/week6/manifests/ 전체를 커밋 후 root-app.yaml 의 repoURL 값을 교체합니다.
kubectl apply -f manifests/01_bootstrap/root-app.yaml
```

이후 각 시나리오는 [docs/week6/5_lab.md](../../docs/week6/5_lab.md) 의 Reproduction 블록대로 진행합니다.

## Cost Warning

ALB 1개(Scenario 5), NAT Gateway 1개, Managed Node Group 1개(t3.large × 3)가 기본 과금 대상입니다. SQS/ECR 비용은 실습 수준에서 무시 가능합니다. 2 ~ 4 시간 내에 teardown을 권장합니다.

## Teardown

```bash
./scripts/99_teardown.sh
```

스크립트는 Kubernetes 리소스(Ingress/Rollout/Application 포함)를 먼저 정리해 ALB 를 해제한 뒤 `terraform destroy` 를 실행합니다. Git 저장소에 생성된 온보딩 values 파일(`manifests/02_tenants/values/*.yaml`)은 실습 흔적 보존을 위해 자동으로 되돌리지 않습니다.
