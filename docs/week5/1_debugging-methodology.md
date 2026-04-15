# Debugging Methodology

EKS 장애 대응에서 가장 먼저 낭비되는 것은 시간입니다. 알림을 받은 직후 어디를 봐야 할지 정하지 못한 채 개별 Pod을 뒤지다 보면, 같은 원인으로 다른 네임스페이스까지 번진 장애를 뒤늦게 발견하게 됩니다. 이 문서는 **장애 범위를 좁히는 순서**, **처음 5분의 사용법**, 그리고 노드 레벨 로그를 확보하는 공식 경로를 정리합니다.

---

## Why Layering Matters

EKS는 control plane과 data plane의 **책임 주체가 분리된 공유 책임 모델**로 동작합니다. control plane은 AWS가 운영하고, data plane(노드, 네트워크, 스토리지, 워크로드)은 사용자가 책임집니다[^eks-reliability]. 장애 발생 시 책임 경계 안팎을 빠르게 판단하려면 먼저 **어느 층위의 문제인지**를 구분해야 합니다.

| Layer | Typical Symptoms | Investigation Start |
|---|---|---|
| Control Plane | `kubectl` 전체 지연, API timeout, webhook 실패 | `aws eks describe-cluster`, CloudWatch control plane logs |
| Nodes | `NotReady`, `DiskPressure`, kubelet 로그 다량 에러 | `kubectl describe node`, `NodeDiagnostic` CRD |
| Networking | Pod 간 통신 실패, DNS timeout, Service endpoint 비어 있음 | `kubectl get endpoints`, netshoot로 DNS/경로 확인 |
| Storage | PVC Pending, mount 실패, read-only filesystem | `kubectl describe pvc`, EBS CSI driver 로그 |
| Workloads | `CrashLoopBackOff`, `OOMKilled`, HPA scale 실패 | `kubectl describe pod`, `logs --previous` |
| Observability | 위 다섯 층의 상태를 언제, 어떻게 보는가 | Container Insights, Prometheus, audit log |

Observability가 독립된 장애 원인이 되는 경우는 드물지만, 관측이 비어 있으면 **같은 장애를 두 번 겪기 전까지 패턴을 보지 못합니다**. Observability 구성은 장애 대응 준비 단계에서 먼저 해야 할 일이며, 공식 Observability Best Practices[^eks-obs]도 MTTD(Mean Time To Detect), MTTR(Mean Time To Resolve) 단축을 가장 먼저 언급합니다.

!!! tip "Symptom layer vs root-cause layer"
    `CrashLoopBackOff`는 Workloads 층의 증상이지만, 원인은 CoreDNS 응답 지연(Networking), PVC mount 실패(Storage), 노드 메모리 압박(Nodes) 어디든 될 수 있습니다. 증상이 발생한 층을 먼저 파헤치기보다 **원인 후보 층부터 범위를 좁히면** 낭비를 줄일 수 있습니다.

---

## Two Directions

=== "Top-down — 증상에서 원인으로"

    결제 API 5xx 증상에서 시작해 Ingress → Service → Pod → Node → DNS 순서로 내려갑니다.

    **운영 incident에 적합합니다.** 영향을 받는 사용자가 있어 원인 규명보다 차단, 우회가 우선일 때 사용합니다.

=== "Bottom-up — 인프라에서 응용으로"

    Control Plane → Node → CNI/CoreDNS → Workload 순으로 아래에서 위로 올라갑니다.

    **예방 점검, 업그레이드 직후 검증에 적합합니다.** 현재 장애가 없는 상태에서 잠재 문제를 찾을 때 사용합니다.

실무에서는 초기 몇 분을 Top-down으로 써 영향 범위를 좁힌 뒤, 원인 후보 층이 생기면 그 층에 한해 Bottom-up으로 정밀 검증하는 방식이 일반적입니다.

---

## First 5 Minutes

알림을 받은 직후 5분은 **진단이 아니라 스코프 파악**에 써야 합니다. 개별 Pod `describe`로 곧장 파고드는 것이 가장 흔한 실패 패턴이며, 스코프가 없으면 같은 원인으로 다른 네임스페이스로 번진 장애를 뒤늦게 발견하게 됩니다.

**30초 — 클러스터가 살아 있는가**

