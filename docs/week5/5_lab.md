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

Managed Node Group 두 개(`ng-cas`, `ng-system`), Karpenter IAM, AWS Load Balancer Controller Helm release가 함께 프로비저닝됩니다. External-DNS는 EKS addon으로 설치되고, Cluster Autoscaler는 Pod Identity association만 선행 생성됩니다.

```bash
cd labs/week5
terraform init
terraform apply -auto-approve
source 00_env.sh
```

!!! warning "Initial Apply"

    `helm` provider가 EKS 클러스터 endpoint에 의존하므로 첫 apply에서 시간이 소요될 수 있습니다. provider 초기화 오류가 발생하면 `terraform apply -target=module.eks`로 클러스터를 먼저 만든 뒤 `terraform apply`를 다시 실행합니다.

### Configure kubectl

먼저 기존 context를 정리한 뒤 새 kubeconfig를 설정합니다.

```bash
kubectl config delete-context myeks
eval $(terraform output -raw configure_kubectl)
kubectl config rename-context $(kubectl config current-context) myeks
kubectl get nodes -L eks.amazonaws.com/nodegroup
```

### Install Controllers and Add-ons

시나리오 진입 전에 Gateway API CRD, Cluster Autoscaler, Karpenter를 순서대로 배포합니다.

```bash
./scripts/01_install-gateway-crd.sh
./scripts/02_install-cas.sh
./scripts/03_install-karpenter.sh
```

설치가 끝나면 다음 리소스가 모두 Ready 상태여야 합니다. GatewayClass 자체는 Scenario 1 에서 apply 하므로 지금 단계에서는 CRD 만 확인합니다.

```bash
kubectl get crd gatewayclasses.gateway.networking.k8s.io
kubectl -n external-dns get deploy external-dns
kubectl -n kube-system get deploy \
  aws-load-balancer-controller \
  cluster-autoscaler-aws-cluster-autoscaler \
  karpenter
```

---

## Scenario 1

???+ info

    서비스 라우팅을 Ingress annotation 방식에서 **Gateway API** 로 전환하는 작업을 진행했습니다. 목적은 두 가지였습니다.

    - ALB 동작을 결정하는 설정을 annotation 키-값 나열에서 **HTTPRoute, Gateway 같은 CRD 필드** 로 옮겨 리뷰 가능한 형태로 관리하기
    - Canary, weighted routing 을 annotation 조합 없이 HTTPRoute 의 표준 필드로 직접 제어하기

    AWS Load Balancer Controller v3.0.0 부터 Gateway API 가 GA 로 지원되면서 동일한 Controller 가 Ingress 와 HTTPRoute 를 동시에 관리할 수 있게 됐고, 기존 Ingress 를 유지한 채 HTTPRoute 를 점진 추가하는 방식으로 무중단 전환이 가능하다고 판단했습니다.

**Incident**

Ingress 에서 Gateway API 로 전환한 직후, 평소처럼 새 이미지로 rolling update 를 수행하자 Prometheus 에 5xx 알림이 올라왔습니다. 전환 전까지는 동일한 배포 프로세스가 무중단으로 동작하고 있었기 때문에 예상하지 못한 증상이었습니다.

**Detection**

5xx 발생 시각이 Pod 종료 시각과 정확히 겹쳤고, ALB access log 상 실패 요청이 특정 Pod 의 SIGTERM 시점에 집중되어 있었습니다. target deregister 가 완료되기 전에 종료 중인 Pod 으로 요청이 계속 전달되고 있다는 신호입니다. Pod spec 의 `readinessGates` 를 확인해 gate 상태를 점검했습니다.

```bash
kubectl -n demo get pod -l app=nginx \
  -o jsonpath='{.items[0].spec.readinessGates}'
```

Ingress 와 Gateway 를 동시에 운영하는 동안에는 `conditionType` 배열에 두 TargetGroup gate 가 모두 들어있어야 정상입니다. 한쪽만 있거나 비어 있다면 Pod 생성 시점에 해당 TargetGroupBinding 이 아직 없었다는 신호입니다.

**Root Cause**

원인은 두 가지였습니다.

**1. `preStop` 과 `terminationGracePeriodSeconds` 누락**

두 값은 ALB 가 target 을 draining 상태로 바꾸는 데 걸리는 시간 동안 Pod 을 살려두는 Kubernetes lifecycle 설정입니다. 라우팅 계층이 Ingress 든 Gateway 든 동일하게 필요합니다. 설정이 빠지는 순간 deregister 가 끝나기 전에 Pod 이 먼저 종료되어 이미 죽은 Pod 으로 요청이 전달되고, 그 결과 5xx 가 발생합니다.

**2. readiness gate 는 Pod 생성 시점에만 추가**

