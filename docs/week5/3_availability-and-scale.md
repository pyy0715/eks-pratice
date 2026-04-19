# Availability and Scale

앞 두 문서가 장애 발생 시의 대응을 다뤘다면, 이 문서는 장애가 나지 않도록 어떻게 운영하는가에 해당합니다.

## Zero-downtime Rolling Updates

Deployment 롤링 업데이트 중 간헐적으로 5xx가 발생하는 현상은 흔합니다. 원인은 Kubernetes와 AWS ELB 사이의 상태 전파가 비동기로 일어난다는 점에 있습니다. Pod에 SIGTERM이 전달되는 시점과 ALB가 그 Pod을 target group에서 deregister하는 시점 사이에 시간 차가 생기고, 이 창에 도착한 요청이 이미 소켓을 닫고 있는 Pod으로 라우팅되면 connection reset이 발생합니다.

AWS Containers 블로그의 [ALB 무중단 스케일 아웃 가이드](https://aws.amazon.com/ko/blogs/containers/how-to-rapidly-scale-your-application-with-alb-on-eks-without-losing-traffic/)와 [EKS Load Balancing best practice](https://docs.aws.amazon.com/eks/latest/best-practices/load-balancing.html)가 공통으로 권하는 구성은 IP target type, Pod Readiness Gate, graceful shutdown(SIGTERM과 preStop), PDB 네 가지입니다. 네 가지 모두 AWS Load Balancer Controller가 클러스터에 설치되어 있어야 동작합니다.

=== "IP target type"

    ALB가 Pod IP로 **직접** 트래픽을 보내게 합니다. Instance target type은 NodePort를 경유해 kube-proxy가 라우팅하는 구조여서 health check가 Pod 자체에 도달하지 않고 AZ 간 불필요한 hop도 생깁니다. AWS Load Balancer Controller와 IP target type 조합이 AWS가 현재 권장하는 표준 구성입니다.

=== "Pod Readiness Gate"

    `Ready=True`인 Pod만 EndpointSlice에 들어갑니다. 초기 기동이 긴 앱은 `initialDelaySeconds`와 `periodSeconds`를 실제 기동 시간에 맞춰야 합니다.

    Pod이 `Ready`가 되어도 ALB target이 Healthy로 바뀌기까지 시간 차가 있어, 이 창에 기존 Pod이 먼저 종료되면 트래픽 단절이 생깁니다. Readiness Gate는 AWS Load Balancer Controller가 ALB target status가 Healthy가 되어야 Pod 조건을 Ready로 승격하도록 만들어 롤링 업데이트 중 기존 Pod 종료를 지연시킵니다. 네임스페이스 라벨 하나로 자동 설정됩니다.

    ```yaml
    apiVersion: v1
    kind: Namespace
    metadata:
      name: prod
      labels:
        elbv2.k8s.aws/pod-readiness-gate-inject: enabled
    ```

=== "Graceful shutdown"

    Kubernetes의 Pod 종료는 다음 순서로 진행됩니다.

    ```mermaid
    flowchart LR
        A["(1) Pod Terminating<br>+ EndpointSlice 제외"] --> B["(2) preStop hook"]
        B --> C["(3) SIGTERM"]
        C --> D["(4) SIGKILL<br>(grace 만료 시)"]
    ```

    preStop과 SIGTERM handler는 이 순서에서 서로 다른 역할을 맡습니다.

    preStop hook은 EndpointSlice 제외 변경이 kube-proxy iptables rule과 ELB target group으로 전파되는 시간(보통 수 초, 대규모 클러스터에서는 더 길어질 수 있음)을 흡수하는 버퍼입니다. Pod이 `Terminating`으로 바뀌는 즉시 애플리케이션이 SIGTERM을 받고 소켓을 닫으면, 예전 iptables rule을 따라 이 Pod으로 라우팅되던 요청이 connection refused로 실패합니다. readiness probe를 일부러 fail시키는 방식으로 대체할 수 없는데, Pod이 `Terminating` 상태가 되는 순간 probe 실행 자체가 멈추고 EndpointSlice 제거는 probe 결과가 아닌 Pod 상태 변경을 트리거로 일어나기 때문입니다.

    ```yaml
    lifecycle:
      preStop:
        exec:
          command: ["/bin/sh", "-c", "sleep 15"]
    ```

    SIGTERM handler는 새 요청 수락을 중단하고 in-flight request를 마친 뒤 DB connection, file descriptor 같은 외부 자원을 정리합니다. 대부분의 웹 프레임워크는 SIGTERM을 받으면 즉시 종료하도록 동작하므로 graceful shutdown은 애플리케이션 코드로 명시 구현이 필요합니다. Node.js는 `server.close()`, Go는 `srv.Shutdown(ctx)`, Python Gunicorn은 `--graceful-timeout` 옵션을 사용합니다. 정리 시간이 `terminationGracePeriodSeconds`(기본 30초)를 넘기면 SIGKILL로 끊겨 connection leak이나 트랜잭션 중단이 발생하므로, 장시간 쿼리나 파일 업로드가 있는 워크로드는 90~120초로 연장이 일반적입니다.

    Docker 컨테이너가 shell script로 앱을 실행하면 shell이 PID 1이 되어 SIGTERM이 자식 프로세스로 전달되지 않는 경우가 있습니다. `exec`로 앱을 직접 실행하거나 [tini](https://github.com/krallin/tini) 같은 init 프로세스를 함께 써야 이 단계가 의도대로 동작합니다.

    preStop 시간은 `terminationGracePeriodSeconds`에 포함되므로 전체 grace period는 `preStop + 애플리케이션 정리 + 안전 여유`로 계산합니다. preStop 15초와 정리 60초가 필요하면 90초 이상이 되어야 합니다. Karpenter를 쓰는 경우 NodePool의 `terminationGracePeriod`가 Pod grace period의 상한으로 작용하므로 두 값을 함께 설계해야 consolidation으로 노드가 회수될 때 Pod이 중간에 끊기지 않습니다.

=== "PDB"

    모든 graceful shutdown 로직은 한 번에 한 Pod씩 종료될 때 제대로 동작합니다. 롤링 업데이트가 여러 Pod을 동시에 교체하면 개별 Pod의 preStop sleep 효과가 사라집니다. `PodDisruptionBudget`으로 동시 disruption 허용 수를 제한해야 합니다.

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

주의할 점은 적용 범위를 선별해야 한다는 것입니다. RollingUpdate 전략과 PDB, Readiness Gate가 갖춰진 stateless API에는 `auto: true`가 편하지만, stateful 워크로드나 재시작이 장애 신호로 해석되는 서비스에는 `reloader.stakater.com/search: "true"` + 특정 ConfigMap 지정 방식이 안전합니다.

앞서 다룬 ALB 무중단 배포 구성이 갖춰진 클러스터에서야 자동 rollout이 실제로 무중단입니다.

## Scaling Identity: IRSA vs Pod Identity

Week 4의 [Pod Workload Identity](../week4/4_pod-workload-identity.md)에서 두 방식의 구조적 차이를 다뤘습니다. 여기서는 운영 규모에서 어느 쪽이 한도에 먼저 부딪히는가를 정리합니다.

### IRSA Scale Limits

EKS 공식 비교[^sacompare]가 명시하는 IRSA의 확장 제약은 두 가지입니다.

<div class="grid cards" markdown>

- :material-counter: **OIDC provider per account**

    ---

    계정당 기본 100개. IRSA는 클러스터마다 IAM에 OIDC provider를 등록하므로 클러스터 수가 이 한도를 넘어가면 quota 상향이 필요합니다.

- :material-format-size: **Trust policy 길이 제한**

    ---

    기본 2,048자. 하나의 IAM role을 여러 클러스터에서 재사용하려면 OIDC issuer와 service account 조건을 trust policy에 누적해야 합니다. 기본 한도에서는 4개 trust relationship까지, 상향해도 한 policy당 8개 정도가 현실적이며, 그 이상 공유하려면 role을 복제해야 합니다.

</div>



### How Pod Identity Scales

Pod Identity는 role trust policy를 단일 EKS 서비스 principal `pods.eks.amazonaws.com`로 고정합니다. 클러스터가 추가되어도 trust policy를 건드리지 않고, OIDC provider도 생성하지 않습니다. 또한 credential에 cluster ARN, namespace, service account, pod UID가 세션 태그로 자동 부착되므로, 이 태그를 ABAC 조건으로 활용하면 하나의 role을 여러 namespace/cluster에서 공유하면서 접근 범위를 세분할 수 있습니다.

### MSK Re-authentication Trap

Pod Identity 전환에서 자주 걸리는 대표 사례는 Managed Streaming for Apache Kafka(MSK) IAM 인증을 쓰는 Kafka 클라이언트입니다. Pod Identity Agent는 credential refresh마다 STS session name을 동적으로 생성하는데(예: `eks-k8s-wl-dev-engine-...-5af5e7ac-5754-...`), MSK 브로커는 IAM 재인증 시 principal을 session name까지 포함해 이전 값과 비교합니다. session name이 달라지는 순간 재인증이 hard failure로 끝납니다.

```text
Cannot change principals during re-authentication from
IAM.arn:aws:sts::...:assumed-role/myRole/eks-k8s-...-session-A to
IAM.arn:aws:sts::...:assumed-role/myRole/eks-k8s-...-session-B
```

이 이슈는 [aws/containers-roadmap #2362](https://github.com/aws/containers-roadmap/issues/2362)에 Pod Identity Agent에 static session name 옵션을 추가해 달라는 요청으로 등록돼 있지만 해결 전입니다. 그때까지는 MSK를 사용하는 워크로드에서 IRSA를 유지하는 것이 안전합니다.

같은 메커니즘 때문에 다른 서비스에서도 충돌이 발생할 수 있습니다. long-lived connection 위에서 IAM 재인증을 수행하며 session name을 세션 identity의 일부로 검사하는 클라이언트라면 동일 증상이 재현되므로, Pod Identity 전환 전에 해당 워크로드를 non-prod에서 재인증 시나리오까지 점검합니다.

[^sacompare]: [AWS Docs — Comparing EKS Pod Identity and IRSA](https://docs.aws.amazon.com/eks/latest/userguide/service-accounts.html)
