# Availability and Scale

앞 두 문서가 장애 발생 시의 대응을 다뤘다면, 이 문서는 장애가 나지 않도록 어떻게 운영하는가에 해당합니다. 세션에서 강조된 세 가지 주제 — **롤링 업데이트 중 5xx가 사라지지 않는 이유**, **설정 변경이 자동으로 반영되지 않는 문제**, **규모가 커지면 선택이 달라지는 지점** — 를 중심으로 정리합니다.

## Zero 5xx on Rolling Update

Deployment 롤링 업데이트 중 간헐적으로 5xx가 발생하는 현상은 흔합니다. 원인은 **Kubernetes 계층과 AWS ELB 계층의 상태 동기화 지연**입니다. Pod에 SIGTERM이 전달되는 시점과 ALB가 그 Pod을 target group에서 deregister하는 시점이 비동기이고, 그 사이에 도착한 요청이 이미 닫히고 있는 Pod으로 라우팅되면 connection reset이 발생합니다.

AWS Containers 블로그의 [ALB 무중단 스케일 아웃 가이드](https://aws.amazon.com/ko/blogs/containers/how-to-rapidly-scale-your-application-with-alb-on-eks-without-losing-traffic/)와 [EKS Load Balancing best practice](https://docs.aws.amazon.com/eks/latest/best-practices/load-balancing.html)가 공통으로 권하는 구성 요소는 다음과 같습니다.

### IP target type

ALB가 Pod IP로 **직접** 트래픽을 보내게 합니다. Instance target type은 NodePort를 경유해 kube-proxy가 라우팅하는 구조여서 health check가 Pod 자체에 도달하지 않고 AZ 간 불필요한 hop도 생깁니다. AWS Load Balancer Controller와 IP target type 조합이 현재의 권장 표준입니다.

### Readiness Probe와 Pod Readiness Gate

`Ready=True`인 Pod만 EndpointSlice에 들어갑니다. 초기 기동이 긴 앱은 `initialDelaySeconds`와 `periodSeconds`를 실제 기동 시간에 맞춰야 합니다.

Pod Readiness Gate는 한 단계 더 들어간 보강입니다. Pod이 `Ready`가 되어도 ALB target으로 Healthy 상태가 되기까지 시간 차가 있어, 이 시간 창에 기존 Pod이 먼저 종료되면 트래픽 단절이 생깁니다. Readiness Gate는 AWS Load Balancer Controller가 **ALB target status가 Healthy가 되어야 Pod 조건을 Ready로 승격**하게 해, 롤링 업데이트 중 기존 Pod 종료를 지연시킵니다. 네임스페이스 라벨 하나로 자동 설정됩니다.

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: prod
  labels:
    elbv2.k8s.aws/pod-readiness-gate-inject: enabled
```

### SIGTERM 처리와 preStop sleep

두 가지는 보완 관계입니다. SIGTERM 핸들러는 in-flight request를 완료하고 DB connection/FD를 닫은 뒤 종료합니다. 이 정리 시간보다 `terminationGracePeriodSeconds`가 길어야 하고, 기본값 30초는 종종 부족합니다.

preStop hook은 **SIGTERM을 애플리케이션이 받기 전에** 수 초를 대기해 ELB deregister와 kube-proxy iptables rule 업데이트가 전파되도록 하는 버퍼입니다.

```yaml
lifecycle:
  preStop:
    exec:
      command: ["/bin/sh", "-c", "sleep 15"]
```

세션에서 강조된 포인트는 **SIGTERM 처리만 잘 해도 부족하다**는 것입니다. kube-proxy iptables rule이 전파되는 수 초 동안 새로 도착한 요청은 여전히 종료 중인 Pod으로 라우팅되고, server socket이 이미 닫히고 있으면 connection reset이 발생합니다. preStop sleep이 이 비동기 전파 시간을 흡수합니다.

### Rate-limit with PDB

모든 graceful shutdown 로직은 **한 번에 한 Pod씩** 종료될 때 유효합니다. 롤링 업데이트가 여러 Pod을 동시에 교체하면 개별 Pod의 preStop sleep 효과가 사라집니다. `PodDisruptionBudget`으로 동시 disruption 허용 수를 제한해야 합니다.

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: api-pdb
spec:
  minAvailable: 80%
  selector:
    matchLabels:
      app: api
```

세션에서 정리된 구성 요소는 ALB Controller, IP target type, Readiness Gate, SIGTERM 핸들러, `terminationGracePeriodSeconds`, preStop sleep, PDB입니다. 이 일곱 가지가 모두 맞물릴 때 롤링 업데이트 중 5xx가 해소됩니다.

## ConfigMap Auto-rollout

ConfigMap/Secret 변경은 Pod이 재시작되기 전까지 반영되지 않습니다. `kubectl rollout restart`로 수동 재시작하거나 env에 해시값을 추가하는 식으로 해결하지만, 서비스가 수십 개 넘어가면 누락이 생깁니다.

[Reloader](https://github.com/stakater/Reloader)는 ConfigMap/Secret 변경을 감지해 해당 리소스를 참조하는 Deployment/StatefulSet/DaemonSet을 자동 rollout하는 오픈소스 컨트롤러입니다. annotation 하나로 동작합니다.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  annotations:
    reloader.stakater.com/auto: "true"
```

세션에서 덧붙은 주의점은 **적용 범위를 선별**하라는 것이었습니다. RollingUpdate 전략과 PDB, Readiness Gate가 갖춰진 stateless API에는 `auto: true`가 편하지만, stateful 워크로드나 재시작 자체가 incident로 이어지는 서비스에는 `reloader.stakater.com/search: "true"` + 특정 ConfigMap 지정 방식이 안전합니다. 앞의 ALB 무중단 배포 구성이 함께 갖춰진 클러스터에서야 자동 rollout이 실제로 무중단입니다.

## Scaling Identity: IRSA vs Pod Identity

Week 4의 [Pod Workload Identity](../week4/4_pod-workload-identity.md)에서 두 방식의 구조적 차이를 다뤘습니다. 여기서는 **운영 규모에서 어느 쪽이 한도에 먼저 부딪히는가**를 정리합니다.

### IRSA Scale Limits

EKS 공식 비교[^sacompare]가 명시하는 IRSA의 확장 제약:

- **OIDC provider per account** — 계정당 기본 100개. IRSA는 클러스터마다 IAM에 OIDC provider를 등록하므로 클러스터가 이 한도를 넘어가면 IAM OIDC provider quota 상향이 필요합니다.
- **Trust policy 길이 제한** — 기본 2,048자. 하나의 IAM role을 여러 클러스터에서 재사용하려면 각 클러스터의 OIDC issuer와 service account 조건을 trust policy에 누적해야 합니다. 공식 문서는 기본 한도 내에서 **4개 trust relationship**을 담을 수 있고, 한도를 상향해도 한 policy당 **8개 정도가 현실적**이라고 명시합니다. 그 이상 공유하려면 role을 복제해야 하므로 IAM 관리 부담이 됩니다.

### How Pod Identity Scales

Pod Identity는 role trust policy를 **단일 EKS 서비스 principal** `pods.eks.amazonaws.com`로 고정합니다. 클러스터가 추가되어도 trust policy를 건드리지 않고, OIDC provider도 생성하지 않습니다. 또한 credential에 cluster ARN, namespace, service account, pod UID를 세션 태그로 자동 부착하므로, 이 태그를 ABAC 조건으로 활용하면 **하나의 role을 여러 namespace/cluster에서 공유하면서 접근 범위를 세분**할 수 있습니다.

### MSK Re-authentication Trap

세션에서 실전 함정으로 언급된 케이스입니다. Pod Identity Agent는 credential refresh마다 **STS session name을 동적으로 생성**합니다(예: `eks-k8s-wl-dev-engine-...-5af5e7ac-5754-...`). Kafka 클라이언트가 MSK에 IAM 기반으로 연결한 뒤 **재인증 시 principal이 바뀌면 hard failure**가 납니다.

```text
Cannot change principals during re-authentication from
IAM.arn:aws:sts::...:assumed-role/myRole/eks-k8s-...-session-A to
IAM.arn:aws:sts::...:assumed-role/myRole/eks-k8s-...-session-B
```

이 이슈는 [aws/containers-roadmap #2362](https://github.com/aws/containers-roadmap/issues/2362)에 Pod Identity Agent에 static session name 옵션을 추가해 달라는 요청으로 등록돼 있습니다. 현재 해결 전이므로 **MSK를 사용하는 워크로드는 IRSA를 유지**하는 것이 안전합니다.

!!! warning "MSK 외의 session-name-sensitive 서비스"
    클라이언트가 STS session name을 session identity의 일부로 삼는 다른 서비스에서도 같은 충돌이 가능합니다. long-lived connection과 IAM 기반 재인증 조합을 쓰는 워크로드는 Pod Identity 적용 전에 session name 재생성 동작과의 호환성을 확인해야 합니다.

### When to Pick Which

- **신규 클러스터, 일반 워크로드**는 AWS가 권하는 Pod Identity
- **MSK IAM auth Kafka 클라이언트**는 IRSA 유지
- **OpenShift, EKS Anywhere, self-managed**는 IRSA (Pod Identity는 EKS 전용)
- **하나의 role을 여러 클러스터/namespace에서 공유**하려면 Pod Identity + session tag ABAC

## 100K-Node Control Plane

대부분의 클러스터는 수천 노드 이하이지만, AWS는 2025 re:Invent에서 EKS가 **클러스터당 100,000 노드**까지 지원한다고 발표하며 control plane 내부 구조를 크게 바꿨습니다[^ultra].

주요 변경은 세 가지입니다.

- **etcd 분리 아키텍처** — Raft 합의를 내부 journal로 오프로드하고, 저장소를 fully in-memory로 전환
- **Hot resource 파티셔닝** — 단일 etcd가 아닌 key-space partitioning으로 hot resource를 분산
- **검증 스케일** — 10M+ Kubernetes objects, 32 GB 집계 etcd 크기 시나리오를 테스트에 포함

추가 튜닝으로 API server/webhook 최적화, cache 기반 consistent read, 대량 collection 효율적 읽기, custom resource binary encoding이 도입됐고, CoreDNS autoscaler는 1.5M QPS 환경에서 replica 4,000개까지 자동 확장하며 p99 query latency 1초 미만을 유지했다고 보고됩니다.

대부분의 변경은 control plane 내부 구현이라 일반 사용자 관점에서는 투명하지만, 운영 판단에 영향을 주는 지점은 있습니다.

- **대규모 CRD/Custom Resource** — 기존 etcd 8 GiB 한도가 실질 상한이었으나, 분할 구조로 천장이 한 곳에 몰리지 않습니다.
- **Kubernetes object 폭증 워크로드** — 10M+ objects 시나리오가 공식 테스트에 포함됐다는 것은 JobBatch, 대규모 CronJob, operator 기반 리소스 다량 생성 같은 패턴의 가능성을 넓혀 줍니다.

이 변경 배경은 [re:Invent 2025 CNS429 세션](https://reinvent2025.summary.events/?session=CNS429)([YouTube](https://www.youtube.com/watch?v=eFrSL5efkk0))과 [AWS Containers 블로그](https://aws.amazon.com/blogs/containers/under-the-hood-amazon-eks-ultra-scale-clusters/)에 더 자세히 나와 있습니다. 운영 규모가 수천 노드 이하여도 이 변경의 방향이 **resource 다량 생성 패턴에 대한 엄격함이 완화되는 쪽**임을 알고 있으면 설계 선택에 도움이 됩니다.

## Related Concepts

- **Graceful shutdown의 네 단계** — SIGTERM 수신 → `terminationGracePeriodSeconds` 카운트다운 → preStop hook → kubelet SIGKILL. preStop sleep을 너무 길게 잡으면 종료 시간이 전체 grace 기간을 갉아먹으므로 둘의 합을 항상 계산해야 합니다.
- **Session Tag ABAC의 한계** — Pod Identity의 자동 세션 태그는 강력하지만, 모든 AWS 서비스가 `aws:PrincipalTag` condition을 지원하지는 않습니다. 적용 전에 대상 서비스의 IAM condition 지원 여부를 확인해야 합니다.
- **Ultra Scale은 Control Plane 변경이지 워크로드 한도가 아닙니다** — Pod 수, 서비스 수, EndpointSlice 수 등 워크로드 레벨의 현실적 운영 한도는 여전히 노드, CNI, kube-proxy 쪽에서 걸립니다. control plane이 풀렸다고 워크로드 레벨 설계 원칙이 함께 완화되는 것은 아닙니다.

[^sacompare]: [AWS Docs — Comparing EKS Pod Identity and IRSA](https://docs.aws.amazon.com/eks/latest/userguide/service-accounts.html)
[^ultra]: [AWS Blog — Under the hood: Amazon EKS ultra scale clusters](https://aws.amazon.com/blogs/containers/under-the-hood-amazon-eks-ultra-scale-clusters/)