AWS Load Balancer Controller 는 Pod 생성 시점의 mutating webhook 에서 그 순간 존재하는 `TargetGroupBinding` 을 조회해 gate 를 추가합니다[^lbc-readiness-gate]. `readinessGates` 는 immutable 이므로 Gateway TGB 가 나중에 생긴 경우 기존 Pod 에는 반영되지 않습니다. Gateway ALB 가 뜬 뒤 rollout 이전까지의 Pod 은 Gateway 쪽 gate 없이 트래픽을 받게 되어, 종료 구간에서 ALB 와 동기화 없이 죽습니다.

**Resolution**

Deployment 에 다음 세 가지 설정을 적용합니다. readiness gate 유무와 무관하게 ALB deregister 가 완료될 때까지 Pod 이 요청을 처리할 수 있도록 lifecycle 을 맞춰줍니다.

`terminationGracePeriodSeconds: 60`
:   SIGTERM 이후 Pod 이 버틸 수 있는 최대 시간. ALB 가 target 을 draining 으로 바꾸고 남은 연결을 마무리할 여유를 확보합니다.

`preStop: sleep 30`
:   SIGTERM 직전 대기. Endpoints 에서 Pod 이 빠졌다는 사실이 ALB 까지 전파되는 동안 Pod 을 살려둡니다.

`spec.strategy.rollingUpdate.maxUnavailable: 1, maxSurge: 0`
:   한 번에 교체되는 Pod 수를 1 로 제한. 여러 Pod 이 동시에 종료되어 ALB 가 healthy target 을 한꺼번에 잃는 상황을 막습니다.

Gateway ALB 를 새로 띄운 직후에는 `kubectl rollout restart` 로 Pod 을 한 번 교체해 양쪽 TargetGroup 의 gate 를 확보합니다.

!!! tip "Lesson"

    - readiness gate 는 Pod 생성 시점에 한 번만 추가됩니다. 새 TargetGroupBinding 이 추가되면 기존 Pod 은 gate 를 받지 못하므로 의도적인 rollout restart 가 필요합니다.
    - rolling update 자체를 gate 확보 수단으로 쓰면, 교체 과정에서 기존 Pod 은 gate 없이 종료됩니다. 이때 5xx 가 발생하지 않도록 preStop 과 gracePeriod 를 반드시 먼저 설정합니다.
    - 마이그레이션 직후에는 Pod `readinessGates` 배열에 양쪽 TargetGroup gate 가 모두 들어있는지 실측으로 확인하는 단계를 체크리스트에 포함합니다.

!!! example "Reproduction"

    ```bash
    cd labs/week5
    source 00_env.sh

    # 0) 미배포 상태면 선행 리소스 apply
    kubectl apply -f manifests/scenario1/deployment.yaml
    envsubst < manifests/scenario1/ingress.yaml | kubectl apply -f -
    envsubst < manifests/scenario1/gateway.yaml | kubectl apply -f -
    envsubst < manifests/scenario1/httproute.yaml | kubectl apply -f -

    # 1) preStop 과 긴 grace period 를 제거한 Deployment 적용
    kubectl apply -f manifests/scenario1/rolling-update-5xx.yaml

    # 2) Pod readinessGates 확인 — 양쪽 TargetGroup gate 가 들어있는지 점검
    kubectl -n demo get pod -l app=nginx -o jsonpath='{.items[0].spec.readinessGates}'; echo

    # 3) 터미널 A — curl 루프로 5xx 관측
    while true; do curl -so /dev/null -w "%{http_code}\n" https://api-gateway.${MyDomain}/; sleep 0.2; done

    # 4) 터미널 B — rolling update 트리거
    kubectl -n demo set image deploy/nginx nginx=public.ecr.aws/nginx/nginx:1.28-alpine
    kubectl -n demo rollout status deploy/nginx

    # 5) 복구 — preStop 과 grace period 복원
    kubectl apply -f manifests/scenario1/deployment.yaml
    ```

[^lbc-readiness-gate]: [AWS Load Balancer Controller — Pod Readiness Gate](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/pod_readiness_gate/)

---

## Scenario 2

???+ info

    Managed Node Group 과 Cluster Autoscaler 구성에서 Karpenter 로 전환했습니다. 목적은 두 가지였습니다.

    - **Bin-packing 효율** — CAS 는 ASG 단위 scale 만 가능해 instance family 가 고정됩니다. Karpenter 는 Pod 요구를 보고 인스턴스 타입을 직접 선택합니다.
    - **Consolidation** — Karpenter 가 저사용 노드를 더 작은 인스턴스로 교체하거나 빈 노드를 제거해 비용을 낮춥니다.

    전환은 **CAS 와 Karpenter 를 병행 운영하는 방식**으로 진행했습니다. 기존 ASG 는 유지한 채 Karpenter NodePool 을 배포하고, 안정성을 확인한 뒤 ASG 를 `min=0` 까지 낮췄습니다.

