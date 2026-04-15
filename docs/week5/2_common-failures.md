# Common Failures

현장에서 자주 만나는 EKS 장애 패턴과 공식 문서가 권하는 복구 절차를 정리합니다. 각 패턴은 증상 → 확인 → 원인 → 복구의 네 단계로 서술하며, 수치와 대응 명령은 AWS 공식 troubleshooting 가이드[^eks-ts]와 EKS Best Practices를 근거로 합니다.

각 패턴을 읽을 때 기본 접근은 [Debugging Methodology](1_debugging-methodology.md)의 First 5 Minutes triage를 전제합니다. 증상 층위와 원인 층위가 다를 수 있음을 잊지 말아야 합니다.

---

## Pod Startup Failures

Pod 기동 단계의 실패는 `kubectl get pods`의 `STATUS` 열에 가장 먼저 드러납니다. 세 가지가 자주 보입니다.

=== "CrashLoopBackOff"

    **증상** — `kubectl get pods`에 `CrashLoopBackOff`가 반복 표시되고 `RESTARTS` 카운트가 계속 증가합니다.

    **확인**

    ```bash
    kubectl describe pod <pod> -n <ns>          # events와 마지막 state.terminated.reason
    kubectl logs <pod> -n <ns> --previous       # 죽기 직전 컨테이너 로그
    kubectl logs <pod> -n <ns> -c <container>   # 특정 컨테이너 지정
    ```

    `describe` 출력에서 `Last State: Terminated`의 `Reason`, `Exit Code`, `Message`를 먼저 봅니다.

    **원인 분류**

    | Exit Code | Typical Cause |
    |---|---|
    | 1 | 애플리케이션 자체 예외 (설정, 의존성 오류) |
    | 2 | misuse of shell (명령 문법 오류, 파일 not found) |
    | 126 | Permission denied — 실행 권한 없음 |
    | 127 | Command not found — 이미지 안에 바이너리 없음 |
    | 137 | SIGKILL — OOMKilled 또는 liveness probe 실패로 강제 종료 |
    | 139 | Segmentation fault (glibc, native lib 이슈) |
    | 143 | SIGTERM — 정상 종료 신호를 받은 뒤 처리 실패 |

    **복구**

    - Exit 1/2/127: 이미지 entrypoint, command, 환경변수 확인, `kubectl exec`로 임시 컨테이너에서 재현
    - Exit 137: 메모리 limit 증가 또는 애플리케이션 메모리 프로파일 조정 (아래 OOMKilled 항목 참고)
    - liveness probe 실패: 초기 기동이 느린 앱은 `startupProbe` 추가. liveness는 단순 health, startup은 기동 시간 확보 용도

=== "ImagePullBackOff"

    **증상** — Pod이 `ImagePullBackOff` 또는 `ErrImagePull` 상태입니다.

    **확인**

    ```bash
    kubectl describe pod <pod> -n <ns> | grep -A5 Events
    ```

    Events 섹션에 `Failed to pull image ...`의 상세 메시지가 남습니다. 공식 가이드[^eks-ts]가 언급하는 4가지 전형 원인을 순서대로 검증합니다.

    **원인 분류**

    1. **이미지 이름, 태그 오타**: `:latest`의 캐시 혼선이나 registry 경로 오타로 발생합니다.
    2. **private registry 인증**: `imagePullSecrets`가 누락되거나 만료됩니다(ECR 토큰은 12시간).
    3. **네트워크 경로 차단**: VPC endpoint 미설정으로 ECR 접근이 불가하거나 NAT 경로에 문제가 있습니다.
    4. **IAM 권한**: 노드 instance profile에 `AmazonEC2ContainerRegistryReadOnly`가 누락되거나 pull-through cache 권한이 부족합니다.

    **복구**

    ECR 사용 시 확인 순서:

    ```bash
    # 노드에서 직접 pull 테스트 (eks-log-collector 또는 debug pod로)
    aws ecr get-login-password --region <region> | \
      docker login --username AWS --password-stdin <account>.dkr.ecr.<region>.amazonaws.com

    # IAM 권한 확인
    aws iam list-attached-role-policies --role-name <node-role>

    # VPC endpoint 상태
    aws ec2 describe-vpc-endpoints \
      --filters "Name=service-name,Values=com.amazonaws.<region>.ecr.*"
    ```

