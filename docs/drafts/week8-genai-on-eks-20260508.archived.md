<!-- WEEK: 8 -->
<!-- TOPIC: genai-on-eks -->
<!-- CREATED: 2026-05-08 -->
<!-- DIRECTION: 워크샵 절차는 간단히 흐름만. 핵심은 개념 정리:
     - EKS Auto Mode (NodePool/NodeClass, 내부 Karpenter, Bottlerocket)
     - Terraform 부트스트래핑 패턴 (provider 초기화 문제, _LOCAL 복사)
     - GPU 인스턴스 운영 (ODCR, Service Quota)
     - ArgoCD self-hosted vs Managed (EKS Capability)
     - Addon 구성과 Auto Mode의 자동 관리 범위
-->

---
## 레포 구조 (ai-on-eks)

AWS의 GenAI on EKS 오픈소스 프로젝트(awslabs/data-on-eks) clone.
크게 3개 레이어:

### infra/ — Terraform 인프라 코드
- `infra/base/terraform/` — 공통 기반 모듈 (VPC, EKS, Karpenter, ArgoCD 등 ~50개 .tf 파일)
- `infra/workshops/genai-on-eks/` — 워크샵 전용 설정
- `infra/nvidia-nim/`, `infra/trainium-inferentia/`, `infra/jark-stack/` 등은 각각 다른 시나리오별 인프라 변형

### blueprints/ — 워크로드 배포 청사진
- `inference/` — vLLM, Ray Serve, NIM 등 추론 서빙 (GPU/Neuron)
- `training/` — 학습 워크로드
- `gateways/` — AI Gateway 패턴
- `notebooks/` — JupyterHub 등

### website/ — Docusaurus 기반 문서 사이트

---
## Terraform 부트스트래핑 흐름

### _LOCAL 복사 패턴