**Incident**

Karpenter 도입 후 consolidation 이 전혀 동작하지 않았습니다. 비용 최적화를 기대했지만 저사용 노드가 줄어들지 않았고, Karpenter 설정 자체에는 문제가 없었습니다.

**Detection**

Karpenter 는 disruption 이 차단된 이유를 `DisruptionBlocked` reason 으로 Node 와 NodeClaim 양쪽에 Event 로 emit 합니다.

```bash
kubectl get events -A --field-selector reason=DisruptionBlocked \
  -o jsonpath='{range .items[*]}{.involvedObject.kind}/{.involvedObject.name}{"\t"}{.message}{"\n"}{end}' \
  | grep -i pdb
# Node/ip-192-168-2-139...       Pdb prevents pod evictions (PodDisruptionBudget=[default/critical-app-pdb])
# NodeClaim/default-slh45        Pdb prevents pod evictions (PodDisruptionBudget=[default/critical-app-pdb])
```

특정 노드를 지정해 `describe` 하면 같은 Event 를 시간순으로 확인할 수 있습니다.

```bash
kubectl describe node <node-name> | grep -A3 DisruptionBlocked
```

PDB 상태를 보면 `disruptionsAllowed: 0` 으로, 단일 Pod 도 eviction 되지 못하는 상태입니다.

```bash
kubectl get pdb critical-app-pdb -n default -o jsonpath='{.status.disruptionsAllowed}'
# 0
```

**Root Cause**

원인은 Karpenter 가 아니라 PDB 설정이었습니다. 서비스 팀이 `minAvailable: 100%` 로 지정해 `disruptionsAllowed` 가 항상 0 으로 고정됐고, consolidation 은 물론 `kubectl drain` 이 차단됐고, Managed Node Group 업그레이드도 `--force` 없이는 `PodEvictionFailure` 로 실패했습니다.

`minAvailable: 100%` 는 disruption 종류별로 다르게 작동합니다.

| Disruption Type | Examples | Effect of `minAvailable: 100%` |
|-----------------|----------|-------------------------------|
| 계획 disruption | consolidation, drain, upgrade | **차단** (유지보수 불가) |
| 비계획 disruption | 노드 장애, AZ 장애, spot 중단 | 보호 없음 (Pod 강제 종료) |

유지보수만 차단하고 실제 장애는 막지 못하는 설정입니다.

**Resolution**

PDB 를 `minAvailable: 80%` 로 완화해 동시에 최대 20% (Pod 2개) 까지 eviction 이 가능하도록 합니다.

```bash
kubectl patch pdb critical-app-pdb -n default -p '{"spec":{"minAvailable":"80%"}}'
```

**Prevention**