=== "Pending"

    **증상** — Pod이 `Pending` 상태로 스케줄링되지 않습니다.

    **확인**

    ```bash
    kubectl describe pod <pod> -n <ns> | tail -20
    ```

    가장 아래의 `Events` 섹션에 `Warning FailedScheduling`이 찍히고, 이 메시지가 원인을 지목합니다.

    **원인 분류 — `FailedScheduling` 메시지별**

    | Message | Cause |
    |---|---|
    | `0/N nodes are available: insufficient cpu` | CPU 총합 부족 — 노드 추가 또는 requests 조정 |
    | `0/N nodes are available: insufficient memory` | 메모리 총합 부족 — 노드 추가 또는 requests 조정 |
    | `N nodes are available: N node(s) had untolerated taint` | taint에 대한 toleration 누락 |
    | `had volume node affinity conflict` | PV의 AZ와 Pod이 요구하는 AZ 불일치 |
    | `didn't match Pod's node affinity/selector` | nodeSelector, affinity 표현식 미부합 |
    | `node(s) didn't have free ports` | hostPort 충돌 |

    **복구** — 메시지에 맞는 조치. Karpenter를 쓰는 클러스터라면 `Pending` 그 자체가 신규 노드 프로비저닝 트리거이므로, 수 분 대기 후에도 Pending이면 NodePool, NodeClass 설정을 확인합니다. 세부는 [Node Health and AZ Failures](3_node-health-and-az.md)에서 다룹니다.

---

## Pod Runtime Failures

기동은 성공했는데 런타임에 죽는 패턴입니다. 원인이 Pod 내부가 아니라 주변 환경(노드, 스토리지, 네트워크)에 있는 경우가 많습니다.

### OOMKilled

**증상** — `kubectl describe pod`에 `Last State: Terminated`, `Reason: OOMKilled`, `Exit Code: 137`. AMS Accelerate baseline alerts[^ams-alerts]도 "Container OOM killed"를 독립 알림 항목으로 정의할 만큼 흔한 이슈입니다.

**확인**

```bash
kubectl describe pod <pod> -n <ns> | grep -E "Reason|Exit Code|Limits"
kubectl top pod <pod> -n <ns>
# 노드 수준 OOM 여부
kubectl get events -n <ns> --field-selector reason=OOMKilling
```

**원인 분류**

| Location | Distinguishing Factor | Action |
|---|---|---|
| **Container limit 초과** | Pod 수준 OOM (해당 컨테이너만 kill) | `resources.limits.memory` 상향 또는 앱 프로파일링 |
| **Node 수준 OOM** | 노드 전체 메모리 고갈 (무관한 Pod이 evict) | Pod requests 정확히 설정, 노드 크기, 개수 증가 |

Node 수준 OOM은 `requests`가 실제 사용량보다 작게 설정된 Pod들이 한 노드에 몰려 overcommit된 경우가 대표적입니다. `kubectl top node`의 memory 수치와 `requests` 합을 비교해 overcommit 비율을 점검합니다.

!!! warning "Why limits alone is not enough"
    limits만 올리고 requests를 그대로 두면 스케줄러의 판단과 실제 사용량 격차가 커져 노드 수준 OOM 위험이 오히려 증가합니다. **requests도 실제 사용량에 맞춰 올려야** 노드 스케줄링이 건전해집니다.

### FailedMount

**증상** — Pod Events에 `Unable to attach or mount volumes` 또는 `MountVolume.SetUp failed`.

**확인**

```bash
kubectl describe pod <pod> -n <ns>
kubectl describe pvc <pvc> -n <ns>
kubectl get pv <pv> -o yaml

# CSI driver 로그 (EBS 예시)
kubectl logs -n kube-system -l app=ebs-csi-controller
```

