#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/00_env.sh"

echo "=== Verifying workshop components ==="
echo ""

echo "--- vLLM ---"
kubectl get pods -n vllm
echo ""

echo "--- Langfuse ---"
kubectl get pods -n langfuse
echo ""

echo "--- LiteLLM ---"
kubectl get pods -n litellm
echo ""

echo "--- Open WebUI ---"
kubectl get pods -n openwebui
echo ""

echo "--- Bedrock model access ---"
aws bedrock list-foundation-models \
  --region "$AWS_REGION" \
  --query "modelSummaries[?contains(modelId, 'claude')].modelId" \
  --output table 2>/dev/null || echo "Bedrock access not available in $AWS_REGION or insufficient permissions"

echo ""
echo "--- vLLM health check ---"
kubectl exec -n litellm deploy/litellm -- \
  curl -s http://qwen3-8b-neuron.vllm:8000/health 2>/dev/null || echo "vLLM not reachable from LiteLLM yet"

echo ""
echo "=== Verification complete ==="
