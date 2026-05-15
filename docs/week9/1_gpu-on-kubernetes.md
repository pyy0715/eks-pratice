# GPU on Kubernetes

Kubernetes가 GPU를 인식하고 Pod에 할당하는 메커니즘을 다룹니다. 하드웨어 accelerator와 도구 생태계에 대한 배경 지식은 [Background](0_background.md)를 참고합니다.

---

## Device Plugin Framework

Kubernetes는 CPU/Memory 외의 하드웨어 리소스를 [Device Plugin Framework](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/device-plugins/)로 관리합니다. Device Plugin은 특정 벤더의 하드웨어를 Kubernetes가 인식하고 scheduling할 수 있게 해주는 gRPC 서버입니다. 각 GPU 노드에서 kubelet과 통신해야 하므로 **DaemonSet**으로 배포되어 GPU가 있는 모든 노드에 하나씩 실행됩니다. NVIDIA의 경우 `nvidia.com/gpu`라는 Extended Resource(CPU/Memory 외에 벤더가 정의하는 커스텀 리소스 타입)를 kubelet에 등록하여 scheduler가 GPU를 인식하게 합니다.

다음 세 가지 RPC로 동작합니다.

`Registration`
:   Plugin이 kubelet에 자신을 등록합니다. Unix 소켓 경로(`/var/lib/kubelet/device-plugins/`)와 리소스 이름을 전달합니다.

`ListAndWatch`
:   사용 가능한 디바이스 목록을 스트리밍합니다. 디바이스 상태가 변경(고장, 추가)되면 업데이트를 보내고, kubelet이 Node의 `Allocatable` 리소스를 API Server에 반영합니다.

`Allocate`
:   Pod가 노드에 scheduling되면 kubelet이 호출합니다. 컨테이너에 필요한 디바이스 경로, 환경변수, 볼륨 마운트를 반환하여 컨테이너 런타임이 GPU에 접근할 수 있게 합니다.

