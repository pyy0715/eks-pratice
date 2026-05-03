<!-- WEEK: 7 -->
<!-- TOPIC: eks-upgrade -->
<!-- CREATED: 2026-04-30 -->

## Reference Documents (AWS Official)

- [Update existing cluster to new Kubernetes version](https://docs.aws.amazon.com/eks/latest/userguide/update-cluster.html)
- [Best Practices for Cluster Upgrades](https://docs.aws.amazon.com/eks/latest/best-practices/cluster-upgrades.html)
- [Cluster Insights for upgrade readiness](https://docs.aws.amazon.com/eks/latest/userguide/cluster-insights.html)
- [Kubernetes version lifecycle on EKS](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)
- [EKS Auto Mode upgrades](https://docs.aws.amazon.com/eks/latest/userguide/auto-upgrade.html)
- [Cluster upgrade policy (Standard vs Extended)](https://docs.aws.amazon.com/eks/latest/userguide/view-upgrade-policy.html)
- [EKS enforces upgrade insights checks (2025-03)](https://aws.amazon.com/about-aws/whats-new/2025/03/amazon-eks-enforces-upgrade-insights-check-cluster-upgrades/)
- [eksctl cluster upgrades](https://docs.aws.amazon.com/eks/latest/eksctl/cluster-upgrade.html)

---

## Workshop Environment

- Workshop: Amazon EKS Upgrades Workshop (catalog.workshops.aws)
- Region: us-west-2
- Cluster name: eksworkshop-eksctl
- Cluster version: 1.30 (upgrade target TBD)
- IaC: Terraform (terraform/ 디렉터리)

### Node Composition (v1.30.14-eks-f69f56f)

| Type | Node Group / Pool | Count |
|------|-------------------|-------|
| Managed Node Group | initial-* | 2 |
| Managed Node Group | blue-mng-* | 1 |
| Self-managed | (no label) | 2 |
| Karpenter | default | 1 |
| Fargate | (no label) | 1 |

### Pre-installed Add-ons (Helm)

| Name | Namespace | Chart Version | App Version |
|------|-----------|---------------|-------------|
| argo-cd | argocd | 5.55.0 | v2.10.0 |
| aws-efs-csi-driver | kube-system | 2.5.6 | 1.7.6 |
| aws-load-balancer-controller | kube-system | 1.7.1 | v2.7.1 |
| karpenter | karpenter | 1.0.0 | 1.0.0 |
| metrics-server | kube-system | 3.12.0 | 0.7.0 |

### Terraform Files

- vpc.tf, versions.tf, variables.tf, outputs.tf
- base.tf — EKS cluster, node groups
- addons.tf — add-on 구성
- gitops-setup.tf — ArgoCD/Flux 연동
- backend_override.tf

---

## Sample Application

- 간단한 웹 스토어 애플리케이션 (catalog, cart, checkout, orders, UI, static assets)
- 모든 컴포넌트가 ArgoCD를 통해 EKS 클러스터에 배포됨
- GitOps repo: AWS CodeCommit (eks-gitops-repo)
- ArgoCD: argocd 네임스페이스, LoadBalancer로 노출
- 초기 상태: AWS 서비스(LB, managed DB 등) 없이 클러스터 내부에 자체 완결
- 소스코드: GitHub 공개

---

## Introduction — Kubernetes Release Cycles & EKS Support

### Kubernetes 릴리스 주기
- Semantic Versioning: x.y.z (major.minor.patch)
- 새 minor 버전: ~4개월마다 릴리스
- v1.19 이상: 12개월 standard support, 최근 3개 minor 버전 유지

### Amazon EKS 릴리스 & 지원
- EKS는 Kubernetes 릴리스 주기를 따르되, 4개 minor 버전 동시 지원 (14개월)
- upstream보다 수 주 늦게 릴리스 (AWS 서비스 호환성 테스트)
- Extended Support: standard support 종료 후 12개월 추가 (총 26개월)
  - v1.21 이상 적용
  - Extended 가격: $0.60/cluster/hour (Standard: $0.10)
  - Extended 종료까지 미업그레이드 시 자동 업그레이드
- Platform Version: minor 버전 내 eks.1, eks.2 등 — EKS가 자동 업그레이드

### Kubernetes Version Policy (2024-07-23)
- supportType 속성으로 end-of-standard-support 동작 제어
  - STANDARD: standard support 종료 시 자동 업그레이드, extended 과금 없음
  - EXTENDED: extended support 진입, 추가 과금 발생, extended 종료 시 자동 업그레이드

### Why Upgrade — Shared Responsibility
- Control Plane: AWS 관리 (업그레이드 시 AWS가 수행)
- Data Plane: 사용자 책임 (Self-managed, MNG, Fargate, add-ons)
  - Karpenter: Drift / Disruption Controller (spec.expireAfter)로 자동 노드 교체 가능
  - PodDisruptionBudgets, topologySpreadConstraints 필수

### In-place Upgrade Workflow (High Level)
1. Kubernetes & EKS release notes 검토 + Before Upgrading 사전 점검
2. 클러스터 백업 (선택)
3. Control Plane 업그레이드 (Console/CLI)
4. Add-on 호환성 확인 및 업그레이드
5. Data Plane 업그레이드
- 추가: API deprecation/remediation, version skew 체크 등

---

## Preparing for Cluster Upgrades

### 사전 요구사항
- 클러스터 생성 시 지정한 서브넷에서 최소 5개 IP 여유 필요
- 클러스터 IAM role, security group이 계정에 존재해야 함
- Secrets encryption 활성화 시 IAM role에 KMS 키 권한 필요

### Upgrade Workflow (상세)
1. EKS / Kubernetes 주요 변경사항 확인
2. Deprecation policy 이해 및 매니페스트 리팩터링
3. Control Plane + Data Plane 업그레이드 (적절한 전략 선택)
4. 다운스트림 add-on 의존성 업그레이드

### EKS Upgrade Insights
- 자동 반복 검사: EKS가 관리하는 curated insight 목록 기반
- 매일 클러스터 audit log 스캔 → deprecated resource 탐지
- Console Upgrade Insights 탭 또는 API/CLI로 조회
- 수동 refresh 불가, 수정 후 자동 반영까지 시간 소요

#### Insight 항목 (v1.31 대상)
- Kubelet version skew
- Cluster health issues
- Amazon Linux 2 compatibility (AL2 EoS 2025-11-26, 1.33부터 AL2 AMI 미제공)
- kube-proxy version skew
- EKS add-on version compatibility

#### Insight 상태값
- ERROR: 다음 minor에서 제거된 API 사용 중 — 업그레이드 실패 가능
- WARNING: 2+ 릴리스 후 deprecation 예정 — 즉시 조치 불필요
- UNKNOWN: 백엔드 처리 오류

#### kubectl-convert
- deprecated API를 사용하는 매니페스트를 새 API 버전으로 자동 변환
- 사용법: `kubectl convert -f <file> --output-version <group>/<version>`
- 변환 후 `kubectl apply` 재적용 필요
- 원본 매니페스트 백업 권장

### Add-on 호환성 확인

#### 주요 Add-on 업그레이드 참고
- VPC CNI: single minor version bump만 가능
- kube-proxy: self-managed add-on 업데이트 문서
- CoreDNS: self-managed add-on 업데이트 문서
- AWS LB Controller: EKS 버전별 호환성 확인
- EBS/EFS CSI Driver: EKS add-on으로 관리
- Metrics Server: GitHub releases
- Cluster Autoscaler: image version 변경, 스케줄러와 밀접하므로 클러스터와 함께 업그레이드
- Karpenter: Karpenter 문서 참조

### 사전 검증 항목

#### 1. 서브넷 가용 IP 확인
```bash
aws ec2 describe-subnets --subnet-ids \
  $(aws eks describe-cluster --name ${CLUSTER_NAME} \
  --query 'cluster.resourcesVpcConfig.subnetIds' --output text) \
  --query 'Subnets[*].[SubnetId,AvailabilityZone,AvailableIpAddressCount]' \
  --output table
```
- IP 부족 시: UpdateClusterConfiguration API로 새 서브넷 추가
- 새 서브넷 조건: 동일 AZ, 동일 VPC
- 추가 CIDR 블록 연결로 IP 풀 확장 가능

#### 2. IAM Role 확인
```bash
ROLE_ARN=$(aws eks describe-cluster --name ${CLUSTER_NAME} \
  --query 'cluster.roleArn' --output text)
aws iam get-role --role-name ${ROLE_ARN##*/} \
  --query 'Role.AssumeRolePolicyDocument'
```
- eks.amazonaws.com이 AssumeRole 가능해야 함

#### 3. Security Group
- EKS 생성 시 자동 생성: eks-cluster-sg-{name}-{uniqueID}
- 기본 규칙: control plane ↔ node 간 모든 트래픽 허용 (인바운드/아웃바운드)
- MNG ENI에도 자동 연결
- 커스텀 SG 지정 가능하나 node group에는 별도 관리 필요
- 아웃바운드 제한 시: 노드 간 통신, ECR/인터넷 접근, IPv4/IPv6 별도 룰 필요

---

## HA Strategies & Upgrade Strategy 선택

### Blue/Green Cluster 전략
- 새 클러스터(green) 생성 → 워크로드 이관 → 트래픽 전환 → 구 클러스터(blue) 폐기

#### 장점
- 여러 minor 버전 한 번에 점프 가능 (e.g. 1.30→1.33)
- 구 클러스터로 즉시 롤백 가능
- 새 IaC 체계(Terraform 등)로 재구성 가능
- 워크로드 개별 마이그레이션 가능

#### 단점
- API endpoint, OIDC 변경 → kubectl, CI/CD 등 소비자 업데이트 필요
- 병행 운영 비용 증가 + 리전 용량 제약
- 워크로드 간 의존성이 있으면 동시 마이그레이션 조율 필요
- LB, External DNS가 다중 클러스터 간 분산 어려움
- Stateful 워크로드: Velero 등으로 PV 데이터 백업/동기화 필요

### In-Place Upgrade 전략
- 기존 클러스터 내에서 Control Plane → Data Plane 순차 업그레이드

#### 장점
- 기존 리소스(VPC, 서브넷, SG) 유지
- API endpoint 동일 → 외부 통합 변경 최소
- 인프라 오버헤드 적음
- Stateful 앱 마이그레이션 불필요

#### 단점
- 다운타임 최소화를 위한 세밀한 계획 필요
- 여러 버전 건너뛸 수 없음 (순차 업그레이드)
- Control Plane 업그레이드 후 롤백 불가
- 모든 컴포넌트/의존성 호환성 검증 필수

### 전략 선택 기준

| Factor | In-Place | Blue/Green |
|--------|----------|------------|
| Downtime tolerance | 짧은 중단 허용 시 | 무중단 요구 시 |
| Version gap | 1 minor | 여러 minor 가능 |
| Stateful workloads | 유리 | 데이터 마이그레이션 필요 |
| Cost | 낮음 | 병행 클러스터 비용 |
| Rollback | CP 롤백 불가 | 트래픽 전환으로 즉시 롤백 |
| Team expertise | 단일 클러스터 운영 | 다중 클러스터 + 트래픽 관리 |

### 앱 배포 방식 — GitOps (ArgoCD)
- 이 워크샵은 ArgoCD 기반 GitOps로 앱 롤아웃 관리
- CodeCommit repo가 single source of truth
- 업그레이드 과정에서 매니페스트 변경 → git push → argocd sync

### PDB 구성 (워크로드 가용성 보장)
- PodDisruptionBudget + TopologySpreadConstraints로 data plane 업그레이드 중 가용성 확보
- 워크샵 예시: orders 서비스에 minAvailable: 1 PDB 적용
  - GitOps repo에 pdb.yaml 추가 → kustomization.yaml 수정 → commit/push → argocd sync
- 검증: `kubectl drain` 으로 노드 drain 시도 → PDB 위반으로 eviction 거부 확인
  - "Cannot evict pod as it would violate the pod's disruption budget"
- 테스트 후 `kubectl uncordon` 으로 노드 복원

---

## Incremental In-Place Upgrade (Version Skew 활용)

### 개념
- Kubernetes version skew: control plane이 worker node보다 최대 2 minor 버전 앞설 수 있음
- 여러 버전 뒤처진 경우, CP만 먼저 순차 업그레이드하고 노드 업그레이드를 지연시키는 전략

### 절차
1. CP를 다음 minor로 업그레이드 (노드는 유지)
2. skew 한도 내에서 CP를 계속 업그레이드 (e.g. CP 1.30→1.31→1.32, 노드 1.30 유지)
3. skew 초과 직전(e.g. CP 1.33이면 노드 1.30은 불가) 노드를 skew 범위 내로 업그레이드
4. 1~3 반복하여 목표 버전 도달

### 적합한 상황
- 여러 버전 뒤처진 클러스터를 점진적으로 따라잡을 때
- 복잡한 stateful 워크로드로 잦은 노드 업그레이드가 어려울 때
- CP 신기능/보안 패치를 먼저 적용하면서 노드 영향 최소화

### 주의사항
- 새 기능/성능 개선이 노드 업그레이드 전까지 완전히 사용 불가능할 수 있음
- 노드 여러 버전 한번에 업그레이드 시 철저한 테스트 필수
- CP-노드 버전 차이를 최소로 유지하는 것이 권장

---

## In-place Control Plane Upgrade (실습)

### 사전 점검
1. Kubernetes & EKS release notes 확인
2. Add-on 호환성 확인
3. Deprecated/removed API 식별 및 리팩터링
4. 클러스터 백업 (선택)

### Control Plane 업그레이드 메커니즘
- AWS가 내부적으로 blue/green 방식으로 수행
- 업그레이드 중 API server endpoint 유지 → 앱 가용성 유지
- 실패 시 자동 롤백 (새 CP 컴포넌트 종료, 구 CP 유지)
- 한 번에 1 minor 버전만 가능

### 업그레이드 방법 3가지
1. eksctl: `eksctl upgrade cluster --name $CLUSTER_NAME --approve`
2. Console: EKS > 클러스터 > Upgrade now
3. AWS CLI: `aws eks update-cluster-version --name $CLUSTER_NAME --kubernetes-version 1.31`
   - 상태 확인: `aws eks describe-update --name $CLUSTER_NAME --update-id <id>`

### Terraform을 이용한 업그레이드 (워크샵 실습)
1. `variables.tf`에서 `cluster_version`을 `1.30` → `1.31`로 변경
2. `terraform plan` — CP, MNG, add-ons 등 변경 사항 확인
3. `terraform apply -auto-approve` — 10~15분 소요
4. Console에서 CP 버전 1.31 확인

- Terraform에서 MNG에 별도 AMI/version 미지정 시 CP와 함께 업그레이드 대상에 포함
- 이 워크샵에서는 CP만 먼저 올리고, add-on → data plane 순서로 진행

---

## EKS Add-on 업그레이드

### 개요
- K8s 클러스터에 네트워킹, 컴퓨팅, 스토리지 등 운영 기능을 제공하는 소프트웨어
- Amazon EKS add-on: AWS가 관리하는 add-on으로, 보안/안정성 보장 및 설치/업데이트 간소화

### 업그레이드 대상 (워크샵)
- CoreDNS
- kube-proxy
- VPC CNI

### 호환 버전 조회 방법
```bash
# CoreDNS
aws eks describe-addon-versions --addon-name coredns \
  --kubernetes-version 1.31 --output table \
  --query "addons[].addonVersions[:10].{Version:addonVersion,DefaultVersion:compatibilities[0].defaultVersion}"

# kube-proxy
aws eks describe-addon-versions --addon-name kube-proxy \
  --kubernetes-version 1.31 --output table \
  --query "addons[].addonVersions[:10].{Version:addonVersion,DefaultVersion:compatibilities[0].defaultVersion}"
```

### Terraform으로 업그레이드
1. `addons.tf`에서 CoreDNS, kube-proxy, VPC CNI 버전을 최신 호환 버전으로 변경
2. `terraform plan && terraform apply -auto-approve`
3. 업그레이드 후 로그/메트릭 모니터링으로 정상 동작 확인

---

## Managed Node Group 업그레이드

### MNG 업그레이드 메커니즘 (In-Place Rolling Update)
- 자동화된 incremental rolling update — 4단계 프로세스

#### 1. Setup Phase
- 새 EC2 Launch Template 버전 생성 (대상 AMI 반영)
- ASG를 최신 launch template으로 업데이트
- `updateConfig` 속성으로 병렬 업그레이드 노드 수 설정 (최대 100)

#### 2. Scale Up Phase
- ASG max/desired를 증가 (AZ 수의 2배 또는 max_unavailable 중 큰 값)
- 새 설정 노드가 Ready 될 때까지 대기
- 기존 노드를 unschedulable 표시 + `node.kubernetes.io/exclude-from-external-load-balancers=true` 레이블

#### 3. Upgrade Phase
- 랜덤으로 업그레이드 대상 노드 선택 (max_unavailable까지)
- Pod drain (15분 타임아웃, 초과 시 PodEvictionFailure — force 옵션으로 우회 가능)
- 노드 cordon → 60초 대기 (서비스 컨트롤러 업데이트 시간)
- ASG에 종료 요청
- 모든 구 버전 노드가 교체될 때까지 반복

#### 4. Scale Down Phase
- ASG max/desired를 원래 값으로 복원

### 업그레이드 방법
1. eksctl: `eksctl upgrade nodegroup --name=<ng> --cluster=$CLUSTER_NAME`
2. Console: EKS > Compute > Node groups > Update now (Rolling/Force 선택)
3. Terraform (워크샵)

### 실습 1: In-Place MNG 업그레이드 (Terraform)

#### 두 가지 시나리오
- **Default AMI**: `mng_cluster_version` 변수만 변경 → 자동으로 최신 EKS-optimized AMI 사용
- **Custom AMI**: 특정 AMI ID를 지정한 MNG는 AMI ID도 함께 변경 필요

#### Custom MNG 생성
```bash
# v1.30용 최신 AMI 조회
aws ssm get-parameter \
  --name /aws/service/eks/optimized-ami/1.30/amazon-linux-2023/x86_64/standard/recommended/image_id \
  --region $AWS_REGION --query "Parameter.Value" --output text
```
- base.tf에 custom MNG 추가 (ami_id, ami_type, enable_bootstrap_user_data 지정)

#### 업그레이드 절차
1. `variables.tf`에서 `mng_cluster_version`을 `1.30` → `1.31`로 변경
2. v1.31용 AMI 조회 후 `ami_id` 변수도 업데이트
3. `terraform plan && terraform apply -auto-approve`
4. initial MNG + custom MNG 모두 1.31로 업그레이드 확인

#### 핵심 포인트
- custom AMI를 지정한 MNG는 `mng_cluster_version`만 바꿔도 업그레이드되지 않음 — AMI ID도 변경 필요
- default AMI MNG는 `eks_managed_node_group_defaults.cluster_version` 따라감

### 실습 2: Blue/Green MNG 업그레이드

#### 시나리오
- blue-mng (v1.30): stateful workload (orders + mysql), taint/label 적용, 단일 AZ
- green-mng 생성 (v1.31): 동일 taint/label/AZ로 프로비저닝
- blue-mng 삭제 → 자동 cordon/drain → Pod가 green-mng으로 이동

#### 절차
1. green-mng를 base.tf에 추가 (blue-mng과 동일 labels, taints, subnet_ids, cluster_version은 default=1.31)
2. `terraform apply` → green-mng 생성
3. 두 노드 그룹 모두 `type=OrdersMNG` 레이블, `dedicated=OrdersApp:NoSchedule` taint 확인
4. PDB가 있으면 orders replica를 2로 증가 (PDB minAvailable=1 위반 방지)
   - `sed -i 's/replicas: 1/replicas: 2/' apps/orders/deployment.yaml` → git push → argocd sync
5. base.tf에서 blue-mng 제거 → `terraform apply`
6. EKS가 자동으로 blue-mng 노드 cordon/drain/delete
7. orders Pod가 green-mng 노드(v1.31)에서 실행 확인

#### Best Practice
- Stateful 워크로드용 MNG는 AZ별로 분리 프로비저닝 권장
- Blue/Green 전환 시 PDB replica 조정으로 가용성 보장

---

## Karpenter Managed Node 업그레이드

### Karpenter 노드 업그레이드 메커니즘

#### Drift
- EC2NodeClass의 AMI 설정이 변경되면 Karpenter가 기존 노드의 drift를 감지
- 새 노드 프로비저닝 → Pod eviction → 구 노드 종료 (rolling deployment 방식)

#### AMI 선택 방식 두 가지
1. **amiSelectorTerms (명시적 AMI 지정)**: AMI ID, name, tag로 지정. 변경 시 drift 발생.
   - 프로덕션 환경에서 AMI 승격을 제어할 때 적합
2. **alias (EKS optimized AMI)**: `family@version` 형식 (e.g. `al2023@latest`)
   - `latest` 핀: SSM 파라미터 모니터링 → 새 AMI 릴리스 시 자동 drift
   - 프리프로덕션에 적합, 프로덕션에서는 특정 버전 핀 권장

#### TTL (expireAfter)
- NodePool의 `spec.disruption.expireAfter`로 노드 수명 설정
- 만료 시 자동 교체 → 주기적 보안 패치 적용 수단

#### Disruption Budgets
- NodePool의 `spec.disruption.budgets`로 disruption 속도/시간 제어
- 미정의 시 기본값: `nodes: 10%`
- `reasons` 필드로 Drifted, Underutilized, Empty 별도 제어 가능

##### 예시 패턴
| 패턴 | 설정 |
|------|------|
| 업무시간 disruption 금지 | `schedule: "0 9 * * mon-fri"`, `duration: 8h`, `nodes: 0` |
| Drift는 1개씩, Empty/Underutilized는 전체 | reasons별 nodes 분리 |
| 완전 disruption 차단 | `nodes: 0` (reasons 없음) |

### 실습: Karpenter 노드 업그레이드

#### 초기 상태
- default NodePool + EC2NodeClass로 checkout 앱 실행
- 노드: v1.30, taint `dedicated=CheckoutApp:NoSchedule`, label `team=checkout`
- checkout은 stateful (PV 부착)

#### 절차
1. checkout replica를 1→10으로 scale up → Karpenter가 추가 노드 프로비저닝 (2개 노드)
2. v1.31 AMI ID 조회: SSM 파라미터에서 가져옴
3. EC2NodeClass (`default-ec2nc.yaml`)의 `amiSelectorTerms`에 v1.31 AMI 설정
4. NodePool (`default-np.yaml`)에 disruption budget 추가:
   ```yaml
   budgets:
     - nodes: "1"
       reasons:
       - Drifted
   ```
5. git commit/push → argocd sync karpenter
6. Karpenter 로그에서 drift 감지 → 노드 1개씩 교체 확인:
   - 새 노드 생성 → 구 노드 taint(`karpenter.sh/disrupted:NoSchedule`) → Pod eviction → 구 노드 삭제
   - 첫 번째 노드 교체 완료 후 두 번째 노드 교체 시작
7. 최종: 모든 checkout Pod가 v1.31 노드에서 실행

---

## Self-managed Node 업그레이드

### 개요
- self-managed 노드: `node.kubernetes.io/lifecycle=self-managed` 레이블
- 워크샵에서 carts 앱이 self-managed 노드에서 실행

### 업그레이드 절차 (Terraform)
1. v1.31 AMI ID 조회 (SSM 파라미터)
2. `base.tf`의 self-managed node group AMI를 새 ID로 변경
3. `terraform plan && terraform apply -auto-approve`
4. 새 노드(v1.31) 확인: `kubectl get nodes -l node.kubernetes.io/lifecycle=self-managed`

- Terraform이 ASG의 Launch Template을 업데이트하고 인스턴스를 교체

---

## Fargate Node 업그레이드

### 특징
- Fargate 노드는 별도의 AMI 관리 불필요
- CP 업그레이드 후, Pod를 재시작하면 새 Fargate 노드가 최신 K8s 버전으로 프로비저닝

### 절차
1. 기존 Fargate Pod 확인: assets 앱 (v1.30)
2. Deployment 재시작: `kubectl rollout restart deployment assets -n assets`
3. 새 Pod Ready 대기: `kubectl wait --for=condition=Ready pods --all -n assets --timeout=180s`
4. 새 Fargate 노드 버전 확인: v1.31로 자동 업그레이드됨

### 핵심
- Fargate는 Pod 단위 인프라이므로, deployment restart만으로 노드 업그레이드 완료
- CP 버전과 자동으로 일치

---

## Blue/Green Cluster Upgrade (실습)

### 개요
- In-place와 달리 새 클러스터(green)를 생성하여 여러 minor 버전 한 번에 점프 가능
- 워크샵: blue(v1.31) → green(v1.32) 클러스터 생성
- 동일 VPC에 생성하여 네트워크, SG, NAT, VPN, DNS 등 기존 리소스 재활용

### Green 클러스터 생성
1. EFS File System ID 확보 (blue 클러스터 생성 시 함께 프로비저닝됨)
   ```bash
   export EFS_ID=$(aws efs describe-file-systems --query "FileSystems[*].FileSystemId" --output text)
   ```
2. `eksgreen-terraform/` 디렉터리에 v1.32 클러스터 Terraform 코드 준비
3. `terraform init && terraform apply -var efs_id=$EFS_ID -auto-approve` (20~30분 소요)
4. kubectl context 설정: blue/green alias
   ```bash
   aws eks update-kubeconfig --name $CLUSTER_NAME --alias blue
   aws eks update-kubeconfig --name ${CLUSTER_NAME}-gr --alias green
   ```
5. green 클러스터 노드 v1.32 확인, add-on(ArgoCD, EFS CSI, LB Controller, Karpenter, Metrics Server) 설치 확인

### Stateless Workload Migration

#### GitOps 브랜치 전략
1. `eks-gitops-repo`에서 `green` 브랜치 생성
2. green 브랜치에서 v1.32 호환 변경 적용:
   - Karpenter EC2NodeClass: v1.32 AL2023 AMI, green 클러스터 SG/IAM role로 교체
   - pluto로 deprecated API 스캔 → `autoscaling/v2beta2` 발견
   - `kubectl convert`로 `autoscaling/v2`로 변환
   - ArgoCD `app-of-apps/values.yaml`에서 `targetRevision: main` → `green` 변경
3. git commit/push → green 브랜치

#### ArgoCD Bootstrap (Green)
1. green 클러스터의 ArgoCD에 로그인
2. CodeCommit repo 등록
3. App of Apps 패턴으로 전체 앱 배포 (`--revision green`)
4. 모든 앱 Synced/Healthy 확인

#### Traffic Routing (이론)
- Route 53 Weighted Records로 blue ↔ green 트래픽 분배
  - blue=100, green=0 → 전량 blue
  - blue=0, green=100 → 전량 green
  - 중간값으로 canary 배포 가능
- external-dns addon으로 자동 관리:
  - `external-dns.alpha.kubernetes.io/set-identifier`: 클러스터 이름
  - `external-dns.alpha.kubernetes.io/aws-weight`: 가중치
- Terraform에서 weight 값 제어 → 점진적 전환

### Stateful Workload Migration

#### 전략
- 공유 스토리지(EFS)로 양쪽 클러스터가 동일 데이터 접근
- 실제 환경에서는 EBS, RDS 등 데이터 동기화 필요

#### 절차
1. Blue 클러스터에 StatefulSet 생성 (nginx + EFS PVC, StorageClass: efs)
   - EFS CSI driver가 Access Point 자동 생성
   - Pod에서 `/usr/share/nginx/html`에 파일 생성 → EFS에 저장
2. Green 클러스터에 동일 StatefulSet 배포
   - 동일 EFS에 마운트 → blue에서 생성한 파일 접근 가능
3. 검증 완료 후 blue 클러스터의 StatefulSet 삭제
   - 파일 락 해제 → green이 완전 소유
4. 트래픽을 green으로 전환하여 업그레이드 완료

#### EFS StorageClass 핵심 설정
- `provisioningMode: efs-ap` (Access Point 자동 생성)
- `subPathPattern: ${.PVC.namespace}/${.PVC.name}` (네임스페이스/PVC명 기반 경로)
- `ensureUniqueDirectory: "false"` (동일 경로 재사용 허용 → 양 클러스터 공유)

#### 핵심 포인트
- Blue에서 EFS lock 보유 중이면 green에서 쓰기 불가 → blue StatefulSet 삭제 후 green 전환
- 실제 운영: 데이터 동기화 → 앱 테스트 → 트래픽 전환 → blue 폐기 순서
