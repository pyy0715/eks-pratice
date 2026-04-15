# Node Health and AZ Failures

노드 한 대가 죽는 장애와 AZ 하나가 장애를 겪는 장애는 성격이 다릅니다. 앞의 것은 신속히 **교체**하면 되고, 뒤의 것은 **격리**가 먼저입니다. EKS는 두 상황 모두를 자동화하는 기능을 갖추고 있습니다 — **Node Monitoring Agent(NMA) + Auto Repair**, 그리고 **ARC Zonal Shift**. 두 기능은 감지 대상과 동작 방식이 다르고, **함께 쓸 수 없는 조합**도 있어 운영에 혼선을 일으킵니다. 이 문서는 각각의 공식 동작 범위와 한계를 정리합니다.

기본 방법론은 [Debugging Methodology](1_debugging-methodology.md)를, 노드 레벨의 패턴 장애는 [Common Failures — Node NotReady](2_common-failures.md#node-notready)를 전제합니다.

---

## Node Monitoring Agent

NMA는 각 워커 노드에서 DaemonSet으로 동작하며 **노드 로그를 파싱해 문제를 `NodeCondition`으로 노출**합니다. 별도 관측 파이프라인을 구성하지 않아도 kubectl 한 번으로 노드 건강 상태가 드러나도록 설계됐습니다[^nma-intro]. 2026년 2월, AWS는 NMA를 오픈소스로 공개했고[^nma-oss] 소스는 `aws/eks-node-monitoring-agent`[^nma-repo]에서 확인할 수 있습니다.

### Detection Taxonomy

공식 문서[^eks-node-health-nma]가 정의하는 감지 대상은 크게 다섯 카테고리입니다.

| Category | Representative Conditions | Meaning |
|---|---|---|
| AcceleratedHardware | `NvidiaXIDError`, `NvidiaNVLinkError`, `NeuronHBMUncorrectableError` | GPU/Neuron 하드웨어 오류, ML 워크로드에서 특히 중요 |
| ContainerRuntime | `ContainerRuntimeFailed`, `KubeletFailed`, `PodStuckTerminating` | kubelet, containerd 레벨 기능 저하 |
| Kernel | `KernelBug`, `SoftLockup`, `ApproachingKernelPidMax` | 커널 수준 이상, OS 패치 유도 |
| Networking | `IPAMDNotReady`, `LinkLocalExceeded`, `PPSExceeded`, `ConntrackExceeded` | VPC CNI, ENI 수준 네트워크 이상 |
| Storage | `DeviceIOError`, `FilesystemReadonly` | 디스크, 파일시스템 장애 |

각 조건은 **Condition(지속 문제)** 과 **Event(일시적 이상)** 로 나뉩니다. Condition은 instance 교체, 재부팅 같은 복구 액션을 트리거할 수 있지만, Event는 단순 경고이므로 자동 복구의 대상이 아닙니다[^eks-node-health-nma].

!!! tip "PPSExceeded / LinkLocalExceeded as early DNS signals"
    [Common Failures의 DNS Resolution](2_common-failures.md#dns-resolution)에서 본 ENI 1024 pps 한도는 NMA가 `LinkLocalExceeded`, `PPSExceeded` 조건으로 직접 노출합니다. 이 조건이 `True`로 뜨는 노드는 DNS 타임아웃 재현 전에 선제 대응 대상이 됩니다.

### What NMA Cannot Detect

로그 파싱 기반이라는 구조적 한계 때문에 감지 불가 영역이 명확합니다.

- **전원 차단, 급작스런 H/W 실패**: 로그가 남기 전에 노드가 사라지므로 감지할 수 없습니다.
- **완전한 네트워크 단절**: 로그가 있어도 API 서버로 전달되지 않습니다.
- **kubelet/containerd 외부의 애플리케이션 결함**: NMA는 노드 수준만 관찰합니다. Pod 내부 앱 문제는 `DiskPressure`, `MemoryPressure`로 간접적으로 드러납니다.

이 영역은 표준 Kubernetes 제어(`NodeLease` 만료에 의한 `NotReady`, `node-lifecycle-controller`의 Pod eviction)에 의해 처리됩니다. NMA는 그 위에 추가된 관찰 레이어이지 대체 레이어가 아닙니다.

### Installation

NMA는 EKS add-on으로 설치됩니다. 오픈소스 공개 이후에는 Helm chart 방식도 지원됩니다[^nma-repo].

```bash
# EKS add-on으로 설치 (권장)
aws eks create-addon \
  --cluster-name <cluster> \
  --addon-name eks-node-monitoring-agent

# 설치 확인
kubectl get daemonset -n kube-system eks-node-monitoring-agent
```

**EKS Auto Mode는 NMA가 기본 포함**됩니다. Auto Mode를 쓰지 않는 MNG, self-managed 노드 그룹에서는 add-on을 별도로 추가해야 합니다.

---

## Auto Repair

NMA가 감지한 조건을 받아 **노드를 실제로 교체/재부팅**하는 것이 Auto Repair입니다. EKS MNG와 Karpenter 기반 노드 모두 지원하며, EKS Auto Mode에서는 기본 활성화됩니다[^node-repair].

### Condition → Action 매핑

| NodeCondition | Default Repair Action |
|---|---|
| `Ready=False` | Replace (표준 Kubernetes 조건, NMA 없이도 반응) |
| `AcceleratedHardwareReady=False` | Replace 또는 Reboot |
| `ContainerRuntimeReady=False` | Replace |
| `StorageReady=False` | Replace |
| `KernelReady=False` | Replace |
| `NetworkingReady=False` | Replace |
| 표준 `DiskPressure` / `MemoryPressure` / `PIDPressure` | **반응하지 않음** |

마지막 줄이 중요합니다. **`DiskPressure`, `MemoryPressure`, `PIDPressure`는 Auto Repair의 대상이 아닙니다**. 이 조건들은 일시적 부하에도 True가 될 수 있어, 자동 교체하면 오히려 장애를 키웁니다. NMA가 감지하는 더 세분화된 조건(예: `ApproachingMaxOpenFiles`)을 통해 근본 원인에 대응합니다.

### Guardrails

Auto Repair는 다음 안전 장치를 갖추고 있습니다[^node-repair].

- **Pod Disruption Budget 존중**: 기본 eviction은 best-effort로 PDB를 기다립니다. **최대 15분 후에는 강제 교체합니다.**
- **Unhealthy 노드 비율 상한**: MNG/NodePool의 노드 중 **20%를 초과**하면 Auto Repair가 중단됩니다. 대규모 장애 상황에서 cascading failure를 방지합니다.
- **동시 교체 개수 제한**: `nodeRepairConfigOverrides`로 동시 replace 수를 조정할 수 있습니다.

15분 강제 교체는 무시 못할 수치입니다. `terminationGracePeriodSeconds`가 긴 워크로드나 long-running job이 있다면 이 값이 그대로 강제 종료 기준이 된다는 점을 계산에 넣어야 합니다.

---

## ARC Zonal Shift

NMA, Auto Repair가 **노드 단위**의 문제를 다룬다면, ARC(Amazon Application Recovery Controller) Zonal Shift는 **AZ 단위**의 문제를 다룹니다.

### What Actually Happens

Zonal Shift는 AZ 하나를 클러스터에서 격리한다는 높은 수준의 표현을 갖지만, 내부적으로는 **여러 제어가 조합된 결과**입니다[^zonal-shift-pod-eviction].

1. **ELB 수준 트래픽 차단**: ALB/NLB가 해당 AZ로의 신규 트래픽을 중단합니다.
2. **EndpointSlice에서 Pod 제외**: 영향 AZ의 Pod이 Service routing에서 제거됩니다. east-west 트래픽도 차단됩니다.
3. **노드 cordon**: 영향 AZ의 노드에 신규 Pod 스케줄이 차단됩니다.
4. **Auto Scaling AZ rebalancing 중단**: 영향 AZ로 신규 용량이 배치되지 않도록 일시 중단합니다.
5. **건강한 AZ로 신규 노드 기동 유도**: EKS가 건강한 AZ에만 신규 노드를 배치합니다.

**기존에 실행 중인 Pod은 evict되지 않고 그대로 남습니다.** 트래픽만 끊기고 리소스는 유지되는 설계인 셈입니다.

### Scope and Limits

공식 문서가 명시하는 주요 제약[^zonal-shift-enable]:

- **Kubernetes Control Plane은 영향을 받지 않습니다** — ARC는 워크로드, 네트워크 계층만 조정합니다.
- **EKS Auto Mode에서는 지원되지 않습니다** — Auto Mode의 네트워킹/스케일링 제어가 자체적이기 때문입니다.
- **Karpenter 미지원** — Zonal Shift는 MNG, ASG 기반에서만 동작합니다.
- **연속 shift 간 60초 대기가 필요합니다.**
- **Fargate는 지원하지 않습니다.**

Karpenter 사용 클러스터에서는 AZ 장애 시 **topology spread constraint**와 Karpenter 자체의 Capacity Reservation/NodePool 조건으로 대응해야 하며, Zonal Shift는 ALB/NLB 레벨에서만 적용됩니다. 최종 end-to-end 커버리지를 원한다면 Istio, App Mesh 같은 서비스 메시와 조합하는 패턴이 AWS 블로그[^zonal-shift-istio]로 공개돼 있습니다.

### Manual vs Autoshift

=== "Manual Shift"

    운영자가 `aws arc-zonal-shift start-zonal-shift`로 명시적으로 시작합니다. AZ 영향이 감지되고 즉시 판단할 수 있을 때 사용합니다.

    ```bash
    aws arc-zonal-shift start-zonal-shift \
      --away-from use1-az1 \
      --expires-in 24h \
      --resource-identifier <cluster-arn> \
      --comment "AZ az1 impairment, rotate"
    ```

=== "Autoshift"

    AWS 내부 telemetry가 AZ 장애를 감지하면 **자동으로 shift를 시작합니다**. 사전 등록이 필요합니다. 테스트 목적의 **Practice Run**(예: 매일 30분 간격으로 연습 shift)도 지원합니다.

Autoshift는 준비를 요구합니다 — AZ 하나가 빠져도 나머지 AZ 용량으로 서비스가 가능해야 하며, 이는 사전 capacity 계획과 topology spread constraint 적용이 전제입니다.

!!! warning "Test before enabling Autoshift"
    Zonal Autoshift는 운영자 개입 없이 트래픽을 이동시킵니다. AZ 하나 손실을 견디지 못하는 capacity로 autoshift가 발동하면 **건강한 AZ로 이동한 트래픽이 그 AZ까지 쓰러뜨리는** 2차 장애가 납니다. 공식 가이드가 Practice Run을 별도 기능으로 제공하는 이유입니다.

---

## Karpenter Failure Modes

Karpenter 기반 클러스터는 장애 지점이 MNG 기반과 다릅니다. 공식 Karpenter troubleshooting 가이드[^karpenter-ts]가 짚는 주요 모드를 EKS 컨텍스트에 맞춰 정리합니다.

### Provisioning Failures

Pod이 `Pending`인데 새 노드가 생성되지 않는 경우입니다. 가장 흔한 원인 세 가지[^karpenter-ts]:

1. **리소스 요청 누락**: Pod에 `resources.requests`가 없으면 Karpenter는 최소 크기 추정이 어려워 bin-packing을 포기합니다. `LimitRange`로 네임스페이스 기본값을 강제하는 것이 권장 패턴입니다.
2. **CNI IP 고갈**: Karpenter가 새 노드를 띄워도 서브넷 IP가 없으면 Pod이 기동할 수 없습니다. 이는 [Common Failures — IP Exhaustion](2_common-failures.md#ip-exhaustion)의 세 전략(Prefix Delegation / Custom Networking / IPv6)과 연결됩니다.
3. **Volume attachment 한도**: PVC 사용 Pod이 노드당 EBS attachment 한도(Nitro 28)[^eks-quotas]를 초과해 기동에 실패합니다.

### Deprovisioning 차단

노드가 empty/underutilized인데 제거되지 않는 주된 이유는 **`karpenter.sh/do-not-disrupt: true` annotation**입니다[^karpenter-ts]. long-running job이나 상태를 가진 워크로드에 흔히 붙이는데, 반대로 **영원히 붙어 있으면 consolidation이 막혀 비용이 누적**됩니다. 주기적으로 이 annotation 사용 현황을 감사하는 것이 권장됩니다.

### Node Readiness 실패

Karpenter가 노드를 띄웠지만 `Ready`가 되지 않는 경우의 체크 포인트:

- `Ready=True` 진입 실패 (kubelet 부팅 이슈)
- GPU/EFA가 노드 allocatable에 등록되지 않습니다 (`vpc.amazonaws.com/pod-eni` 등)
- NodePool의 startup taint가 제거되지 않습니다 (GPU driver 설치 지연 등)

kubelet 부팅 자체가 실패하는 원인은 Security Group, 네트워킹, IAM 설정 문제가 가장 흔합니다[^karpenter-ts].

### Spot Interruption

Karpenter 자체에 spot interruption 처리가 내장돼 있어, **AWS Node Termination Handler(NTH)를 병행하면 recursive churn**이 발생합니다[^karpenter-ts]. NTH가 노드를 evict하고 Karpenter가 즉시 동일 타입을 재프로비저닝하는 루프입니다. 공식 권고는 **NTH의 `enableSpotInterruptionDraining`, `enableRebalanceDraining`을 비활성화**하거나 NTH 자체를 제거하는 것입니다.

---

## Decision Matrix

노드, AZ 수준 문제를 대할 때 각 기능의 역할을 정리하면 다음과 같습니다.

| Situation | Primary Action | Prerequisite |
|---|---|---|
| 개별 노드 kubelet/runtime 이상 | NMA 감지 → Auto Repair | NMA add-on 설치, MNG는 `nodeRepairConfig` 활성화 |
| GPU 워커의 하드웨어 이상 | NMA `NvidiaXIDError` → Replace | NMA + DCGM 구성 |
| AZ 전체 네트워크 impairment | Zonal Shift (Manual 또는 Autoshift) | MNG + ALB/NLB, Auto Mode/Karpenter 제외 |
| Karpenter Pending 노드 | NodePool, CNI, IAM 점검 | Karpenter troubleshooting 가이드 흐름 |
| spot interruption 연쇄 | NTH 제거 또는 drain 비활성화 | Karpenter의 내장 spot 처리 사용 |

[^nma-intro]: [AWS Containers Blog — Amazon EKS introduces node monitoring and auto repair capabilities](https://aws.amazon.com/blogs/containers/amazon-eks-introduces-node-monitoring-and-auto-repair-capabilities/)
[^nma-oss]: [AWS What's New — Amazon EKS Node Monitoring Agent is now open source (2026-02)](https://aws.amazon.com/about-aws/whats-new/2026/02/amazon-eks-node-monitoring-agent-open-source/)
[^nma-repo]: [GitHub — aws/eks-node-monitoring-agent](https://github.com/aws/eks-node-monitoring-agent)
[^eks-node-health-nma]: [Amazon EKS — Detect node health issues with the EKS node monitoring agent](https://docs.aws.amazon.com/eks/latest/userguide/node-health-nma.html)
[^node-repair]: [Amazon EKS — Automatically repair nodes in EKS clusters](https://docs.aws.amazon.com/eks/latest/userguide/node-repair.html)
[^zonal-shift-pod-eviction]: [AWS Prescriptive Guidance — Understand pod eviction during zonal disruptions](https://docs.aws.amazon.com/prescriptive-guidance/latest/ha-resiliency-amazon-eks-apps/pod-eviction.html)
[^zonal-shift-enable]: [Amazon EKS — Enable EKS zonal shift to avoid impaired Availability Zones](https://docs.aws.amazon.com/eks/latest/userguide/zone-shift-enable.html)
[^zonal-shift-istio]: [AWS Containers Blog — End-to-end recovery from AZ impairments in Amazon EKS using EKS Zonal shift and Istio](https://aws.amazon.com/blogs/containers/end-to-end-recovery-from-az-impairments-in-amazon-eks-using-eks-zonal-shift-and-istio/)
[^karpenter-ts]: [Karpenter — Troubleshooting](https://karpenter.sh/docs/troubleshooting/)
[^eks-quotas]: [Amazon EKS Best Practices — Known Limits and Service Quotas](https://docs.aws.amazon.com/eks/latest/best-practices/known_limits_and_service_quotas.html)
