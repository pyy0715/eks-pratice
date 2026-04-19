# Lab

실습 스크립트와 매니페스트는 [:octicons-mark-github-16: labs/week5/](https://github.com/pyy0715/eks-pratice/tree/main/labs/week5) 디렉터리를 참고하세요.

저는 EKS를 실제로 운영하고 있지는 않지만, 실제 운영 상황을 가정하고 실습 시나리오를 구성했습니다. 각 사례는 **EKS 운영 중 마이그레이션 과정에서 마주칠 수 있는 장애**를 사후 보고 형식으로 정리한 것이며, 증상과 탐지 경로, 해결 과정은 공개 사례와 AWS 공식 가이드에 근거합니다.

각 사례는 다음 일곱 단계를 공통 구조로 따릅니다.

| 단계 | 내용 |
|------|------|
| **Background** | 조직 상황과 변경 이유 |
| **Incident** | 관찰된 증상 |
| **Detection** | 어떻게 감지했는가 |
| **Root Cause** | 진단 과정에서 확인한 원인 |
| **Resolution** | 복구 조치 |
| **Lesson** | 다시 반복하지 않기 위한 교훈 |
| **Reproduction** | 실습 매니페스트 실행 방법 |

---

## Environment Setup

### Terraform Deploy

Managed Node Group 두 개(`ng-cas`, `ng-system`), Karpenter IAM, AWS Load Balancer Controller Helm release, External-DNS와 Cluster Autoscaler용 Pod Identity association이 함께 프로비저닝됩니다.

```bash
cd labs/week5
terraform init
terraform apply -auto-approve
source 00_env.sh
```

!!! warning "Initial Apply"

    `helm` provider가 EKS 클러스터 endpoint에 의존하므로 첫 apply에서 20분 이상 소요됩니다. provider 초기화 오류가 발생하면 `terraform apply -target=module.eks`로 클러스터를 먼저 만든 뒤 `terraform apply`를 다시 실행합니다.

### Configure kubectl

```bash
eval $(terraform -chdir=labs/week5 output -raw configure_kubectl)
kubectl config rename-context $(kubectl config current-context) myeks
kubectl get nodes -L eks.amazonaws.com/nodegroup
```

### Install Controllers and Add-ons

시나리오 진입 전에 Gateway API CRD, External-DNS, Cluster Autoscaler, Karpenter를 순서대로 배포합니다. 각 스크립트는 `set -euo pipefail`과 설치 검증 커맨드를 포함합니다.

```bash
./scripts/01_install-gateway-crd.sh
./scripts/02_install-external-dns.sh
./scripts/03_install-cas.sh
./scripts/04_install-karpenter.sh
```

### Verify

```bash
kubectl get gatewayclass                             # "alb" 등록 확인
kubectl -n external-dns get deploy external-dns
kubectl -n kube-system get deploy \
  aws-load-balancer-controller \
  cluster-autoscaler-aws-cluster-autoscaler \
  karpenter
```

위 Deployment가 모두 `AVAILABLE: 1` 이상이면 시나리오 재현으로 진행합니다.

---

## Case 1 — Ingress(ALB) → Gateway API Migration

???+ info "Migration motivation"

    서비스 라우팅을 기존 Ingress(annotations 기반)에서 **Gateway API**(표준 리소스 기반)로 전환하는 작업을 진행했습니다. 목적은 두 가지였습니다.

    - ALB 설정을 annotation 키-값 나열에서 **CRD 필드**로 옮겨 검토 가능한 상태로 만들기
    - Canary, weighted routing을 별도 툴 없이 HTTPRoute 단위로 제어하기

    AWS Load Balancer Controller v2.14.0부터 Gateway API가 GA로 지원되면서 동일 Controller가 Ingress와 HTTPRoute를 동시에 관리할 수 있게 되어, 중단 없이 점진 전환이 가능하다고 판단했습니다.

### Rolling Update 5xx After Gateway Cutover

**Incident**

Ingress에서 Gateway API로 전환한 직후, 평소처럼 새 이미지로 rolling update를 수행하자 Prometheus에 5xx 알림이 올라왔습니다. Ingress 시절에는 동일한 배포 프로세스가 무중단으로 동작하고 있었기 때문에 예상하지 못한 증상이었습니다.

**Detection**

5xx가 발생한 시각과 Pod 종료 시각이 정확히 겹쳤습니다. Ingress 시절의 무중단 배포 구성 요소 중 하나가 빠졌다는 가설로 Pod spec을 확인했습니다.

```bash
kubectl -n demo get pod -l app=nginx \
  -o jsonpath='{.items[0].spec.readinessGates}' # (1)
```

1.  출력이 `[]`(빈 배열)이면 AWS LBC의 자동 추가가 적용되지 않은 상태입니다. Ingress 당시에는 `target-health.elbv2.k8s.aws/...` 조건이 자동으로 채워져 있었습니다.

ALB access log의 5xx 분포도 특정 Pod의 SIGTERM 시점에 몰려 있어, target deregister가 완료되기 전에 들어온 연결이 종료 중인 Pod으로 계속 전달되고 있었음을 확인했습니다.

**Root Cause**

5xx의 직접 원인은 `preStop` sleep과 `terminationGracePeriodSeconds`가 누락된 것이었습니다. 이 두 값은 서비스 초기에 ALB Ingress의 deregister 전파 지연을 흡수하기 위해 추가된 설정이었는데, Gateway 전환 과정에서 "Ingress의 한계를 우회하는 임시 조치"로 간주해 제거했습니다. 실제로는 ALB deregister 지연을 흡수하는 Kubernetes 자체의 lifecycle 메커니즘이며, 라우팅 계층이 Ingress든 Gateway든 관계없이 필요한 설정이었습니다. 이 값들이 빠지자 deregister가 완료되기 전에 들어온 연결이 종료 중인 Pod으로 전달되면서 5xx가 나타났습니다.

한편 Pod Readiness Gate 동작도 검증되지 않은 전제로 남아 있었습니다. AWS Load Balancer Controller는 namespace label `elbv2.k8s.aws/pod-readiness-gate-inject=enabled`와 **Service selector 매칭**을 기반으로 Pod에 readiness gate 조건을 추가합니다[^lbc-readiness-gate]. HTTPRoute도 `backendRefs`로 Service를 참조하므로 같은 로직이 적용될 가능성이 큽니다. 다만 공식 가이드와 릴리스 노트에는 Gateway API 워크로드에서의 readiness gate 동작이 명시적으로 다뤄지지 않아 검증 사각지대가 있습니다. 전환 당시에는 기존 Ingress에서 검증된 보호 구성이 Gateway에서도 그대로 적용된다고 전제했지만, 장애 발생 후에도 readiness gate가 정상 주입됐는지 확인하지 못했습니다.

**Resolution**

Deployment의 `terminationGracePeriodSeconds`를 60초, `preStop` sleep을 30초로 명시하고 PDB `minAvailable`을 80%에서 90%로 올렸습니다. rolling update 전략도 `maxUnavailable: 1, maxSurge: 0`으로 좁히면 readiness gate 동작 여부와 무관하게 ALB deregister 지연을 흡수할 수 있어 5xx 증상이 사라집니다.

이후에는 readiness gate 자체의 작동 여부를 배포마다 Pod spec의 `readinessGates` 필드로 확인해야 합니다. Service 기반 injection 로직상 Gateway API 워크로드에서도 동작할 가능성이 높지만 공식 문서가 이를 명시하지 않는 한 각 팀이 실측으로 확인할 수밖에 없습니다. 커뮤니티 사례 공유나 공식 issue로 문서화 gap을 제기하면 다음 사용자의 사각지대를 줄이는 데 도움이 됩니다.

!!! tip "Lesson"

    - Gateway 전환 후에는 readiness gate, preStop, PDB 등 보호 구성이 의도대로 동작하는지 Pod spec과 end-to-end로 직접 확인합니다. 기존 환경에서 검증됐다는 이유로 새 환경에서도 보장된다고 전제하지 않습니다.
    - 공식 문서가 특정 조합의 동작을 명시하지 않으면 그 조합은 자동으로 검증 사각지대가 됩니다. 마이그레이션 체크리스트에 "문서에 명시되지 않은 전제" 항목을 따로 둡니다.

!!! example "Reproduction"

    Baseline Deployment, Ingress, Gateway, HTTPRoute가 배포된 상태에서 시작합니다. 시나리오 순서대로 진행 중이면 `manifests/scenario1/README.md` Step 3까지 완료한 뒤 아래 단계로 진입합니다.

    ```bash
    # 0) 미배포 상태면 선행 리소스 apply
    kubectl apply -f labs/week5/manifests/scenario1/00-baseline/app-deployment.yaml
    envsubst < labs/week5/manifests/scenario1/00-baseline/ingress.yaml | kubectl apply -f -
    envsubst < labs/week5/manifests/scenario1/10-gateway-install/gatewayclass-alb.yaml | kubectl apply -f -
    envsubst < labs/week5/manifests/scenario1/20-migration/httproute.yaml | kubectl apply -f -

    # 1) preStop 과 긴 grace period 를 제거한 Deployment 적용
    kubectl apply -f labs/week5/manifests/scenario1/incidents/01-rolling-update-5xx.yaml

    # 2) readiness gate 자동 추가 여부 확인 — 빈 배열이면 미적용
    kubectl -n demo get pod -l app=nginx -o jsonpath='{.items[0].spec.readinessGates}'

    # 3) 별도 터미널에서 curl 루프를 돌린 상태로 rolling update 트리거
    kubectl -n demo set image deploy/nginx nginx=public.ecr.aws/nginx/nginx:1.28-alpine
    # 관측: while true; do curl -so /dev/null -w "%{http_code}\n" https://gw.${MyDomain}/; sleep 0.2; done

    # 4) 복구 — baseline Deployment 재적용으로 preStop 과 grace period 복원
    kubectl apply -f labs/week5/manifests/scenario1/00-baseline/app-deployment.yaml
    ```

[^lbc-readiness-gate]: [AWS Load Balancer Controller — Pod Readiness Gate](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/pod_readiness_gate/). Injection 로직은 Service selector 매칭 기반으로 설명돼 있습니다. Gateway API 워크로드에서의 동작을 직접 다룬 섹션은 없어 설치 후 Pod spec의 `readinessGates` 필드로 실측 확인이 필요합니다.

### Hostname Claim Conflict During Coexistence

**Incident**

마이그레이션 공존 구간에 Gateway 쪽 HTTPRoute가 기존 Ingress와 같은 `nginx.${MyDomain}` hostname을 잠시 claim했습니다. 직후 일부 클라이언트는 새 Gateway ALB으로, 일부는 옛 Ingress ALB으로 붙으면서 간헐적으로 예전 버전 응답이 돌아오는 현상이 모니터링 대시보드에 잡혔습니다.

**Detection**

같은 hostname을 반복해서 조회해 보면 A record 값이 두 ALB 사이에서 바뀌어 나오는 것이 보입니다.

```bash
for i in 1 2 3 4 5; do dig +short nginx.${MyDomain}; sleep 3; done
kubectl -n external-dns logs deploy/external-dns --tail=100 | grep -i "nginx\.${MyDomain}"
```

External-DNS 로그에는 Ingress source와 HTTPRoute source가 번갈아 같은 record를 update하는 흔적이 남습니다.

**Root Cause**

External-DNS는 `sources`로 지정된 Ingress, HTTPRoute 같은 리소스를 독립적으로 관찰합니다. 서로 다른 source가 같은 hostname을 claim하면 가장 최근 reconcile의 결과가 record 값이 되고, 다음 reconcile 때 반대편 source가 이를 다시 덮어쓰면서 record가 flip합니다. Ingress와 HTTPRoute가 같은 backend Service를 가리키더라도 External-DNS 입장에서는 서로 다른 ownership을 주장하는 두 리소스입니다. `txt registry`로 ownership을 관리해도 두 source 간 경합 자체는 막지 못합니다.

**Resolution**

공존 구간에는 Ingress와 Gateway가 **서로 다른 hostname**을 쓰도록 분리합니다. 기존 Ingress는 `nginx.${MyDomain}`을 유지하고 Gateway는 `gw.${MyDomain}`으로 노출해, 마지막 cutover 시점에 DNS를 한 번만 전환하는 canary 구조가 안전합니다. 이미 conflict가 발생한 상태라면 HTTPRoute의 hostname을 변경해 reconcile을 유도한 뒤, Route53에 남은 stale record가 있으면 수동 정리합니다.

!!! tip "Lesson"

    - External-DNS의 여러 source가 같은 hostname을 claim하면 record가 source 간 경합으로 flip합니다. 공존 구간에는 항상 별도 hostname을 사용합니다.
    - 실제 전환은 HTTPRoute를 바꾸는 순간이 아니라 DNS record가 새 ALB을 가리키는 순간입니다. 마이그레이션 계획을 DNS 기준으로 세웁니다.

!!! example "Reproduction"

    ```bash
    # 1) Ingress baseline 이 이미 nginx.${MyDomain} 을 사용 중인 상태에서
    #    Gateway 쪽 HTTPRoute 가 같은 hostname 을 claim 하게 만드는 incident 매니페스트 apply
    envsubst < labs/week5/manifests/scenario1/incidents/02-hostname-conflict.yaml | kubectl apply -f -

    # 2) dig 로 A record flip 관찰
    for i in 1 2 3 4 5; do dig +short nginx.${MyDomain}; sleep 3; done

    # 3) External-DNS 로그에서 source 경합 흔적 확인
    kubectl -n external-dns logs deploy/external-dns --tail=100 | grep -i "nginx\.${MyDomain}"

    # 4) 복구 — HTTPRoute hostname 을 gw.${MyDomain} 으로 되돌림
    envsubst < labs/week5/manifests/scenario1/20-migration/httproute.yaml | kubectl apply -f -
    ```

---

## Case 2 — Cluster Autoscaler → Karpenter Migration

???+ info "Migration motivation"

    Managed Node Group과 Cluster Autoscaler 구성으로 운영하다가 Karpenter로 전환했습니다. 동기는 두 가지였습니다.

    - **Bin-packing 효율** — CAS는 ASG 단위 scale만 가능해 instance family가 고정됐습니다. Karpenter는 Pod 요구를 보고 인스턴스 타입을 직접 선택합니다.
    - **Spot 안정성** — Karpenter는 여러 instance pool에서 spot을 선택하고 interruption을 처리하는 내장 로직을 가집니다.

    전환은 **dual-run** 방식으로 진행했습니다. 기존 ASG는 유지한 채 Karpenter NodePool을 배포하고, 안정성을 확인한 뒤 ASG를 `min=0`까지 낮췄습니다.

### Consolidation Blocked by Overly Strict PDB

**Incident**

Karpenter 도입 후 consolidation이 전혀 동작하지 않았습니다. 비용 최적화를 위해 Karpenter를 도입했음에도 노드가 교체되지 않아 오래된 노드가 계속 실행됐고, spot 인스턴스가 만료돼도 교체되지 않는 상황이 발생했습니다. Karpenter 설정 자체는 정상이었습니다.

**Detection**

Karpenter Controller 로그에 반복되는 disruption 차단 메시지가 확인됐습니다.

```bash
kubectl -n kube-system logs deploy/karpenter --tail=200 | grep -i disrupt
# level=INFO msg="disrupting via consolidation replace"
# level=WARN msg="cannot disrupt due to PDB"
```

PDB 상태를 확인하니 `disruptionsAllowed: 0`으로, 단일 Pod도 eviction할 수 없는 상태였습니다.

```bash
kubectl get pdb critical-app-pdb -n default -o jsonpath='{.status.disruptionsAllowed}'
# 0
```

**Root Cause**

문제는 Karpenter 설정이 아니라 PDB에 있었습니다. 서비스 팀이 `minAvailable: 100%`로 PDB를 설정했는데, 이는 어떤 상황에서도 Pod을 내리지 마라와 같습니다. `disruptionsAllowed`가 항상 0이므로 Karpenter는 물론이고 수동 `kubectl drain`이나 노드 업그레이드도 불가능합니다.

`minAvailable: 100%`는 계획된 disruption만 차단합니다. 노드 장애, AZ 장애, spot 중단 등의 비계획 disruption에는 아무런 보호가 되지 않습니다. 즉, 가용성을 보장하지도 않으면서 유지보수만 막는 설정이었습니다.

Salesforce도 1,000개 클러스터 마이그레이션에서 동일한 문제를 겪었으며[^salesforce-karpenter], "과도하게 엄격하거나 잘못 설정된 PDB가 node 교체를 차단했다"고 보고했습니다. 이를 계기로 OPA 정책으로 PDB 설정을 사전 검증하는 체계를 구축했습니다.

**Resolution**

PDB를 `minAvailable: 80%`로 완화했습니다. 이 값은 최대 20%까지 동시에 Pod을 내릴 수 있도록 허용하면서, 계획된 disruption 중에도 최소 80%의 Pod은 유지됨을 보장합니다.

```bash
kubectl patch pdb critical-app-pdb -n default -p '{"spec":{"minAvailable":"80%"}}'
```

PDB 변경 후 Karpenter consolidation이 정상 동작하기 시작했고, 노드 교체와 drift 감지도 정상적으로 수행됐습니다.

!!! tip "Lesson"

    - `minAvailable: 100%`는 가용성을 보장하지 않으면서 유지보수만 차단합니다. 비계획 disruption(장애, spot 중단)에는 무력하고 계획된 disruption(consolidation, 업그레이드)만 막습니다. PDB는 "어느 수준까지 견딜 수 있는가"에 대한 답이어야 합니다.
    - `kubectl get pdb -A`에서 `disruptionsAllowed`가 0인 PDB가 있으면 해당 서비스는 모든 노드 유지보수가 불가능합니다. OPA/Kyverno 같은 정책 엔진으로 `minAvailable`이 100%인 PDB 생성을 차단할 수 있습니다.
    - PDB은 Pod 단위 보호막이고 `disruption.budgets`은 노드 단위 속도 제한입니다. 두 장치가 함께 작동해야 consolidation이 안전하게 진행됩니다.

!!! example "Reproduction"

    ```bash
    # 1) critical-app deployment + PDB(minAvailable: 100%) + NodePool 배포
    kubectl apply -f labs/week5/manifests/scenario2/incidents/01-consolidation-pdb-violation.yaml

    # 2) PDB 상태 확인 — disruptionsAllowed: 0
    kubectl get pdb critical-app-pdb -n default -o wide
    kubectl get pdb critical-app-pdb -n default -o jsonpath='{.status.disruptionsAllowed}'

    # 3) Karpenter 로그에서 consolidation 차단 관찰
    kubectl -n kube-system logs deploy/karpenter --tail=200 | grep -i disrupt

    # 4) 복구 — PDB를 허용 가능한 수준으로 변경
    kubectl patch pdb critical-app-pdb -n default -p '{"spec":{"minAvailable":"80%"}}'
    ```

### NodeClaim Launch Failure

**Incident**

CAS에서 Karpenter로 전환한 직후, 트래픽 증가로 Karpenter가 새 노드를 provisioning해야 하는 상황이 발생했습니다. Pod은 Pending 상태로 남아 있고, Karpenter는 NodeClaim을 생성했지만 노드가 cluster에 join하지 못했습니다. 새 노드가 프로비저닝되지 않으면서 서비스 복구가 지연됐습니다.

**Detection**

`kubectl get nodeclaim`에서 NodeClaim이 에러 상태로 머물러 있는 것을 확인했습니다.

```bash
kubectl get nodeclaim -o wide
# NAME              STATUS         READY   AGE
# broken-xxxxx      LaunchFailed   False   2m

kubectl describe nodeclaim -l karpenter.sh/nodepool=broken
# Status:
#   Conditions:
#     Type: Ready
#     Status: False
#     Reason: LaunchFailed
#     Message: ...InvalidParameterValue: Invalid IAM Instance Profile name...
```

Karpenter Controller 로그에도 provisioning 실패가 반복해서 기록됐습니다.

```bash
kubectl -n kube-system logs deploy/karpenter --tail=100 | grep -i "launch\|instance\|iam"
```

**Root Cause**

EC2NodeClass의 `role` 필드에 CAS가 사용하던 **instance profile 이름**을 그대로 적었습니다. Karpenter EC2NodeClass의 `role` 필드는 instance profile이 아니라 **IAM role 이름**을 요구합니다. 두 이름은 다릅니다 — Managed Node Group은 `myeks-ng-cas` 같은 instance profile을 생성하지만, Karpenter는 `KarpenterNodeRole-myeks` 같은 role 이름을 기대합니다. Karpenter는 EC2 `RunInstances` API를 호출할 때 이 role 이름으로 instance profile을 생성하는데, 존재하지 않는 role이면 API 호출이 실패합니다. NodeClaim의 `status.conditions`에서 `LaunchFailed`와 함께 에러 메시지를 확인할 수 있었습니다.

이런 EC2NodeClass 설정 오류는 CAS→Karpenter 마이그레이션에서 반복적으로 발생합니다. Salesforce도 ASG 설정을 EC2NodeClass로 변환하는 과정에서 [설정 누락 문제](https://aws.amazon.com/blogs/architecture/how-salesforce-migrated-from-cluster-autoscaler-to-karpenter-across-their-fleet-of-1000-eks-clusters/)를 겪었으며, 이를 자동화 도구(Karpenter transition tool)로 해결했습니다. AWS re:Post의 트러블슈팅 가이드[^karpenter-troubleshoot]에서도 "Nodes not initialized properly" 항목으로 유사 사례를 다룹니다.

**Resolution**

틀린 EC2NodeClass를 삭제하고 올바른 설정을 재적용했습니다.

```bash
# broken 리소스 정리
kubectl delete nodepool broken
kubectl delete ec2nodeclass broken
```

EC2NodeClass 작성 시 `role` 필드가 Terraform에서 생성한 `KarpenterNodeRole-${CLUSTER_NAME}`과 정확히 일치하는지 검증하는 절차를 마이그레이션 체크리스트에 추가했습니다. `aws iam get-role --role-name KarpenterNodeRole-${CLUSTER_NAME}`으로 role 존재 여부를 사전에 확인할 수 있습니다.

!!! tip "Lesson"

    - Karpenter provisioning 문제는 NodeClaim의 `status.conditions`와 `events`에서 추적합니다. Pod이 Pending인 경우 `kubectl get nodeclaim`을 먼저 확인합니다.
    - Karpenter provisioning은 NodeClaim 생성 → EC2 RunInstances → 인스턴스 부트스트랩 → kubelet 인증 → 노드 Ready의 다단계 파이프라인입니다. 어느 단계에서 실패했는지 conditions 메시지로 구분합니다.
    - EC2NodeClass의 `role`, `subnetSelectorTerms`, `securityGroupSelectorTerms` 세 필드는 provisioning 성패를 가릅니다. apply 전에 `aws iam get-role`, `aws ec2 describe-subnets`로 존재 여부를 확인합니다.
    - 수동으로 ASG 설정을 EC2NodeClass로 변환하면 IAM role 이름, subnet tag, storage parameter 등에서 누락과 오타가 반복됩니다. Salesforce는 1,180개 node pool의 변환을 자동화한 Karpenter transition tool로 이 문제를 해결했습니다[^salesforce-karpenter]. 소규모라면 `eksctl`이나 Terraform output 기반 스크립트로라도 매핑을 자동화하는 것이 수동 작성보다 안전합니다.

!!! example "Reproduction"

    ```bash
    # 1) broken EC2NodeClass + NodePool + trigger 워크로드 배포
    envsubst < labs/week5/manifests/scenario2/incidents/02-nodeclaim-launch-failure.yaml | kubectl apply -f -

    # 2) NodeClaim 상태 확인
    kubectl get nodeclaim -o wide
    kubectl describe nodeclaim -l karpenter.sh/nodepool=broken

    # 3) Karpenter 로그에서 provisioning 실패 흔적
    kubectl -n kube-system logs deploy/karpenter --tail=100 | grep -i "launch\|instance\|iam"

    # 4) 복구 — broken 리소스 삭제
    kubectl delete nodepool broken
    kubectl delete ec2nodeclass broken
    kubectl delete deploy trigger-broken -n default
    ```

[^karpenter-troubleshoot]: [Troubleshoot cluster scaling in Amazon EKS with Karpenter](https://repost.aws/knowledge-center/eks-troubleshoot-cluster-scaling-with-karpenter) — AWS re:Post Knowledge Center. "Nodes not initialized properly" 및 "Node consolidation failures" 항목에서 NodeClaim 디버깅 절차를 다룹니다.