![Device Plugin 등록 프로세스 — Registration, gRPC Server, ListAndWatch, API Server 보고](https://yqintl.alicdn.com/41cfad37a780da81f4f01f6e43b944ee9ad2a175.png) *Source: [Getting Started with Kubernetes GPU Management and Device Plugin — Alibaba Cloud Blog](https://www.alibabacloud.com/blog/getting-started-with-kubernetes-%7C-gpu-management-and-device-plugin-implementation_596306)*

![Pod scheduling부터 GPU 할당까지 전체 워크플로우](https://yqintl.alicdn.com/3a9600ba5556e5ef8bcc7631c875f8694dc95f0b.png) *Source: [Getting Started with Kubernetes GPU Management and Device Plugin — Alibaba Cloud Blog](https://www.alibabacloud.com/blog/getting-started-with-kubernetes-%7C-gpu-management-and-device-plugin-implementation_596306)*

### GPU Management on EKS

위에서 설명한 Device Plugin의 설치 방식은 EKS 클러스터 유형에 따라 달라집니다.

=== "Standard EKS"

    표준 EKS에서는 Device Plugin을 직접 설치해야 합니다.

    | 방식 | 설명 |
    |---|---|
    | NVIDIA Device Plugin DaemonSet | Helm으로 직접 설치. 각 GPU 노드에서 `nvidia.com/gpu` 리소스를 등록 |
    | NVIDIA GPU Operator | Device Plugin + 드라이버 + Container Toolkit + GFD를 통합 관리하는 Operator |

    AMI에 따라 pre-install 범위가 다릅니다. **AL2023 NVIDIA AMI**는 호스트에 드라이버와 Container Toolkit이 포함되어 있어 Device Plugin DaemonSet만 추가하면 되고, **Bottlerocket NVIDIA AMI**는 Device Plugin까지 내장되어 별도 설치가 불필요합니다.

=== "EKS Auto Mode"

    Auto Mode는 accelerator 드라이버와 Device Plugin을 자동 관리합니다[^auto-acc]. NVIDIA, Trainium, Inferentia 모두 동일하게 처리되며, DaemonSet으로 보이지 않습니다(Auto Mode가 내부적으로 관리). 워크로드가 없으면 GPU 노드를 terminate합니다.

    사용자는 NodePool에 instance family와 taint만 정의하면 됩니다.

    ```yaml
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: gpu
    spec:
      template:
        spec:
          nodeClassRef:
            group: eks.amazonaws.com
            kind: NodeClass
            name: default
          requirements:
            - key: eks.amazonaws.com/instance-family
              operator: In
              values: [g6e, g6]
          taints:
            - key: nvidia.com/gpu
              effect: NoSchedule
    ```

    Auto Mode는 GFD를 배포하지 않습니다. `eks.amazonaws.com/instance-family` 같은 EKS managed label로 instance type을 지정하면, Auto Mode가 해당 instance에 맞는 드라이버를 provisioning합니다. 동일 NodePool 내에서는 드라이버 버전이 일관되므로 CUDA 버전 mismatch가 발생하지 않습니다.

=== "DRA Driver (K8s 1.34+)"

    Kubernetes 1.34부터 DRA 기반의 새로운 GPU 관리 방식이 도입되었습니다[^dra]. DRA는 Device Plugin을 **대체**하는 차세대 방식으로, 같은 노드에 Device Plugin과 동시에 설치할 수 없습니다.

    Device Plugin은 `nvidia.com/gpu: 1`처럼 정수 카운트로만 GPU를 등록하므로, scheduler가 GPU 모델이나 메모리를 구분할 수 없습니다. DRA는 세 가지 오브젝트로 이 한계를 해결합니다.

    - **ResourceSlice** — DRA 드라이버가 각 GPU 노드에서 자동 생성하여 API Server에 등록. 사용자가 직접 작성하지 않음
    - **DeviceClass** — 클러스터 관리자가 GPU 카테고리를 정의 (또는 DRA 드라이버 설치 시 기본 생성)
    - **ResourceClaimTemplate** — 워크로드 배포 시 사용자가 작성하여 GPU를 요청

    ```yaml
    # 1. ResourceSlice — DRA 드라이버가 노드별로 자동 생성
    #    각 GPU의 모델, 메모리, 토폴로지 등 속성을 API Server에 등록
    apiVersion: resource.k8s.io/v1
    kind: ResourceSlice
    metadata:
      name: gpu-node1
    spec:
      driver: gpu.nvidia.com
      nodeName: node-1
      devices:
        - name: gpu-0
          basic:
            attributes:
              model: { string: "NVIDIA-A100" }   # (1)
              memory: { int: 81920 }
    ```

    1. Device Plugin에서는 이 정보가 없어 scheduler가 "GPU 1개"만 알 수 있었지만, DRA에서는 모델, 메모리 등 속성을 기반으로 scheduling합니다.

    ```yaml
    # 2. DeviceClass — 클러스터 관리자가 GPU 카테고리를 정의
    #    CEL expression으로 조건을 지정
    apiVersion: resource.k8s.io/v1
    kind: DeviceClass
    metadata:
      name: gpu.nvidia.com
    spec:
      selectors:
        - cel:
            expression: device.driver == 'gpu.nvidia.com'
    ```

    ```yaml
    # 3. ResourceClaimTemplate — 워크로드가 GPU를 요청
    #    Device Plugin의 resources.requests와 완전히 다른 API
    apiVersion: resource.k8s.io/v1
    kind: ResourceClaimTemplate
    metadata:
      name: single-gpu
    spec:
      spec:
        devices:
          requests:
            - name: gpu
              exactly:
                deviceClassName: gpu.nvidia.com
                count: 1
    ```

    Scheduler는 Pod의 `ResourceClaimTemplate`을 보고, `DeviceClass`의 조건에 맞는 `ResourceSlice`가 있는 노드를 찾아 scheduling합니다. StorageClass → PVC → PV 관계와 유사한 구조입니다.

    | 기능 | Device Plugin | DRA Driver |
    |---|---|---|
    | GPU 등록 | 정수 카운트 (`nvidia.com/gpu: 1`) | `ResourceSlice` (모델, 메모리, 토폴로지) |
    | GPU 요청 API | `resources.requests` | `ResourceClaimTemplate` + `DeviceClass` |
    | GPU 공유 | 불가 | 같은 Pod 내 컨테이너 간 공유 가능 |
    | Multi-Node NVLink | 미지원 | ComputeDomain으로 지원 |
    | EKS Auto Mode / Karpenter | 지원 | **미지원** |

    !!! warning "DRA is incompatible with Auto Mode / Karpenter"
        DRA Driver는 Managed Node Group이나 Self-managed Node에서만 사용할 수 있습니다. 또한 현재 Bottlerocket AMI는 지원되지 않으며 AL2023 NVIDIA AMI만 사용 가능합니다.

[^auto-acc]: [Deploy an accelerated workload — Amazon EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/auto-accelerated.html)
[^dra]: [Manage NVIDIA GPU devices on Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/device-management-nvidia.html)

---

## GPU Scheduling Rules

Device Plugin이 등록한 GPU는 Extended Resource로 취급되며, CPU/Memory와 다른 규칙이 적용됩니다.

### Requests = Limits

```yaml
resources:
  requests:
    nvidia.com/gpu: 1    # (1)
  limits:
    nvidia.com/gpu: 1
```

1. Extended Resource는 `requests`와 `limits`가 반드시 동일해야 합니다. 다르게 설정하면 API Server가 거부합니다.

CPU는 time-sharing으로 여러 프로세스가 공유할 수 있고, Memory는 byte 단위로 분할 가능하므로 `requests < limits`(overcommit)가 허용됩니다. 하지만 GPU는 정수 단위의 물리 디바이스이므로 fractional allocation이나 overcommit이 불가능합니다. 물리 디바이스 수를 초과하여 할당하면 실제로 사용할 수 없기 때문에, API Server가 `requests ≠ limits`를 거부합니다.

`requests = limits`이면 Pod에 Guaranteed QoS class가 부여됩니다. Guaranteed Pod는 노드 리소스가 부족해도 가장 마지막에 eviction 대상이 되므로, 모델 로딩에 수 분이 걸리는 GPU 워크로드에서 안정적입니다.

???+ info
    GPU는 `limits`만 지정하면 Kubernetes가 자동으로 `requests`를 동일한 값으로 설정합니다. 반대로 `requests`만 지정하고 `limits`를 생략하면 API Server가 거부합니다. MIG를 사용하면 하나의 물리 GPU를 분할할 수 있지만, 각 인스턴스는 별도의 리소스 이름(`nvidia.com/mig-1g.5gb`)으로 등록됩니다.

### GPU Taint and Toleration

GPU 노드에는 `nvidia.com/gpu=true:NoSchedule` taint를 설정하여 GPU를 요청하지 않는 Pod의 scheduling을 방지합니다. taint 없이 운영하면 로그 수집기나 모니터링 DaemonSet이 GPU 노드에 배치되어 GPU 리소스를 낭비합니다.

```yaml
tolerations:
  - key: nvidia.com/gpu
    operator: Exists
    effect: NoSchedule
nodeSelector:
  karpenter.sh/nodepool: gpu
```

### CUDA Driver Version Pinning

CUDA 버전 불일치는 Kubernetes scheduler가 감지할 수 없는 문제입니다. scheduler는 `nvidia.com/gpu: 1`이라는 정수 카운트만 보고 배치하므로, 컨테이너의 CUDA 버전과 노드의 드라이버 버전이 호환되지 않아도 Pod를 scheduling합니다.

!!! warning
    이 mismatch는 scheduler가 아닌 **kubelet 수준**에서 발생합니다. 컨테이너가 요구하는 CUDA Toolkit 버전(예: 12.9)이 노드 드라이버가 지원하는 최대 CUDA 버전(예: 12.2)보다 높으면, 컨테이너 시작 후 CUDA 초기화에서 실패합니다. `CrashLoopBackOff`로 나타나고 로그에서 `CUDA driver version is insufficient for CUDA runtime version` 에러를 확인해야 합니다.

이 문제를 방지하려면 [GPU Feature Discovery(GFD)](https://github.com/NVIDIA/k8s-device-plugin/blob/main/docs/gpu-feature-discovery/README.md)가 노드에 자동 추가하는 라벨을 `nodeSelector`에 명시합니다. GFD는 NVIDIA GPU Operator 또는 Device Plugin과 함께 배포되며, CUDA 드라이버 버전, GPU 모델, 메모리 등의 라벨을 노드에 추가합니다.

| Label | Example | Description |
|---|---|---|
| `nvidia.com/cuda.driver-version.major` | `535` | 호스트 GPU 드라이버의 CUDA 메이저 버전 |
| `nvidia.com/cuda.runtime-version.major` | `12` | CUDA Runtime 메이저 버전 |
| `nvidia.com/gpu.product` | `NVIDIA-L40S` | GPU 모델명 |
| `nvidia.com/gpu.memory` | `46068` | GPU 메모리 (MiB) |

```yaml
nodeSelector:
  karpenter.sh/nodepool: gpu
  nvidia.com/cuda.driver-version.major: "535"        # (1)
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: nvidia.com/cuda.runtime-version.major
              operator: Gt
              values: ["11"]                 # (2)
```

1. 특정 드라이버 버전의 노드에만 scheduling합니다. Node Group별로 AMI 버전이 다르면 드라이버 버전도 달라지므로 pinning이 중요합니다.
2. Kubernetes `nodeAffinity`에는 `Gte`(이상) 연산자가 없으므로, `Gt` + `"11"`로 CUDA Runtime 12 이상을 표현합니다.

---

## Multi-GPU Parallelism

모델이 단일 GPU 메모리에 맞지 않으면 여러 GPU에 분산해야 합니다. 이때 GPU 간 데이터를 주고받는 물리적 연결(interconnect)의 대역폭이 parallelism 전략을 결정합니다[^vllm-parallel].

`PCIe`
:   CPU와 디바이스(GPU, SSD, NIC 등)를 연결하는 범용 버스입니다. GPU 간 통신도 가능하지만 CPU의 PCIe 스위치를 경유하므로 대역폭이 제한됩니다 (Gen5 x16 기준 ~128 GB/s 양방향).

`NVLink`
:   NVIDIA가 GPU 간 직접 통신 전용으로 만든 interconnect입니다. CPU를 거치지 않고 GPU끼리 직접 데이터를 주고받으며, PCIe의 5~7배 대역폭을 제공합니다 (A100: ~600 GB/s, H100: ~900 GB/s).

Instance별 NVLink/PCIe 사양은 [Background — GPU Instance Selection](0_background.md#gpu-instance-selection)을 참고합니다.

[^vllm-parallel]: [Parallelism and Scaling — vLLM Documentation](https://docs.vllm.ai/en/stable/serving/parallelism_scaling/)

`Tensor Parallelism (TP)`
:   하나의 레이어의 weight matrix를 여러 GPU에 쪼개서 동시에 계산합니다. 각 GPU가 부분 결과를 계산한 뒤, 매 레이어마다 **AllReduce**(모든 GPU가 자신의 부분 결과를 교환하여 동일한 전체 결과를 얻는 collective 통신)를 수행해야 합니다. 예를 들어 GPU 4장으로 TP를 하면 매 레이어마다 4장이 모두 데이터를 주고받아야 다음 레이어로 넘어갈 수 있으므로, GPU 간 대역폭이 전체 throughput을 결정합니다.

`Pipeline Parallelism (PP)`
:   모델을 레이어 단위로 순차 분할합니다(GPU 1이 레이어 1~40, GPU 2가 레이어 41~80). 레이어 경계에서 activation tensor만 한 번 전달하면 되므로 통신량이 TP에 비해 훨씬 적고, PCIe 대역폭에서도 동작합니다.

!!! warning "Do not use Tensor Parallelism without NVLink"
    [vLLM 공식 문서](https://docs.vllm.ai/en/stable/serving/parallelism_scaling/)에서 L40S 등 NVLink가 없는 GPU에서는 TP 대신 PP를 권장합니다. TP의 AllReduce는 **매 레이어마다** 발생합니다. 예를 들어 32-layer 모델을 GPU 4장으로 TP하면 forward pass에서 AllReduce가 32회 실행되고, 매번 가장 느린 링크가 끝날 때까지 전체 GPU가 대기합니다. NVLink(~600 GB/s)에서는 1회당 수십 μs로 무시할 수 있지만, PCIe(~128 GB/s)에서는 1회당 수백 μs~ms가 걸려 32회가 누적되면 GPU 계산 시간보다 통신 대기가 더 길어집니다. PP는 레이어 경계에서 activation을 1회만 전달하므로 이 문제가 없습니다.