**원인 분류**

1. **AZ 불일치**: EBS는 AZ-bound 리소스라서 Pod이 다른 AZ로 스케줄되면 attach할 수 없습니다. `topology.ebs.csi.aws.com/zone` 라벨 기반 스케줄링이 필요합니다.
2. **detach 지연**: 노드 교체 시 EBS가 이전 노드에 아직 붙어 있는 상태입니다. 공식 known-limit[^eks-quotas]에 "volume attachment limit of 28 for some Nitro instance types"가 명시되어 있으므로 Nitro 세대 인스턴스별 한도를 확인합니다.
3. **CSI driver IRSA 권한**: `ebs-csi-controller` ServiceAccount의 role에 `ec2:AttachVolume`, `ec2:DetachVolume`이 없습니다.
4. **보안 그룹**: EFS의 경우 노드 SG에서 NFS 포트(2049) egress가 차단됩니다.

### Node NotReady

**증상** — `kubectl get nodes`에 특정 노드가 `NotReady`. `kubectl describe node`의 `Conditions` 섹션에 구체 사유가 노출됩니다.

**확인**

```bash
kubectl describe node <node> | sed -n '/Conditions:/,/Addresses:/p'
```

Conditions에는 다음 조합이 나타날 수 있습니다[^eks-node-health].

| Condition | Meaning when True |
|---|---|
| `MemoryPressure` | 노드 메모리 임계치 초과, Pod eviction 가능 |
| `DiskPressure` | inode, 디스크 사용률 임계치 초과, 이미지 GC 개입 |
| `PIDPressure` | PID 한도 임박, 신규 프로세스 실패 위험 |
| `NetworkUnavailable` | 노드 라우팅 설정 문제 |
| `Ready=False` | kubelet heartbeat 단절 또는 컨테이너 런타임 실패 |

**복구 흐름**

1. **노드 수준 로그**: `NodeDiagnostic` CRD로 kubelet, containerd, dmesg를 수집합니다(Debugging Methodology 참고).
2. **cordon, drain 후 교체**: 임시 복구가 어려우면 `kubectl cordon`으로 신규 스케줄 차단, `drain` 뒤 노드 교체
3. **NMA가 설치돼 있으면 자동 복구**: Node Monitoring Agent + Auto Repair 조합[^eks-node-health]은 위 Conditions 중 다수를 감지해 자동으로 노드를 교체합니다. 설치 여부는 `kubectl get daemonset -n kube-system eks-node-monitoring-agent`로 확인합니다.

NMA의 상세 감지 조건과 감지 불가 영역은 [Node Health and AZ Failures](3_node-health-and-az.md)에서 별도로 다룹니다.

---

## Networking Failures

네트워크 층 장애는 Pod 상태는 `Running`인데 서비스가 동작하지 않는 양상으로 나타납니다. 증상 층위(Workloads)와 원인 층위(Networking)가 다른 대표 사례입니다.

### Service Endpoint가 비어 있음

**증상** — `curl service:port`가 timeout, `kubectl get endpoints`가 `<none>` 또는 누락된 Pod IP.

**확인**

```bash
# Service가 매칭하는 Pod이 실제로 Ready인지
kubectl get endpoints <svc> -n <ns>
kubectl get pods -n <ns> -l <service의 selector> -o wide

# Readiness probe가 통과하지 못했을 가능성
kubectl describe pod <pod> -n <ns> | grep -A5 Conditions
```

Service selector가 지목하는 Pod 중 **Ready 상태만** Endpoints에 들어갑니다. readiness probe가 실패 중이면 Pod은 살아 있어도 트래픽을 받지 못합니다. Pod Readiness Gate를 쓰는 경우는 추가 조건도 확인 대상이며, 이는 [Availability and Scale](4_availability-and-scale.md)에서 다룹니다.

### DNS Resolution 실패