```bash
aws eks describe-cluster --name <cluster> --query 'cluster.status'
kubectl get nodes
kubectl get pods -A --field-selector=status.phase!=Running | wc -l
```

`describe-cluster`가 `ACTIVE`가 아니거나 AWS Health Dashboard에 이벤트가 떠 있으면, 그 다음 단계는 무의미합니다. control plane 문제는 사용자가 복구할 수 없으므로 AWS Support 경로로 곧장 넘깁니다.

**2분 — 영향 범위는 어디까지인가**

```bash
kubectl get events -A --sort-by='.lastTimestamp' | tail -50
kubectl get pods -A -o wide | awk '{print $1, $4}' | sort | uniq -c
kubectl get pods -A --field-selector=status.phase=Failed \
  -o custom-columns=NODE:.spec.nodeName,NS:.metadata.namespace
```

네임스페이스, AZ, 노드별 실패 분포가 드러나면 원인 후보 층이 자연스럽게 좁혀집니다. 특정 AZ에 실패가 쏠리면 AZ 장애 가설, 특정 노드 그룹에 쏠리면 노드, CNI 가설, 네임스페이스 단위로 퍼지면 그 네임스페이스에 최근 배포된 변경사항을 의심합니다.

**5분 — 좁혀진 대상을 들여다보기**

```bash
kubectl describe pod <pod> -n <ns>
kubectl logs <pod> -n <ns> --previous
kubectl top pod <pod> -n <ns>
```

`--previous`는 반드시 붙입니다. 재시작 직후의 새 컨테이너 로그만 보면 원인을 덮어쓴 상태를 관찰하게 됩니다.

---

## Core Tool Set

이 다섯 도구로 대부분의 상황에 대응할 수 있습니다. 용도가 겹치지 않으니 목적에 맞게 고릅니다.

<div class="grid cards" markdown>

- :material-clipboard-text: **`kubectl describe`**

    ---
    events, conditions, 관련 객체(Endpoints, Events)를 한 번에 보여 줍니다. Pod 기동 실패 원인의 상당수는 여기서 파악됩니다.

- :material-history: **`kubectl logs --previous`**

    ---
    재시작 직전 컨테이너의 stdout/stderr를 확인합니다. `CrashLoopBackOff` 상태에서 원인 파악의 출발점입니다.

- :material-bug: **`kubectl debug`**

    ---
    Ephemeral container를 추가해 운영 Pod을 수정하지 않고 진단합니다. 원본 이미지에 도구가 없거나 `exec`가 막혀 있을 때 사용합니다.

- :material-wrench-outline: **netshoot**

    ---
    dig, curl, tcpdump, mtr이 담긴 네트워크 진단 이미지입니다. `kubectl debug --image=nicolaka/netshoot`과 짝으로 사용합니다.

- :material-server-network: **eks-log-collector**

    ---
    노드의 kubelet, containerd, CNI, dmesg 로그를 수집합니다. AWS 공식 troubleshooting 가이드[^eks-ts]가 Support 티켓 첨부 자료로 권장합니다.

</div>

### Ephemeral container 사용 패턴

원본 Pod을 건드리지 않고 같은 네트워크, PID 네임스페이스에서 진단할 때의 표준 형태입니다.

```bash
kubectl debug -it <pod> -n <ns> \
  --image=nicolaka/netshoot \
  --target=<container-name> \
  -- dig +short kubernetes.default
```

`--target`을 지정하면 PID 네임스페이스까지 공유되어 `/proc/<pid>/net/tcp` 같은 저수준 상태를 볼 수 있습니다. 생략하면 네트워크만 공유됩니다.

### 노드 레벨 로그 — `NodeDiagnostic` CRD

전통적인 `eks-log-collector`는 노드에 SSH 또는 SSM으로 접근해 스크립트를 실행하는 방식이라, 노드 접근 권한이 제한된 환경에서는 쓰기 어려웠습니다. Node Monitoring Agent(NMA)가 설치되어 있으면 `NodeDiagnostic` CRD를 만들어 **kubectl만으로 노드 로그를 S3에 수집**할 수 있습니다[^eks-node-logs].

```yaml
apiVersion: eks.amazonaws.com/v1alpha1
kind: NodeDiagnostic
metadata:
  name: ip-192-168-1-10
spec:
  logCapture:
    destination: "https://<bucket>.s3.amazonaws.com/..."  # pre-signed URL
```

