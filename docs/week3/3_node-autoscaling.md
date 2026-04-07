# Node Autoscaling

Pod 스케일링(HPA/VPA)은 기존 노드 안에서 워크로드를 조정하지만, 노드 자체의 리소스가 부족하면 새 Pod을 배치할 수 없습니다. [Pod Capacity](../week2/3_pod-capacity.md)에서 다뤘듯이 각 노드에 배치 가능한 Pod 수는 ENI와 kubelet 설정에 의해 제한되며, 모든 노드에서 requests 합이 allocatable 리소스에 도달하면 새 Pod은 Pending 상태로 남습니다. Node Autoscaling은 이 시점에 새 노드를 자동으로 프로비저닝하여 클러스터 용량을 확장합니다.

---

## CPA - Cluster Proportional Autoscaler

CPA(Cluster Proportional Autoscaler)는 노드를 직접 추가하지는 않지만, 클러스터 크기에 비례하여 특정 Deployment의 replica 수를 자동 조정합니다. `options.target`으로 대상 Deployment를 지정하면 어떤 워크로드든 비례 스케일링을 적용할 수 있으며, 대표적인 사용 사례는 CoreDNS, metrics-server 같은 클러스터 인프라 서비스입니다.

### Scaling Policies

CPA는 두 가지 매핑 정책을 지원합니다. 노드 수 기반과 CPU 코어 수 기반 중 클러스터 특성에 맞는 정책을 선택합니다.

=== "nodesToReplicas (ladder)"

    노드 수 구간별로 replica 수를 지정합니다. 노드 수가 해당 구간에 도달하면 대응하는 replica 수로 조정됩니다.

    ```yaml
    config:
      ladder:
        nodesToReplicas:
          - [1, 1]
          - [2, 2]
          - [3, 3]
          - [4, 3]   # 노드 4개일 때도 replica 3개 유지
          - [5, 5]
    ```

=== "coresToReplicas"

    CPU 코어 수를 기준으로 replica를 매핑합니다. 코어 밀도가 높은 인스턴스(예: `c5.4xlarge`)를 사용하는 클러스터에서는 노드 수보다 코어 수가 워크로드 부하를 더 정확히 반영합니다.

    ```yaml
    config:
      ladder:
        coresToReplicas:
          - [1, 1]
          - [64, 3]
          - [512, 5]
          - [1024, 7]
          - [2048, 10]
          - [4096, 15]
    ```

### Considerations

CPA는 노드 수 또는 코어 수라는 간접 지표를 기준으로 스케일링합니다. 클러스터 크기와 실제 워크로드 부하가 비례한다는 가정 아래 동작하므로, 노드 수가 같아도 워크로드 패턴에 따라 실제 부하는 크게 달라질 수 있어, 간접 지표만으로는 실제 수요를 정확히 반영하지 못할 수 있습니다. 이 한계를 보완하기 위해 HPA로 대상 워크로드의 실제 CPU 사용량이나 custom metrics를 기준으로 스케일링하는 접근이 함께 사용됩니다.[^scale-cluster-services]

EKS에서 CoreDNS를 스케일링하는 경우, CPA를 별도로 배포하는 대신 EKS CoreDNS addon의 내장 autoscaling을 사용할 수 있습니다. Control Plane 내장 컴포넌트가 $\max\!\left(\frac{\text{nodes}}{16},\, \frac{\text{cores}}{256}\right)$ 공식으로 필요한 replica 수를 계산하며, 10분 단위 피크 기간을 평가하여 scale-up은 즉시 수행하고 scale-down은 3분마다 33%씩 점진적으로 줄입니다.[^coredns-autoscaling] CoreDNS 부하를 근본적으로 줄이려면 NodeLocal DNS Cache를 DaemonSet으로 배포하여 노드 로컬에서 DNS 응답을 캐싱하는 방법도 있습니다.

```json title="EKS CoreDNS addon autoScaling 설정"
{
  "autoScaling": {
    "enabled": true,
    "minReplicas": 2,
    "maxReplicas": 10
  }
}
```

