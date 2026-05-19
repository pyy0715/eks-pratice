# Week 9 — GenAI on EKS Lab

EKS Auto Mode 클러스터에 GenAI 플랫폼 스택(vLLM, LiteLLM, Langfuse, Open WebUI)을 배포합니다.

## Service Quotas

GPU/Neuron 인스턴스의 기본 vCPU 할당량은 0입니다. AWS 콘솔 > Service Quotas에서 아래 항목을 요청합니다.

| Quota Name | Instance | vCPU/ea | Minimum |
|---|---|---|---|
| Running On-Demand Inf Instances | inf2.xlarge | 4 | 4 |
| Running On-Demand G and VT Instances | g6e.2xlarge | 8 | 8 |

## Deployment

### Step 1: Infrastructure (Terraform)

```bash
cd labs/week9
terraform init

# 1단계: VPC + EKS 클러스터 생성 (VPC는 의존성으로 자동 포함)
terraform apply -target=module.eks

# 2단계: 나머지 리소스 생성 (Addons, EFS, NodePools 등)
terraform apply
```

> [!NOTE]
> **왜 2단계로 나누나요?**
> `kubectl`, `kubernetes`, `helm` provider는 EKS 클러스터 endpoint와 인증 토큰을 참조합니다.
> 클러스터가 존재하지 않는 상태에서 `terraform apply`를 실행하면 provider 초기화가 실패합니다.
> 1단계에서 클러스터를 먼저 만들면 2단계에서 provider가 정상 연결됩니다.

VPC, EKS Auto Mode, EFS, NodePools(general/GPU/Neuron), EFS CSI Driver, StorageClasses가 생성됩니다.

### Step 2: Environment Variables

`00_env.sh`에서 `AWS_REGION`(기본 `us-east-2`)과 `EKS_CLUSTER_NAME`(기본 `genai-eks`)을 자동 설정합니다.
vLLM 배포 시 HuggingFace 토큰만 직접 설정하면 됩니다.

```bash
export HF_TOKEN="hf_xxx"
```

### Step 3: Components

```bash
./01_vllm.sh       # vLLM (Neuron, inf2.xlarge) — 첫 시작 시 10분+ 소요
./02_langfuse.sh   # Langfuse (ClickHouse + PostgreSQL + Redis + ZooKeeper)
./03_litellm.sh    # LiteLLM (vLLM + Bedrock 모델 등록, Langfuse callback)
./04_openwebui.sh  # Open WebUI (LiteLLM 백엔드 연결)
```

배포 순서가 중요합니다:
- LiteLLM은 vLLM의 ClusterIP Service에 연결하므로 vLLM이 먼저 실행되어야 합니다
- LiteLLM은 Langfuse에 trace를 전송하므로 Langfuse가 먼저 실행되어야 합니다
- Open WebUI는 LiteLLM의 API 엔드포인트에 연결합니다

### Step 4: Verification

```bash
./05_verify.sh
```

또는 개별 확인:

```bash
# Pod 상태
kubectl get pods -n vllm
kubectl get pods -n langfuse
kubectl get pods -n litellm
kubectl get pods -n openwebui

# Bedrock 모델 접근 확인
aws bedrock list-foundation-models \
  --region us-east-2 \
  --query "modelSummaries[?contains(modelId, 'claude')].modelId" \
  --output table

# vLLM 헬스체크 (LiteLLM Pod에서 내부 통신 확인)
kubectl exec -n litellm deploy/litellm -- \
  curl -s http://qwen3-8b-neuron.vllm:8000/health

# LiteLLM 모델 목록 확인
kubectl exec -n litellm deploy/litellm -- \
  curl -s http://localhost:4000/v1/models -H "Authorization: Bearer sk-1234"

# Open WebUI 접근
kubectl port-forward svc/openwebui 8080:80 -n openwebui
# 브라우저에서 http://localhost:8080
```

## Cost Warning

| Instance | Hourly (us-east-2, on-demand) |
|---|---|
| inf2.xlarge | ~$0.76 |
| g6e.2xlarge | ~$1.34 |

실습 완료 후 반드시 정리합니다.

## Teardown

```bash
./99_teardown.sh      # 컴포넌트 제거
terraform destroy     # 인프라 제거
```