install.sh 실행 시:
1. base/terraform/* 파일을 _LOCAL/로 복사
2. 워크샵 전용 tf 파일(s3-workshop.tf, pull.tf, grafana.tf) 덮어쓰기
3. blueprint.tfvars 복사
4. base의 install.sh 실행

Terraform은 한 디렉토리 안의 모든 .tf 파일을 하나의 설정으로 합쳐서 처리.
base 코드를 직접 수정하지 않고, 시나리오별로 .tf 파일만 추가/덮어쓰기해서 변형을 만드는 패턴.
_LOCAL이라는 이름 자체는 아무 의미 없음. 아무 이름이나 써도 됨.

### 순차 apply — provider 초기화 문제

```bash
targets=(
  "module.vpc"
  "module.eks"
  "module.karpenter"
  "module.argocd"
)
for target in "${targets[@]}"; do
  terraform apply -auto-approve -target="$target"
done
terraform apply -auto-approve  # 나머지 전체
```

-target으로 순차 apply하는 이유: provider 초기화 시점 문제.
- kubernetes/helm provider가 module.eks.cluster_endpoint에 의존
- plan 단계에서 EKS가 없으면 provider 초기화 실패
- VPC → EKS → Karpenter → ArgoCD 순서로 인프라 레이어를 쌓아야 함

### blueprint.tfvars 워크샵 설정
- 클러스터명: genai-workshop, 리전: us-east-2
- EKS Auto Mode 활성화
- Prometheus + Grafana 모니터링 스택
- S3 모델 저장소 연동

---
## ArgoCD 설치 방식

이 워크샵은 Managed ArgoCD(EKS Capability for Argo CD)가 아니라,
오픈소스 ArgoCD를 Helm으로 직접 설치하는 self-hosted 방식.

```hcl
resource "helm_release" "argocd" {
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "8.1.1"
  namespace  = "argocd"
}
```

- Dex: ArgoCD의 SSO/인증 컴포넌트(Identity Provider connector). 워크샵에서는 불필요하므로 비활성화.
- Notifications: 비활성화.

참고: AWS에는 EKS Capability for Argo CD가 있음 — AWS가 관리하는 Managed ArgoCD.
scaling, patching, updates를 AWS가 처리. EKS 콘솔에서 활성화 가능.

---
## EKS Addon 구성

base 기본 addon (7개):
- coredns, kube-proxy, vpc-cni, eks-pod-identity-agent
- metrics-server, eks-node-monitoring-agent, amazon-cloudwatch-observability

워크샵 blueprint.tfvars에서 2개 비활성화:
- metrics-server = false
- amazon-cloudwatch-observability = false

EKS Auto Mode에서는 vpc-cni, eks-pod-identity-agent, coredns, kube-proxy,
eks-node-monitoring-agent, aws-ebs-csi-driver를 Auto Mode가 자체 관리.
EKS 모듈에서 스킵 후, NodePool 생성 이후 aws_eks_addon.auto_mode_after_compute로 별도 설치.

S3 CSI driver(Mountpoint for Amazon S3)는 설치되지 않음.
s3.tf는 S3 버킷 + IAM Role + Pod Identity Association만 구성.
Pod에서 aws s3 cp나 SDK로 직접 접근하는 방식.

---
## ODCR (On-Demand Capacity Reservation)과 Service Quota

### 왜 용량 예약이 필요한가
GPU 인스턴스(g6e 등)는 수요 대비 공급 부족.
그냥 프로비저닝하면 InsufficientInstanceCapacity 에러 가능.
ODCR은 "자리를 미리 잡아두는 것" — 예약 시점부터 과금(사용 안 해도).

워크샵에서 필요한 이유:
- 참가자 수십~수백 명이 같은 리전, 같은 인스턴스 타입 동시 요청
- 혼자 연습한다면 ODCR 없이 시도해도 됨

### Service Quota 제한
GPU 인스턴스는 기본 vCPU 한도가 0.
Service Quotas → EC2 → "Running On-Demand G and VT instances" 검색.
g6e.2xlarge는 vCPU 8개이므로 최소 8로 증가 요청 필요.

---
## EKS Auto Mode NodePool / NodeClass

### NodePool이란
Karpenter의 리소스. Pod가 스케줄링 안 될 때 NodePool 조건에 맞는 EC2 인스턴스를 자동 프로비저닝.

NodePool = "어떤 종류의 인스턴스를 쓸 것인가" (K8s 레벨)
NodeClass = "인스턴스의 AWS 인프라 설정" (AWS 레벨)

### 일반 Karpenter vs Auto Mode 차이

| 항목 | 일반 Karpenter | EKS Auto Mode |
|---|---|---|
| Karpenter 설치 | 직접 Helm 설치/관리 | AWS 내장·관리 |
| NodePool API | karpenter.sh/v1 | karpenter.sh/v1 (동일) |
| NodeClass API | karpenter.k8s.aws/v1 → EC2NodeClass | eks.amazonaws.com/v1 → NodeClass |
| AMI 관리 | 사용자가 AMI family 지정 | AWS가 관리 |
| 기본 NodePool | 없음 | system + general-purpose 내장 |
| Label prefix | karpenter.k8s.aws/... | eks.amazonaws.com/... |

### 워크샵의 NodePool 구성 (4종)

| NodePool | NodeClass | Instance | Architecture | Taint | Use |
|---|---|---|---|---|---|
| system | general | c, m, r (5세대+) | amd64, arm64 | CriticalAddonsOnly | 시스템 컴포넌트 |
| general-purpose | general | c, m, r (5세대+) | amd64 | 없음 | 일반 워크로드 |
| gpu | gpu | g5, g6, g6e | amd64 | nvidia.com/gpu | GPU 추론 |
| neuron | neuron | inf2, trn1, trn2 | amd64 | aws.amazon.com/neuron | Inferentia/Trainium |

### System vs General-Purpose 차이
- System: CriticalAddonsOnly taint → 시스템 컴포넌트만 스케줄링. amd64+arm64 모두 지원 (Graviton 비용 효율).
- General-Purpose: taint 없음 → 일반 Pod 스케줄링. amd64만 (애플리케이션 이미지 호환성).
- 분리 이유: 사용자 워크로드가 리소스 과도 사용/OOM이 나도 시스템 컴포넌트는 별도 노드에서 안전하게 동작.

---
## Bottlerocket OS

AWS가 만든 컨테이너만 돌리기 위한 초경량 Linux.
EKS Auto Mode에서 기본 OS로 사용.

| 항목 | Amazon Linux 2023 | Bottlerocket |
|---|---|---|
| 용도 | 범용 서버 | 컨테이너 전용 |
| 설치 소프트웨어 | 패키지 매니저, shell, SSH 등 | containerd + kubelet만 |
| SSH 접근 | 가능 | 불가 (SSM으로만) |
| OS 업데이트 | yum update (패키지 개별) | 원자적 업데이트 (전체 OS 통째 교체, 실패 시 롤백) |
| 루트 파일시스템 | 읽기/쓰기 | 읽기전용 (변조 불가) |
| 공격 표면 | 넓음 | 최소화 |
| 부팅 속도 | 보통 | 빠름 |

---
## 워크샵 페이지: 환경 탐색하기 (fetch 원문 요약)

### 워크샵 인프라 구성
- Amazon VPC: 멀티 AZ, 퍼블릭/프라이빗 서브넷
- Amazon EKS Auto Mode 클러스터 (genai-workshop)
- 자체 관리형 모니터링: Kube Prometheus Stack, Grafana Operator
- Amazon Managed Prometheus: 메트릭 수집/저장

### Auto Mode 내장 컴포넌트 (자동 관리)
- CoreDNS, kube-proxy, VPC CNI, EKS Pod Identity Agent, EBS CSI Driver
- NVIDIA Device Plugin: Bottlerocket OS에 포함 (GPU 워크로드용)
- 내부적으로 Karpenter 사용, 최대 21일마다 노드 자동 교체

### 워크샵 모니터링 스택 배치
- 워크샵 문서는 "system nodepool에 배치"라고 설명하지만, 실제 코드에는
  tolerations/nodeSelector 설정이 없음 → general-purpose nodepool에 배치됨
- Helm values(kube-prometheus.yaml)와 grafana_operator 모두 toleration 미설정
- node-exporter → DaemonSet이므로 모든 nodepool에 배치 (정상 동작)

### 모델 다운로드 Job
- general-purpose nodepool에서 실행
- GPU 불필요 + system taint toleration 없음 → general-purpose로 스케줄링

### NVIDIA Device Plugin 관련 메모
- Auto Mode + Bottlerocket에서는 OS에 내장되어 별도 설치 불필요
- 일반 Karpenter + AL2023 환경이라면 별도 DaemonSet 설치 필요

---
## 워크샵 페이지: LLM 추론을 위한 GPU 인프라 최적화

### GPU NodePool / NodeClass 구성
- 인스턴스 타입: g6e.2xlarge (NVIDIA L40S)
- AMI: NVIDIA 드라이버 내장 Bottlerocket 변형
- Taint: nvidia.com/gpu:NoSchedule → GPU 워크로드만 스케줄링
- 커스텀 NodeClass: SOCI 성능 최적화된 스토리지 구성

### SOCI (Seekable OCI) 스냅샷터
- EKS Auto Mode가 G, P, Trn 계열 인스턴스에서 자동 활성화
- ML 컨테이너 이미지(5-20GB)의 시작 시간을 대폭 단축
- NVMe 로컬 스토리지에서 병렬 pull + 압축 해제
- 2025년 11월 19일부터 추가 구성 없이 자동 활성화
- 전체 이미지를 다운로드하기 전에 컨테이너 시작 가능 (lazy loading)

### Bottlerocket GPU AMI 변형
- Auto Mode가 GPU 인스턴스에 자동으로 GPU용 Bottlerocket AMI 선택
- NVIDIA 드라이버 + Device Plugin 내장
- 별도 DaemonSet 설치 불필요 (일반 Karpenter + AL2023이라면 필요)

IMAGE: Bottlerocket GPU AMI + Device Plugin 구조
  URL: https://static.us-east-1.prod.workshops.aws/public/3c4bb70e-51c5-414c-b71c-9fd7bc2ed032/static/images/100-intro/ami-device-plugin.png
  Source: GenAI on EKS Workshop - LLM 추론을 위한 GPU 인프라 최적화

### ODCR과 NodeClass 연동
- NodeClass에 capacityReservationSelectorTerms로 ODCR ID 지정
- kubectl patch nodeclass gpu --type=merge로 적용
- Auto Mode가 GPU 노드 프로비저닝 시 ODCR 인스턴스 사용

IMAGE: GPU NodePool 추가 후 클러스터 아키텍처
  URL: https://static.us-east-1.prod.workshops.aws/public/3c4bb70e-51c5-414c-b71c-9fd7bc2ed032/static/images/100-intro/gpu-initial-architecture.png
  Source: GenAI on EKS Workshop - LLM 추론을 위한 GPU 인프라 최적화

### GPU 기능 테스트 (nvidia-smi Pod)
- tolerations: nvidia.com/gpu 키
- nodeSelector: karpenter.sh/nodepool: gpu
- resources.limits: nvidia.com/gpu: 1
- 흐름: Pod Pending → Karpenter가 GPU 노드 프로비저닝 (30초~1분) → Pod Running
- nvidia-smi 출력: GPU 모델, CUDA 버전, 메모리, 전력 등 확인

---
## 워크샵 페이지: Amazon EKS에서 추론

### 모듈 개요
- NVIDIA GPU로 LLM 추론 워크로드 배포 및 확장
- 모델: Mistral-8B
- 서빙 프레임워크: vLLM (최적화된 성능/메모리 활용)
- 오케스트레이션: Ray Serve (분산 컴퓨팅, 확장)
- 모니터링: GPU + LLM 메트릭 관찰 가능성

### 핵심 개념 정리 필요
- vLLM: LLM 추론 최적화 프레임워크 (PagedAttention, continuous batching)
- Ray Serve: 분산 추론 오케스트레이션
- vLLM + Ray Serve 조합의 이유
- GPU 메트릭 모니터링 (DCGM exporter?)

---
## vLLM 개념

### vLLM이란
오픈소스 LLM 추론/서빙 엔진. GPU 메모리를 효율적으로 활용하여 추론 성능 최적화.
다른 옵션: TensorRT-LLM, Triton Inference Server 등.

### 핵심 기술
- **PagedAttention**: KV 캐시를 페이지 단위로 동적 할당 → GPU 메모리 최대 60% 절감
  - 기존: 시퀀스 최대 길이만큼 메모리를 미리 할당 (낭비 발생)
  - PagedAttention: OS의 가상 메모리 페이징처럼 필요한 만큼만 할당
- **Continuous Batching**: 요청을 개별 처리하지 않고 연속적으로 배칭
  - 기존 static batching: 배치 내 가장 긴 시퀀스가 끝날 때까지 대기
  - continuous batching: 완료된 요청은 즉시 빠지고, 새 요청이 즉시 들어옴
  - GPU 활용률 극대화
- **최적화된 CUDA 커널**: GPU 연산 최적화
- **텐서 병렬 처리**: 모델을 여러 GPU에 분산

### 프로덕션 특성
- OpenAI 호환 API 서버 (기존 코드 변경 없이 교체 가능)
- 스트리밍 응답 지원
- 내장 요청 스케줄링

### 성능
- 표준 PyTorch 대비 최대 24배 처리량
- 더 큰 배치 크기 + 더 긴 시퀀스 지원 가능

---
## 워크샵 페이지: vLLM을 사용한 모델 배포

### 모델
- Ministral-3-8B-Instruct-2512
- S3 버킷에 사전 업로드: s3://genai-models-{ACCOUNT_ID}/Ministral-3-8B-Instruct-2512/
- 모델 가중치: consolidated.safetensors (~10GB, 단일 파일)

### 모델 파일 형식
- SafeTensors (.safetensors): HuggingFace의 보안 중심 형식. 제로 카피 로딩, 빠른 속도. 프로덕션 권장.
- PyTorch (.pt/.pth): 네이티브 PyTorch 직렬화. 연구/개발용. pickle 기반이라 보안 주의.
- tokenizer.json: 텍스트 → 토큰 변환 규칙 + 어휘
- config.json / params.json: 모델 아키텍처 (레이어 수, 어텐션 헤드 등)

### Run:ai Streamer — S3에서 직접 모델 로딩
- PV/PVC 없이 S3에서 직접 모델 가중치를 스트리밍
- 이점:
  - 로컬 스토리지에 전체 모델 복사 불필요 → 빠른 시작
  - 스토리지 프로비저닝 지연 없이 빠른 확장
  - 모델 중복 복사 방지 → 비용 절감
  - 구성 가능한 동시성 (concurrency:16 → 16개 병렬 스트림)

### vLLM 주요 구성 매개변수
- --model=s3://... : S3 모델 경로
- --load-format=runai_streamer : Run:ai 스트리머로 S3 직접 로딩
- --model-loader-extra-config={"concurrency":16} : 16개 병렬 스트림
- --gpu_memory_utilization=0.90 : GPU 메모리 90% 사용
- --max-model-len=2048 : 최대 시퀀스 길이
- --tensor-parallel-size=1 : 텐서 병렬 처리 GPU 수 (1 = 단일 GPU)
- --max-num-batched-tokens=8192 : 배치 당 최대 토큰 수
- --max-num-seqs=256 : 동시 처리 최대 시퀀스 수
- --block-size=16 : continuous batching 블록 크기
- --enforce-eager : CUDA 그래프 대신 eager 실행 (디버깅/호환성)
- --swap-space=16 : GPU 메모리 부족 시 CPU 메모리 스왑 (16GB)
- --enable-auto-tool-choice : 자동 도구 선택 (function calling)
- --tool-call-parser=mistral : Mistral 도구 호출 파서

### 배포 방식
- 일반 K8s Deployment + Service
- AWS Deep Learning Container 이미지 (vLLM + Run:ai 스트리머 포함)
- GPU 노드 없으면 Auto Mode가 자동 프로비저닝
- 모델 로딩 완료까지 수초~수분 소요

---
## vLLM 배포 매니페스트 분석 (vllm-s3-deployment.yml)

### Service
```yaml
apiVersion: v1
kind: Service
metadata:
  name: vllm-serve-svc
  annotations:
    prometheus.io/scrape: "true"       # Prometheus가 메트릭 자동 수집
    prometheus.io/app-metrics: "true"
    prometheus.io/port: "8000"
  labels:
    model: mistral
spec:
  ports:
    - port: 8000        # vLLM 추론 API 포트
  selector:
    model: mistral       # Deployment의 Pod를 선택
```
- ClusterIP 타입 (기본) → 클러스터 내부에서만 접근
- Prometheus annotation으로 메트릭 자동 스크래핑

### Deployment 핵심 분석

**스케줄링:**
```yaml
serviceAccountName: model-storage-sa   # S3 접근용 Pod Identity
tolerations:
  - key: nvidia.com/gpu                # GPU nodepool의 taint 허용
    operator: Exists
    effect: NoSchedule
nodeSelector:
  karpenter.sh/nodepool: gpu           # GPU nodepool에만 배치
```
- model-storage-sa: Terraform의 s3.tf에서 생성한 Pod Identity Association과 연결
  → AWS 자격 증명 없이 S3 접근 가능

**컨테이너 이미지:**
```
763104351884.dkr.ecr.us-east-1.amazonaws.com/vllm:0.15.1-gpu-py312-cu129-ubuntu22.04-ec2-v1.1-soci
```
- AWS Deep Learning Container (DLC)
- vLLM 0.15.1 + CUDA 12.9 + Python 3.12 + SOCI 지원
- 763104351884 = AWS 관리 ECR 계정 (DLC 공용)

**환경 변수:**
```yaml
- CUDA_LAUNCH_BLOCKING: "1"            # CUDA 커널 동기 실행 (디버깅 용이)
- PYTORCH_CUDA_ALLOC_CONF: "max_split_size_mb:512"  # GPU 메모리 단편화 방지
- VLLM_ATTENTION_BACKEND: "FLASHINFER" # FlashInfer 어텐션 백엔드 사용
```
- FLASHINFER: FlashAttention의 대안. 더 유연한 어텐션 커널. PagedAttention과 함께 사용.

**리소스:**
```yaml
resources:
  requests:
    cpu: 6
    memory: 32Gi
    nvidia.com/gpu: 1     # GPU 1장 요청
  limits:
    cpu: 6
    memory: 32Gi
    nvidia.com/gpu: 1     # GPU 1장 제한 (requests = limits → QoS: Guaranteed)
```
- requests = limits → Guaranteed QoS class
- GPU는 항상 requests = limits여야 함 (GPU는 부분 할당 불가)

**헬스체크:**
```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 8000
  initialDelaySeconds: 60    # 모델 로딩 대기 (60초)
  periodSeconds: 10
livenessProbe:
  httpGet:
    path: /health
    port: 8000
  initialDelaySeconds: 120   # 모델 로딩 완전 대기 (120초)
  periodSeconds: 30
```
- readiness: 60초 후 시작. 트래픽 수신 가능 여부 판단
- liveness: 120초 후 시작. Pod 재시작 여부 판단
- initialDelaySeconds 차이: 모델 로딩이 느리므로 liveness는 더 여유를 줌

**배포 전략:**
```yaml
strategy:
  type: Recreate    # Rolling update가 아닌 전부 종료 후 재생성
```
- GPU 리소스는 한정적이므로 Rolling update 시 동시에 2개 Pod가 GPU를 요구하면 스케줄링 실패
- Recreate: 기존 Pod 종료 → GPU 반환 → 새 Pod 생성

---
## 워크샵 페이지: LLM과 상호작용하기

### vLLM API 테스트
- vLLM은 OpenAI 호환 API를 제공
- /v1/completions 엔드포인트로 curl 테스트
- 포트 포워딩: kubectl port-forward svc/vllm-serve-svc 8000:8000
- 응답에 usage 포함: prompt_tokens, completion_tokens, total_tokens

### Open WebUI 배포
- 자체 호스팅 LLM 웹 인터페이스 (ChatGPT와 유사한 UI)
- vLLM 서비스(vllm-serve-svc)에 연결하여 Mistral 모델과 대화
- Ingress로 외부 노출:
  - ALB (Application Load Balancer) 사용
  - EKS Auto Mode의 IngressClass: alb (eks.amazonaws.com/alb 컨트롤러)
  - alb.ingress.kubernetes.io/scheme: internet-facing
  - alb.ingress.kubernetes.io/target-type: ip (Pod IP 직접 타겟)
  - inbound-cidrs로 접근 IP 제한 가능

### 아키텍처 흐름
```
브라우저 → ALB (internet-facing)
  → Open WebUI Pod (general-purpose nodepool)
    → vllm-serve-svc:8000 (ClusterIP)
      → vLLM Pod (gpu nodepool, g6e.2xlarge)
        → Mistral-3-8B 모델 (S3에서 Run:ai Streamer로 로딩)
```

---
## 워크샵 페이지: LLM 추론 워크로드 관찰하기

### 모듈 구성 (3단계)

1. **관측성 스택 설정**
   - Prometheus + Grafana 아키텍처 (이미 배포됨)
   - Grafana Operator 구성
   - NVIDIA DCGM Exporter 배포 + 대시보드

2. **NVIDIA DCGM 모니터링**
   - DCGM (Data Center GPU Manager) Exporter: GPU 메트릭 수집
   - GPU 온도, 전력, 메모리 사용량, 활용률 등
   - Grafana 대시보드 시각화

3. **vLLM 모델 모니터링**
   - vLLM 자체 메트릭 (Prometheus endpoint)
   - 토큰 생성 속도 (tokens/sec)
   - 추론 지연 시간 (latency)
   - 추론 대기열 깊이
   - 배치 처리 시간

### 핵심 개념 정리 필요
- DCGM Exporter: NVIDIA GPU 메트릭을 Prometheus 형식으로 노출하는 DaemonSet
- vLLM 내장 메트릭: /metrics 엔드포인트 (Service annotation으로 Prometheus 자동 스크래핑)
- Grafana Operator: CRD로 대시보드를 선언적 관리 (GrafanaDashboard CR)
- Amazon Managed Prometheus: 메트릭 장기 저장소 (클러스터 외부)

---
## 워크샵 페이지: 관찰 가능성 스택 설정하기

### 모니터링 아키텍처 흐름
```
GPU 노드                     일반 노드
┌─────────────┐             ┌─────────────┐
│ DCGM Export │             │ Node Export  │
│ (GPU 메트릭) │             │ (OS 메트릭)  │
│ :9400       │             │              │
│ vLLM /metrics│             │ kube-state   │
│ :8000       │             │ (K8s 메트릭)  │
└──────┬──────┘             └──────┬───────┘
       │                          │
       └──────────┬───────────────┘
                  ▼
           Prometheus (스크래핑)
                  │
                  │ remote_write (SigV4 인증)
                  ▼
        Amazon Managed Prometheus (AMP)
                  │
                  │ PromQL 쿼리 (SigV4 인증)
                  ▼
              Grafana → 대시보드
```

### Kube Prometheus Stack 구성요소 역할
- Prometheus 서버: 메트릭 수집 + AMP로 remote_write 전송
- Node Exporter: 각 노드 하드웨어/OS 메트릭 (DaemonSet)
- Kube State Metrics: K8s 오브젝트 상태 메트릭 (Deployment replica 수, Pod 상태 등)

### Amazon Managed Prometheus (AMP) 통합
- Prometheus → AMP: remote_write + AWS SigV4 인증
- Grafana → AMP: PromQL 쿼리 + SigV4 인증
- 인증: EKS Pod Identity (ServiceAccount → IAM Role)
- 이점:
  - 관리형: 스토리지/확장/HA 불필요
  - 장기 보존: 클러스터 외부에 메트릭 저장
  - 비용: 수집/저장된 메트릭에 대해서만 과금

### Grafana Operator
- CRD (GrafanaDashboard)로 대시보드를 선언적 관리
- YAML로 대시보드 정의 → kubectl apply → Grafana에 자동 프로비저닝
- Grafana 서버가 재시작되어도 대시보드 유지

### NVIDIA DCGM Exporter
- NVIDIA Data Center GPU Manager의 메트릭을 Prometheus 형식으로 노출
- DaemonSet으로 GPU 노드에만 배포 (nodeSelector + toleration)
- 수집 메트릭: GPU 활용률, 메모리 사용량, 온도, 전력 소비, ECC 에러 등
- 포트 9400, /metrics 엔드포인트
- Helm 설치: gpu-helm-charts/dcgm-exporter

DCGM Exporter 배포 설정:
```yaml
nodeSelector:
  karpenter.sh/nodepool: gpu        # GPU 노드에만 배포
tolerations:
  - key: "nvidia.com/gpu"           # GPU taint 허용
    operator: "Exists"
    effect: "NoSchedule"
serviceMonitor:
  enabled: true
  additionalLabels:
    release: kube-prometheus-stack   # Prometheus Operator가 자동 발견
```
- serviceMonitor.additionalLabels.release: Prometheus Operator가 이 라벨로
  ServiceMonitor를 필터링 → 이 라벨이 없으면 Prometheus가 DCGM 메트릭을 수집하지 않음

### Prometheus 메트릭 수집 경로 (3가지)
1. ServiceMonitor (CRD): Prometheus Operator가 관리. DCGM Exporter가 이 방식 사용.
2. prometheus.io annotation: Service/Pod에 annotation → Prometheus가 자동 스크래핑. vLLM이 이 방식 사용.
3. additionalScrapeConfigs: Prometheus values에 직접 정의. Karpenter, EKS control plane 메트릭이 이 방식.

---
## 워크샵 페이지: NVIDIA DCGM 대시보드 구성하기

### Grafana Ingress 구성
- ALB로 Grafana 외부 노출 (Open WebUI와 동일 패턴)
- inbound-cidrs로 접근 IP 제한 가능
- 비밀번호: K8s Secret (kube-prometheus-stack-grafana)에서 base64 디코딩

### AMP 데이터소스 연결 확인
- Grafana → Connections → Data Sources → Amazon Managed Prometheus
- Save & Test로 연결 확인 필요

### DCGM 대시보드 패널 목록
| Panel | Metric | Description |
|---|---|---|
| GPU Temperature | DCGM_FI_DEV_GPU_TEMP | GPU 온도 (°C) |
| GPU Avg. Temp | avg(DCGM_FI_DEV_GPU_TEMP) | 전체 GPU 평균 온도 |
| GPU Power Usage | DCGM_FI_DEV_POWER_USAGE | GPU별 전력 소비 (W) |
| GPU Power Total | sum(DCGM_FI_DEV_POWER_USAGE) | 총 전력 소비 |
| GPU SM Clocks | DCGM_FI_DEV_SM_CLOCK | 스트리밍 멀티프로세서 클럭 (Hz) |
| GPU Utilization | DCGM_FI_DEV_GPU_UTIL | GPU 활용률 (%) |
| Framebuffer Mem Used | DCGM_FI_DEV_FB_USED | GPU 메모리 사용량 (MB) |
| Tensor Core Util | DCGM_FI_PROF_PIPE_TENSOR_ACTIVE | 텐서 코어 활용률 (%) |

### DCGM 메트릭 의미
- GPU Utilization vs Tensor Core Utilization:
  - GPU Utilization: GPU가 "어떤 작업이든" 하고 있는 시간 비율
  - Tensor Core Utilization: 행렬 연산(ML 추론 핵심)에 쓰이는 텐서 코어 활용률
  - LLM 추론 시 Tensor Core Util이 높아야 GPU를 효율적으로 쓰고 있는 것
- Framebuffer Mem Used: 모델 가중치 + KV 캐시가 차지하는 GPU 메모리
  - gpu_memory_utilization=0.90 설정에 따라 ~90%까지 사용
- SM Clocks: GPU가 부스트 클럭으로 동작 중인지 확인. 서멀 스로틀링 시 하락.

---
## 워크샵 페이지: vLLM 모델 모니터링

### vLLM ServiceMonitor
- 앞서 vLLM Service에 prometheus.io annotation이 있었지만, 여기서는 ServiceMonitor(CRD)도 추가
- ServiceMonitor를 쓰는 이유: annotation 방식보다 세밀한 제어 가능 (interval, path, namespaceSelector 등)
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: mistral-monitor
  namespace: monitoring             # ServiceMonitor는 monitoring에 배치
  labels:
    release: kube-prometheus-stack   # Prometheus Operator가 발견하려면 이 라벨 필수
spec:
  namespaceSelector:
    matchNames: [default]            # vLLM Service가 있는 네임스페이스
  selector:
    matchLabels:
      model: mistral                 # vLLM Service의 라벨과 매칭
  endpoints:
    - port: http                     # Service의 port name
      interval: 30s
      path: /metrics                 # vLLM 내장 메트릭 엔드포인트
```

### vLLM 메트릭 대시보드 패널

#### 처리량 메트릭
| Metric | Description |
|---|---|
| Iterations Token | vLLM 처리 반복(iteration) 횟수. 시간당 처리량 파악 |
| Generations Tokens | 생성된 총 토큰 수. 출력 볼륨/처리량 추적 |

#### 지연 시간 메트릭 (사용자 경험에 직결)
| Metric | Description |
|---|---|
| Time to First Token (TTFT) | 요청 수신 → 첫 번째 토큰 생성까지 시간. 사용자가 느끼는 "응답 시작 속도" |
| Time Per Output Token (TPOT) | 토큰 하나 생성에 걸리는 시간. 스트리밍 속도 결정 |
| Request Inference Time | 전체 추론 처리 시간. 요청 완료까지 총 시간 |
| Time in Queue | 요청이 대기열에서 기다린 시간. 높으면 GPU 용량 부족 신호 |

#### 리소스/스케줄링 메트릭
| Metric | Description |
|---|---|
| Request Prompt Tokens | 입력 프롬프트 토큰 수. 워크로드 패턴 파악 |
| Num Preemptions Total | 요청 선점(preemption) 횟수. KV 캐시 메모리 부족 시 발생. 높으면 gpu_memory_utilization 조정 필요 |

### LLM 추론 핵심 지표 설명
- **TTFT (Time to First Token)**: 사용자가 "응답이 시작됐다"고 느끼는 시간. 
  대화형 AI에서 가장 중요한 UX 지표.
- **TPOT (Time Per Output Token)**: 토큰 간 간격. 
  스트리밍 응답에서 "타이핑 속도"를 결정.
- **Throughput (tokens/sec)**: 초당 생성 토큰. 
  배치 처리/동시 사용자 수 결정.
- **Preemption**: KV 캐시 공간이 부족하면 진행 중인 요청을 중단하고 
  나중에 다시 처리. 메모리 관련 성능 저하 신호.
  → gpu_memory_utilization 낮추거나 max-model-len 줄이기.

---
## 워크샵 페이지: 정리

### 제거 대상
- vLLM ServiceMonitor
- DCGM Exporter (helm uninstall)
- vLLM Deployment + Service
- Open WebUI

### 유지 대상
- Prometheus, Grafana, Grafana Ingress → 다음 모듈(Ray)에서 계속 사용
- Grafana Operator, GrafanaDashboard CRDs
- AMP workspace

---
## 워크샵 트러블슈팅 메모

### DCGM Exporter 설치 실패 — 환경 변수 중복
- 워크샵 가이드의 values.yaml에 extraEnv로 DCGM_EXPORTER_LISTEN, DCGM_EXPORTER_KUBERNETES 정의
- 차트 기본값에 이미 동일 키가 있어서 DaemonSet env 키 중복 에러
- 해결: extraEnv 섹션 제거

### vLLM 대시보드 — Time Per Output Token nodata
- 대시보드 PromQL: vllm:time_per_output_token_seconds_bucket
- 실제 메트릭 이름: vllm:request_time_per_output_token_seconds_bucket
- vLLM 버전 업데이트로 메트릭 이름에 request_ 추가됨. 대시보드 JSON 미반영.
- 해결: ConfigMap의 대시보드 JSON에서 메트릭 이름 수정 후 GrafanaDashboard CR 재생성

### GrafanaDashboard CR 재생성 시 주의
- configMapRef.key를 정확히 맞춰야 함
- ConfigMap의 실제 key 확인: kubectl get cm <name> -o go-template='{{range $k,$v := .data}}{{$k}}{{end}}'
- key가 틀리면 대시보드가 사라짐

### 모니터링 스택 nodepool 배치 — 워크샵 문서 오류
- 워크샵 문서: "system nodepool에 배치"라고 설명
- 실제 코드: tolerations/nodeSelector 설정 없음 → general-purpose에 배치
- 해결: kube-prometheus.yaml에 tolerations + nodeSelector 추가, grafana_operator tf에도 추가

---
## 트러블슈팅 추가

### cleanup.sh — ArgoCD Application 삭제 무한 대기
- cleanup.sh가 NodePool을 먼저 삭제 → 노드 종료
- 이후 ArgoCD Application 삭제 시도 → finalizer가 하위 리소스 정리 대기
- 노드가 없어 Pod graceful 종료 불가 + ArgoCD도 동작 불가 → 무한 대기
- 해결: kubectl patch application <name> -n argocd --type json -p '[{"op":"remove","path":"/metadata/finalizers"}]'

### cleanup.sh — Unauthorized 에러
- EKS 토큰 기본 유효기간 15분. cleanup.sh가 오래 걸리면 토큰 만료
- 해결: aws eks update-kubeconfig --name genai-workshop --region us-east-2 후 재실행
