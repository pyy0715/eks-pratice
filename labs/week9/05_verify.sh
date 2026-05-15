#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/00_env.sh"

echo "=== Verifying workshop components ==="
echo ""

for ns in vllm langfuse litellm openwebui; do
  echo "--- $ns ---"
  kubectl get pods -n "$ns" 2>/dev/null || echo "namespace $ns not found"
  echo ""
done

echo "--- Bedrock model access ---"
aws bedrock list-foundation-models \
  --region "$AWS_REGION" \
  --query "modelSummaries[?contains(modelId, 'claude')].modelId" \
  --output table 2>/dev/null || echo "Bedrock not available in $AWS_REGION or insufficient permissions"

echo ""
echo "--- vLLM health check ---"
kubectl run curl-test --rm -i --restart=Never --image=curlimages/curl -n vllm -- \
  curl -s --max-time 5 http://qwen3-8b-neuron.vllm:8000/health 2>/dev/null || echo "vLLM not reachable yet"

echo ""
echo "--- LiteLLM model list ---"
kubectl run curl-test --rm -i --restart=Never --image=curlimages/curl -n litellm -- \
  curl -s --max-time 5 http://litellm:4000/v1/models -H "Authorization: Bearer $LITELLM_API_KEY" 2>/dev/null || echo "LiteLLM not reachable yet"

echo ""
echo "=== Verification complete ==="
