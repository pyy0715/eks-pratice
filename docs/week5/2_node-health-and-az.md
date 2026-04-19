# Node and AZ Resilience

노드 단일 장애와 AZ 전체 장애는 대응 방식이 다릅니다. 노드 장애는 교체로 복구하고, AZ 장애는 해당 AZ를 먼저 격리합니다. EKS는 이 두 흐름을 각각 자동화하는 기능(NMA, Auto Repair, ARC Zonal Shift)을 제공합니다.

## Node Monitoring Agent

NMA는 워커 노드에 DaemonSet으로 돌며 노드 로그를 파싱해 문제를 `NodeCondition`으로 노출하는 컴포넌트입니다. 별도 관측 파이프라인을 구축하지 않아도 `kubectl describe node`만으로 하드웨어, 커널, 네트워크, 스토리지 수준의 이상이 드러나도록 설계됐습니다. 파싱 결과인 조건만 Kubernetes API로 올라가고 로그 자체는 노드 밖으로 나가지 않습니다. 2026년 2월 오픈소스로도 공개됐습니다[^nmarepo].

### Operating Modes

NMA는 서로 다른 두 가지 방식으로 동작합니다. 이 섹션은 상시 모니터링의 동작을 다루며, 온디맨드 로그 수집은 [Common Failures — Collecting Node Logs](1_common-failures.md#collecting-node-logs)에서 설명하였습니다.

<div class="grid cards" markdown>

- :material-chart-line: **Continuous Monitoring**

    ---

    노드 로그를 상시 파싱해 `NodeCondition`을 갱신합니다. Auto Repair가 읽는 입력 신호로 쓰이며, 평상시 노드 상태 판단의 기준이 됩니다.

- :material-magnify-scan: **On-demand Diagnostic**

    ---

    운영자가 `NodeDiagnostic` 리소스를 만들면 그 시점의 로그를 묶어 S3 또는 노드 로컬에 수집합니다. 개별 노드를 깊이 조사할 때 사용합니다.

</div>

### Exposed Conditions

NMA는 공식 문서가 정의하는 다섯 가지 조건과 ENI 패킷 한도 관련 조건을 노출하며, 표준 Kubernetes 조건(`Ready`, `DiskPressure`, `MemoryPressure`)이 함께 보입니다. 각 조건은 지속 문제(Condition)와 일시적 이상(Event)으로 구분되며, Condition만 자동 복구 대상입니다[^nodehealth].

| Condition | Source | Meaning |
|---|---|---|
| `AcceleratedHardwareReady` | NMA | GPU 및 가속기 하드웨어 준비 상태 |
| `ContainerRuntimeReady` | NMA | containerd 런타임 상태 |
| `KernelReady` | NMA | 커널 수준 이상 여부 |
| `NetworkingReady` | NMA | 노드 네트워크 스택 상태 |
| `StorageReady` | NMA | 스토리지 마운트 및 디스크 상태 |
| `LinkLocalExceeded` | NMA | primary ENI link-local 1024 pps 한도 초과 |
| `PPSExceeded` | NMA | ENI PPS 한도 초과 |
| `ConntrackExceeded` | NMA | conntrack 테이블 한도 초과 |
| `Ready` | Kubernetes | kubelet 하트비트 상태 |
| `DiskPressure` | Kubernetes | 디스크 여유 공간 부족 |
| `MemoryPressure` | Kubernetes | 노드 메모리 부족 |

`LinkLocalExceeded`, `PPSExceeded`, `ConntrackExceeded`가 True로 뜨는 노드는 DNS 타임아웃이 재현되기 전에 선제 대응 대상이 됩니다. 동일 증상의 진단 흐름은 [Common Failures — DNS Timeouts from ENI Packet Limit](1_common-failures.md#dns-timeouts-from-eni-packet-limit)에서 다룹니다.

### Detection Blind Spots

NMA는 노드에서 수집한 로그를 파싱해 조건으로 변환하므로, 로그가 남지 않는 장애는 포착할 수 없습니다. 대표적으로 다음 상황이 사각지대입니다.

- 전원 차단이나 하드웨어 failure — 로그가 남기 전에 노드가 사라집니다.
- 완전한 네트워크 단절 — 로그가 API 서버로 전달되지 않습니다.
- kubelet과 containerd 외부의 애플리케이션 결함 — NMA는 노드 수준만 관찰합니다.

이 영역은 표준 Kubernetes 제어(NodeLease 만료에 의한 NotReady, node-lifecycle-controller의 Pod eviction)가 처리합니다. NMA는 표준 제어를 대체하지 않고 그 위에 덧붙는 관찰 계층입니다.

### Installing NMA

EKS Auto Mode는 NMA가 기본 포함됩니다. Managed Node Group과 self-managed 노드에서는 EKS add-on으로 설치하거나 Helm chart를 사용합니다.

```bash
aws eks create-addon \
  --cluster-name <cluster> \
  --addon-name eks-node-monitoring-agent
```

## Automatic Node Repair

NMA가 감지한 조건을 받아 노드를 실제로 교체하거나 재부팅하는 것이 Auto Repair입니다. EKS Auto Mode에서 기본 활성화되며, Managed Node Group과 Karpenter도 지원합니다[^noderepair].

공식 문서가 규정하는 조건별 기본 동작은 다음과 같습니다.

| Node Condition | Repair after | Action |
|---|---|---|
| `AcceleratedHardwareReady=False` | 10m | Replace (Managed Node Group은 Reboot도 가능) |
| `ContainerRuntimeReady=False` | 30m | Replace |
| `KernelReady=False` | 30m | Replace |
| `NetworkingReady=False` | 30m | Replace |
| `StorageReady=False` | 30m | Replace |
| `Ready=False` | 30m | Replace |
| `DiskPressure` / `MemoryPressure` / `PIDPressure` | — | 반응하지 않음 |

!!! warning
    `DiskPressure`, `MemoryPressure`, `PIDPressure`는 Auto Repair 대상이 아닙니다. 이 조건들은 워크로드 구성, 애플리케이션 동작, 리소스 limits 쪽 이슈인 경우가 많아 자동 교체가 오히려 장애를 키울 수 있기 때문입니다. 이때 Pod은 Kubernetes 표준 node pressure eviction으로 처리됩니다.

Auto Repair는 대규모 장애가 노드 전체 교체로 번지는 것을 막기 위해 다음 가드레일을 갖습니다[^noderepair].

- **Managed Node Group**: 노드 그룹이 5개를 초과하고 unhealthy 노드 비율이 20%를 초과하면 Auto Repair가 중단됩니다. ARC Zonal Shift가 발동되면 Auto Repair도 함께 중단됩니다.
- **Auto Mode / Karpenter**: NodePool 내 unhealthy 노드 비율이 20%를 초과하면 중단됩니다.

조건별 노드 지속 최소 시간, repair action, 최대 동시 repair 수는 `nodeRepairConfigOverrides`로 재정의할 수 있습니다.

Karpenter에서 Auto Repair를 쓰려면 feature gate `NodeRepair=true`를 활성화해야 합니다[^karpenterdisruption].

## ARC Zonal Shift

NMA와 Auto Repair가 노드 단위 문제를 다룬다면, ARC(Amazon Application Recovery Controller) Zonal Shift는 AZ 단위 문제를 다룹니다. impairment가 발생한 AZ로 향하는 네트워크 트래픽을 일시적으로 차단하는 기능입니다.

### Scope

AZ 격리라는 표현은 단순화된 표현이며, 내부적으로는 여러 제어가 조합됩니다.

- ELB 수준에서 해당 AZ로의 트래픽 중단
- EndpointSlice에서 해당 AZ의 Pod 제외 (east-west 트래픽 차단)
- Auto Scaling의 AZ rebalancing 중단
- Managed Node Group 사용 시 신규 노드를 정상 AZ에만 배치

기존 실행 중인 Pod은 evict되지 않습니다. 트래픽만 차단되고 리소스는 그대로 유지됩니다. shift가 만료되거나 취소되면 네트워크 구성은 원래대로 복원됩니다.

### Limits

공식 문서가 명시하는 제약은 다음과 같습니다[^zonalshift].

- Kubernetes Control Plane은 영향 범위 밖이며, ARC는 워크로드와 네트워크 계층만 조정합니다.
- EKS Auto Mode는 지원하지 않습니다. Auto Mode는 네트워킹과 스케일링을 자체 제어하기 때문입니다.
- 연속 shift 간 최소 60초 대기가 필요합니다. EKS의 상태 폴링이 요청을 순차적으로 반영하지 못할 수 있습니다.

Karpenter 클러스터에서는 Zonal Shift의 신규 노드 배치 제어가 적용되지 않습니다. Pod 분산은 topology spread constraint와 NodePool 조건으로 별도 설계해야 합니다. 트래픽 차단, 서비스 메시 라우팅, Pod 재배치를 아우르는 end-to-end 복구 패턴은 [AWS Containers 블로그의 Istio 조합 가이드](https://aws.amazon.com/ko/blogs/containers/end-to-end-recovery-from-az-impairments-in-amazon-eks-using-eks-zonal-shift-and-istio/)를 참고합니다.

### Manual vs Autoshift

=== "Manual Shift"

    운영자가 AZ 영향을 확인한 뒤 명시적으로 시작합니다.

    ```bash
    aws arc-zonal-shift start-zonal-shift \
      --away-from use1-az1 \
      --expires-in 24h \
      --resource-identifier <cluster-arn> \
      --comment "AZ az1 impairment"
    ```

=== "Autoshift"

    AWS 내부 telemetry가 AZ 장애를 감지하면 AWS가 자동으로 shift를 시작합니다. 사전 등록이 필요하며, Practice Run(정기 연습 shift)도 지원됩니다.

!!! warning
    Autoshift는 운영자 개입 없이 트래픽을 이동시킵니다. AZ 하나 손실을 감당하지 못하는 capacity 상태에서 autoshift가 발동하면 나머지 AZ에 트래픽이 몰려 해당 AZ까지 과부하가 되는 2차 장애로 이어질 수 있습니다. 공식 가이드가 [Practice Run](https://docs.aws.amazon.com/r53recovery/latest/dg/arc-zonal-autoshift.how-it-works.html)을 별도 기능으로 제공하는 이유입니다.

## Karpenter Failure Modes

Karpenter는 Managed Node Group과 장애 유형이 다릅니다. 공식 troubleshooting 가이드의 주요 모드는 다음과 같습니다[^karptrouble].

- **Pending Pod에 노드가 뜨지 않음** — `resources.requests` 부재로 Karpenter가 bin-packing 최소 크기를 추정하지 못하는 경우입니다. namespace `LimitRange`로 기본값을 설정하는 것이 권장 패턴이며, 증상이 재현되면 서브넷 IP 고갈과 Nitro 볼륨 attachment 한도도 확인합니다.
- **Deprovisioning 중단** — `karpenter.sh/do-not-disrupt: true` annotation이 남아 있으면 consolidation이 차단되어 비용이 누적됩니다. annotation 적용 범위를 주기적으로 점검합니다.
- **노드가 NotReady 상태에 머무는 경우** — kubelet 부팅 실패, GPU 또는 EFA의 allocatable 미등록, startup taint 미제거(드라이버 설치 지연 등)가 원인입니다. kubelet 부팅 실패 자체는 주로 SG, 라우팅, IAM 구성 문제입니다.
- **Spot interruption 루프** — Karpenter에 spot interruption 처리가 내장되어 있어, AWS Node Termination Handler(NTH)를 함께 배포하면 NTH가 drain한 노드를 Karpenter가 즉시 재프로비저닝하는 루프가 생깁니다. NTH의 spot과 rebalance draining을 비활성화하거나 NTH를 제거하는 것이 공식 권고입니다.

## Related Concepts

- **NodeLease** — kubelet이 주기적으로 lease를 갱신해 살아있음을 API 서버에 알리는 표준 메커니즘입니다. lease 갱신이 끊기면 노드는 NotReady로 전환됩니다. NMA가 로그 기반이라 놓치는 전원 차단, 네트워크 단절 같은 사각지대를 NodeLease가 커버합니다.
- **PDB와 Auto Repair의 상호작용** — Auto Repair는 기본 drain 동작을 따르므로 PDB를 일정 시간 기다립니다. PDB가 충족되지 않은 상태가 지속되면 `nodeRepairConfigOverrides`의 최대 대기 시간이 강제 종료 기준이 됩니다. `terminationGracePeriodSeconds`가 긴 워크로드는 이 설정과 함께 설계해야 합니다.
- **Zonal Shift와 Pod eviction의 관계** — Zonal Shift는 트래픽을 차단할 뿐 Pod을 직접 evict하지 않습니다. 실제 Pod 재배치는 Deployment나 ReplicaSet 같은 상위 controller가 노드 상태 변화를 감지해 트리거합니다. 어떤 조건이 eviction으로 이어지는지는 [AWS Prescriptive Guidance](https://docs.aws.amazon.com/prescriptive-guidance/latest/ha-resiliency-amazon-eks-apps/pod-eviction.html)에 시나리오별로 정리되어 있습니다.

[^nmarepo]: [GitHub — aws/eks-node-monitoring-agent](https://github.com/aws/eks-node-monitoring-agent)
[^nodehealth]: [AWS Docs — Detect node health issues and enable automatic node repair](https://docs.aws.amazon.com/eks/latest/userguide/node-health.html)
[^noderepair]: [AWS Docs — Automatically repair nodes in EKS clusters](https://docs.aws.amazon.com/eks/latest/userguide/node-repair.html)
[^karpenterdisruption]: [Karpenter Docs — Disruption: Node Auto Repair](https://karpenter.sh/docs/concepts/disruption/#node-auto-repair)
[^zonalshift]: [AWS Docs — Enable EKS zonal shift](https://docs.aws.amazon.com/eks/latest/userguide/zone-shift-enable.html)
[^karptrouble]: [Karpenter Docs — Troubleshooting](https://karpenter.sh/docs/troubleshooting/)