**증상** — `kubectl exec`로 Pod에서 `nslookup kubernetes.default` 실행 시 timeout 또는 `NXDOMAIN`. 일시적 실패와 지속적 실패는 원인이 다릅니다.

**확인 — 공식 Support runbook 기반**

AWS는 `AWSSupport-TroubleshootEKSDNSFailure`[^ssm-dns]라는 자동화 runbook을 제공합니다. 이 runbook이 검사하는 항목을 그대로 수동으로 따라갈 수도 있습니다.

```bash
# 1) CoreDNS Pod 상태
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=100

# 2) CoreDNS Corefile 확인
kubectl get configmap coredns -n kube-system -o yaml

# 3) Pod 안에서 이름 해석
kubectl exec -it <pod> -n <ns> -- cat /etc/resolv.conf
kubectl exec -it <pod> -n <ns> -- nslookup kubernetes.default

# 4) 노드에서 VPC resolver로 직접 질의
kubectl debug node/<node> --image=nicolaka/netshoot \
  -- dig @169.254.169.253 amazon.com
```

**원인 분류**

1. **CoreDNS Pod 부족 또는 부하 쏠림**: 기본 replica 2개는 대형 클러스터에서 부족. EKS는 Kubernetes 1.25+ 클러스터 대상 **CoreDNS autoscaling**을 add-on 기능으로 제공[^coredns-autoscaling] — 10분 주기 peak 평가로 노드, CPU 기반 자동 스케일링.
2. **ENI 수준 패킷 throttling**: Linux는 VPC resolver로 보내는 DNS 요청을 모두 **primary ENI 주소를 source IP로 사용**합니다. 그리고 각 ENI에는 **초당 최대 1024 패킷**의 `link-local` 트래픽 한도가 있어, DNS 트래픽이 많으면 여기서 drop이 발생합니다[^eks-netperf].

!!! tip "Detecting and mitigating ENI 1024 pps DNS throttle"
    이 현상은 증상이 **간헐적 DNS 타임아웃**으로 나타나 단순 CoreDNS 성능 저하로 오진하기 쉽습니다. 공식 모니터링 가이드[^eks-netperf]가 제시하는 지표와 완화책은 다음과 같습니다.

    **탐지 메트릭** (ethtool, `cloudwatch_agent`로 수집)

    - `linklocal_allowance_exceeded` — VPC resolver로의 링크-로컬 트래픽 drop
    - `pps_allowance_exceeded` — ENI 전체 패킷 한도 초과
    - `conntrack_allowance_exceeded` — connection tracking 한도 초과

    EKS NMA가 설치돼 있으면 `LinkLocalExceeded`, `PPSExceeded`, `ConntrackExceeded` 조건으로 자동 노출됩니다[^eks-node-health].

    **완화 방법 (공식 권고)**

    1. **CoreDNS replica 증설 또는 autoscaling 활성화**[^coredns-autoscaling] — 질의가 더 많은 Pod으로 분산
    2. **NodeLocal DNSCache 도입**[^coredns-scale] — 각 노드에 로컬 캐시 DaemonSet을 두어 VPC resolver 질의 자체를 줄임. 이는 `link-local` 트래픽 감소로 직결
    3. **`ndots` 설정 조정**[^coredns-scale] — Pod의 `/etc/resolv.conf` `ndots:5` 기본값은 FQDN을 여러 번 검색하게 만듦. 공식 가이드는 `ndots`를 낮춰 search suffix 체인을 줄이라고 권장

### IP Exhaustion

**증상** — Pod이 `Pending` + Events에 `failed to assign an IP address to container`가 나타납니다. 다른 관점에서 보면 신규 Pod이 기동되지 않고, VPC CNI `ipamd` 로그에 `no IP addresses available` 메시지가 찍힙니다.

**원인** — 노드가 속한 서브넷의 가용 IP 또는 ENI당 할당 가능한 IP 수 소진.

**복구 전략 — EKS 공식이 권하는 세 갈래[^eks-ip-opt]**

