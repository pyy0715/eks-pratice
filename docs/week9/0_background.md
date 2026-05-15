# Background: AI Workloads on EKS

EKS에서 AI/ML 워크로드를 운영하려면 하드웨어 accelerator, 서빙 엔진, 컨테이너 이미지, 노드 OS, Job scheduler까지 여러 계층에서 선택이 필요합니다. 이 문서는 각 계층의 선택지와 판단 기준을 정리합니다. GPU를 Kubernetes에서 scheduling하고 배포하는 메커니즘은 [GPU on Kubernetes](1_gpu-on-kubernetes.md)에서 별도로 다룹니다.

---

## AWS Accelerator Types

AWS는 세 가지 유형의 하드웨어 accelerator를 제공합니다.

| Accelerator | Instance Family | Use Case | Device Resource |
|---|---|---|---|
| NVIDIA GPU | G5, G6, G6e, P4, P5 | 범용 ML 학습/추론 | `nvidia.com/gpu` |
| AWS Trainium | Trn1, Trn2 | 대규모 모델 학습 최적화 | `aws.amazon.com/neuroncore` |
| AWS Inferentia | Inf1, Inf2 | 추론 비용 최적화 | `aws.amazon.com/neuroncore` |

NVIDIA GPU는 CUDA 생태계와의 호환성으로 가장 범용적이고, Trainium/Inferentia는 AWS Neuron SDK 기반으로 동일 성능 대비 비용이 낮지만 프레임워크 호환성 확인이 필요합니다.

???+ info "Trainium/Inferentia and Neuron Compiler"
    NVIDIA GPU는 범용 프로세서로, PyTorch의 **Eager Execution**(연산을 정의 즉시 실행) 모드에서 CUDA 커널을 바로 실행할 수 있습니다. 반면 Trainium/Inferentia는 ML 연산에 최적화된 전용 칩(ASIC)으로, 임의의 코드를 바로 실행할 수 없습니다. 연산 그래프를 먼저 구성한 뒤 칩에 맞게 AOT(Ahead-of-Time) 컴파일하는 [Neuron Compiler](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/compiler/index.html)가 필요합니다.

    컴파일 과정: PyTorch/JAX 모델 → Neuron Compiler(연산 그래프 분석, 정밀도 변환, NeuronCore 분배 최적화) → **NEFF**(Neuron Executable File Format) → Neuron Runtime이 칩에서 실행.

    이 사전 컴파일 단계 때문에 모델이나 batch size를 변경하면 다시 컴파일해야 하고(수 분~수십 분), 모든 PyTorch 연산이 Neuron Compiler에서 지원되는 것은 아닙니다. 비용이 저렴하지만 유연성은 NVIDIA GPU보다 낮습니다.

### GPU Instance Selection

NVIDIA GPU를 선택했다면, 다음은 어떤 instance family를 쓸지 결정합니다. G series와 P series는 용도가 다릅니다.

| Family | GPU | GPU Memory | NVLink | EFA | Use Case |
|---|---|---|---|---|---|
| G5 | A10G | 24 GB | - | - | 소규모 추론, fine-tuning |
| G6 | L4 | 24 GB | - | - | 비용 효율 추론 |
| G6e | L40S | 48 GB | - | - | 중규모 LLM 추론 |
| P4d | A100 | 40/80 GB | 600 GB/s | O | 대규모 학습, multi-GPU 추론 |
| P5 | H100 | 80 GB | 900 GB/s | O | 초대규모 학습 |

`G series`
:   추론과 경량 학습에 최적화되어 있습니다. 비용이 P series 대비 낮고 단일 GPU로 서빙하는 경우에 적합합니다. NVLink가 없으므로 multi-GPU Tensor Parallelism에는 부적합합니다.

`P series`
:   대규모 학습과 multi-GPU 추론에 최적화되어 있습니다. **NVLink**로 동일 노드 내 GPU 간 고속 통신이 가능하고, **EFA**(Elastic Fabric Adapter)로 노드 간 고속 통신을 지원합니다. EFA는 OS 커널을 bypass하여 애플리케이션이 네트워크 디바이스와 직접 통신하므로, 일반 TCP/IP(ENA) 대비 latency가 크게 낮습니다. Multi-node 분산 학습에서 노드 간 gradient 동기화가 병목이 되는데, EFA + NCCL 조합으로 이를 해결합니다. 비용이 높으므로 단일 GPU로 충분한 워크로드에서는 과도합니다.