[^scale-cluster-services]: [AWS EKS Best Practices — Cluster Services](https://docs.aws.amazon.com/eks/latest/best-practices/scale-cluster-services.html) — Scale CoreDNS, NodeLocal DNS, ndots 설정 등 클러스터 서비스 스케일링 가이드
[^coredns-autoscaling]: [Scale CoreDNS Pods for high DNS traffic](https://docs.aws.amazon.com/eks/latest/userguide/coredns-autoscaling.html) — CoreDNS autoscaling formula 및 최소 버전 요구사항 참고

---

## CAS - Cluster Autoscaler

### How CAS Works

CAS(Cluster Autoscaler)는 Kubernetes 내장 기능이 아니라 별도로 설치해야 하는 구성 요소입니다. Kubernetes 1.8에서 GA되었으며, cluster-autoscaler Pod을 Deployment로 배포하여 사용합니다. ASG는 내부적으로 EC2 Fleet API를 호출하므로, 전체 프로비저닝 경로는 CAS → ASG → EC2 Fleet API가 됩니다.

![Cluster Autoscaler Architecture](https://docs.aws.amazon.com/images/eks/latest/best-practices/images/autoscaling/cas_architecture.png)
*[Source: AWS EKS Best Practices — Cluster Autoscaler](https://docs.aws.amazon.com/eks/latest/best-practices/cas.html)*

CAS의 스케일 아웃 기준은 노드의 CPU 부하 평균이 아니라 **Pending Pod의 존재 여부**입니다. kube-scheduler가 Pod을 배치할 노드를 찾지 못하면 Pending 상태가 되고, CAS는 이를 감지하여 ASG의 DesiredCapacity를 증가시킵니다. 반대로 requests 대비 사용량이 낮은 노드는 주기적으로 제거합니다.

스케줄링 가능 여부는 실제 리소스 사용량이 아니라 `resources.requests` 합계로 판단됩니다. 따라서 requests 설정이 CAS의 스케일링 동작에 직접적인 영향을 줍니다.

!!! warning "Requests misconfiguration"
    requests를 실제 사용량보다 높게 설정하면, 스케줄링 가능한 리소스가 빠르게 소진되어 실제 부하가 낮아도 Pending Pod이 발생하고, 이에 따라 Cluster Autoscaler가 불필요한 스케일 아웃을 유발할 수 있습니다. 반대로 requests를 너무 낮게 설정하면, 스케줄링 관점에서는 여유가 있어 Pending Pod이 발생하지 않아 Cluster Autoscaler 기반 스케일 아웃이 트리거되지 않습니다.

### Node Group Constraints

CAS는 하나의 노드 그룹에 속한 인스턴스들이 동일한 리소스(vCPU, 메모리)를 가진다고 가정합니다. Managed Node Group도 생성 시 capacity type(On-Demand 또는 Spot)을 지정해야 하므로, On-Demand/Spot, Intel/Graviton, 인스턴스 사이즈별로 노드 그룹을 분리해야 합니다. 요구사항이 복잡해질수록 노드 그룹 수가 기하급수적으로 증가합니다.[^cas-best-practices]

[^cas-best-practices]: [AWS EKS Best Practices — Cluster Autoscaler](https://docs.aws.amazon.com/eks/latest/best-practices/cas.html)

노드 그룹 구성 시 다음 원칙을 준수해야 CAS가 정확한 스케일링 판단을 내릴 수 있습니다.

- 동일 Node Group 내 모든 노드는 동일한 labels, taints, allocatable 리소스를 가져야 합니다. CAS는 노드 그룹의 대표 노드 하나를 기준으로 스케줄링을 시뮬레이션하기 때문에, 노드 간 구성이 다르면 잘못된 스케일링 판단으로 이어질 수 있습니다.
- ASG의 MixedInstancePolicies를 사용할 때는 CPU, Memory, GPU 스펙이 유사한 인스턴스 타입만 조합해야 합니다. 예를 들어 `c5.xlarge`(4 vCPU, 8 GiB)와 `c5.4xlarge`(16 vCPU, 32 GiB)를 같은 그룹에 혼용하면 CAS가 가용 리소스를 잘못 예측할 수 있습니다.
- 많은 수의 소규모 Node Group보다 적은 수의 대규모 Node Group이 확장성에 유리합니다. CAS는 각 Node Group을 개별적으로 평가하므로 그룹 수가 많아질수록 스케일링 판단에 필요한 연산 비용도 함께 증가합니다.

![On-Demand/Spot + Intel/Graviton 조합에 따른 노드 그룹 구성](https://d2908q01vomqb2.cloudfront.net/2a459380709e2fe4ac2dae5733c73225ff6cfee1/2023/05/18/image-2-1024x818.png)
*[Source: Amazon EKS 클러스터를 비용 효율적으로 오토스케일링하기](https://aws.amazon.com/ko/blogs/tech/amazon-eks-cluster-auto-scaling-karpenter-bp/)*

### Auto-Discovery

CAS는 ASG 태그를 기반으로 관리 대상 노드 그룹을 자동 탐색합니다. EKS Managed Node Group을 생성하면 다음 태그가 자동으로 부여되므로 별도 설정 없이 탐색이 가능합니다.

- `k8s.io/cluster-autoscaler/enabled: true`
- `k8s.io/cluster-autoscaler/<cluster-name>: owned`

CAS 배포 시 `--node-group-auto-discovery` 플래그에 이 태그를 지정합니다.

```bash
# cluster-autoscaler-autodiscover.yaml 내 주요 args
- --cloud-provider=aws
- --skip-nodes-with-local-storage=false
- --expander=least-waste
- --node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/<cluster-name>
```

### Key Parameters

Cluster Autoscaler는 command-line flags 기반으로 동작을 제어하며, 스케일 아웃뿐 아니라 스케일 다운 정책 역시 세밀하게 조정할 수 있습니다. 위 배포 예시에 포함된 `--expander`나 `--skip-nodes-with-local-storage`와 같은 옵션 외에도, 노드 제거 시점과 조건을 결정하는 다양한 파라미터를 제공합니다.

=== "Scale-Out"

    Pending Pod 발생 시 여러 노드 그룹이 후보가 될 수 있으며, `--expander`는 이 중 어떤 노드 그룹을 확장할지 결정하는 전략입니다. 1.23.0부터 `--expander=priority,least-waste`처럼 여러 전략을 조합할 수 있습니다.

    | Expander | Description |
    |---|---|
    | `random` | 기본값. 후보 노드 그룹 중 무작위로 선택합니다 |
    | `most-pods` | Pending Pod을 가장 많이 수용할 수 있는 노드 그룹을 선택합니다 |
    | `least-waste` | 노드 추가 후 남는 CPU/메모리가 가장 적은 노드 그룹을 선택합니다 |
    | `priority` | ConfigMap(`cluster-autoscaler-priority-expander`)에 정의한 우선순위에 따라 선택합니다 |
    | `price` | 비용이 가장 낮은 노드 그룹을 선택합니다 (AWS 미지원) |

=== "Scale-In"

    일정 시간 동안 사용률이 낮은 노드를 자동으로 제거하여 불필요한 비용을 줄입니다. 각 파라미터는 노드 제거 판단의 시점, 기준, 예외 조건을 세밀하게 조정합니다.

    | Parameter | Default | Description |
    |---|---|---|
    | `--scale-down-delay-after-add` | `10m` | 노드 추가 후 이 시간 동안 스케일 다운 평가를 수행하지 않습니다. 일시적인 트래픽 증가로 생성된 노드가 곧바로 제거되는 것을 방지합니다 |
    | `--scale-down-utilization-threshold` | `0.5` | 노드의 requests 총합이 Allocatable 대비 이 비율 이하인 경우, 해당 노드를 스케일 다운 후보로 간주합니다 |
    | `--scale-down-unneeded-time` | `10m` | 노드가 스케일 다운 후보 상태를 이 시간 이상 유지해야 실제 제거 대상이 됩니다 |
    | `--skip-nodes-with-local-storage` | `true` | `true`이면 emptyDir 등 로컬 스토리지를 사용하는 Pod이 있는 노드는 스케일 다운에서 제외됩니다. `false`이면 해당 노드도 제거 대상에 포함됩니다 |

### Over-Provisioning with Placeholder Pods

Cluster Autoscaler가 클러스터를 빈 노드 없이 최적화하면, 새로운 Pod이 생성될 때마다 노드 프로비저닝 지연이 발생할 수 있습니다. 기존 노드에 여유 자원이 있는 경우에는 컨테이너 이미지 pull과 초기화만으로 빠르게 실행되지만, 노드가 부족한 경우에는 인스턴스 생성 및 부팅 과정이 선행되어야 하기 때문입니다.

이 지연을 줄이기 위해, 우선순위가 낮은 placeholder Pod을 활용하여 노드에 미리 스케줄링 가능한 공간을 확보하는 방법이 있습니다.

1. placeholder Pod(`PriorityClass.value: -10`)이 노드에 배치되어 `resources.requests`만큼의 공간을 선점합니다.
2. 실제 워크로드가 생성되면, kube-scheduler는 더 높은 우선순위의 Pod을 위해 placeholder Pod을 preemption(선점)합니다.
3. 선점된 placeholder Pod은 Pending 상태로 전환됩니다.
4. Cluster Autoscaler가 이 Pending Pod을 감지하고 새로운 노드를 프로비저닝합니다.

placeholder Pod의 `resources.requests`는 실제 워크로드 중 가장 큰 Pod의 requests 이상이어야 합니다. 그보다 작으면 선점이 발생해도 워크로드가 해당 공간에 스케줄링되지 않습니다.

확보할 예비 노드 수는 스케일 아웃 빈도와 프로비저닝 소요 시간을 기준으로 산정합니다. AZ별 분산 배치가 필요한 경우 AZ 수만큼 over-provision합니다.[^cas-overprovisioning]

[^cas-overprovisioning]: [AWS EKS Best Practices — Overprovisioning](https://docs.aws.amazon.com/eks/latest/best-practices/cas.html) 참고

### ASG Scaling Policies

CAS가 DesiredCapacity를 직접 설정하는 방식 외에, ASG 자체도 아래 정책으로 용량을 조정할 수 있습니다. CAS와 ASG 정책을 동시에 활성화하면 서로 충돌할 수 있으므로, CAS를 사용할 때는 ASG 정책을 비활성화하는 것을 권장합니다.

<div class="grid cards" markdown>

- :material-stairs-up: **Simple/Step Scaling**

    ---
    CloudWatch 경보 임계값에 따라 단계별로 인스턴스를 추가하거나 제거합니다. 운영자가 직접 임계값과 조정 단위를 정의합니다.

    `Reactive` · `Manual`

- :material-target: **Target Tracking**

    ---
    목표 메트릭 값(예: 평균 CPU 50%)을 지정하면 Auto Scaling이 해당 값을 유지하도록 인스턴스 수를 자동 조정합니다.

    `Reactive` · `Automated`

- :material-calendar-clock: **Scheduled Scaling**

    ---
    정의한 일정에 따라 용량을 미리 조정합니다. 트래픽 패턴이 예측 가능한 시간대에 유용합니다.

    `Proactive` · `Manual`

- :material-chart-timeline-variant: **Predictive Scaling**

    ---
    과거 14일간의 메트릭을 분석해 향후 48시간의 수요를 예측하고, 증가 전에 선제적으로 확장합니다.

    `Proactive` · `Automated`

</div>

### Limitations

CAS는 ASG를 통해 EC2 인스턴스를 관리합니다. Kubernetes와 AWS가 동일한 인스턴스를 각자의 방식으로 관리하는 구조이기 때문에, 앞서 다룬 노드 그룹 증가 문제와 더불어 아래와 같은 구조적 제약이 존재합니다. 이러한 한계가 [Karpenter](4_karpenter.md)가 ASG를 거치지 않고 EC2 Fleet API를 직접 호출하는 방식으로 재설계된 배경이기도 합니다.

- CAS는 ASG의 DesiredCapacity를 조정하여 노드 수만 결정하며, 어떤 인스턴스를 제거할지는 ASG의 termination policy가 결정합니다. `kubectl delete node`로 Kubernetes에서 노드를 제거해도 EC2 인스턴스는 ASG에 그대로 남아 수동 정리가 필요하고, 반대로 특정 노드를 지정하여 스케일 다운하는 것도 직접 지원되지 않습니다.
- CAS → ASG → EC2 Fleet API 경로를 거치므로, Pending Pod 감지부터 노드 Ready까지 수 분이 소요될 수 있습니다. 이 지연 동안 워크로드는 스케줄링되지 못합니다.
- CAS는 주기적으로 Kubernetes API를 폴링하여 Pending Pod을 확인합니다. 클러스터 규모가 커질수록 API server 호출량이 증가하며, throttling으로 인해 스케일링 판단이 지연될 수 있습니다.

---

## Karpenter

CAS의 이러한 구조적 제약을 재설계하여, ASG 없이 EC2 Fleet API를 직접 호출하고 Kubernetes Watch API로 Pending Pod을 실시간 감지하는 것이 Karpenter입니다.
이에 대한 자세한 내용은 [Karpenter](4_karpenter.md) 문서에서 다룹니다.