=== "Prefix Delegation"

    ENI에 개별 IP가 아닌 `/28`(16개 IP) prefix 단위로 IP를 할당합니다. 노드당 Pod 밀도가 크게 늘어 **IP exhaustion 완화의 첫 선택지**[^eks-prefix-mode].

    ```bash
    kubectl set env ds aws-node -n kube-system \
      ENABLE_PREFIX_DELEGATION=true
    ```

    단, 서브넷이 파편화돼 `/28` 연속 블록을 찾을 수 없으면 비효율적. 신규 클러스터 또는 신규 노드 그룹부터 적용 권장.

=== "Custom Networking"

    Pod IP만 secondary CIDR(보통 100.64.0.0/10 같은 non-routable space)에서 할당하고, 노드 primary ENI의 IP는 routable subnet에 유지. **primary ENI가 Pod IP 할당에 사용되지 않으므로 노드당 최대 Pod 수가 줄어드는 trade-off** 존재.

    ```bash
    kubectl set env ds aws-node -n kube-system \
      AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true
    # ENIConfig CRD로 AZ별 secondary 서브넷 정의
    ```

=== "IPv6"

    VPC 전체를 dual-stack으로 전환. 주소 공간 제약 자체가 사실상 사라짐. 다만 **기존 IPv4 전용 onprem, downstream 시스템과의 호환성 검증**이 가장 큰 작업.

이 세 전략은 서로 배타적이지 않고 조합 가능합니다(예: IPv4는 Prefix Delegation + IPv6 병행). 구체 선택 기준과 운영 시 고려사항은 Week 2의 [IP Allocation Modes](../week2/2_ip-modes.md)와 연결됩니다.

---

다음 문서 [Node Health and AZ Failures](3_node-health-and-az.md)는 여기서 언급한 NMA의 감지 범위, Karpenter 장애 모드, AZ 장애에 대한 ARC Zonal Shift를 자세히 다룹니다.

[^eks-ts]: [Amazon EKS — Troubleshoot problems with Amazon EKS clusters and nodes](https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting.html)
[^ams-alerts]: [AMS Accelerate — Baseline alerts in monitoring and incident management for Amazon EKS](https://docs.aws.amazon.com/managedservices/latest/accelerate-guide/acc-baseline-eks-alerts.html)
[^eks-quotas]: [Amazon EKS Best Practices — Known Limits and Service Quotas](https://docs.aws.amazon.com/eks/latest/best-practices/known_limits_and_service_quotas.html)
[^eks-node-health]: [Amazon EKS — Detect node health issues with the EKS node monitoring agent](https://docs.aws.amazon.com/eks/latest/userguide/node-health-nma.html)
[^ssm-dns]: [AWS Systems Manager Automation — AWSSupport-TroubleshootEKSDNSFailure](https://docs.aws.amazon.com/systems-manager-automation-runbooks/latest/userguide/automation-awssupport-troubleshooteksdnsfailure.html)
[^coredns-autoscaling]: [Amazon EKS — Scale CoreDNS Pods for high DNS traffic](https://docs.aws.amazon.com/eks/latest/userguide/coredns-autoscaling.html)
[^coredns-scale]: [Amazon EKS Best Practices — Cluster Services (CoreDNS scaling, ndots, NodeLocal DNS)](https://docs.aws.amazon.com/eks/latest/best-practices/scale-cluster-services.html)
[^eks-netperf]: [Amazon EKS Best Practices — Monitoring EKS workloads for Network performance issues](https://docs.aws.amazon.com/eks/latest/best-practices/monitoring_eks_workloads_for_network_performance_issues.html)
[^eks-ip-opt]: [Amazon EKS Best Practices — Optimizing IP Address Utilization](https://docs.aws.amazon.com/eks/latest/best-practices/ip-opt.html)
[^eks-prefix-mode]: [Amazon EKS Best Practices — Prefix Mode for Linux](https://docs.aws.amazon.com/eks/latest/best-practices/prefix-mode-linux.html)