!!! tip "Instance Selection"
    모델이 단일 GPU 메모리에 적재 가능하면 G series가 비용 효율적입니다. 모델 크기가 GPU 메모리를 초과하여 multi-GPU parallelism이 필요하면, NVLink가 있는 P series를 선택합니다. Quantization(INT8/FP8)으로 모델 크기를 줄여 G series에 맞출 수 있는지 먼저 검토하는 것이 권장됩니다. 자세한 parallelism 전략은 [GPU on Kubernetes — Multi-GPU Parallelism](1_gpu-on-kubernetes.md#multi-gpu-parallelism)을 참고합니다.

[네오사피엔스의 AWS G6e 기반 LLM 추론 최적화 사례](https://aws.amazon.com/ko/blogs/tech/neosapience-llm-inference-optimization-aws-g6e/)에서는 G5(A10G), G6e(L40S), G7e(RTX PRO 6000 Blackwell) 인스턴스를 벤치마크했습니다. 배치 크기 64 기준 G7e가 11,554 token/s로 처리량이 가장 높았으나, 실제 프로덕션 트래픽은 배치 크기 1-16에 집중되어 있었습니다. 최종적으로 G6e + INT8을 선택한 이유는 중소형 배치에서의 지연 예측성, 리전 가용성(G7e는 제한적), PrivateLink 기반 네트워크 구조에서의 교차 리전 통신 부담이었습니다. G5 대비 처리량 46% 향상, TTFT 39% 감소, 토큰당 비용 약 15% 절감을 달성했습니다. 벤치마크 수치는 성능의 상한선일 뿐, 프로덕션 최적화는 배치 분포, 네트워크 구조, 리전 제약을 종합적으로 고려해야 합니다.

---

## AI/ML Tooling on Kubernetes

Kubernetes에서 AI/ML 워크로드를 운영할 때 사용하는 도구 생태계입니다[^ml-on-eks].

[^ml-on-eks]: [Overview of AI and ML on Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/machine-learning-on-eks.html)

### Model Serving

ML 모델을 API로 노출하여 요청을 받고 추론 결과를 반환하는 도구들입니다. 각 도구는 GPU 최적화, 모델 패키징, 배포/운영 관리 중 어디에 무게를 두느냐가 다릅니다.

`vLLM` :fontawesome-brands-github: [vllm-project/vllm](https://github.com/vllm-project/vllm)
:   LLM 서빙에 특화된 오픈소스 엔진. PagedAttention(KV 캐시 동적 할당)과 Continuous Batching으로 GPU 메모리 효율과 throughput을 높입니다. OpenAI 호환 API를 내장하고 있어 기존 코드에서 endpoint URL만 교체하면 migration이 가능하고, HuggingFace 모델을 별도 컴파일 없이 바로 로딩할 수 있습니다. NVIDIA, AMD, Intel GPU를 모두 지원하며, 대부분의 cloud API endpoint에서 기본 backend로 사용됩니다.

`SGLang` :fontawesome-brands-github: [sgl-project/sglang](https://github.com/sgl-project/sglang)
:   구조화된 추론과 agent 워크로드에 최적화된 서빙 엔진. RadixAttention으로 prefix가 겹치는 워크로드(RAG, multi-turn chat)에서 vLLM 대비 높은 throughput을 제공합니다.

`TensorRT-LLM` :fontawesome-brands-github: [NVIDIA/TensorRT-LLM](https://github.com/NVIDIA/TensorRT-LLM)
:   NVIDIA GPU 전용 LLM 서빙 엔진. CUDA graph 최적화, fused kernel, Tensor Core acceleration으로 NVIDIA GPU에서 높은 성능을 추출합니다. 모델을 TensorRT 엔진으로 사전 컴파일해야 하므로 flexibility가 낮지만, NVIDIA GPU에 최적화된 낮은 latency를 제공합니다.

`Triton Inference Server` :fontawesome-brands-github: [triton-inference-server/server](https://github.com/triton-inference-server/server)
:   NVIDIA의 모델 서빙 플랫폼. vLLM, TensorRT-LLM, PyTorch, TensorFlow, ONNX 등 여러 서빙 엔진을 backend로 통합 관리합니다. LLM뿐 아니라 vision, speech 등 다양한 모델을 하나의 서버에서 운영할 때 사용하며, HTTP/gRPC API, model management, ensemble pipeline을 제공합니다.

`Ray Serve` :fontawesome-brands-github: [ray-project/ray](https://github.com/ray-project/ray)
:   Ray 기반 서빙 프레임워크. 여러 모델을 하나의 deployment로 compose하거나, 동적으로 모델을 교체할 수 있습니다. Ray 생태계(Ray Train, Ray Data)와의 통합이 강점이며, KubeRay operator로 Kubernetes에 배포합니다.

???+ info "vLLM vs SGLang"
    vLLM과 SGLang은 현재 LLM 서빙에서 가장 널리 사용되는 두 엔진입니다. 소규모 모델(7B~8B)에서는 SGLang이 RadixAttention 덕분에 H100 기준 약 29% 높은 throughput을 보이지만, 70B 이상 대형 모델에서는 차이가 3~5%로 줄어듭니다. prefix가 겹치는 워크로드(RAG, multi-turn chat, agent)에서는 SGLang이 유리하고, 멀티 벤더 GPU 환경이나 encoder-decoder 모델이 필요한 경우에는 vLLM이 적합합니다. HuggingFace Inference Endpoints도 기본값은 vLLM이고 SGLang을 대안으로 제공하고 있습니다.

### GPU Job Scheduling

기본 Kubernetes scheduler는 ML 학습 Job에 필요한 gang scheduling(모든 worker가 동시에 시작)이나 GPU topology-aware 배치를 지원하지 않으므로, multi-tenant GPU 클러스터에서는 별도 scheduler가 필요합니다.

`Slurm` :fontawesome-brands-github: [SchedMD/slurm](https://github.com/SchedMD/slurm)
:   HPC 진영의 표준 Job scheduler. GPU 클러스터의 자원 할당, 우선순위, queue 관리에서 가장 오랜 역사를 가지고 있습니다. Kubernetes와는 별도로 동작하며, AWS에서는 AWS Batch나 ParallelCluster를 통해 Slurm 기반 GPU 클러스터를 구성할 수 있습니다.

`Volcano` :fontawesome-brands-github: [volcano-sh/volcano](https://github.com/volcano-sh/volcano)
:   Kubernetes 환경에서의 batch scheduling 표준(CNCF 프로젝트). Gang scheduling(모든 worker가 동시에 시작), fair-share queue, preemption을 지원합니다. Kubernetes 위에서 분산 학습 Job을 운영할 때 가장 널리 사용됩니다.

`KAI Scheduler` :fontawesome-brands-github: [NVIDIA/KAI-Scheduler](https://github.com/NVIDIA/KAI-Scheduler)
:   NVIDIA가 오픈소스로 공개한 AI workload 전용 scheduler. Topology-Aware Scheduling(GPU/NVLink 토폴로지를 고려한 배치), 계층적 PodGroup, time-based fairshare를 지원합니다. DRA와의 통합이 설계 단계부터 고려되어 있으며, KubeCon NA 2025에서 AI workload scheduling의 reference 구현으로 부상했습니다.

---

## ML Container Images

서빙 엔진과 ML 프레임워크를 실제로 GPU 노드에서 실행하려면 컨테이너 이미지가 필요합니다. 노드 OS(Bottlerocket 등)에는 GPU 드라이버와 Device Plugin이 설치되어 있어 컨테이너가 GPU에 접근할 수 있지만, vLLM이나 PyTorch 같은 ML 프레임워크와 CUDA user-space 라이브러리(cuDNN, NCCL)는 컨테이너 이미지 안에 포함되어야 합니다. 이 의존성을 직접 관리하면 버전 충돌이 잦으므로, pre-built 이미지를 사용하는 것이 일반적입니다.

`AWS Deep Learning Containers (DLC)`
:   AWS가 관리하는 pre-built Docker 이미지로, ECR(`763104351884.dkr.ecr.<region>.amazonaws.com`)에서 제공됩니다. vLLM, PyTorch, TensorFlow, Neuron SDK 등 프레임워크별 이미지가 학습/추론 용도로 구분되어 있고, CUDA 라이브러리, EFA 드라이버, SOCI 지원이 포함되어 있습니다. EKS, ECS, SageMaker에서 사용할 수 있습니다[^dlc].

`NVIDIA NGC Catalog`
:   NVIDIA가 관리하는 GPU-optimized 컨테이너 이미지 레지스트리. TensorRT-LLM, Triton, PyTorch, NeMo 등 NVIDIA 도구의 공식 이미지를 제공합니다. `nvcr.io`에서 pull합니다.

[^dlc]: [AWS Deep Learning Containers](https://github.com/aws/deep-learning-containers)

???+ info
    GPU 워크로드의 컨테이너 이미지는 CUDA Toolkit, cuDNN, NCCL 등의 버전 조합이 정확해야 합니다. 예를 들어 vLLM 0.15 + CUDA 12.9 + Python 3.12 조합을 직접 빌드하면 의존성 충돌을 해결하는 데 시간이 걸립니다. DLC나 NGC 이미지는 이 조합이 테스트된 상태로 제공되므로, 커스텀 빌드 없이 바로 배포할 수 있습니다.

---

## Container OS for GPU Workloads

컨테이너 이미지가 결정되었으면, 그 이미지가 실행될 노드의 OS를 선택합니다. GPU 워크로드에서는 OS가 보안, 드라이버 관리, boot time에 직접 영향을 줍니다.

#### Why Container-Optimized OS

범용 Linux(AL2023, Ubuntu 등)에는 package manager, SSH, 다양한 시스템 데몬이 포함되어 공격 면적이 넓고, OS 업데이트 시 패키지 간 의존성 충돌이 발생할 수 있습니다. GPU 노드에서는 NVIDIA 드라이버, Container Toolkit, Device Plugin의 버전 조합이 중요한데, 범용 OS에서는 이 조합을 직접 관리해야 합니다.

Container-optimized OS는 컨테이너 실행에 필요한 최소 component(containerd, kubelet)만 포함하고 나머지를 제거하여 이 문제를 해결합니다.

### Bottlerocket

[Bottlerocket](https://docs.aws.amazon.com/eks/latest/userguide/eks-optimized-ami-bottlerocket.html)은 AWS가 관리하는 container-optimized Linux입니다.

| Attribute | Amazon Linux 2023 | Bottlerocket |
|---|---|---|
| Purpose | 범용 서버 | 컨테이너 전용 |
| Installed software | 패키지 매니저, shell, SSH 등 | `containerd` + `kubelet`만 |
| SSH access | 가능 | 불가 (SSM으로만 접근) |
| OS update | `yum update` (패키지 개별) | 원자적 업데이트 (전체 OS 교체, 실패 시 rollback) |
| Root filesystem | 읽기/쓰기 | 읽기전용 |
| Attack surface | 넓음 | 최소화 |
| Boot time | 보통 | 빠름 (경량) |

#### GPU AMI

Bottlerocket은 GPU instance용 AMI를 별도로 제공합니다. 이 AMI에는 NVIDIA 드라이버, Container Toolkit, Device Plugin이 pre-install되어 있어, 표준 EKS처럼 GPU Operator나 Device Plugin DaemonSet을 직접 설치할 필요가 없습니다. EKS Auto Mode에서는 GPU instance를 provisioning할 때 이 AMI가 자동 선택됩니다[^auto-accelerated].

[^auto-accelerated]: [Deploy an accelerated workload — EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/auto-accelerated.html)

![Bottlerocket GPU AMI + Device Plugin](https://static.us-east-1.prod.workshops.aws/public/f03c4506-a01e-47de-89fb-051911565b16/static/images/100-intro/ami-device-plugin.png)

#### SOCI Snapshotter

ML 컨테이너 이미지는 보통 5~20GB로 크기가 큽니다. 일반적인 컨테이너 이미지 Pull은 모든 레이어를 순차적으로 다운로드하고 압축 해제한 뒤에야 컨테이너를 시작할 수 있으므로, GPU 노드에서 새 Pod를 시작할 때 수 분의 cold start가 발생합니다. SOCI(Seekable OCI)는 이미지 레이어에 대한 인덱스를 미리 생성해두고, 컨테이너가 실제로 접근하는 파일만 on-demand로 fetch합니다. 전체 이미지를 다운로드하지 않고 컨테이너를 즉시 시작할 수 있어, GPU 워크로드의 autoscaling이나 Pod 재시작 시 대기 시간을 크게 줄입니다. EKS Auto Mode는 G, P, Trn 계열 인스턴스에서 로컬 NVMe 스토리지를 활용하여 SOCI를 추가 구성 없이 자동 활성화합니다[^soci].

[^soci]: [EKS Auto Mode release notes — November 19, 2025](https://docs.aws.amazon.com/eks/latest/userguide/auto-change.html)

---

## GPU Metrics

GPU 워크로드의 성능을 파악하려면 GPU 하드웨어 수준과 LLM 애플리케이션 수준 모두에서 메트릭을 수집해야 합니다.

#### DCGM Exporter

[NVIDIA DCGM Exporter](https://github.com/NVIDIA/dcgm-exporter)는 GPU 하드웨어 메트릭을 Prometheus 형식으로 노출하는 DaemonSet입니다. GPU 노드에만 배포되어 포트 9400의 `/metrics` endpoint를 제공합니다.

| Metric | PromQL | Description |
|---|---|---|
| GPU Temperature | `DCGM_FI_DEV_GPU_TEMP` | GPU 온도 (°C) |
| GPU Power Usage | `DCGM_FI_DEV_POWER_USAGE` | GPU별 전력 소비 (W) |
| GPU SM Clocks | `DCGM_FI_DEV_SM_CLOCK` | Streaming Multiprocessor 클럭 속도 (Hz). thermal throttling 시 하락 |
| GPU Utilization | `DCGM_FI_DEV_GPU_UTIL` | GPU가 어떤 작업이든 하고 있는 시간 비율 (%) |
| Tensor Core Utilization | `DCGM_FI_PROF_PIPE_TENSOR_ACTIVE` | 행렬 연산에 쓰이는 Tensor Core 활용률 (%). LLM 추론 효율 지표 |
| Framebuffer Memory Used | `DCGM_FI_DEV_FB_USED` | 모델 가중치 + KV 캐시가 차지하는 GPU 메모리 (MiB) |

GPU Utilization과 Tensor Core Utilization은 다른 지표입니다. GPU Utilization은 GPU가 작업을 수행하는 시간 비율이고, Tensor Core Utilization은 그 중에서 행렬 연산(ML 추론의 핵심)에 Tensor Core가 활용되는 비율입니다. LLM 추론 시 Tensor Core Utilization이 높아야 GPU를 효율적으로 쓰고 있다는 의미입니다.

#### vLLM Metrics

vLLM은 `/metrics` endpoint에서 추론 관련 메트릭을 Prometheus 형식으로 제공합니다.

`TTFT` (Time to First Token)
:   요청 수신부터 첫 번째 토큰 생성까지의 시간. 사용자가 응답이 시작되었다고 느끼는 시점을 결정하며, 대화형 AI에서 UX에 직접 영향을 줍니다.

`TPOT` (Time Per Output Token)
:   토큰 하나를 생성하는 데 걸리는 시간. streaming 응답에서 텍스트가 나타나는 속도를 결정합니다.

`Time in Queue`
:   요청이 처리 대기열에서 기다린 시간. 이 값이 높으면 GPU 용량이 부족하다는 신호이며 Pod 수평 확장이나 GPU 노드 추가를 고려해야 합니다.

`Num Preemptions Total`
:   요청 preemption 횟수. KV 캐시 메모리가 부족하면 진행 중인 요청을 중단하고 나중에 재처리합니다. 이 값이 높으면 `gpu_memory_utilization`을 낮추거나 `max-model-len`을 줄여야 합니다.