흐름은 다음과 같습니다.

1. S3 PUT pre-signed URL 생성
2. `NodeDiagnostic` 리소스를 대상 노드 이름으로 생성
3. NMA가 노드에서 로그를 수집해 S3로 업로드
4. `status: Success`가 되면 S3에서 다운로드

EKS Auto Mode에서는 NMA가 기본으로 설치되어 있어 즉시 사용할 수 있고, MNG에서는 Node Monitoring Agent add-on을 추가로 설치해야 합니다. NMA 자체의 구조와 감지 범위는 [Node Health and AZ Failures](3_node-health-and-az.md)에서 다룹니다.

---

## Severity and Response

장애의 파급도에 따라 대응 창(window)과 에스컬레이션을 미리 정해 두면, 현장에서 에스컬레이션 대상 판단을 즉각 내릴 수 있습니다. devfloor9 playbook의 권장 기준은 다음과 같으며, P1, P2에서 원인 규명보다 차단, 우회를 우선하는 원칙은 AWS Security Incident Response 가이드[^eks-incident]가 권하는 **격리 우선** 접근과도 일치합니다.

| Level | Window | Example | Escalation |
|---|---|---|---|
| P1 — Critical | 5분 | Control Plane 다운, 전체 노드 NotReady | 온콜 즉시 + 매니지먼트 |
| P2 — High | 15분 | 단일 AZ 장애, 여러 Pod CrashLoopBackOff 확산 | 온콜 팀 |
| P3 — Medium | 1시간 | HPA scale 실패, 간헐적 5xx | 담당 팀 |
| P4 — Low | 4시간 | 단일 Pod 재시작, non-prod | 백로그 |

**차단, 우회의 표준 동작**은 상황에 따라 다르지만, AWS 공식 incident response 가이드가 제시하는 기본 패턴은 다음과 같습니다.

- **Pod 격리**: `NetworkPolicy`로 ingress/egress 모두 deny 처리해 추가 피해 차단
- **노드 cordon**: `kubectl cordon <node>`로 신규 스케줄 차단, 이후에 drain
- **AZ 격리**: ARC Zonal Shift로 해당 AZ로의 신규 트래픽 차단 (기존 Pod은 남김)
- **Volatile artifact 수집**: 메모리 덤프, `netstat`, 컨테이너 state, 로그 — **복구 전에** 확보

복구 전 증거 수집은 사후 분석의 전제입니다. 재시작으로 문제가 덮이면 같은 원인으로 다시 터질 때까지 추적이 불가능해집니다.

---

다음 문서 [Common Failures](2_common-failures.md)는 이 방법론을 `CrashLoopBackOff`, `OOMKilled`, `ImagePullBackOff` 같은 빈발 패턴에 적용해 증상 → 확인 → 원인 → 복구 네 단계로 정리합니다. AWS 공식 EKS troubleshooting 페이지[^eks-ts]도 같은 구조를 따르며, EKS Workshop troubleshooting lab[^eks-workshop-ts]은 실습 환경에서 직접 재현할 수 있는 경로를 제공합니다.

[^devfloor9-debug]: [devfloor9 engineering-playbook — EKS Debugging](https://devfloor9.github.io/engineering-playbook/docs/eks-best-practices/operations-reliability/eks-debugging)
[^eks-ts]: [Amazon EKS — Troubleshoot problems with Amazon EKS clusters and nodes](https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting.html)
[^eks-reliability]: [Amazon EKS Best Practices — Reliability](https://docs.aws.amazon.com/eks/latest/best-practices/reliability.html)
[^eks-obs]: [AWS Prescriptive Guidance — Best practices for streamlining Amazon EKS observability](https://docs.aws.amazon.com/prescriptive-guidance/latest/amazon-eks-observability-best-practices/introduction.html)
[^eks-node-logs]: [Amazon EKS — Retrieve node logs for a managed node using kubectl and S3](https://docs.aws.amazon.com/eks/latest/userguide/auto-get-logs.html)
[^eks-incident]: [Amazon EKS Best Practices — Incident response and forensics](https://docs.aws.amazon.com/eks/latest/best-practices/incident-response-and-forensics.html)
[^eks-workshop-ts]: [AWS EKS Workshop — Troubleshooting](https://www.eksworkshop.com/docs/troubleshooting/)