사후 완화만으로는 동일 사고가 재발합니다. Salesforce 도 [1,000 개 클러스터 마이그레이션](https://aws.amazon.com/blogs/architecture/how-salesforce-migrated-from-cluster-autoscaler-to-karpenter-across-their-fleet-of-1000-eks-clusters/) 에서 동일 문제를 겪고 Open Policy Agent(OPA) 로 PDB 를 사전 검증하는 체계를 구축했습니다. 여기서는 동일한 접근을 [Kyverno](https://kyverno.io/policies/) 로 구현합니다. 안티패턴 PDB 를 생성 시점에 차단하는 admission policy 로 `minAvailable: 100%` 와 `maxUnavailable: 0` 을 모두 거부합니다.

```yaml title="manifests/scenario2/kyverno-pdb-policy.yaml"
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: pdb-anti-patterns
spec:
  validationFailureAction: Enforce
  background: false
  rules:
    - name: maxunavailable-nonzero
      match:
        any:
          - resources:
              kinds: [PodDisruptionBudget]
      validate:
        message: "maxUnavailable 은 0 보다 커야 합니다. 0 은 모든 자발적 eviction 을 차단합니다."
        pattern:
          spec:
            "=(maxUnavailable)": ">0"
    - name: minavailable-not-100-percent
      match:
        any:
          - resources:
              kinds: [PodDisruptionBudget]
      validate:
        message: "minAvailable: 100% 는 disruptionsAllowed 를 0 으로 고정시켜 consolidation, drain, upgrade 를 전면 차단합니다."
        deny:
          conditions:
            any:
              - key: "{{ request.object.spec.minAvailable || '' }}"
                operator: Equals
                value: "100%"
```

설치와 적용은 다음과 같습니다.

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm install kyverno kyverno/kyverno -n kyverno --create-namespace --wait
kubectl apply -f manifests/scenario2/kyverno-pdb-policy.yaml
```

이후 `consolidation-pdb-violation.yaml` 을 재적용하면 PDB 생성이 admission webhook 단계에서 거부됩니다.

다만 이 두 규칙은 PDB 매니페스트 하나만 놓고 검사하기 때문에 PDB 와 Deployment 를 엮어봐야 드러나는 문제는 잡지 못합니다. 예를 들어 `replicas: 3` Deployment 에 `minAvailable: 3` PDB 를 붙이면 숫자만 보면 평범하지만, 실제로는 항상 3 개 전부 살아있어야 한다는 뜻이라 `minAvailable: 100%` 와 결과가 같습니다. 앞의 `minavailable-not-100-percent` 규칙은 "100%" 문자열만 검사하므로 이 케이스는 통과합니다.

이런 절대값 안티패턴까지 막으려면 검증 방향을 뒤집어야 합니다. **PDB 가 아니라 Deployment, StatefulSet 이 생성, 변경될 때 해당 워크로드의 `replicas` 와 매칭되는 PDB 의 `minAvailable` 을 같이 읽어서 `replicas == minAvailable` 이면 거부하는 방식입니다.** Kyverno 공식 policy 라이브러리의 `pdb-minavailable-check`[^kyverno-minavailable] 규칙이 이 역할을 합니다. 앞의 두 규칙과 함께 배포하면 세 가지 안티패턴(`maxUnavailable: 0`, `minAvailable: 100%`, `replicas == minAvailable`) 이 모두 차단됩니다.

!!! tip "Lesson"

    - `minAvailable: 100%` 는 가용성을 보장하지 않으면서 유지보수만 차단합니다. PDB 값은 어느 수준까지 견딜 수 있는가에 대한 답으로 설정합니다.
    - 이런 설정을 사전 차단하려면 OPA 나 Kyverno 로 admission policy 를 추가해 `minAvailable: 100%` 또는 `maxUnavailable: 0` PDB 생성을 막습니다.
    - PDB 퍼센트는 올림으로 계산되므로 `replicas` 가 작을수록 의도한 여유가 사라집니다. 예를 들어 `replicas: 3` + `minAvailable: 80%` 는 `ceil(2.4) = 3` 이라 3 available 을 요구해 `disruptionsAllowed = 0` 이 됩니다. 소규모 Deployment 는 절대수(`maxUnavailable: 1`) 를 함께 검토하는 편이 안전합니다.
    - PDB 는 Pod 단위 eviction 제약이고 NodePool 의 `disruption.budgets` 은 노드 단위 속도 제한입니다. 두 장치가 함께 작동해야 consolidation 이 안전하게 진행됩니다.

!!! example "Reproduction"

    `labs/week5` 디렉터리에서 실행합니다.

    ```bash
    # 0) 선행 리소스 — EC2NodeClass, NodePool 배포
    source 00_env.sh
    envsubst < manifests/scenario2/ec2nodeclass.yaml | kubectl apply -f -
    kubectl apply -f manifests/scenario2/nodepool.yaml

    # 1) critical-app deployment + PDB(minAvailable: 100%) 배포
    kubectl apply -f manifests/scenario2/consolidation-pdb-violation.yaml

    # 2) PDB 상태 확인 — disruptionsAllowed: 0
    kubectl get pdb critical-app-pdb -n default -o wide
    kubectl get pdb critical-app-pdb -n default -o jsonpath='{.status.disruptionsAllowed}'

    # 3) Node, NodeClaim Event 에서 consolidation 차단 관찰
    kubectl get events -A --field-selector reason=DisruptionBlocked \
      -o jsonpath='{range .items[*]}{.involvedObject.kind}/{.involvedObject.name}{"\t"}{.message}{"\n"}{end}' \
      | grep -i pdb

    # 4) 복구 — PDB를 허용 가능한 수준으로 변경
    kubectl patch pdb critical-app-pdb -n default -p '{"spec":{"minAvailable":"80%"}}'

    # 5) (선택) Kyverno 로 사전 차단 — 재적용 시 admission 거부 확인
    helm repo add kyverno https://kyverno.github.io/kyverno/
    helm install kyverno kyverno/kyverno -n kyverno --create-namespace --wait
    kubectl apply -f manifests/scenario2/kyverno-pdb-policy.yaml
    kubectl delete -f manifests/scenario2/consolidation-pdb-violation.yaml
    kubectl apply -f manifests/scenario2/consolidation-pdb-violation.yaml
    # admission webhook "validate.kyverno.svc-fail" denied the request
    ```

[^kyverno-minavailable]: [Kyverno — Check PodDisruptionBudget minAvailable](https://kyverno.io/policies/other/pdb-minavailable/pdb-minavailable/)
